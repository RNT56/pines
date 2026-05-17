import Foundation
import ImageIO
import PinesCore
import UniformTypeIdentifiers

struct BYOKCloudInferenceProvider: InferenceProvider {
    private static let openAIReasoningDefaultMaxCompletionTokens = 16_384
    fileprivate static let openAIResponseIDMetadataKey = CloudProviderMetadataKeys.openAIResponseID
    fileprivate static let openAIRequestIDMetadataKey = CloudProviderMetadataKeys.openAIRequestID
    fileprivate static let openAIClientRequestIDMetadataKey = CloudProviderMetadataKeys.openAIClientRequestID
    fileprivate static let anthropicMessageIDMetadataKey = CloudProviderMetadataKeys.anthropicMessageID
    fileprivate static let anthropicRequestIDMetadataKey = CloudProviderMetadataKeys.anthropicRequestID
    fileprivate static let anthropicThinkingContentMetadataKey = CloudProviderMetadataKeys.anthropicThinkingContentJSON
    fileprivate static let geminiResponseIDMetadataKey = CloudProviderMetadataKeys.geminiResponseID
    fileprivate static let geminiModelVersionMetadataKey = CloudProviderMetadataKeys.geminiModelVersion
    fileprivate static let geminiRequestIDMetadataKey = CloudProviderMetadataKeys.geminiRequestID
    fileprivate static let geminiModelContentMetadataKey = CloudProviderMetadataKeys.geminiModelContentJSON
    fileprivate static let geminiInteractionIDMetadataKey = CloudProviderMetadataKeys.geminiInteractionID
    fileprivate static let maxInlineImageBytes = 20 * 1024 * 1024
    fileprivate static let maxInlineFileBytes = 50 * 1024 * 1024

    let configuration: CloudProviderConfiguration
    let secretStore: any SecretStore
    private let embeddingRequestBuilder = CloudEmbeddingRequestBuilder()

    var id: ProviderID { configuration.id }

