import Foundation
import PinesCore

public struct GeminiLiveSessionService: Sendable {
    public let configuration: CloudProviderConfiguration
    public let secretStore: any SecretStore
    public var urlSession: URLSession

    public init(
        configuration: CloudProviderConfiguration,
        secretStore: any SecretStore,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.secretStore = secretStore
        self.urlSession = urlSession
    }

    public func connect(_ request: GeminiLiveConnectRequest) async throws -> GeminiLiveSession {
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }

        var urlRequest = URLRequest(url: try Self.webSocketURL(baseURL: configuration.baseURL))
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        try await applyExtraHeaders(to: &urlRequest)

        let sessionID = request.sessionID ?? "gemini-live-\(UUID().uuidString)"
        let task = urlSession.webSocketTask(with: urlRequest)
        let session = GeminiLiveSession(
            id: sessionID,
            providerID: configuration.id,
            modelID: request.setup.modelID,
            modalities: request.setup.responseModalities,
            task: task,
            setup: request.setup,
            createdAt: Date()
        )
        task.resume()
        try await session.send(.setup(request.setup))
        await session.updateState(.open)
        return session
    }

    public static func webSocketURL(baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw CloudProviderError.invalidResponse
        }
        let scheme = components.scheme?.lowercased()
        switch scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            throw EndpointSecurityError.unsupportedScheme(baseURL)
        }

        let existingPath = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .droppingRESTVersionSuffix()
        components.percentEncodedPath = "/" + (existingPath + [
            "ws",
            "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent",
        ]).joined(separator: "/")
        components.queryItems = nil
        guard let url = components.url else {
            throw CloudProviderError.invalidResponse
        }
        try validateWebSocketEndpoint(url)
        return url
    }

    private func readAPIKey() async throws -> String? {
        let apiKey = try await secretStore.read(
            service: configuration.keychainService,
            account: configuration.keychainAccount
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return apiKey?.isEmpty == false ? apiKey : nil
    }

    private func applyExtraHeaders(to request: inout URLRequest) async throws {
        if let url = request.url {
            try Self.validateWebSocketEndpoint(url, allowsExplicitLocalHTTP: configuration.allowInsecureLocalHTTP)
        }

        for header in configuration.headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard header.kind == .secretReference || !CloudProviderHeader.isSecretLikeName(name) else {
                throw InferenceError.invalidRequest("Cloud provider header \(name) must be stored as a Keychain secret reference.")
            }
            let value: String?
            switch header.kind {
            case .publicValue:
                value = header.value
            case .secretReference:
                guard let service = header.keychainService,
                      let account = header.keychainAccount
                else {
                    throw InferenceError.invalidRequest("Cloud provider header \(name) is missing its Keychain reference.")
                }
                value = try await secretStore.read(service: service, account: account)
            }
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func validateWebSocketEndpoint(_ url: URL, allowsExplicitLocalHTTP: Bool = false) throws {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            throw EndpointSecurityError.missingScheme
        }
        if scheme == "wss" {
            return
        }
        guard scheme == "ws" else {
            throw EndpointSecurityError.unsupportedScheme(url)
        }
        guard EndpointSecurityPolicy.isLoopbackHost(url.host(percentEncoded: false)) else {
            throw EndpointSecurityError.insecureRemoteHTTP(url)
        }
        guard allowsExplicitLocalHTTP else {
            throw EndpointSecurityError.insecureLocalHTTPNotAllowed(url)
        }
    }
}

