import Foundation

public enum CloudProviderKind: String, Codable, Sendable, CaseIterable {
    case openAI
    case openAICompatible
    case anthropic
    case gemini
    case openRouter
    case voyageAI
    case custom
}

public struct CloudProviderModel: Identifiable, Hashable, Codable, Sendable {
    public var id: ModelID
    public var displayName: String
    public var createdAt: Date?
    public var rank: Double

    public init(
        id: ModelID,
        displayName: String,
        createdAt: Date? = nil,
        rank: Double = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.rank = rank
    }
}

public struct CloudProviderConfiguration: Identifiable, Hashable, Codable, Sendable {
    public var id: ProviderID
    public var kind: CloudProviderKind
    public var displayName: String
    public var baseURL: URL
    public var defaultModelID: ModelID?
    public var validationStatus: ProviderValidationStatus
    public var lastValidationError: String?
    public var extraHeadersJSON: String?
    public var keychainService: String
    public var keychainAccount: String
    public var enabledForAgents: Bool
    public var lastValidatedAt: Date?

    public init(
        id: ProviderID,
        kind: CloudProviderKind,
        displayName: String,
        baseURL: URL,
        defaultModelID: ModelID? = nil,
        validationStatus: ProviderValidationStatus = .unvalidated,
        lastValidationError: String? = nil,
        extraHeadersJSON: String? = nil,
        keychainService: String = "com.schtack.pines.cloud",
        keychainAccount: String,
        enabledForAgents: Bool = false,
        lastValidatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.baseURL = baseURL
        self.defaultModelID = defaultModelID
        self.validationStatus = validationStatus
        self.lastValidationError = lastValidationError
        self.extraHeadersJSON = extraHeadersJSON
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.enabledForAgents = enabledForAgents
        self.lastValidatedAt = lastValidatedAt
    }
}

public extension CloudProviderConfiguration {
    var capabilities: ProviderCapabilities {
        let officialOpenAI = isOfficialOpenAIAPI
        let imageInputs: Bool
        let pdfInputs: Bool
        let textDocumentInputs: Bool

        switch kind {
        case .openAI:
            imageInputs = officialOpenAI
            pdfInputs = officialOpenAI
            textDocumentInputs = officialOpenAI
        case .anthropic, .gemini:
            imageInputs = true
            pdfInputs = true
            textDocumentInputs = true
        case .openRouter:
            imageInputs = true
            pdfInputs = true
            textDocumentInputs = false
        case .voyageAI:
            imageInputs = false
            pdfInputs = false
            textDocumentInputs = false
        case .openAICompatible, .custom:
            imageInputs = officialOpenAI
            pdfInputs = officialOpenAI
            textDocumentInputs = officialOpenAI
        }

        return ProviderCapabilities(
            local: false,
            streaming: kind != .voyageAI,
            textGeneration: kind != .voyageAI,
            vision: imageInputs,
            imageInputs: imageInputs,
            pdfInputs: pdfInputs,
            textDocumentInputs: textDocumentInputs,
            embeddings: kind.supportsVaultEmbeddings,
            toolCalling: kind != .custom && kind != .voyageAI,
            jsonMode: kind != .custom && kind != .voyageAI,
            maxContextTokens: nil
        )
    }

    var isOfficialOpenAIAPI: Bool {
        if kind == .openAI {
            return true
        }
        guard let host = baseURL.host(percentEncoded: false)?.lowercased() else {
            return false
        }
        return host == "api.openai.com"
    }
}

public extension CloudProviderKind {
    var supportsVaultEmbeddings: Bool {
        switch self {
        case .openAI, .openAICompatible, .gemini, .openRouter, .voyageAI, .custom:
            true
        case .anthropic:
            false
        }
    }
}

public struct CloudEmbeddingRequestBuilder: Sendable {
    public init() {}