    var capabilities: ProviderCapabilities {
        configuration.capabilities
    }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }

        let streamingFormat = self.streamingFormat(for: request)
        let urlRequest = try buildStreamingRequest(apiKey: apiKey, chatRequest: request)
        let clientRequestID = urlRequest.value(forHTTPHeaderField: "X-Client-Request-Id")
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
                            message: Self.messageWithRequestID(
                                Self.providerErrorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                                requestID: Self.providerRequestID(from: http, body: body, providerKind: configuration.kind),
                                providerKind: configuration.kind
                            )
                        )
                    }

                    var dataLines = [String]()
                    var streamParser = CloudProviderStreamParser()
                    streamParser.recordRequestMetadata(
                        providerKind: configuration.kind,
                        serverRequestID: Self.providerRequestID(from: http, body: nil, providerKind: configuration.kind),
                        clientRequestID: clientRequestID
                    )
                    var pendingFinish: InferenceFinish?
                    for try await rawLine in bytes.lines {
                        guard !Task.isCancelled else { throw InferenceError.cancelled }
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.isEmpty {
                            handleSSEDataLines(dataLines, format: streamingFormat, parser: &streamParser, pendingFinish: &pendingFinish, continuation: continuation)
                            dataLines.removeAll(keepingCapacity: true)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    if !dataLines.isEmpty {
                        handleSSEDataLines(dataLines, format: streamingFormat, parser: &streamParser, pendingFinish: &pendingFinish, continuation: continuation)
                    }
                    continuation.yield(.finish(pendingFinish ?? streamParser.fallbackFinish(
                        format: streamingFormat,
                        providerKind: configuration.kind,
                        modelID: request.modelID,
                        usesOfficialOpenAIReasoningChat: usesOfficialOpenAIAPI && usesOpenAIReasoningChatParameters(modelID: request.modelID)
                    )))
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
        guard configuration.kind.supportsVaultEmbeddings else {
            throw InferenceError.unsupportedCapability("\(configuration.displayName) does not provide a native embedding API.")
        }
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }

        let urlRequest: URLRequest
        switch configuration.kind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            urlRequest = try openAICompatibleEmbeddingRequest(apiKey: apiKey, embeddingRequest: request)
        case .gemini:
            urlRequest = try geminiEmbeddingRequest(apiKey: apiKey, embeddingRequest: request)
        case .voyageAI:
            urlRequest = try voyageEmbeddingRequest(apiKey: apiKey, embeddingRequest: request)
        case .anthropic:
            throw InferenceError.unsupportedCapability("Anthropic does not provide a native embedding API. Configure Voyage AI, OpenAI, Gemini, OpenRouter, or a local embedding model.")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let http = try Self.httpResponse(from: response)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudProviderError.providerRejectedRequest(
                statusCode: http.statusCode,
                message: Self.messageWithRequestID(
                    Self.providerErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                    requestID: Self.providerRequestID(from: http, body: data, providerKind: configuration.kind),
                    providerKind: configuration.kind
                )
            )
        }

        let vectors = try Self.parseEmbeddingVectors(data: data, providerKind: configuration.kind)
        guard vectors.count == request.inputs.count else {
            throw CloudProviderError.invalidResponse
        }
        return EmbeddingResult(
            modelID: request.modelID,
            vectors: request.normalize ? vectors.map(Self.normalizedEmbedding) : vectors
        )
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

        let availableModels = configuration.kind == .voyageAI ? [] : ((try? await listTextModels(apiKey: apiKey).map(\.id)) ?? [])

        var request: URLRequest
        switch configuration.kind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            request = URLRequest(url: apiBaseURL.appending(path: "models"))
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            addOpenAIClientRequestID(to: &request)
        case .anthropic:
            request = URLRequest(url: configuration.baseURL.appending(path: "v1/messages"))
            request.httpMethod = "POST"
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": modelID?.rawValue ?? configuration.defaultModelID?.rawValue ?? "claude-sonnet-4-6",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "ping"]],
            ])
        case .gemini:
            let model = modelID?.rawValue ?? configuration.defaultModelID?.rawValue ?? "gemini-2.5-flash"
            let version = Self.geminiAPIVersion(for: ModelID(rawValue: model))
            let components = URLComponents(url: configuration.baseURL.appending(path: "\(version)/models/\(model):generateContent"), resolvingAgainstBaseURL: false)!
            request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "contents": [["parts": [["text": "ping"]]]],
            ])
        case .voyageAI:
            let defaults = VaultEmbeddingDefaults.defaults(for: .voyageAI)
            request = try voyageEmbeddingRequest(
                apiKey: apiKey,
                embeddingRequest: EmbeddingRequest(
                    modelID: defaults.modelID,
                    inputs: ["ping"],
                    dimensions: defaults.dimensions,
                    inputType: .query
                )
            )
        }

        try applyExtraHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try Self.httpResponse(from: response)
        if (200..<300).contains(http.statusCode) {
            return ProviderValidationResult(providerID: configuration.id, status: .valid, message: "Provider validated.", availableModels: availableModels)
        }
        let message = Self.messageWithRequestID(
            Self.providerErrorMessage(from: data) ?? "Validation failed with HTTP \(http.statusCode).",
            requestID: Self.providerRequestID(from: http, body: data, providerKind: configuration.kind),
            providerKind: configuration.kind
        )
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
            return usesGeminiInteractionsAPI(chatRequest: chatRequest)
                ? try geminiInteractionsRequest(apiKey: apiKey, chatRequest: chatRequest)
                : try geminiRequest(apiKey: apiKey, chatRequest: chatRequest)
        case .voyageAI:
            throw InferenceError.unsupportedCapability("Voyage AI is configured for embeddings only.")
        }
    }

    private func streamingFormat(for chatRequest: ChatRequest) -> CloudProviderStreamFormat {
        if usesOpenAIResponsesAPI(chatRequest: chatRequest) {
            return .openAIResponses
        }
        switch configuration.kind {
        case .anthropic:
            return .anthropicMessages
        case .gemini:
            return usesGeminiInteractionsAPI(chatRequest: chatRequest) ? .geminiInteractions : .geminiGenerateContent
        case .openAI, .openAICompatible, .openRouter, .custom, .voyageAI:
            return .chatCompletions
        }
    }

    private func readAPIKey() async throws -> String? {
        let apiKey = try await secretStore.read(
            service: configuration.keychainService,
            account: configuration.keychainAccount
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return apiKey?.isEmpty == false ? apiKey : nil
    }

    private func openAICompatibleEmbeddingRequest(apiKey: String, embeddingRequest: EmbeddingRequest) throws -> URLRequest {
        var request = URLRequest(url: apiBaseURL.appending(path: "embeddings"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        addOpenAIClientRequestID(to: &request)

        let body = embeddingRequestBuilder.openAICompatibleBody(
            providerKind: configuration.kind,
            modelID: embeddingRequest.modelID,
            inputs: embeddingRequest.inputs,
            dimensions: embeddingRequest.dimensions,
            inputType: embeddingRequest.inputType
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body.anySendable)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func geminiEmbeddingRequest(apiKey: String, embeddingRequest: EmbeddingRequest) throws -> URLRequest {
        let plan = embeddingRequestBuilder.geminiBatchBody(
            modelID: embeddingRequest.modelID,
            inputs: embeddingRequest.inputs,
            dimensions: embeddingRequest.dimensions,
            inputType: embeddingRequest.inputType
        )
        let modelName = plan.modelName
        let url = configuration.baseURL.appending(path: "v1beta/\(modelName):batchEmbedContents")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: plan.body.anySendable)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func voyageEmbeddingRequest(apiKey: String, embeddingRequest: EmbeddingRequest) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appending(path: "embeddings"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = embeddingRequestBuilder.voyageBody(
            modelID: embeddingRequest.modelID,
            inputs: embeddingRequest.inputs,
            dimensions: embeddingRequest.dimensions,
            inputType: embeddingRequest.inputType
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body.anySendable)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func openAICompatibleRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let url = apiBaseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        addOpenAIClientRequestID(to: &request)
        let usesOpenAIReasoningParameters = usesOpenAIReasoningChatParameters(modelID: chatRequest.modelID)
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "stream_options": ["include_usage": true],
            "messages": try chatRequest.messages.map { message in
                try Self.openAIMessageObject(message, providerKind: configuration.kind)
            },
        ]
        body[usesOpenAIReasoningParameters ? "max_completion_tokens" : "max_tokens"] = openAICompletionTokenLimit(
            for: chatRequest,
            usesReasoningParameters: usesOpenAIReasoningParameters
        )
        if !usesOpenAIReasoningParameters {
            body["temperature"] = chatRequest.sampling.temperature
            body["top_p"] = chatRequest.sampling.topP
        } else {
            body["reasoning_effort"] = CloudProviderModelEligibility.openAIReasoningEffort(
                for: chatRequest.modelID,
                requested: chatRequest.sampling.openAIReasoningEffort
            ).rawValue
            body["verbosity"] = chatRequest.sampling.openAITextVerbosity.rawValue
        }
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map { Self.jsonSerializable($0.openAIFunctionToolObject()) }
            body["tool_choice"] = "auto"
            body["parallel_tool_calls"] = false
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func openAIResponsesRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let url = apiBaseURL.appending(path: "responses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        addOpenAIClientRequestID(to: &request)

        let payload = try Self.openAIResponsesPayload(from: chatRequest.messages)
        let usesReasoningControls = Self.isOpenAIReasoningModelID(chatRequest.modelID)
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "store": chatRequest.sampling.openAIResponseStorage == .stateful,
            "input": payload.input,
            "max_output_tokens": openAICompletionTokenLimit(for: chatRequest, usesReasoningParameters: usesReasoningControls),
            "truncation": "auto",
        ]
        if usesReasoningControls {
            body["reasoning"] = [
                "effort": CloudProviderModelEligibility.openAIReasoningEffort(
                    for: chatRequest.modelID,
                    requested: chatRequest.sampling.openAIReasoningEffort
                ).rawValue,
            ]
            body["text"] = ["verbosity": chatRequest.sampling.openAITextVerbosity.rawValue]
            if chatRequest.sampling.openAIResponseStorage == .statelessEncrypted {
                body["include"] = ["reasoning.encrypted_content"]
            }
        } else {
            body["temperature"] = chatRequest.sampling.temperature
            body["top_p"] = chatRequest.sampling.topP
        }
        if chatRequest.sampling.openAIResponseStorage == .stateful, let previousResponseID = payload.previousResponseID {
            body["previous_response_id"] = previousResponseID
        }
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map(Self.openAIResponsesFunctionToolObject)
            body["tool_choice"] = "auto"
            body["parallel_tool_calls"] = false
        }
        let instructions = payload.instructions
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
            request = URLRequest(url: apiBaseURL.appending(path: "models"))
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            addOpenAIClientRequestID(to: &request)
        case .anthropic:
            request = URLRequest(url: configuration.baseURL.appending(path: "v1/models"))
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            let components = URLComponents(url: configuration.baseURL.appending(path: "v1beta/models"), resolvingAgainstBaseURL: false)!
            request = URLRequest(url: components.url!)
            request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .voyageAI:
            return []
        }

        try applyExtraHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try Self.httpResponse(from: response)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudProviderError.providerRejectedRequest(
                statusCode: http.statusCode,
                message: Self.messageWithRequestID(
                    Self.providerErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                    requestID: Self.providerRequestID(from: http, body: data, providerKind: configuration.kind),
                    providerKind: configuration.kind
                )
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
            "messages": try chatRequest.messages.filter { $0.role != .system }.map(Self.anthropicMessageObject),
            "system": chatRequest.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n"),
        ]
        if shouldEnableAnthropicPromptCaching(for: chatRequest) {
            body["cache_control"] = ["type": "ephemeral"]
        }
        if let thinking = anthropicThinkingConfiguration(for: chatRequest.modelID) {
            body["thinking"] = thinking
            if chatRequest.sampling.topP >= 0.95, chatRequest.sampling.topP < 1 {
                body["top_p"] = chatRequest.sampling.topP
            }
        } else {
            body["temperature"] = chatRequest.sampling.temperature
            if chatRequest.sampling.topP < 1 {
                body["top_p"] = chatRequest.sampling.topP
            }
            if chatRequest.sampling.topK > 0 {
                body["top_k"] = chatRequest.sampling.topK
            }
        }
        let anthropicEffortOptions = CloudProviderModelEligibility.anthropicEffortOptions(for: chatRequest.modelID)
        if !anthropicEffortOptions.isEmpty {
            body["output_config"] = [
                "effort": CloudProviderModelEligibility.anthropicEffort(
                    for: chatRequest.modelID,
                    requested: chatRequest.sampling.anthropicEffort
                ).rawValue,
            ]
        }
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map { Self.jsonSerializable($0.anthropicToolObject()) }
            body["tool_choice"] = ["type": "auto"]
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
        guard usesOfficialOpenAIAPI else { return false }
        if Self.isOpenAIReasoningModelID(chatRequest.modelID) {
            return true
        }
        return chatRequest.messages.contains { message in
            !message.attachments.isEmpty
                || !message.toolCalls.isEmpty
                || message.role == .tool
                || message.providerMetadata[Self.openAIResponseIDMetadataKey]?.isEmpty == false
        }
    }

    private func shouldEnableAnthropicPromptCaching(for chatRequest: ChatRequest) -> Bool {
        guard configuration.kind == .anthropic else { return false }
        return chatRequest.messages.count > 2
            || chatRequest.allowsTools
            || chatRequest.messages.contains { !$0.attachments.isEmpty || $0.role == .system }
    }

    private func anthropicThinkingConfiguration(for modelID: ModelID) -> [String: Any]? {
        guard CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: modelID) else {
            return nil
        }
        return [
            "type": "adaptive",
            "display": "omitted",
        ]
    }

    private func usesGeminiInteractionsAPI(chatRequest: ChatRequest) -> Bool {
        guard configuration.kind == .gemini else { return false }
        let id = chatRequest.modelID.rawValue.lowercased()
        return id.contains("gemini-3") || id.contains("deep-research")
    }

    private var apiBaseURL: URL {
        guard usesOfficialOpenAIAPI else {
            return configuration.baseURL
        }
        return Self.openAIV1BaseURL(from: configuration.baseURL)
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

    private static func openAIV1BaseURL(from url: URL) -> URL {
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.split(separator: "/").last?.lowercased() == "v1" {
            return url
        }
        return url.appending(path: "v1")
    }

    private static func geminiAPIVersion(for modelID: ModelID) -> String {
        let id = modelID.rawValue.lowercased()
        if id.contains("preview") || id.contains("gemini-3") {
            return "v1beta"
        }
        return "v1"
    }

    private static func geminiRecommendedTemperature(for modelID: ModelID, requested: Float) -> Float {
        CloudProviderModelEligibility.geminiThinkingLevelOptions(for: modelID).isEmpty ? requested : 1.0
    }

    private func addOpenAIClientRequestID(to request: inout URLRequest) {
        guard usesOfficialOpenAIAPI else { return }
        request.addValue(UUID().uuidString, forHTTPHeaderField: "X-Client-Request-Id")
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

    private func geminiRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let version = Self.geminiAPIVersion(for: chatRequest.modelID)
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "\(version)/models/\(chatRequest.modelID.rawValue):streamGenerateContent"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let systemInstruction = chatRequest.messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        var generationConfig: [String: Any] = [
            "maxOutputTokens": chatRequest.sampling.maxTokens ?? AppSettingsSnapshot.defaultCloudMaxCompletionTokens,
            "temperature": Self.geminiRecommendedTemperature(for: chatRequest.modelID, requested: chatRequest.sampling.temperature),
            "topP": chatRequest.sampling.topP,
        ]
        if chatRequest.sampling.topK > 0 {
            generationConfig["topK"] = chatRequest.sampling.topK
        }
        let geminiThinkingLevelOptions = CloudProviderModelEligibility.geminiThinkingLevelOptions(for: chatRequest.modelID)
        if !geminiThinkingLevelOptions.isEmpty {
            generationConfig["thinkingConfig"] = [
                "thinkingLevel": CloudProviderModelEligibility.geminiThinkingLevel(
                    for: chatRequest.modelID,
                    requested: chatRequest.sampling.geminiThinkingLevel
                ).rawValue,
            ]
        }
        var body: [String: Any] = [
            "contents": try chatRequest.messages.filter { $0.role != .system }.map(Self.geminiContentObject),
            "generationConfig": generationConfig,
        ]
        if !systemInstruction.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": systemInstruction]],
            ]
        }
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = [[
                "functionDeclarations": chatRequest.availableTools.map {
                    Self.jsonSerializable($0.geminiFunctionDeclarationObject())
                },
            ]]
            body["toolConfig"] = [
                "functionCallingConfig": [
                    "mode": "AUTO",
                ],
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try applyExtraHeaders(to: &request)
        return request
    }

    private func geminiInteractionsRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        var components = URLComponents(url: configuration.baseURL.appending(path: "v1beta/interactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemInstruction = chatRequest.messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        var generationConfig: [String: Any] = [
            "max_output_tokens": chatRequest.sampling.maxTokens ?? AppSettingsSnapshot.defaultCloudMaxCompletionTokens,
            "temperature": Self.geminiRecommendedTemperature(for: chatRequest.modelID, requested: chatRequest.sampling.temperature),
            "top_p": chatRequest.sampling.topP,
            "thinking_summaries": "none",
        ]
        let geminiThinkingLevelOptions = CloudProviderModelEligibility.geminiThinkingLevelOptions(for: chatRequest.modelID)
        if !geminiThinkingLevelOptions.isEmpty {
            generationConfig["thinking_level"] = CloudProviderModelEligibility.geminiThinkingLevel(
                for: chatRequest.modelID,
                requested: chatRequest.sampling.geminiThinkingLevel
            ).rawValue
        }
        if chatRequest.sampling.topK > 0 {
            generationConfig["top_k"] = chatRequest.sampling.topK
        }

        var body: [String: Any] = [
            "stream": true,
            "store": true,
            "input": try Self.geminiInteractionInput(from: chatRequest.messages),
            "response_modalities": "text",
        ]
        if Self.isGeminiDeepResearchAgentID(chatRequest.modelID) {
            body["agent"] = chatRequest.modelID.rawValue
            body["agent_config"] = [
                "type": "deep-research",
                "thinking_summaries": "none",
                "visualization": "off",
            ]
        } else {
            body["model"] = chatRequest.modelID.rawValue
            body["generation_config"] = generationConfig
        }
        if !systemInstruction.isEmpty {
            body["system_instruction"] = systemInstruction
        }
        if let previousInteractionID = Self.latestGeminiInteractionID(from: chatRequest.messages) {
            body["previous_interaction_id"] = previousInteractionID
        }
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map(Self.geminiInteractionFunctionToolObject)
            body["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try applyExtraHeaders(to: &request)
        return request
    }

    private static func isGeminiDeepResearchAgentID(_ modelID: ModelID) -> Bool {
        modelID.rawValue.lowercased().contains("deep-research")
    }

    private static func openAIMessageObject(_ message: ChatMessage, providerKind: CloudProviderKind) throws -> [String: Any] {
        if message.role == .tool {
            return [
                "role": "tool",
                "tool_call_id": message.toolCallID ?? "",
                "content": message.content,
            ]
        }

        var object: [String: Any] = [
            "role": message.role.rawValue,
            "content": try openAIChatContent(from: message, providerKind: providerKind),
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

    private static func openAIChatContent(from message: ChatMessage, providerKind: CloudProviderKind) throws -> Any {
        let attachments = try normalizedCloudAttachments(from: message)
        guard !attachments.isEmpty else {
            return message.content
        }
        guard message.role == .user else {
            throw InferenceError.invalidRequest("Cloud attachments are only supported on user messages.")
        }

        var parts = [[String: Any]]()
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        for attachment in attachments {
            switch attachment.kind {
            case .image:
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": attachment.dataURL],
                ])
            case .pdf:
                guard providerKind == .openRouter else {
                    throw unsupportedAttachment(attachment, providerName: "this OpenAI-compatible provider")
                }
                parts.append([
                    "type": "file",
                    "file": [
                        "filename": attachment.fileName,
                        "file_data": attachment.dataURL,
                    ],
                ])
            case .textDocument:
                throw unsupportedAttachment(attachment, providerName: providerKind == .openRouter ? "OpenRouter" : "this OpenAI-compatible provider")
            }
        }
        return parts.isEmpty ? message.content : parts
    }

    private static func openAIResponsesPayload(from messages: [ChatMessage]) throws -> OpenAIResponsesPayload {
        let instructions = messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let previousResponse = messages.enumerated().last { _, message in
            message.providerMetadata[openAIResponseIDMetadataKey]?.isEmpty == false
        }
        let replayStartIndex = previousResponse.map { messages.index(after: $0.offset) } ?? messages.startIndex
        let replayMessages = messages[replayStartIndex...]
        let input = try replayMessages.reduce(into: [[String: Any]]()) { input, message in
            guard message.role != .system else { return }
            if message.role == .tool {
                input.append([
                    "type": "function_call_output",
                    "call_id": message.toolCallID ?? "",
                    "output": message.content,
                ])
                return
            }
            if message.role == .assistant,
               let outputItems = openAIStoredOutputItems(from: message) {
                input.append(contentsOf: outputItems)
                return
            }
            if message.role == .assistant, !message.toolCalls.isEmpty {
                for toolCall in message.toolCalls {
                    input.append([
                        "type": "function_call",
                        "call_id": toolCall.id,
                        "name": toolCall.name,
                        "arguments": toolCall.argumentsFragment,
                    ])
                }
                return
            }

            let content = try openAIResponsesMessageContent(from: message)
            if !content.isEmpty {
                input.append([
                    "role": message.role == .assistant ? "assistant" : "user",
                    "content": content,
                ])
            }
        }

        return OpenAIResponsesPayload(
            input: input,
            instructions: instructions,
            previousResponseID: previousResponse?.element.providerMetadata[openAIResponseIDMetadataKey]
        )
    }

    private static func openAIStoredOutputItems(from message: ChatMessage) -> [[String: Any]]? {
        guard let raw = message.providerMetadata[CloudProviderMetadataKeys.openAIOutputItemsJSON],
              let data = raw.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !items.isEmpty
        else {
            return nil
        }
        return items
    }

    private static func openAIResponsesMessageContent(from message: ChatMessage) throws -> [[String: Any]] {
        var content = [[String: Any]]()
        if !message.content.isEmpty {
            content.append([
                "type": message.role == .assistant ? "output_text" : "input_text",
                "text": message.content,
            ])
        }
        guard message.role == .user else {
            return content
        }
        for attachment in try normalizedCloudAttachments(from: message) {
            switch attachment.kind {
            case .image:
                content.append([
                    "type": "input_image",
                    "image_url": attachment.dataURL,
                    "detail": "auto",
                ])
            case .pdf, .textDocument:
                content.append([
                    "type": "input_file",
                    "filename": attachment.fileName,
                    "file_data": attachment.dataURL,
                ])
            }
        }
        return content
    }

    private static func anthropicImageBlock(from attachment: CloudAttachmentPayload) -> [String: Any] {
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": attachment.contentType,
                "data": attachment.base64Data,
            ],
        ]
    }

    private static func anthropicDocumentBlock(from attachment: CloudAttachmentPayload) -> [String: Any] {
        [
            "type": "document",
            "source": [
                "type": "base64",
                "media_type": attachment.contentType,
                "data": attachment.base64Data,
            ],
        ]
    }

    private static func anthropicTextDocumentBlock(from attachment: CloudAttachmentPayload) throws -> [String: Any] {
        [
            "type": "text",
            "text": try textDocumentPrompt(from: attachment),
        ]
    }

    private static func geminiInlinePart(from attachment: CloudAttachmentPayload) throws -> [String: Any] {
        let geminiAttachment = try geminiCompatibleAttachment(attachment)
        return [
            "inlineData": [
                "mimeType": geminiAttachment.contentType,
                "data": geminiAttachment.base64Data,
            ],
        ]
    }

    private static func openAIResponsesFunctionToolObject(_ spec: AnyToolSpec) -> [String: Any] {
        [
            "type": "function",
            "name": spec.name,
            "description": spec.description,
            "parameters": jsonSerializable((spec.inputJSONSchema ?? spec.inputSchema.jsonValue).anySendable),
        ]
    }

    private static func anthropicMessageObject(_ message: ChatMessage) throws -> [String: Any] {
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

        var content = anthropicThinkingContentBlocks(from: message)
        if message.role == .user {
            for attachment in try normalizedCloudAttachments(from: message) {
                switch attachment.kind {
                case .image:
                    content.append(anthropicImageBlock(from: attachment))
                case .pdf:
                    content.append(anthropicDocumentBlock(from: attachment))
                case .textDocument:
                    content.append(try anthropicTextDocumentBlock(from: attachment))
                }
            }
        } else if !message.attachments.isEmpty {
            throw InferenceError.invalidRequest("Cloud attachments are only supported on user messages.")
        }
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

    private static func anthropicThinkingContentBlocks(from message: ChatMessage) -> [[String: Any]] {
        guard message.role == .assistant,
              let rawContent = message.providerMetadata[anthropicThinkingContentMetadataKey],
              let data = rawContent.data(using: .utf8),
              let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        return blocks.filter { $0["type"] as? String == "thinking" }
    }

    private static func geminiContentObject(_ message: ChatMessage) throws -> [String: Any] {
        if message.role == .assistant,
           let rawContent = message.providerMetadata[geminiModelContentMetadataKey],
           let data = rawContent.data(using: .utf8),
           let content = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           content["role"] as? String == "model",
           content["parts"] is [[String: Any]] {
            return content
        }

        if message.role == .tool {
            var functionResponse: [String: Any] = [
                "name": message.toolName ?? "",
                "response": Self.jsonObject(fromJSONString: message.content) ?? ["result": message.content],
            ]
            if let toolCallID = message.toolCallID, !toolCallID.isEmpty {
                functionResponse["id"] = toolCallID
            }
            return [
                "role": "user",
                "parts": [["functionResponse": functionResponse]],
            ]
        }

        var parts = [[String: Any]]()
        if message.role == .user {
            for attachment in try normalizedCloudAttachments(from: message) {
                switch attachment.kind {
                case .image, .pdf:
                    parts.append(try geminiInlinePart(from: attachment))
                case .textDocument:
                    parts.append(["text": try textDocumentPrompt(from: attachment)])
                }
            }
        } else if !message.attachments.isEmpty {
            throw InferenceError.invalidRequest("Cloud attachments are only supported on user messages.")
        }
        if !message.content.isEmpty {
            parts.append(["text": message.content])
        }
        for toolCall in message.toolCalls {
            var functionCall: [String: Any] = [
                "name": toolCall.name,
                "args": Self.jsonObject(fromJSONString: toolCall.argumentsFragment) ?? [:],
            ]
            if !toolCall.id.isEmpty {
                functionCall["id"] = toolCall.id
            }
            parts.append(["functionCall": functionCall])
        }
        return [
            "role": message.role == .assistant ? "model" : "user",
            "parts": parts.isEmpty ? [["text": message.content]] : parts,
        ]
    }

    private static func latestGeminiInteractionID(from messages: [ChatMessage]) -> String? {
        messages.reversed().compactMap { message in
            let id = message.providerMetadata[geminiInteractionIDMetadataKey]
            return id?.isEmpty == false ? id : nil
        }.first
    }

    private static func geminiInteractionInput(from messages: [ChatMessage]) throws -> [[String: Any]] {
        try messages.reduce(into: [[String: Any]]()) { input, message in
            guard message.role != .system else { return }
            switch message.role {
            case .user:
                input.append([
                    "type": "user_input",
                    "content": try geminiInteractionContent(from: message),
                ])
            case .assistant:
                if !message.content.isEmpty {
                    input.append([
                        "type": "model_output",
                        "content": [["type": "text", "text": message.content]],
                    ])
                }
                for toolCall in message.toolCalls {
                    input.append([
                        "type": "function_call",
                        "id": toolCall.id,
                        "name": toolCall.name,
                        "arguments": Self.jsonObject(fromJSONString: toolCall.argumentsFragment) ?? [:],
                    ])
                }
            case .tool:
                input.append([
                    "type": "function_result",
                    "name": message.toolName ?? "",
                    "call_id": message.toolCallID ?? "",
                    "result": message.content,
                ])
            case .system:
                break
            }
        }
    }

    private static func geminiInteractionContent(from message: ChatMessage) throws -> [[String: Any]] {
        var content = [[String: Any]]()
        if !message.content.isEmpty {
            content.append(["type": "text", "text": message.content])
        }
        for attachment in try normalizedCloudAttachments(from: message) {
            switch attachment.kind {
            case .image:
                let geminiAttachment = try geminiCompatibleAttachment(attachment)
                content.append([
                    "type": "image",
                    "mime_type": geminiAttachment.contentType,
                    "data": geminiAttachment.base64Data,
                ])
            case .pdf:
                content.append([
                    "type": "document",
                    "mime_type": attachment.contentType,
                    "data": attachment.base64Data,
                ])
            case .textDocument:
                content.append(["type": "text", "text": try textDocumentPrompt(from: attachment)])
            }
        }
        return content.isEmpty ? [["type": "text", "text": message.content]] : content
    }

    private static func geminiInteractionFunctionToolObject(_ spec: AnyToolSpec) -> [String: Any] {
        [
            "type": "function",
            "name": spec.name,
            "description": spec.description,
            "parameters": jsonSerializable((spec.inputJSONSchema ?? spec.inputSchema.jsonValue).anySendable),
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

    private static func normalizedCloudAttachments(from message: ChatMessage) throws -> [CloudAttachmentPayload] {
        try message.attachments.map(normalizedCloudAttachment)
    }

    private static func normalizedCloudAttachment(_ attachment: ChatAttachment) throws -> CloudAttachmentPayload {
        let contentType = normalizedCloudAttachmentContentType(attachment.normalizedContentType)
        let kind: CloudAttachmentPayload.Kind
        switch attachment.cloudInputKind {
        case .image:
            kind = .image
        case .pdf:
            kind = .pdf
        case .textDocument:
            kind = .textDocument
        case .unsupported:
            throw InferenceError.unsupportedCapability("Cloud attachment \(attachment.fileName) has unsupported MIME type \(contentType).")
        }

        guard let localURL = attachment.localURL else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) is missing a local file URL.")
        }
        guard localURL.isFileURL else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) must be a local file.")
        }

        let data: Data
        do {
            data = try Data(contentsOf: localURL)
        } catch {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) could not be read from disk: \(error.localizedDescription)")
        }
        guard !data.isEmpty else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) is empty.")
        }

        let maxBytes = kind == .image ? maxInlineImageBytes : maxInlineFileBytes
        guard data.count <= maxBytes else {
            throw InferenceError.invalidRequest("Cloud attachment \(attachment.fileName) exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)) inline limit.")
        }

        let rawFileName = attachment.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = rawFileName.isEmpty ? localURL.lastPathComponent : rawFileName
        return CloudAttachmentPayload(
            kind: kind,
            fileName: fileName.isEmpty ? "attachment" : fileName,
            contentType: contentType,
            data: data
        )
    }

    private static func normalizedCloudAttachmentContentType(_ contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/jpg":
            return "image/jpeg"
        case "text/x-markdown":
            return "text/markdown"
        default:
            return contentType.lowercased()
        }
    }

    private static func unsupportedAttachment(_ attachment: CloudAttachmentPayload, providerName: String) -> InferenceError {
        .unsupportedCapability("\(providerName) does not support \(attachment.contentType) attachment inputs in Pines yet.")
    }

    private static func textDocumentPrompt(from attachment: CloudAttachmentPayload) throws -> String {
        guard let text = String(data: attachment.data, encoding: .utf8) else {
            throw InferenceError.invalidRequest("Cloud text attachment \(attachment.fileName) is not valid UTF-8.")
        }
        return """
        Attached file \(attachment.fileName) (\(attachment.contentType)):

        \(text)
        """
    }

    private static func geminiCompatibleAttachment(_ attachment: CloudAttachmentPayload) throws -> CloudAttachmentPayload {
        guard attachment.kind == .image,
              attachment.contentType == "image/gif"
        else {
            return attachment
        }
        let pngData = try pngDataFromFirstGIFFrame(attachment.data, fileName: attachment.fileName)
        return CloudAttachmentPayload(
            kind: .image,
            fileName: attachment.fileName.replacingFileExtension(with: "png"),
            contentType: "image/png",
            data: pngData
        )
    }

    private static func pngDataFromFirstGIFFrame(_ data: Data, fileName: String) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw InferenceError.invalidRequest("Gemini image attachment \(fileName) could not be decoded as a GIF.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw InferenceError.invalidRequest("Gemini image attachment \(fileName) could not be converted to PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw InferenceError.invalidRequest("Gemini image attachment \(fileName) could not be finalized as PNG.")
        }
        return output as Data
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

    private static func parseEmbeddingVectors(data: Data, providerKind: CloudProviderKind) throws -> [[Float]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudProviderError.invalidResponse
        }

        switch providerKind {
        case .gemini:
            if let embeddings = json["embeddings"] as? [[String: Any]] {
                return try embeddings.map { item in
                    guard let values = item["values"] as? [Double] else {
                        throw CloudProviderError.invalidResponse
                    }
                    return values.map(Float.init)
                }
            }
            if let embedding = json["embedding"] as? [String: Any],
               let values = embedding["values"] as? [Double] {
                return [values.map(Float.init)]
            }
            throw CloudProviderError.invalidResponse
        case .openAI, .openAICompatible, .openRouter, .voyageAI, .custom:
            guard let data = json["data"] as? [[String: Any]] else {
                throw CloudProviderError.invalidResponse
            }
            return try data.sorted { lhs, rhs in
                (lhs["index"] as? Int ?? 0) < (rhs["index"] as? Int ?? 0)
            }.map { item in
                if let values = item["embedding"] as? [Double] {
                    return values.map(Float.init)
                }
                if let values = item["embedding"] as? [Float] {
                    return values
                }
                throw CloudProviderError.invalidResponse
            }
        case .anthropic:
            throw InferenceError.unsupportedCapability("Anthropic does not provide a native embedding API.")
        }
    }

    private static func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw CloudProviderError.invalidResponse
        }
        return http
    }

    private static func normalizedEmbedding(_ vector: [Float]) -> [Float] {
        let magnitude = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    private static func messageWithRequestID(_ message: String, requestID: String?, providerKind: CloudProviderKind) -> String {
        guard let requestID, !requestID.isEmpty else { return message }
        return "\(message) (\(requestIDLabel(for: providerKind)): \(requestID))"
    }

    private static func requestIDLabel(for providerKind: CloudProviderKind) -> String {
        switch providerKind {
        case .anthropic:
            return "Anthropic request ID"
        case .gemini:
            return "Gemini request ID"
        case .voyageAI:
            return "Voyage AI request ID"
        case .openAI, .openAICompatible, .openRouter, .custom:
            return "OpenAI request ID"
        }
    }

    private static func providerRequestID(from response: HTTPURLResponse, body: Data?, providerKind: CloudProviderKind) -> String? {
        switch providerKind {
        case .anthropic:
            return response.value(forHTTPHeaderField: "request-id")
                ?? response.value(forHTTPHeaderField: "x-request-id")
                ?? requestIDFromErrorBody(body, keys: ["request_id"])
        case .gemini:
            return response.value(forHTTPHeaderField: "x-request-id")
                ?? response.value(forHTTPHeaderField: "x-goog-request-id")
                ?? response.value(forHTTPHeaderField: "x-cloud-trace-context")
        case .openAI, .openAICompatible, .openRouter, .voyageAI, .custom:
            return response.value(forHTTPHeaderField: "x-request-id")
        }
    }

    private static func requestIDFromErrorBody(_ body: Data?, keys: [String]) -> String? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return nil
        }
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func handleSSEDataLines(
        _ dataLines: [String],
        format: CloudProviderStreamFormat,
        parser: inout CloudProviderStreamParser,
        pendingFinish: inout InferenceFinish?,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) {
        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload != "[DONE]", let data = payload.data(using: .utf8) else { return }

        let output = parser.parse(data: data, format: format, providerKind: configuration.kind)
        if let finish = output.finish {
            pendingFinish = finish
        }
        for event in output.events {
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
                ?? (item["displayName"] as? String)
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
        case .voyageAI:
            if id.contains("voyage") { score += 300 }
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

}

private struct OpenAIResponsesPayload {
    var input: [[String: Any]]
    var instructions: String
    var previousResponseID: String?
}

private struct CloudAttachmentPayload {
    enum Kind {
        case image
        case pdf
        case textDocument
    }

    var kind: Kind
    var fileName: String
    var contentType: String
    var data: Data

    var base64Data: String {
        data.base64EncodedString()
    }

    var dataURL: String {
        "data:\(contentType);base64,\(base64Data)"
    }
}

private extension String {
    func replacingFileExtension(with newExtension: String) -> String {
        let url = URL(fileURLWithPath: self)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? "attachment.\(newExtension)" : "\(base).\(newExtension)"
    }
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