public actor GeminiLiveSession {
    public let id: String
    public let providerID: ProviderID
    public let modelID: ModelID
    public let modalities: [String]
    public let setup: GeminiLiveSetup
    public let createdAt: Date

    private let task: URLSessionWebSocketTask
    private var stateStorage: GeminiLiveSessionState = .connecting
    private var lastError: String?
    private var resumptionHandle: String?
    private var usageMetadata: JSONValue?
    private var closedAt: Date?

    init(
        id: String,
        providerID: ProviderID,
        modelID: ModelID,
        modalities: [String],
        task: URLSessionWebSocketTask,
        setup: GeminiLiveSetup,
        createdAt: Date
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.modalities = modalities
        self.task = task
        self.setup = setup
        self.createdAt = createdAt
    }

    public var state: GeminiLiveSessionState {
        stateStorage
    }

    public func send(_ message: GeminiLiveClientMessage) async throws {
        try await task.send(.data(try JSONEncoder().encode(message)))
    }

    public func sendText(_ text: String, turnComplete: Bool = true) async throws {
        try await send(.clientContent(.text(text, turnComplete: turnComplete)))
    }

    public func sendRealtimeText(_ text: String) async throws {
        try await send(.realtimeInput(.text(text)))
    }

    public func sendRealtimeAudio(_ data: Data, mimeType: String) async throws {
        try await send(.realtimeInput(.audio(data, mimeType: mimeType)))
    }

    public func receive() -> AsyncThrowingStream<GeminiLiveSessionEvent, Error> {
        AsyncThrowingStream { continuation in
            let receiver = Task {
                await receiveLoop(continuation: continuation)
            }
            continuation.onTermination = { _ in
                receiver.cancel()
            }
        }
    }

    public func close() async {
        closedAt = Date()
        stateStorage = .closed
        task.cancel(with: .normalClosure, reason: nil)
    }

    public func cancel(reason: String? = nil) async {
        closedAt = Date()
        stateStorage = .cancelled
        lastError = reason
        task.cancel(with: .goingAway, reason: reason.map { Data($0.utf8) })
    }

    public func sessionRecord() -> ProviderLiveSessionRecord {
        ProviderLiveSessionRecord(
            id: id,
            providerID: providerID,
            providerKind: .gemini,
            modelID: modelID,
            status: stateStorage.recordStatus,
            modalities: modalities,
            providerMetadata: [
                "live_endpoint": "BidiGenerateContent",
                "resumption_handle": resumptionHandle,
                "usage_metadata": usageMetadata.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            ].compactMapValues { $0 },
            createdAt: createdAt,
            closedAt: closedAt,
            lastError: lastError
        )
    }

    fileprivate func updateState(_ state: GeminiLiveSessionState) {
        stateStorage = state
    }

    private func receiveLoop(continuation: AsyncThrowingStream<GeminiLiveSessionEvent, Error>.Continuation) async {
        do {
            while !Task.isCancelled {
                let frame = try await task.receive()
                let data: Data
                switch frame {
                case let .data(frameData):
                    data = frameData
                case let .string(string):
                    data = Data(string.utf8)
                @unknown default:
                    continue
                }
                let message = try JSONDecoder().decode(GeminiLiveServerMessage.self, from: data)
                for event in message.sessionEvents(sessionID: id) {
                    apply(event)
                    continuation.yield(event)
                }
            }
        } catch {
            lastError = error.localizedDescription
            closedAt = Date()
            stateStorage = .failed(error.localizedDescription)
            continuation.finish(throwing: error)
            return
        }
        continuation.finish()
    }

    private func apply(_ event: GeminiLiveSessionEvent) {
        switch event {
        case .setupComplete:
            stateStorage = .open
        case let .usage(_, metadata):
            usageMetadata = metadata
        case let .sessionResumption(_, update):
            if let handle = update.newHandle, !handle.isEmpty {
                resumptionHandle = handle
            }
        case let .goAway(_, goAway):
            if let text = goAway.timeLeft {
                lastError = "Server goAway received; time left: \(text)."
            }
        case .closed:
            closedAt = Date()
            stateStorage = .closed
        case let .raw(_, message):
            if let usage = message.usageMetadata {
                usageMetadata = usage
            }
        default:
            break
        }
    }
}

public struct GeminiLiveConnectRequest: Sendable {
    public var sessionID: String?
    public var setup: GeminiLiveSetup
    public var timeoutInterval: TimeInterval

    public init(
        sessionID: String? = nil,
        setup: GeminiLiveSetup,
        timeoutInterval: TimeInterval = 30
    ) {
        self.sessionID = sessionID
        self.setup = setup
        self.timeoutInterval = timeoutInterval
    }
}

public enum GeminiLiveSessionState: Equatable, Sendable {
    case connecting
    case open
    case closing
    case closed
    case cancelled
    case failed(String)

    var recordStatus: String {
        switch self {
        case .connecting:
            "connecting"
        case .open:
            "active"
        case .closing:
            "closing"
        case .closed:
            "closed"
        case .cancelled:
            "cancelled"
        case .failed:
            "failed"
        }
    }
}