    public func openAICompatibleBody(
        providerKind: CloudProviderKind,
        modelID: ModelID,
        inputs: [String],
        dimensions: Int?,
        inputType: EmbeddingInputType?
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID.rawValue),
            "input": .array(inputs.map(JSONValue.string)),
            "encoding_format": .string("float"),
        ]
        if let dimensions, dimensions > 0 {
            body["dimensions"] = .number(Double(dimensions))
        }
        if providerKind == .openRouter, let inputType {
            body["input_type"] = .string(inputType == .query ? "search_query" : "search_document")
        }
        return .object(body)
    }

    public func geminiBatchBody(
        modelID: ModelID,
        inputs: [String],
        dimensions: Int?,
        inputType: EmbeddingInputType?
    ) -> (modelName: String, body: JSONValue) {
        let modelName = modelID.rawValue.hasPrefix("models/")
            ? modelID.rawValue
            : "models/\(modelID.rawValue)"
        let isGeminiEmbedding2 = modelName.hasSuffix("/gemini-embedding-2") || modelName == "models/gemini-embedding-2"
        let requests: [JSONValue] = inputs.map { input in
            let contentText = isGeminiEmbedding2
                ? Self.geminiEmbedding2Content(input, inputType: inputType)
                : input
            var item: [String: JSONValue] = [
                "model": .string(modelName),
                "content": .object([
                    "parts": .array([
                        .object(["text": .string(contentText)]),
                    ]),
                ]),
            ]
            if let dimensions, dimensions > 0 {
                item[isGeminiEmbedding2 ? "output_dimensionality" : "outputDimensionality"] = .number(Double(dimensions))
            }
            if !isGeminiEmbedding2 {
                item["taskType"] = .string(inputType == .query ? "RETRIEVAL_QUERY" : "RETRIEVAL_DOCUMENT")
            }
            return .object(item)
        }
        return (modelName, .object(["requests": .array(requests)]))
    }

    public func voyageBody(
        modelID: ModelID,
        inputs: [String],
        dimensions: Int?,
        inputType: EmbeddingInputType?
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID.rawValue),
            "input": .array(inputs.map(JSONValue.string)),
            "input_type": .string(inputType == .query ? "query" : "document"),
        ]
        if let dimensions, dimensions > 0 {
            body["output_dimension"] = .number(Double(dimensions))
        }
        return .object(body)
    }

    public static func geminiEmbedding2Content(_ input: String, inputType: EmbeddingInputType?) -> String {
        switch inputType {
        case .query:
            return "task: search result | query: \(input)"
        case .document, .none:
            return "title: none | text: \(input)"
        }
    }
}

public protocol SecretStore: Sendable {
    func read(service: String, account: String) async throws -> String?
    func write(_ secret: String, service: String, account: String) async throws
    func delete(service: String, account: String) async throws
}

public enum CloudProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case disabledForAgents
    case invalidResponse
    case providerRejectedRequest(statusCode: Int, message: String)
}

public enum CloudProviderModelEligibility: Sendable {
    public static func isTextOutputModel(
        id rawID: String,
        providerKind: CloudProviderKind,
        supportedGenerationMethods: [String] = []
    ) -> Bool {
        let id = rawID.lowercased()
        let modelName = id
            .split(separator: "/")
            .last
            .map(String.init) ?? id
        let blocked = [
            "embedding", "embed", "moderation", "image", "imagen", "dall-e", "sora",
            "tts", "transcribe", "whisper", "audio", "realtime", "vision-preview"
        ]
        guard !blocked.contains(where: { id.contains($0) }) else { return false }

        switch providerKind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            guard !isOpenAIOSeries(modelName) else { return false }
        case .anthropic, .gemini, .voyageAI:
            break
        }

        if providerKind == .gemini {
            guard supportedGenerationMethods.contains(where: { method in
                method == "generateContent"
                    || method == "streamGenerateContent"
                    || method == "createInteraction"
                    || method == "interactions"
            }) else {
                return false
            }
        }

        switch providerKind {
        case .openAI:
            return modelName.hasPrefix("gpt-")
        case .anthropic:
            return modelName.hasPrefix("claude-")
        case .gemini:
            return modelName.hasPrefix("gemini-")
        case .openAICompatible, .openRouter, .custom:
            return true
        case .voyageAI:
            return false
        }
    }

    public static func isOpenAIOSeries(_ modelName: String) -> Bool {
        let id = modelName.lowercased()
        guard id.hasPrefix("o") else { return false }
        return id.dropFirst().first?.isNumber == true
    }

    public static func openAIReasoningEffort(for modelID: ModelID, requested: OpenAIReasoningEffort) -> OpenAIReasoningEffort {
        let id = modelID.rawValue.lowercased()
        let modelName = id
            .split(separator: "/")
            .last
            .map(String.init) ?? id
        if modelName.contains("-pro") {
            return .high
        }
        if requested == .none, !(modelName.hasPrefix("gpt-5.1") || modelName.hasPrefix("gpt-5.5")) {
            return .low
        }
        return requested
    }
}

