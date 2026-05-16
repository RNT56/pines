import Foundation
import PinesCore

struct BYOKCloudInferenceProvider: InferenceProvider {
    private static let openAIReasoningDefaultMaxCompletionTokens = 16_384

    let configuration: CloudProviderConfiguration
    let secretStore: any SecretStore

    var id: ProviderID { configuration.id }

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            local: false,
            streaming: true,
            textGeneration: true,
            vision: true,
            embeddings: false,
            toolCalling: true,
            jsonMode: true,
            maxContextTokens: nil
        )
    }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }

        let streamingFormat = self.streamingFormat(for: request)
        let urlRequest = try buildStreamingRequest(apiKey: apiKey, chatRequest: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw CloudProviderError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(contentsOf: [byte])
                            if body.count >= 8192 { break }
                        }
                        throw CloudProviderError.providerRejectedRequest(
                            statusCode: http.statusCode,
                            message: Self.providerErrorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                        )
                    }

                    var dataLines = [String]()
                    var toolState = CloudToolCallStreamState()
                    var pendingFinish: InferenceFinish?
                    for try await rawLine in bytes.lines {
                        guard !Task.isCancelled else { throw InferenceError.cancelled }
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.isEmpty {
                            handleSSEDataLines(dataLines, format: streamingFormat, state: &toolState, pendingFinish: &pendingFinish, continuation: continuation)
                            dataLines.removeAll(keepingCapacity: true)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    if !dataLines.isEmpty {
                        handleSSEDataLines(dataLines, format: streamingFormat, state: &toolState, pendingFinish: &pendingFinish, continuation: continuation)
                    }
                    continuation.yield(.finish(pendingFinish ?? fallbackFinish(format: streamingFormat, state: toolState, chatRequest: request)))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch {
                    continuation.yield(
                        .failure(
                            InferenceStreamFailure(
                                code: "cloud_stream_failed",
                                message: error.localizedDescription,
                                recoverable: true
                            )
                        )
                    )
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        throw InferenceError.unsupportedCapability("Cloud embeddings are disabled for v1 local-first vault indexing.")
    }

    func listTextModels() async throws -> [CloudProviderModel] {
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }
        return try await listTextModels(apiKey: apiKey)
    }

    func validate(modelID: ModelID?) async throws -> ProviderValidationResult {
        guard let apiKey = try await readAPIKey() else {
            return ProviderValidationResult(providerID: configuration.id, status: .invalid, message: "Missing API key.")
        }

        let availableModels = (try? await listTextModels(apiKey: apiKey).map(\.id)) ?? []

        var request: URLRequest
        switch configuration.kind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            request = URLRequest(url: configuration.baseURL.appending(path: "models"))
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request = URLRequest(url: configuration.baseURL.appending(path: "v1/messages"))
            request.httpMethod = "POST"
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": modelID?.rawValue ?? configuration.defaultModelID?.rawValue ?? "claude-3-5-haiku-latest",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "ping"]],
            ])
        case .gemini:
            let model = modelID?.rawValue ?? configuration.defaultModelID?.rawValue ?? "gemini-2.0-flash"
            var components = URLComponents(url: configuration.baseURL.appending(path: "v1beta/models/\(model):generateContent"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "contents": [["parts": [["text": "ping"]]]],
            ])
        }

        try applyExtraHeaders(to: &request)
        let (data, http) = try await URLSession.shared.data(for: request)
        if (200..<300).contains(http.statusCode) {
            return ProviderValidationResult(providerID: configuration.id, status: .valid, message: "Provider validated.", availableModels: availableModels)
        }
        let message = Self.providerErrorMessage(from: data) ?? "Validation failed with HTTP \(http.statusCode)."
        if http.statusCode == 429 {
            return ProviderValidationResult(providerID: configuration.id, status: .rateLimited, message: message, availableModels: availableModels)
        }
        return ProviderValidationResult(providerID: configuration.id, status: .invalid, message: message, availableModels: availableModels)
    }

    private func buildStreamingRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        if usesOpenAIResponsesAPI(chatRequest: chatRequest) {
            return try openAIResponsesRequest(apiKey: apiKey, chatRequest: chatRequest)
        }

        switch configuration.kind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            return try openAICompatibleRequest(apiKey: apiKey, chatRequest: chatRequest)
        case .anthropic:
            return try anthropicRequest(apiKey: apiKey, chatRequest: chatRequest)
        case .gemini:
            return try geminiRequest(apiKey: apiKey, chatRequest: chatRequest)
        }
    }

    private func streamingFormat(for chatRequest: ChatRequest) -> CloudStreamingFormat {
        usesOpenAIResponsesAPI(chatRequest: chatRequest) ? .openAIResponses : .chatCompletions
    }

    private func readAPIKey() async throws -> String? {
        let apiKey = try await secretStore.read(
            service: configuration.keychainService,
            account: configuration.keychainAccount
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return apiKey?.isEmpty == false ? apiKey : nil
    }

    private func openAICompatibleRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let url = configuration.baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let usesOpenAIReasoningParameters = usesOpenAIReasoningChatParameters(modelID: chatRequest.modelID)
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "messages": chatRequest.messages.map(Self.openAIMessageObject),
        ]
        body[usesOpenAIReasoningParameters ? "max_completion_tokens" : "max_tokens"] = openAICompletionTokenLimit(
            for: chatRequest,
            usesReasoningParameters: usesOpenAIReasoningParameters
        )
        if !usesOpenAIReasoningParameters {
            body["temperature"] = chatRequest.sampling.temperature
            body["top_p"] = chatRequest.sampling.topP
        } else {
            body["reasoning_effort"] = "low"
        }
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map { Self.jsonSerializable($0.openAIFunctionToolObject()) }
            body["tool_choice"] = "auto"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func openAIResponsesRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let url = configuration.baseURL.appending(path: "responses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "input": Self.openAIResponsesInput(from: chatRequest.messages),
            "max_output_tokens": openAICompletionTokenLimit(for: chatRequest, usesReasoningParameters: true),
            "reasoning": ["effort": "low"],
            "text": ["verbosity": "low"],
        ]
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map(Self.openAIResponsesFunctionToolObject)
            body["tool_choice"] = "auto"
        }
        let instructions = chatRequest.messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !instructions.isEmpty {
            body["instructions"] = instructions
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func listTextModels(apiKey: String) async throws -> [CloudProviderModel] {
        var request: URLRequest
        switch configuration.kind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            request = URLRequest(url: configuration.baseURL.appending(path: "models"))
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request = URLRequest(url: configuration.baseURL.appending(path: "v1/models"))
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            var components = URLComponents(url: configuration.baseURL.appending(path: "v1beta/models"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            request = URLRequest(url: components.url!)
        }

        try applyExtraHeaders(to: &request)
        let (data, http) = try await URLSession.shared.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudProviderError.providerRejectedRequest(
                statusCode: http.statusCode,
                message: Self.providerErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudProviderError.invalidResponse
        }
        return Self.parseModels(json, providerKind: configuration.kind)
    }

    private func anthropicRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let url = configuration.baseURL.appending(path: "v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "max_tokens": chatRequest.sampling.maxTokens ?? 1024,
            "temperature": chatRequest.sampling.temperature,
            "messages": chatRequest.messages.filter { $0.role != .system }.map(Self.anthropicMessageObject),
            "system": chatRequest.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n"),
        ]
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map { Self.jsonSerializable($0.anthropicToolObject()) }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func usesOpenAIReasoningChatParameters(modelID: ModelID) -> Bool {
        guard usesOfficialOpenAIAPI else { return false }
        return Self.isOpenAIReasoningModelID(modelID)
    }

    private func usesOpenAIResponsesAPI(chatRequest: ChatRequest) -> Bool {
        guard usesOfficialOpenAIAPI,
              usesOpenAIReasoningChatParameters(modelID: chatRequest.modelID)
        else {
            return false
        }
        return true
    }

    private var usesOfficialOpenAIAPI: Bool {
        if configuration.kind == .openAI {
            return true
        }
        guard let host = configuration.baseURL.host(percentEncoded: false)?.lowercased() else {
            return false
        }
        return host == "api.openai.com"
    }

    private func openAICompletionTokenLimit(for chatRequest: ChatRequest, usesReasoningParameters: Bool) -> Int {
        let requested = chatRequest.sampling.maxTokens ?? 1024
        guard usesReasoningParameters else { return requested }
        return max(requested, Self.openAIReasoningDefaultMaxCompletionTokens)
    }

    private static func isOpenAIReasoningModelID(_ modelID: ModelID) -> Bool {
        let id = modelID.rawValue.lowercased()
        let modelName = id
            .split(separator: "/")
            .last
            .map(String.init) ?? id
        return modelName.hasPrefix("gpt-5") || CloudProviderModelEligibility.isOpenAIOSeries(modelName)
    }

    private func fallbackFinish(
        format: CloudStreamingFormat,
        state: CloudToolCallStreamState,
        chatRequest: ChatRequest
    ) -> InferenceFinish {
        switch format {
        case .openAIResponses:
            return InferenceFinish(
                reason: .stop,
                message: Self.openAIResponsesEmptyOutputMessage(response: nil, eventTypes: state.openAIResponsesEventTypes)
            )
        case .chatCompletions:
            guard usesOfficialOpenAIAPI,
                  usesOpenAIReasoningChatParameters(modelID: chatRequest.modelID)
            else {
                return InferenceFinish(reason: .stop)
            }
            return InferenceFinish(
                reason: .stop,
                message: "Pines received an empty OpenAI Chat Completions stream for \(chatRequest.modelID.rawValue). Official OpenAI GPT-5 chats should use the Responses API; check that the provider base URL is api.openai.com and retry from the latest build."
            )
        }
    }

    private func geminiRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "v1beta/models/\(chatRequest.modelID.rawValue):streamGenerateContent"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "contents": chatRequest.messages.filter { $0.role != .system }.map(Self.geminiContentObject),
            "generationConfig": [
                "maxOutputTokens": chatRequest.sampling.maxTokens ?? AppSettingsSnapshot.defaultCloudMaxCompletionTokens,
                "temperature": chatRequest.sampling.temperature,
                "topP": chatRequest.sampling.topP,
            ],
        ]
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = [[
                "functionDeclarations": chatRequest.availableTools.map {
                    Self.jsonSerializable($0.geminiFunctionDeclarationObject())
                },
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try applyExtraHeaders(to: &request)
        return request
    }

    private static func openAIMessageObject(_ message: ChatMessage) -> [String: Any] {
        if message.role == .tool {
            return [
                "role": "tool",
                "tool_call_id": message.toolCallID ?? "",
                "content": message.content,
            ]
        }

        var object: [String: Any] = [
            "role": message.role.rawValue,
            "content": message.content,
        ]
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = message.toolCalls.map { toolCall in
                [
                    "id": toolCall.id,
                    "type": "function",
                    "function": [
                        "name": toolCall.name,
                        "arguments": toolCall.argumentsFragment,
                    ],
                ] as [String: Any]
            }
        }
        return object
    }

    private static func openAIResponsesInput(from messages: [ChatMessage]) -> [[String: Any]] {
        messages.reduce(into: [[String: Any]]()) { input, message in
            guard message.role != .system else { return }
            if message.role == .tool {
                input.append([
                    "type": "function_call_output",
                    "call_id": message.toolCallID ?? "",
                    "output": message.content,
                ])
                return
            }
            if !message.content.isEmpty {
                input.append([
                    "role": message.role == .assistant ? "assistant" : "user",
                    "content": message.content,
                ])
            }
            for toolCall in message.toolCalls {
                input.append([
                    "type": "function_call",
                    "call_id": toolCall.id,
                    "name": toolCall.name,
                    "arguments": toolCall.argumentsFragment,
                ])
            }
        }
    }

    private static func openAIResponsesFunctionToolObject(_ spec: AnyToolSpec) -> [String: Any] {
        [
            "type": "function",
            "name": spec.name,
            "description": spec.description,
            "parameters": jsonSerializable((spec.inputJSONSchema ?? spec.inputSchema.jsonValue).anySendable),
        ]
    }

    private static func anthropicMessageObject(_ message: ChatMessage) -> [String: Any] {
        if message.role == .tool {
            return [
                "role": "user",
                "content": [[
                    "type": "tool_result",
                    "tool_use_id": message.toolCallID ?? "",
                    "content": message.content,
                ]],
            ]
        }

        var content = [[String: Any]]()
        if !message.content.isEmpty {
            content.append(["type": "text", "text": message.content])
        }
        for toolCall in message.toolCalls {
            content.append([
                "type": "tool_use",
                "id": toolCall.id,
                "name": toolCall.name,
                "input": Self.jsonObject(fromJSONString: toolCall.argumentsFragment) ?? [:],
            ])
        }
        return [
            "role": message.role == .assistant ? "assistant" : "user",
            "content": content.isEmpty ? [["type": "text", "text": message.content]] : content,
        ]
    }

    private static func geminiContentObject(_ message: ChatMessage) -> [String: Any] {
        if message.role == .tool {
            return [
                "role": "function",
                "parts": [[
                    "functionResponse": [
                        "name": message.toolName ?? "",
                        "response": Self.jsonObject(fromJSONString: message.content) ?? ["result": message.content],
                    ],
                ]],
            ]
        }

        var parts = [[String: Any]]()
        if !message.content.isEmpty {
            parts.append(["text": message.content])
        }
        for toolCall in message.toolCalls {
            parts.append([
                "functionCall": [
                    "name": toolCall.name,
                    "args": Self.jsonObject(fromJSONString: toolCall.argumentsFragment) ?? [:],
                ],
            ])
        }
        return [
            "role": message.role == .assistant ? "model" : "user",
            "parts": parts.isEmpty ? [["text": message.content]] : parts,
        ]
    }

    private static func jsonSerializable(_ dictionary: [String: any Sendable]) -> [String: Any] {
        dictionary.mapValues { jsonSerializable($0) }
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

    private static func jsonObject(fromJSONString string: String) -> Any? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func providerErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = json["message"] as? String {
                return message
            }
            if let detail = json["detail"] as? String {
                return detail
            }
            if let errors = json["errors"] as? [[String: Any]],
               let message = errors.compactMap({ $0["message"] as? String }).first {
                return message
            }
        }
        let fallback = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback?.isEmpty == false ? fallback : nil
    }

    private func handleSSEDataLines(
        _ dataLines: [String],
        format: CloudStreamingFormat,
        state: inout CloudToolCallStreamState,
        pendingFinish: inout InferenceFinish?,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) {
        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload != "[DONE]", let data = payload.data(using: .utf8) else { return }

        for event in Self.extractEvents(from: data, format: format, providerKind: configuration.kind, state: &state, pendingFinish: &pendingFinish) {
            continuation.yield(event)
        }
    }

    private func applyExtraHeaders(to request: inout URLRequest) throws {
        guard let json = configuration.extraHeadersJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty
        else {
            return
        }
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw InferenceError.invalidRequest("Cloud provider extra headers must be a JSON object.")
        }
        let blockedHeaders = Set(["authorization", "content-type", "x-api-key"])
        for (rawName, rawValue) in object {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard !blockedHeaders.contains(name.lowercased()) else {
                throw InferenceError.invalidRequest("Cloud provider extra headers cannot override \(name).")
            }
            guard let value = rawValue as? String else {
                throw InferenceError.invalidRequest("Cloud provider extra header \(name) must be a string.")
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func parseModels(_ json: [String: Any], providerKind: CloudProviderKind) -> [CloudProviderModel] {
        let rawItems: [[String: Any]]
        switch providerKind {
        case .gemini:
            rawItems = json["models"] as? [[String: Any]] ?? []
        default:
            rawItems = json["data"] as? [[String: Any]] ?? []
        }

        let parsed = rawItems.compactMap { item -> CloudProviderModel? in
            let rawID: String?
            if providerKind == .gemini {
                rawID = (item["name"] as? String)?.replacingOccurrences(of: "models/", with: "")
            } else {
                rawID = item["id"] as? String
            }
            let supportedGenerationMethods = item["supportedGenerationMethods"] as? [String] ?? []
            guard let id = rawID,
                  CloudProviderModelEligibility.isTextOutputModel(
                      id: id,
                      providerKind: providerKind,
                      supportedGenerationMethods: supportedGenerationMethods
                  )
            else {
                return nil
            }

            let displayName = (item["display_name"] as? String)
                ?? readableModelName(id)
            let createdAt = createdDate(from: item)
            return CloudProviderModel(
                id: ModelID(rawValue: id),
                displayName: displayName,
                createdAt: createdAt,
                rank: modelRank(id: id, providerKind: providerKind, createdAt: createdAt)
            )
        }

        return parsed
            .sorted {
                if $0.rank == $1.rank {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.rank > $1.rank
            }
            .uniqued(by: \.id)
            .prefix(providerKind == .openAI ? 64 : 24)
            .map { $0 }
    }

    private static func createdDate(from item: [String: Any]) -> Date? {
        if let created = item["created"] as? TimeInterval {
            return Date(timeIntervalSince1970: created)
        }
        if let created = item["created_at"] as? String {
            return ISO8601DateFormatter().date(from: created)
        }
        return nil
    }

    private static func readableModelName(_ rawID: String) -> String {
        rawID
            .split(separator: "/")
            .last
            .map(String.init) ?? rawID
    }

    private static func modelRank(id rawID: String, providerKind: CloudProviderKind, createdAt: Date?) -> Double {
        let id = rawID.lowercased()
        var score = createdAt.map { $0.timeIntervalSince1970 / 1_000_000_000 } ?? 0
        score += numericVersionScore(id) * 100

        switch providerKind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            if id.contains("gpt-5") { score += 900 }
            if id.contains("gpt-4.1") { score += 650 }
            if id.contains("gpt-4o") { score += 560 }
            if id.contains("pro") { score += 80 }
            if id.contains("gpt-5") && id.contains("mini") { score += 45 }
            if id.contains("gpt-5") && id.contains("nano") { score += 30 }
            if id.contains("mini") { score -= 35 }
            if id.contains("nano") { score -= 70 }
        case .anthropic:
            if id.contains("opus") { score += 900 }
            if id.contains("sonnet") { score += 760 }
            if id.contains("haiku") { score += 520 }
            if id.contains("4-1") { score += 140 }
            if id.contains("-4-") { score += 110 }
            if id.contains("3-7") { score += 70 }
        case .gemini:
            if id.contains("pro") { score += 850 }
            if id.contains("flash") { score += 700 }
            if id.contains("flash-lite") { score -= 60 }
            if id.contains("preview") { score += 20 }
        }
        return score
    }

    private static func numericVersionScore(_ id: String) -> Double {
        let pattern = #"(\d+(?:[\.-]\d+)*)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
            let range = Range(match.range(at: 1), in: id)
        else {
            return 0
        }
        return id[range]
            .split { $0 == "." || $0 == "-" }
            .prefix(3)
            .enumerated()
            .reduce(0) { partial, item in
                partial + (Double(item.element) ?? 0) / pow(10, Double(item.offset * 2))
            }
    }

    private static func extractEvents(
        from data: Data,
        format: CloudStreamingFormat,
        providerKind: CloudProviderKind,
        state: inout CloudToolCallStreamState,
        pendingFinish: inout InferenceFinish?
    ) -> [InferenceStreamEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var events = [InferenceStreamEvent]()
        if format == .openAIResponses {
            return extractOpenAIResponsesEvents(json, state: &state, pendingFinish: &pendingFinish)
        }

        switch providerKind {
        case .anthropic:
            let type = json["type"] as? String
            if type == "content_block_start",
               let index = json["index"] as? Int,
               let block = json["content_block"] as? [String: Any],
               block["type"] as? String == "tool_use" {
                state.anthropicToolIndex = index
                state.anthropicToolID = block["id"] as? String
                state.anthropicToolName = block["name"] as? String
                state.anthropicArguments = jsonString(from: block["input"]) ?? ""
            }
            if let delta = json["delta"] as? [String: Any] {
                if delta["type"] as? String == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                    events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                }
                if delta["type"] as? String == "input_json_delta", let partial = delta["partial_json"] as? String {
                    state.anthropicArguments += partial
                }
            }
            if type == "content_block_stop",
               let index = json["index"] as? Int,
               index == state.anthropicToolIndex,
               let id = state.anthropicToolID,
               let name = state.anthropicToolName {
                events.append(
                    .toolCall(
                        ToolCallDelta(
                            id: id,
                            name: name,
                            argumentsFragment: state.anthropicArguments.isEmpty ? "{}" : state.anthropicArguments,
                            isComplete: true
                        )
                    )
                )
                state.clearAnthropicTool()
            }
        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            for part in parts ?? [] {
                if let text = part["text"] as? String, !text.isEmpty {
                    events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                }
                if let call = part["functionCall"] as? [String: Any],
                   let name = call["name"] as? String {
                    events.append(
                        .toolCall(
                            ToolCallDelta(
                                id: UUID().uuidString,
                                name: name,
                                argumentsFragment: jsonString(from: call["args"]) ?? "{}",
                                isComplete: true
                            )
                        )
                    )
                }
            }
        case .openAI, .openAICompatible, .openRouter, .custom:
            let choices = json["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            if let text = delta?["content"] as? String, !text.isEmpty {
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
            if let toolCalls = delta?["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    let index = call["index"] as? Int ?? 0
                    if let id = call["id"] as? String {
                        state.openAIToolIDs[index] = id
                    }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String {
                            state.openAIToolNames[index] = name
                        }
                        if let arguments = function["arguments"] as? String {
                            state.openAIArguments[index, default: ""] += arguments
                        }
                    }
                }
            }
            if let finish = choices?.first?["finish_reason"] as? String {
                pendingFinish = openAIFinish(from: finish)
            }
            if let finish = choices?.first?["finish_reason"] as? String, finish == "tool_calls" {
                for index in state.openAIToolNames.keys.sorted() {
                    guard let name = state.openAIToolNames[index] else { continue }
                    events.append(
                        .toolCall(
                            ToolCallDelta(
                                id: state.openAIToolIDs[index] ?? UUID().uuidString,
                                name: name,
                                argumentsFragment: state.openAIArguments[index] ?? "{}",
                                isComplete: true
                            )
                        )
                    )
                }
                state.clearOpenAITools()
            }
        }

        return events
    }

    private static func extractOpenAIResponsesEvents(
        _ json: [String: Any],
        state: inout CloudToolCallStreamState,
        pendingFinish: inout InferenceFinish?
    ) -> [InferenceStreamEvent] {
        let type = json["type"] as? String
        if let type {
            state.openAIResponsesEventTypes.insert(type)
        }
        switch type {
        case "response.output_item.added":
            if let index = json["output_index"] as? Int,
               let item = json["item"] as? [String: Any],
               item["type"] as? String == "function_call" {
                state.openAIToolIDs[index] = (item["call_id"] as? String) ?? (item["id"] as? String)
                state.openAIToolNames[index] = item["name"] as? String
                if let arguments = item["arguments"] as? String {
                    state.openAIArguments[index] = arguments
                }
            }
        case "response.output_text.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                state.openAIResponsesTextEmitted = true
                return [.token(TokenDelta(kind: .token, text: delta, tokenCount: 1))]
            }
        case "response.output_text.done":
            if !state.openAIResponsesTextEmitted,
               let text = json["text"] as? String,
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                return [.token(TokenDelta(kind: .token, text: text, tokenCount: 1))]
            }
        case "response.content_part.done":
            if !state.openAIResponsesTextEmitted,
               let part = json["part"] as? [String: Any],
               let text = part["text"] as? String,
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                return [.token(TokenDelta(kind: .token, text: text, tokenCount: 1))]
            }
        case "response.refusal.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                state.openAIResponsesTextEmitted = true
                return [.token(TokenDelta(kind: .token, text: delta, tokenCount: 1))]
            }
        case "response.refusal.done":
            if !state.openAIResponsesTextEmitted,
               let refusal = json["refusal"] as? String,
               !refusal.isEmpty {
                state.openAIResponsesTextEmitted = true
                return [.token(TokenDelta(kind: .token, text: refusal, tokenCount: 1))]
            }
        case "response.function_call_arguments.delta":
            let index = json["output_index"] as? Int ?? 0
            if let itemID = json["item_id"] as? String {
                state.openAIToolIDs[index] = state.openAIToolIDs[index] ?? itemID
            }
            if let delta = json["delta"] as? String {
                state.openAIArguments[index, default: ""] += delta
            }
        case "response.function_call_arguments.done":
            let index = json["output_index"] as? Int ?? 0
            if let itemID = json["item_id"] as? String {
                state.openAIToolIDs[index] = state.openAIToolIDs[index] ?? itemID
            }
            if let name = json["name"] as? String {
                state.openAIToolNames[index] = name
            }
            if let arguments = json["arguments"] as? String {
                state.openAIArguments[index] = arguments
            }
            if let name = state.openAIToolNames[index] {
                let event = InferenceStreamEvent.toolCall(
                    ToolCallDelta(
                        id: state.openAIToolIDs[index] ?? UUID().uuidString,
                        name: name,
                        argumentsFragment: state.openAIArguments[index] ?? "{}",
                        isComplete: true
                    )
                )
                state.openAIToolIDs.removeValue(forKey: index)
                state.openAIToolNames.removeValue(forKey: index)
                state.openAIArguments.removeValue(forKey: index)
                return [event]
            }
        case "response.completed":
            let response = json["response"] as? [String: Any]
            if !state.openAIResponsesTextEmitted,
               let response,
               let text = openAIResponsesOutputText(from: response),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                pendingFinish = InferenceFinish(reason: .stop)
                return [.token(TokenDelta(kind: .token, text: text, tokenCount: 1))]
            }
            if let response,
               let toolCall = openAIResponsesFunctionCall(from: response) {
                pendingFinish = InferenceFinish(reason: .toolCall)
                return [.toolCall(toolCall)]
            }
            pendingFinish = InferenceFinish(
                reason: .stop,
                message: openAIResponsesEmptyOutputMessage(response: response, eventTypes: state.openAIResponsesEventTypes)
            )
        case "response.incomplete":
            let response = json["response"] as? [String: Any]
            let details = response?["incomplete_details"] as? [String: Any]
            let reason = details?["reason"] as? String
            pendingFinish = InferenceFinish(
                reason: reason == "max_output_tokens" ? .length : .error,
                message: reason == "max_output_tokens"
                    ? "The selected OpenAI model used its max output token budget before producing visible output."
                    : "The selected OpenAI model returned an incomplete response."
            )
        case "response.failed":
            let response = json["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            pendingFinish = InferenceFinish(
                reason: .error,
                message: error?["message"] as? String ?? "The selected OpenAI model failed to produce a response."
            )
        default:
            break
        }
        return []
    }

    private static func openAIResponsesFunctionCall(from response: [String: Any]) -> ToolCallDelta? {
        guard let output = response["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "function_call" {
            guard let name = item["name"] as? String else { continue }
            return ToolCallDelta(
                id: (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString,
                name: name,
                argumentsFragment: item["arguments"] as? String ?? "{}",
                isComplete: true
            )
        }
        return nil
    }

    private static func openAIResponsesOutputText(from response: [String: Any]) -> String? {
        guard let output = response["output"] as? [[String: Any]] else { return nil }
        let parts = output.flatMap { item -> [String] in
            guard let content = item["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { part in
                let type = part["type"] as? String
                guard type == nil || type == "output_text" || type == "text" else { return nil }
                return part["text"] as? String
            }
        }
        let text = parts.joined()
        return text.isEmpty ? nil : text
    }

    private static func openAIResponsesEmptyOutputMessage(
        response: [String: Any]?,
        eventTypes: Set<String>
    ) -> String {
        let status = response?["status"] as? String
        let outputCount = (response?["output"] as? [[String: Any]])?.count
        var details = [String]()
        if let status {
            details.append("status: \(status)")
        }
        if let outputCount {
            details.append("output items: \(outputCount)")
        }
        if !eventTypes.isEmpty {
            details.append("events: \(eventTypes.sorted().joined(separator: ", "))")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))."
        return "OpenAI completed the Responses stream without visible output text\(suffix)"
    }

    private static func openAIFinish(from finishReason: String) -> InferenceFinish {
        switch finishReason {
        case "length":
            return InferenceFinish(
                reason: .length,
                message: "The selected OpenAI model used its completion token budget before producing visible output. Try again; Pines now reserves more completion tokens for GPT-5 reasoning models."
            )
        case "tool_calls":
            return InferenceFinish(reason: .toolCall)
        case "content_filter":
            return InferenceFinish(reason: .error, message: "The provider stopped the response because of its content filter.")
        default:
            return InferenceFinish(reason: .stop)
        }
    }

    private static func jsonString(from value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct CloudToolCallStreamState {
    var openAIToolIDs: [Int: String] = [:]
    var openAIToolNames: [Int: String] = [:]
    var openAIArguments: [Int: String] = [:]
    var openAIResponsesTextEmitted = false
    var openAIResponsesEventTypes = Set<String>()

    var anthropicToolIndex: Int?
    var anthropicToolID: String?
    var anthropicToolName: String?
    var anthropicArguments = ""

    mutating func clearOpenAITools() {
        openAIToolIDs.removeAll(keepingCapacity: true)
        openAIToolNames.removeAll(keepingCapacity: true)
        openAIArguments.removeAll(keepingCapacity: true)
    }

    mutating func clearAnthropicTool() {
        anthropicToolIndex = nil
        anthropicToolID = nil
        anthropicToolName = nil
        anthropicArguments.removeAll(keepingCapacity: true)
    }
}

private enum CloudStreamingFormat {
    case chatCompletions
    case openAIResponses
}

private extension Sequence {
    func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen = Set<ID>()
        var values = [Element]()
        for element in self where seen.insert(element[keyPath: keyPath]).inserted {
            values.append(element)
        }
        return values
    }
}