public struct GeminiLiveSetup: Hashable, Codable, Sendable {
    public var modelID: ModelID
    public var generationConfig: JSONValue?
    public var systemInstruction: JSONValue?
    public var tools: [JSONValue]
    public var realtimeInputConfig: JSONValue?
    public var sessionResumption: JSONValue?
    public var contextWindowCompression: JSONValue?
    public var inputAudioTranscription: JSONValue?
    public var outputAudioTranscription: JSONValue?
    public var historyConfig: JSONValue?

    public init(
        modelID: ModelID,
        responseModalities: [String] = ["TEXT"],
        systemInstructionText: String? = nil,
        generationConfig: JSONValue? = nil,
        tools: [JSONValue] = [],
        realtimeInputConfig: JSONValue? = nil,
        sessionResumption: JSONValue? = nil,
        contextWindowCompression: JSONValue? = nil,
        inputAudioTranscription: JSONValue? = nil,
        outputAudioTranscription: JSONValue? = nil,
        historyConfig: JSONValue? = nil
    ) {
        self.modelID = modelID
        var resolvedGenerationConfig = generationConfig?.objectValue ?? [:]
        if !responseModalities.isEmpty {
            resolvedGenerationConfig["responseModalities"] = .array(responseModalities.map(JSONValue.string))
        }
        self.generationConfig = resolvedGenerationConfig.isEmpty ? nil : .object(resolvedGenerationConfig)
        self.systemInstruction = systemInstructionText.map(Self.systemInstructionContent)
        self.tools = tools
        self.realtimeInputConfig = realtimeInputConfig
        self.sessionResumption = sessionResumption
        self.contextWindowCompression = contextWindowCompression
        self.inputAudioTranscription = inputAudioTranscription
        self.outputAudioTranscription = outputAudioTranscription
        self.historyConfig = historyConfig
    }

    public var responseModalities: [String] {
        generationConfig?.objectValue?["responseModalities"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    public var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(Self.normalizedModelName(modelID)),
        ]
        object["generationConfig"] = generationConfig
        object["systemInstruction"] = systemInstruction
        if !tools.isEmpty {
            object["tools"] = .array(tools)
        }
        object["realtimeInputConfig"] = realtimeInputConfig
        object["sessionResumption"] = sessionResumption
        object["contextWindowCompression"] = contextWindowCompression
        object["inputAudioTranscription"] = inputAudioTranscription
        object["outputAudioTranscription"] = outputAudioTranscription
        object["historyConfig"] = historyConfig
        return .object(object)
    }

    public static func normalizedModelName(_ modelID: ModelID) -> String {
        let raw = modelID.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.hasPrefix("models/") ? raw : "models/\(raw)"
    }

    public static func systemInstructionContent(_ text: String) -> JSONValue {
        .object([
            "role": .string("system"),
            "parts": .array([.object(["text": .string(text)])]),
        ])
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let object = value.objectValue,
              let model = object["model"]?.stringValue ?? object["modelID"]?.stringValue
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Gemini Live setup requires a model."))
        }
        modelID = ModelID(rawValue: model)
        generationConfig = object["generationConfig"]
        systemInstruction = object["systemInstruction"]
        tools = object["tools"]?.arrayValue ?? []
        realtimeInputConfig = object["realtimeInputConfig"]
        sessionResumption = object["sessionResumption"]
        contextWindowCompression = object["contextWindowCompression"]
        inputAudioTranscription = object["inputAudioTranscription"]
        outputAudioTranscription = object["outputAudioTranscription"]
        historyConfig = object["historyConfig"]
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue.encode(to: encoder)
    }
}

public enum GeminiLiveClientMessage: Hashable, Codable, Sendable {
    case setup(GeminiLiveSetup)
    case clientContent(GeminiLiveClientContent)
    case realtimeInput(GeminiLiveRealtimeInput)
    case toolResponse(JSONValue)