public struct OpenAICompatibleRequestBuilder: Sendable {
    private static let reasoningDefaultMaxCompletionTokens = 16_384

    public init() {}

    public func chatRequest(
        baseURL: URL,
        apiKey: String,
        request: ChatRequest,
        toolsJSON: [[String: any Sendable]] = []
    ) throws -> URLRequest {
        let url = Self.v1BaseURL(from: baseURL).appending(path: "chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let usesReasoningChatParameters = Self.usesReasoningChatParameters(modelID: request.modelID)
        var body: [String: Any] = [
            "model": request.modelID.rawValue,
            "stream": true,
            "messages": try request.messages.map(Self.messageObject),
        ]
        if let maxTokens = request.sampling.maxTokens {
            body[usesReasoningChatParameters ? "max_completion_tokens" : "max_tokens"] = usesReasoningChatParameters
                ? max(maxTokens, Self.reasoningDefaultMaxCompletionTokens)
                : maxTokens
        }
        if !usesReasoningChatParameters {
            body["temperature"] = request.sampling.temperature
            body["top_p"] = request.sampling.topP
        } else {
            body["reasoning_effort"] = CloudProviderModelEligibility.openAIReasoningEffort(
                for: request.modelID,
                requested: request.sampling.openAIReasoningEffort
            ).rawValue
            body["verbosity"] = request.sampling.openAITextVerbosity.rawValue
        }
        let advertisedTools = !toolsJSON.isEmpty
            ? toolsJSON
            : (request.allowsTools ? request.availableTools.map { $0.openAIFunctionToolObject() } : [])
        if !advertisedTools.isEmpty {
            body["tools"] = advertisedTools.map(Self.jsonSerializable)
            body["tool_choice"] = "auto"
            body["parallel_tool_calls"] = false
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private static func v1BaseURL(from url: URL) -> URL {
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.split(separator: "/").last?.lowercased() == "v1" {
            return url
        }
        return url.appending(path: "v1")
    }

    private static func jsonSerializable(_ dictionary: [String: any Sendable]) -> [String: Any] {
        dictionary.mapValues { jsonSerializable($0) }
    }

    private static func messageObject(_ message: ChatMessage) throws -> [String: Any] {
        guard message.role != .tool else {
            return [
                "role": "tool",
                "tool_call_id": message.toolCallID ?? "",
                "content": message.content,
            ]
        }
        return [
            "role": message.role.rawValue,
            "content": try chatContent(from: message),
        ]
    }

    private static func chatContent(from message: ChatMessage) throws -> Any {
        guard !message.attachments.isEmpty else {
            return message.content
        }
        guard message.role == .user else {
            throw InferenceError.invalidRequest("OpenAI-compatible attachments are only supported on user messages.")
        }
        var parts = [[String: Any]]()
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        for attachment in message.attachments {
            guard attachment.cloudInputKind == .image else {
                throw InferenceError.unsupportedCapability("OpenAI-compatible chat completions only support image attachments.")
            }
            guard let localURL = attachment.localURL, localURL.isFileURL else {
                throw InferenceError.invalidRequest("Image attachment \(attachment.fileName) must have a local file URL.")
            }
            let data = try Data(contentsOf: localURL)
            let contentType = attachment.normalizedContentType == "image/jpg" ? "image/jpeg" : attachment.normalizedContentType
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:\(contentType);base64,\(data.base64EncodedString())"],
            ])
        }
        return parts
    }

    private static func jsonSerializable(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: any Sendable]:
            return jsonSerializable(dictionary)
        case let array as [any Sendable]:
            return array.map { jsonSerializable($0) }
        default:
            return value
        }
    }

    private static func usesReasoningChatParameters(modelID: ModelID) -> Bool {
        let id = modelID.rawValue.lowercased()
        return id.hasPrefix("o") || id.hasPrefix("gpt-5")
    }
}

extension CloudProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No API key is saved for this cloud provider."
        case .disabledForAgents:
            "This cloud provider is disabled for agent execution."
        case .invalidResponse:
            "The cloud provider returned an invalid response."
        case let .providerRejectedRequest(statusCode, message):
            "The cloud provider rejected the request with HTTP \(statusCode): \(message)"
        }
    }
}
