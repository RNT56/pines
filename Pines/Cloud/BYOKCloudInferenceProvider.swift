import Foundation
import ImageIO
import PinesCore
import UniformTypeIdentifiers

struct BYOKCloudInferenceProvider: InferenceProvider {
    private static let openAIReasoningDefaultMaxCompletionTokens = 16_384
    static let openAIResponseIDMetadataKey = CloudProviderMetadataKeys.openAIResponseID
    static let openAIRequestIDMetadataKey = CloudProviderMetadataKeys.openAIRequestID
    static let openAIClientRequestIDMetadataKey = CloudProviderMetadataKeys.openAIClientRequestID
    static let anthropicMessageIDMetadataKey = CloudProviderMetadataKeys.anthropicMessageID
    static let anthropicRequestIDMetadataKey = CloudProviderMetadataKeys.anthropicRequestID
    static let anthropicThinkingContentMetadataKey = CloudProviderMetadataKeys.anthropicThinkingContentJSON
    static let geminiResponseIDMetadataKey = CloudProviderMetadataKeys.geminiResponseID
    static let geminiModelVersionMetadataKey = CloudProviderMetadataKeys.geminiModelVersion
    static let geminiRequestIDMetadataKey = CloudProviderMetadataKeys.geminiRequestID
    static let geminiModelContentMetadataKey = CloudProviderMetadataKeys.geminiModelContentJSON
    static let geminiInteractionIDMetadataKey = CloudProviderMetadataKeys.geminiInteractionID
    static let maxInlineImageBytes = 20 * 1024 * 1024
    static let maxInlineFileBytes = 50 * 1024 * 1024

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

                    var sseDecoder = CloudProviderSSEStreamDecoder()
                    var streamParser = CloudProviderStreamParser()
                    streamParser.recordRequestMetadata(
                        providerKind: configuration.kind,
                        serverRequestID: Self.providerRequestID(from: http, body: nil, providerKind: configuration.kind),
                        clientRequestID: clientRequestID
                    )
                    var pendingFinish: InferenceFinish?
                    for try await rawLine in bytes.lines {
                        guard !Task.isCancelled else { throw InferenceError.cancelled }
                        if let event = sseDecoder.ingest(rawLine) {
                            handleSSEEvent(event, format: streamingFormat, parser: &streamParser, pendingFinish: &pendingFinish, continuation: continuation)
                        }
                    }
                    if let event = sseDecoder.finish() {
                        handleSSEEvent(event, format: streamingFormat, parser: &streamParser, pendingFinish: &pendingFinish, continuation: continuation)
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

        let availableModels: [ModelID]
        let catalogWarning: String?
        if configuration.kind == .voyageAI {
            availableModels = []
            catalogWarning = nil
        } else {
            do {
                availableModels = try await listTextModels(apiKey: apiKey).map(\.id)
                catalogWarning = nil
            } catch {
                availableModels = []
                catalogWarning = "Model catalog unavailable: \(error.localizedDescription)"
            }
        }

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
            return ProviderValidationResult(
                providerID: configuration.id,
                status: .valid,
                message: catalogWarning.map { "Provider validated. \($0)" } ?? "Provider validated.",
                availableModels: availableModels
            )
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
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        addOpenAIClientRequestID(to: &request)

        let payload = try Self.openAIResponsesPayload(from: chatRequest.messages)
        let usesReasoningControls = Self.isOpenAIReasoningModelID(chatRequest.modelID)
        var textConfiguration: [String: Any] = [
            "format": ["type": "text"],
        ]
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "store": chatRequest.sampling.openAIResponseStorage == .stateful,
            "input": payload.input,
            "max_output_tokens": openAICompletionTokenLimit(for: chatRequest, usesReasoningParameters: usesReasoningControls),
            "truncation": "auto",
            "text": textConfiguration,
        ]
        if usesReasoningControls {
            body["reasoning"] = [
                "effort": CloudProviderModelEligibility.openAIReasoningEffort(
                    for: chatRequest.modelID,
                    requested: chatRequest.sampling.openAIReasoningEffort
                ).rawValue,
            ]
            textConfiguration["verbosity"] = chatRequest.sampling.openAITextVerbosity.rawValue
            body["text"] = textConfiguration
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

    private func handleSSEEvent(
        _ event: CloudProviderSSEEvent,
        format: CloudProviderStreamFormat,
        parser: inout CloudProviderStreamParser,
        pendingFinish: inout InferenceFinish?,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) {
        guard let data = event.jsonData() else { return }

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
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            return 0
        }
        guard let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
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