    public func encode(to encoder: Encoder) throws {
        try jsonValue.encode(to: encoder)
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let object = value.objectValue else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Gemini Live client message must be an object."))
        }
        if let setup = object["setup"] {
            self = .setup(try setup.decode(GeminiLiveSetup.self))
        } else if let clientContent = object["clientContent"] {
            self = .clientContent(try clientContent.decode(GeminiLiveClientContent.self))
        } else if let realtimeInput = object["realtimeInput"] {
            self = .realtimeInput(try realtimeInput.decode(GeminiLiveRealtimeInput.self))
        } else if let toolResponse = object["toolResponse"] {
            self = .toolResponse(toolResponse)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Gemini Live client message has no supported envelope key."))
        }
    }

    public var jsonValue: JSONValue {
        switch self {
        case let .setup(setup):
            .object(["setup": setup.jsonValue])
        case let .clientContent(content):
            .object(["clientContent": content.jsonValue])
        case let .realtimeInput(input):
            .object(["realtimeInput": input.jsonValue])
        case let .toolResponse(response):
            .object(["toolResponse": response])
        }
    }
}

public struct GeminiLiveClientContent: Hashable, Codable, Sendable {
    public var turns: [JSONValue]
    public var turnComplete: Bool?

    public init(turns: [JSONValue], turnComplete: Bool? = nil) {
        self.turns = turns
        self.turnComplete = turnComplete
    }

    public static func text(_ text: String, role: String = "user", turnComplete: Bool = true) -> Self {
        Self(
            turns: [
                .object([
                    "role": .string(role),
                    "parts": .array([.object(["text": .string(text)])]),
                ]),
            ],
            turnComplete: turnComplete
        )
    }

    public var jsonValue: JSONValue {
        var object: [String: JSONValue] = ["turns": .array(turns)]
        if let turnComplete {
            object["turnComplete"] = .bool(turnComplete)
        }
        return .object(object)
    }
}

public struct GeminiLiveRealtimeInput: Hashable, Codable, Sendable {
    public var audio: JSONValue?
    public var video: JSONValue?
    public var text: String?
    public var activityStart: Bool
    public var activityEnd: Bool

    public init(
        audio: JSONValue? = nil,
        video: JSONValue? = nil,
        text: String? = nil,
        activityStart: Bool = false,
        activityEnd: Bool = false
    ) {
        self.audio = audio
        self.video = video
        self.text = text
        self.activityStart = activityStart
        self.activityEnd = activityEnd
    }

    public static func text(_ text: String) -> Self {
        Self(text: text)
    }

    public static func audio(_ data: Data, mimeType: String) -> Self {
        Self(audio: GeminiLiveBlob(mimeType: mimeType, data: data).jsonValue)
    }

    public var jsonValue: JSONValue {
        var object = [String: JSONValue]()
        object["audio"] = audio
        object["video"] = video
        object["text"] = text.map(JSONValue.string)
        if activityStart {
            object["activityStart"] = .object([:])
        }
        if activityEnd {
            object["activityEnd"] = .object([:])
        }
        return .object(object)
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let object = value.objectValue ?? [:]
        audio = object["audio"]
        video = object["video"]
        text = object["text"]?.stringValue
        activityStart = object["activityStart"] != nil
        activityEnd = object["activityEnd"] != nil
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue.encode(to: encoder)
    }
}

public struct GeminiLiveBlob: Hashable, Codable, Sendable {
    public var mimeType: String
    public var data: Data

    public init(mimeType: String, data: Data) {
        self.mimeType = mimeType
        self.data = data
    }

    public var jsonValue: JSONValue {
        .object([
            "mimeType": .string(mimeType),
            "data": .string(data.base64EncodedString()),
        ])
    }
}

public struct GeminiLiveServerMessage: Hashable, Codable, Sendable {
    public var raw: JSONValue
    public var usageMetadata: JSONValue?
    public var setupComplete: JSONValue?
    public var serverContent: JSONValue?
    public var toolCall: JSONValue?
    public var toolCallCancellation: JSONValue?
    public var goAway: JSONValue?
    public var sessionResumptionUpdate: JSONValue?

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        self.raw = raw
        let object = raw.objectValue ?? [:]
        usageMetadata = object["usageMetadata"]
        setupComplete = object["setupComplete"]
        serverContent = object["serverContent"]
        toolCall = object["toolCall"]
        toolCallCancellation = object["toolCallCancellation"]
        goAway = object["goAway"]
        sessionResumptionUpdate = object["sessionResumptionUpdate"]
    }

    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }

    public func sessionEvents(sessionID: String) -> [GeminiLiveSessionEvent] {
        var events = [GeminiLiveSessionEvent]()
        if setupComplete != nil {
            events.append(.setupComplete(sessionID: sessionID))
        }
        if let serverContent {
            events.append(contentsOf: GeminiLiveTranscriptEvent.events(fromServerContent: serverContent).map {
                .transcript(sessionID: sessionID, $0)
            })
        }
        if let toolCall {
            events.append(.toolCall(sessionID: sessionID, toolCall))
        }
        if let toolCallCancellation {
            let ids = toolCallCancellation.objectValue?["ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
            events.append(.toolCallCancellation(sessionID: sessionID, ids: ids, raw: toolCallCancellation))
        }
        if let goAway {
            events.append(.goAway(sessionID: sessionID, GeminiLiveGoAway(raw: goAway)))
        }
        if let sessionResumptionUpdate {
            events.append(.sessionResumption(sessionID: sessionID, GeminiLiveSessionResumptionUpdate(raw: sessionResumptionUpdate)))
        }
        if let usageMetadata {
            events.append(.usage(sessionID: sessionID, usageMetadata))
        }
        if events.isEmpty {
            events.append(.raw(sessionID: sessionID, self))
        }
        return events
    }
}

public enum GeminiLiveSessionEvent: Hashable, Sendable {
    case setupComplete(sessionID: String)
    case transcript(sessionID: String, GeminiLiveTranscriptEvent)
    case toolCall(sessionID: String, JSONValue)
    case toolCallCancellation(sessionID: String, ids: [String], raw: JSONValue)
    case goAway(sessionID: String, GeminiLiveGoAway)
    case sessionResumption(sessionID: String, GeminiLiveSessionResumptionUpdate)
    case usage(sessionID: String, JSONValue)
    case raw(sessionID: String, GeminiLiveServerMessage)
    case closed(sessionID: String)
}

public enum GeminiLiveTranscriptEvent: Hashable, Sendable {
    case assistantText(String)
    case inputTranscription(String)
    case outputTranscription(String)
    case interrupted
    case turnComplete
    case generationComplete

    public var chatMessage: ChatMessage? {
        switch self {
        case let .assistantText(text), let .outputTranscription(text):
            ChatMessage(role: .assistant, content: text)
        case let .inputTranscription(text):
            ChatMessage(role: .user, content: text)
        default:
            nil
        }
    }

    static func events(fromServerContent value: JSONValue) -> [GeminiLiveTranscriptEvent] {
        guard let object = value.objectValue else { return [] }
        var events = [GeminiLiveTranscriptEvent]()
        if object["interrupted"]?.boolValue == true {
            events.append(.interrupted)
        }
        if object["turnComplete"]?.boolValue == true {
            events.append(.turnComplete)
        }
        if object["generationComplete"]?.boolValue == true {
            events.append(.generationComplete)
        }
        if let text = object["inputTranscription"]?.objectValue?["text"]?.stringValue, !text.isEmpty {
            events.append(.inputTranscription(text))
        }
        if let text = object["outputTranscription"]?.objectValue?["text"]?.stringValue, !text.isEmpty {
            events.append(.outputTranscription(text))
        }
        events.append(contentsOf: textParts(in: object["modelTurn"]).map(GeminiLiveTranscriptEvent.assistantText))
        return events
    }

    private static func textParts(in value: JSONValue?) -> [String] {
        guard let parts = value?.objectValue?["parts"]?.arrayValue else { return [] }
        return parts.compactMap { part in
            part.objectValue?["text"]?.stringValue
        }
        .filter { !$0.isEmpty }
    }
}

public struct GeminiLiveGoAway: Hashable, Sendable {
    public var raw: JSONValue
    public var timeLeft: String?

    init(raw: JSONValue) {
        self.raw = raw
        timeLeft = raw.objectValue?["timeLeft"]?.stringValue
    }
}

public struct GeminiLiveSessionResumptionUpdate: Hashable, Sendable {
    public var raw: JSONValue
    public var newHandle: String?
    public var resumable: Bool?

    init(raw: JSONValue) {
        self.raw = raw
        let object = raw.objectValue
        newHandle = object?["newHandle"]?.stringValue
        resumable = object?["resumable"]?.boolValue
    }
}

private extension Array where Element == String {
    func droppingRESTVersionSuffix() -> [String] {
        if suffix(2) == ["upload", "v1beta"] {
            return Array(dropLast(2))
        }
        if ["v1", "v1beta", "v1alpha"].contains(last ?? "") {
            return Array(dropLast())
        }
        return self
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}
