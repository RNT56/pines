import Foundation
import CryptoKit
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
        if usesOpenAIResponsesAPI(chatRequest: request),
           request.openAIResponseOptions?.background == true || request.openAIOptions?.background == true {
            throw InferenceError.invalidRequest("OpenAI background Responses runs must be created through the provider lifecycle service, not the foreground chat stream.")
        }

        let streamingFormat = self.streamingFormat(for: request)
        let urlRequest = try await buildStreamingRequest(apiKey: apiKey, chatRequest: request)
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
            urlRequest = try await openAICompatibleEmbeddingRequest(apiKey: apiKey, embeddingRequest: request)
        case .gemini:
            urlRequest = try await geminiEmbeddingRequest(apiKey: apiKey, embeddingRequest: request)
        case .voyageAI:
            urlRequest = try await voyageEmbeddingRequest(apiKey: apiKey, embeddingRequest: request)
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
            request = try await voyageEmbeddingRequest(
                apiKey: apiKey,
                embeddingRequest: EmbeddingRequest(
                    modelID: defaults.modelID,
                    inputs: ["ping"],
                    dimensions: defaults.dimensions,
                    inputType: .query
                )
            )
        }

        try await applyExtraHeaders(to: &request)
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

    private func buildStreamingRequest(apiKey: String, chatRequest: ChatRequest) async throws -> URLRequest {
        if usesOpenAIResponsesAPI(chatRequest: chatRequest) {
            return try await openAIResponsesRequest(apiKey: apiKey, chatRequest: chatRequest)
        }

        switch configuration.kind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            return try await openAICompatibleRequest(apiKey: apiKey, chatRequest: chatRequest)
        case .anthropic:
            return try await anthropicRequest(apiKey: apiKey, chatRequest: chatRequest)
        case .gemini:
            return usesGeminiInteractionsAPI(chatRequest: chatRequest)
                ? try await geminiInteractionsRequest(apiKey: apiKey, chatRequest: chatRequest)
                : try await geminiRequest(apiKey: apiKey, chatRequest: chatRequest)
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

    private func openAICompatibleEmbeddingRequest(apiKey: String, embeddingRequest: EmbeddingRequest) async throws -> URLRequest {
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
        try await applyExtraHeaders(to: &request)
        return request
    }

    private func geminiEmbeddingRequest(apiKey: String, embeddingRequest: EmbeddingRequest) async throws -> URLRequest {
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
        try await applyExtraHeaders(to: &request)
        return request
    }

    private func voyageEmbeddingRequest(apiKey: String, embeddingRequest: EmbeddingRequest) async throws -> URLRequest {
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
        try await applyExtraHeaders(to: &request)
        return request
    }

    private func openAICompatibleRequest(apiKey: String, chatRequest: ChatRequest) async throws -> URLRequest {
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
        try await applyExtraHeaders(to: &request)
        return request
    }

    private func openAIResponsesRequest(apiKey: String, chatRequest: ChatRequest) async throws -> URLRequest {
        let url = apiBaseURL.appending(path: "responses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        addOpenAIClientRequestID(to: &request)

        let payload = try Self.openAIResponsesPayload(from: chatRequest.messages)
        let instructions = payload.instructions
        let responseOptions = chatRequest.openAIResponseOptions
        let requestOptions = chatRequest.openAIOptions
        let storageMode = responseOptions?.store ?? requestOptions?.store ?? chatRequest.sampling.openAIResponseStorage
        let promptCacheKey = requestOptions?.promptCacheKey ?? openAIPromptCacheKey(for: chatRequest, instructions: instructions)
        let usesReasoningControls = Self.isOpenAIReasoningModelID(chatRequest.modelID)
        let body = try Self.openAIResponsesRequestBody(
            chatRequest: chatRequest,
            payload: payload,
            storageMode: storageMode,
            promptCacheKey: promptCacheKey,
            safetyIdentifier: requestOptions?.safetyIdentifier ?? openAISafetyIdentifier(for: chatRequest),
            maxOutputTokens: openAICompletionTokenLimit(for: chatRequest, usesReasoningParameters: usesReasoningControls),
            nativeWebSearchEnabled: openAINativeWebSearchEnabled(for: chatRequest)
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await applyExtraHeaders(to: &request)
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

        try await applyExtraHeaders(to: &request)
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

    private func anthropicRequest(apiKey: String, chatRequest: ChatRequest) async throws -> URLRequest {
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
        let anthropicFunctionTools = chatRequest.allowsTools
            ? chatRequest.availableTools.map { Self.jsonSerializable($0.anthropicToolObject()) }
            : []
        let anthropicNativeTools = anthropicNativeWebSearchEnabled(for: chatRequest) ? [Self.anthropicWebSearchToolObject(options: chatRequest.webSearchOptions)] : []
        let anthropicTools = anthropicFunctionTools + anthropicNativeTools
        if !anthropicTools.isEmpty {
            body["tools"] = anthropicTools
            body["tool_choice"] = anthropicToolChoice(for: chatRequest, hasNativeSearch: !anthropicNativeTools.isEmpty)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await applyExtraHeaders(to: &request)
        return request
    }

    private func openAINativeWebSearchEnabled(for chatRequest: ChatRequest) -> Bool {
        guard usesOfficialOpenAIAPI else { return false }
        return chatRequest.sampling.cloudWebSearchMode != .off
    }

    private func anthropicNativeWebSearchEnabled(for chatRequest: ChatRequest) -> Bool {
        guard configuration.kind == .anthropic else { return false }
        return chatRequest.sampling.cloudWebSearchMode != .off
    }

    private func geminiNativeWebSearchEnabled(for chatRequest: ChatRequest, hasFunctionTools: Bool) -> Bool {
        guard configuration.kind == .gemini, chatRequest.sampling.cloudWebSearchMode != .off else { return false }
        return !hasFunctionTools || Self.supportsGeminiBuiltInAndFunctionToolCombination(chatRequest.modelID)
    }

    private static func openAIToolChoice(for chatRequest: ChatRequest, hasFunctionTools: Bool, hasNativeSearch: Bool) -> Any {
        guard hasNativeSearch else { return "auto" }
        guard chatRequest.sampling.cloudWebSearchMode == .required else { return "auto" }
        return ["type": "web_search"]
    }

    private func anthropicToolChoice(for chatRequest: ChatRequest, hasNativeSearch: Bool) -> [String: Any] {
        guard hasNativeSearch, chatRequest.sampling.cloudWebSearchMode == .required else {
            return ["type": "auto"]
        }
        return [
            "type": "tool",
            "name": "web_search",
        ]
    }

    private static func openAIWebSearchToolObject(options: CloudWebSearchOptions?) -> [String: Any] {
        let resolvedOptions = options ?? CloudWebSearchOptions()
        var tool: [String: Any] = [
            "type": "web_search",
            "search_context_size": resolvedOptions.contextSize.rawValue,
            "external_web_access": resolvedOptions.externalWebAccess,
        ]
        if let filters = openAIWebSearchFilters(from: resolvedOptions) {
            tool["filters"] = filters
        }
        if let userLocation = webSearchUserLocationObject(from: resolvedOptions.userLocation) {
            tool["user_location"] = userLocation
        }
        return tool
    }

    private static func openAITextFormatObject(from format: StructuredOutputFormat) -> [String: Any] {
        switch format {
        case .text:
            return ["type": "text"]
        case .jsonObject:
            return ["type": "json_object"]
        case let .jsonSchema(name, schema, strict):
            return [
                "type": "json_schema",
                "name": name,
                "schema": jsonObject(from: schema),
                "strict": strict,
            ]
        }
    }

    private static func openAITextFormatObject(from request: OpenAIStructuredOutputRequest) -> [String: Any] {
        var format: [String: Any] = [
            "type": "json_schema",
            "name": request.name,
            "schema": jsonObject(from: request.schema),
            "strict": request.strictness == .strict,
        ]
        if let description = request.description, !description.isEmpty {
            format["description"] = description
        }
        return format
    }

    static func openAIResponsesRequestBody(
        chatRequest: ChatRequest,
        payload: OpenAIResponsesPayload,
        storageMode: OpenAIResponseStorage,
        promptCacheKey: String,
        safetyIdentifier: String,
        maxOutputTokens: Int,
        nativeWebSearchEnabled: Bool
    ) throws -> [String: Any] {
        let responseOptions = chatRequest.openAIResponseOptions
        let requestOptions = chatRequest.openAIOptions
        let usesReasoningControls = isOpenAIReasoningModelID(chatRequest.modelID)
        var textConfiguration: [String: Any] = [
            "format": responseOptions?.structuredOutput.map { openAITextFormatObject(from: $0) }
                ?? openAITextFormatObject(from: chatRequest.structuredOutput),
        ]
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "store": storageMode == .stateful,
            "input": payload.input,
            "max_output_tokens": maxOutputTokens,
            "truncation": "auto",
            "text": textConfiguration,
        ]
        var includeValues = Set(requestOptions?.include ?? [])
        if nativeWebSearchEnabled {
            includeValues.insert("web_search_call.action.sources")
        }
        if usesReasoningControls {
            body["reasoning"] = [
                "effort": CloudProviderModelEligibility.openAIReasoningEffort(
                    for: chatRequest.modelID,
                    requested: chatRequest.sampling.openAIReasoningEffort
                ).rawValue,
            ]
            textConfiguration["verbosity"] = chatRequest.sampling.openAITextVerbosity.rawValue
            body["text"] = textConfiguration
            if storageMode == .statelessEncrypted {
                includeValues.insert("reasoning.encrypted_content")
            }
        } else {
            body["temperature"] = chatRequest.sampling.temperature
            body["top_p"] = chatRequest.sampling.topP
        }
        let previousResponseID = responseOptions?.previousResponseID?.rawValue ?? payload.previousResponseID
        if storageMode == .stateful, let previousResponseID, !previousResponseID.isEmpty {
            body["previous_response_id"] = previousResponseID
        }
        var metadata = requestOptions?.metadata ?? [:]
        metadata.merge(responseOptions?.metadata ?? [:], uniquingKeysWith: { _, new in new })
        metadata.merge([
            "pines_request_id": chatRequest.id.uuidString,
            "pines_execution_context": chatRequest.executionContext.rawValue,
            "pines_prompt_cache_key": promptCacheKey,
        ], uniquingKeysWith: { _, new in new })
        body["metadata"] = metadata
        body["prompt_cache_key"] = promptCacheKey
        if let retention = requestOptions?.promptCacheRetention, retention != .standard {
            body["prompt_cache_retention"] = retention.rawValue
        }
        body["safety_identifier"] = safetyIdentifier
        body["service_tier"] = requestOptions?.serviceTier.rawValue ?? OpenAIServiceTier.auto.rawValue
        body["background"] = responseOptions?.background ?? requestOptions?.background ?? false
        body["max_tool_calls"] = requestOptions?.maxToolCalls ?? (chatRequest.executionContext == .agent ? 8 : 4)
        if let conversationID = requestOptions?.conversationID, !conversationID.isEmpty {
            body["conversation"] = conversationID
        }

        let functionTools = chatRequest.allowsTools ? chatRequest.availableTools.map(openAIResponsesFunctionToolObject) : []
        let nativeSearchTools = nativeWebSearchEnabled ? [openAIWebSearchToolObject(options: chatRequest.webSearchOptions)] : []
        var hostedTools = try openAIHostedTools(for: chatRequest, includeValues: &includeValues)
        if hostedTools.isEmpty, let vectorStoreIDs = responseOptions?.vectorStoreIDs, !vectorStoreIDs.isEmpty {
            hostedTools.append(openAIFileSearchToolObject(vectorStoreIDs: vectorStoreIDs.map(\.rawValue), maxResults: nil))
            includeValues.insert("file_search_call.results")
        }
        let responseTools = functionTools + nativeSearchTools + hostedTools
        if !responseTools.isEmpty {
            body["tools"] = responseTools
            body["tool_choice"] = openAIToolChoice(for: chatRequest, hasFunctionTools: !functionTools.isEmpty, hasNativeSearch: !nativeSearchTools.isEmpty)
            body["parallel_tool_calls"] = false
        }
        if !includeValues.isEmpty {
            body["include"] = includeValues.sorted()
        }
        if !payload.instructions.isEmpty {
            body["instructions"] = payload.instructions
        }
        return body
    }

    private static func openAIHostedTools(for chatRequest: ChatRequest, includeValues: inout Set<String>) throws -> [[String: Any]] {
        var tools = [[String: Any]]()
        for tool in chatRequest.hostedTools {
            let mapped = try Self.openAIHostedToolObject(tool, executionContext: chatRequest.executionContext)
            tools.append(mapped.tool)
            includeValues.formUnion(mapped.include)
        }
        for tool in chatRequest.openAIResponseOptions?.hostedTools ?? [] {
            let mapped = try Self.openAIHostedToolObject(tool, executionContext: chatRequest.executionContext)
            tools.append(mapped.tool)
            includeValues.formUnion(mapped.include)
        }
        return tools
    }

    private static func openAIHostedToolObject(
        _ tool: HostedToolConfiguration,
        executionContext: ChatRequest.ExecutionContext
    ) throws -> (tool: [String: Any], include: [String]) {
        switch tool {
        case .webSearch:
            return (openAIWebSearchToolObject(options: nil), ["web_search_call.action.sources"])
        case let .fileSearch(vectorStoreIDs, maxResults):
            return (openAIFileSearchToolObject(vectorStoreIDs: vectorStoreIDs, maxResults: maxResults), ["file_search_call.results"])
        case let .codeInterpreter(containerID, memoryLimit):
            return (openAICodeInterpreterToolObject(containerID: containerID, memoryLimit: memoryLimit), ["code_interpreter_call.outputs"])
        case let .imageGeneration(action, quality, size, partialImages):
            return (openAIImageGenerationToolObject(action: action, quality: quality, size: size, partialImages: partialImages), [])
        case let .computerUse(displayWidth, displayHeight):
            try requireAgentContext(executionContext, toolName: "Computer Use")
            return (openAIComputerUseToolObject(displayWidth: displayWidth, displayHeight: displayHeight), [])
        case let .remoteMCP(serverLabel, serverURL, requireApproval):
            try requireAgentContext(executionContext, toolName: "remote MCP")
            return ([
                "type": "mcp",
                "server_label": serverLabel,
                "server_url": serverURL,
                "require_approval": requireApproval,
            ], [])
        case .toolSearch:
            try requireAgentContext(executionContext, toolName: "Tool Search")
            return (["type": "tool_search"], [])
        }
    }

    private static func openAIHostedToolObject(
        _ tool: OpenAIHostedToolRequest,
        executionContext: ChatRequest.ExecutionContext
    ) throws -> (tool: [String: Any], include: [String]) {
        switch tool.kind {
        case .webSearch:
            return (openAIWebSearchToolObject(options: nil), ["web_search_call.action.sources"])
        case .fileSearch:
            let maxResults = tool.configuration?.objectValue?["max_results"].flatMap(intValue)
            return (
                openAIFileSearchToolObject(vectorStoreIDs: tool.vectorStoreIDs.map(\.rawValue), maxResults: maxResults),
                ["file_search_call.results"]
            )
        case .codeInterpreter:
            let configuration = tool.configuration?.objectValue
            return (
                openAICodeInterpreterToolObject(
                    containerID: configuration?["container_id"]?.stringValue,
                    memoryLimit: configuration?["memory_limit"]?.stringValue
                ),
                ["code_interpreter_call.outputs"]
            )
        case .imageGeneration:
            let configuration = tool.configuration?.objectValue
            return (
                openAIImageGenerationToolObject(
                    action: configuration?["action"]?.stringValue,
                    quality: configuration?["quality"]?.stringValue,
                    size: configuration?["size"]?.stringValue,
                    partialImages: configuration?["partial_images"].flatMap(intValue)
                ),
                []
            )
        case .computerUse:
            try requireAgentContext(executionContext, toolName: "Computer Use")
            let configuration = tool.configuration?.objectValue
            return (
                openAIComputerUseToolObject(
                    displayWidth: configuration?["display_width"].flatMap(intValue),
                    displayHeight: configuration?["display_height"].flatMap(intValue)
                ),
                []
            )
        case .mcp:
            try requireAgentContext(executionContext, toolName: "remote MCP")
            guard let configuration = tool.configuration?.objectValue,
                  let serverLabel = configuration["server_label"]?.stringValue,
                  let serverURL = configuration["server_url"]?.stringValue
            else {
                throw InferenceError.invalidRequest("Remote MCP hosted tools require a server label and URL.")
            }
            var object: [String: Any] = [
                "type": "mcp",
                "server_label": serverLabel,
                "server_url": serverURL,
            ]
            if let approval = configuration["require_approval"]?.stringValue {
                object["require_approval"] = approval
            }
            return (object, [])
        case .toolSearch:
            try requireAgentContext(executionContext, toolName: "Tool Search")
            return (["type": "tool_search"], [])
        case .custom:
            guard let configuration = tool.configuration else {
                throw InferenceError.invalidRequest("Custom hosted tools require a provider configuration object.")
            }
            return (jsonObject(from: configuration) as? [String: Any] ?? [:], [])
        }
    }

    private static func openAIFileSearchToolObject(vectorStoreIDs: [String], maxResults: Int?) -> [String: Any] {
        var tool: [String: Any] = [
            "type": "file_search",
            "vector_store_ids": vectorStoreIDs,
        ]
        if let maxResults {
            tool["max_num_results"] = maxResults
        }
        return tool
    }

    private static func openAICodeInterpreterToolObject(containerID: String?, memoryLimit: String?) -> [String: Any] {
        var container: [String: Any] = containerID.map { ["type": "container_id", "id": $0] } ?? ["type": "auto"]
        if let memoryLimit, !memoryLimit.isEmpty {
            container["memory_limit"] = memoryLimit
        }
        return [
            "type": "code_interpreter",
            "container": container,
        ]
    }

    private static func openAIImageGenerationToolObject(
        action: String?,
        quality: String?,
        size: String?,
        partialImages: Int?
    ) -> [String: Any] {
        var tool: [String: Any] = ["type": "image_generation"]
        if let action, !action.isEmpty {
            tool["action"] = action
        }
        if let quality, !quality.isEmpty {
            tool["quality"] = quality
        }
        if let size, !size.isEmpty {
            tool["size"] = size
        }
        if let partialImages {
            tool["partial_images"] = partialImages
        }
        return tool
    }

    private static func openAIComputerUseToolObject(displayWidth: Int?, displayHeight: Int?) -> [String: Any] {
        var tool: [String: Any] = ["type": "computer_use_preview"]
        if let displayWidth {
            tool["display_width"] = displayWidth
        }
        if let displayHeight {
            tool["display_height"] = displayHeight
        }
        return tool
    }

    private static func requireAgentContext(_ executionContext: ChatRequest.ExecutionContext, toolName: String) throws {
        guard executionContext == .agent else {
            throw InferenceError.invalidRequest("\(toolName) hosted tools are only available in Agent runs.")
        }
    }

    private static func intValue(from value: JSONValue) -> Int? {
        if case let .number(number) = value {
            return Int(number)
        }
        return nil
    }

    private static func jsonObject(from value: JSONValue) -> Any {
        switch value {
        case let .object(object):
            return object.mapValues(jsonObject)
        case let .array(array):
            return array.map(jsonObject)
        case let .string(string):
            return string
        case let .number(number):
            return number
        case let .bool(bool):
            return bool
        case .null:
            return NSNull()
        }
    }

    private static func anthropicWebSearchToolObject(options: CloudWebSearchOptions?) -> [String: Any] {
        let resolvedOptions = options ?? CloudWebSearchOptions()
        var tool: [String: Any] = [
            "type": "web_search_20250305",
            "name": "web_search",
            "max_uses": 5,
        ]
        let allowedDomains = normalizedWebSearchDomains(resolvedOptions.allowedDomains)
        if !allowedDomains.isEmpty {
            tool["allowed_domains"] = allowedDomains
        }
        let blockedDomains = normalizedWebSearchDomains(resolvedOptions.blockedDomains)
        if !blockedDomains.isEmpty {
            tool["blocked_domains"] = blockedDomains
        }
        if let userLocation = webSearchUserLocationObject(from: resolvedOptions.userLocation) {
            tool["user_location"] = userLocation
        }
        return tool
    }

    private static func openAIWebSearchFilters(from options: CloudWebSearchOptions) -> [String: Any]? {
        let allowedDomains = normalizedWebSearchDomains(options.allowedDomains)
        let blockedDomains = normalizedWebSearchDomains(options.blockedDomains)
        guard !allowedDomains.isEmpty || !blockedDomains.isEmpty else { return nil }
        var filters = [String: Any]()
        if !allowedDomains.isEmpty {
            filters["allowed_domains"] = allowedDomains
        }
        if !blockedDomains.isEmpty {
            filters["blocked_domains"] = blockedDomains
        }
        return filters
    }

    private static func webSearchUserLocationObject(from location: CloudWebSearchUserLocation?) -> [String: Any]? {
        guard let location, !location.isEmpty else { return nil }
        var object: [String: Any] = ["type": "approximate"]
        if let city = normalizedWebSearchString(location.city) {
            object["city"] = city
        }
        if let region = normalizedWebSearchString(location.region) {
            object["region"] = region
        }
        if let country = normalizedWebSearchString(location.country) {
            object["country"] = country
        }
        if let timezone = normalizedWebSearchString(location.timezone) {
            object["timezone"] = timezone
        }
        return object.count > 1 ? object : nil
    }

    private static func normalizedWebSearchString(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedWebSearchDomains(_ domains: [String]) -> [String] {
        var seen = Set<String>()
        return domains.compactMap { domain in
            var cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let url = URL(string: cleaned), let host = url.host(percentEncoded: false) {
                cleaned = host
            }
            if cleaned.hasPrefix("https://") {
                cleaned.removeFirst("https://".count)
            } else if cleaned.hasPrefix("http://") {
                cleaned.removeFirst("http://".count)
            }
            cleaned = cleaned.split(separator: "/").first.map(String.init) ?? cleaned
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }
    }

    private static func supportsGeminiBuiltInAndFunctionToolCombination(_ modelID: ModelID) -> Bool {
        !CloudProviderModelEligibility.geminiThinkingLevelOptions(for: modelID).isEmpty
    }

    private func usesOpenAIReasoningChatParameters(modelID: ModelID) -> Bool {
        guard usesOfficialOpenAIAPI else { return false }
        return Self.isOpenAIReasoningModelID(modelID)
    }

    private func usesOpenAIResponsesAPI(chatRequest: ChatRequest) -> Bool {
        guard usesOfficialOpenAIAPI else { return false }
        return true
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
        return !CloudProviderModelEligibility.geminiThinkingLevelOptions(for: chatRequest.modelID).isEmpty
            || id.contains("deep-research")
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
        if id.contains("preview") || !CloudProviderModelEligibility.geminiThinkingLevelOptions(for: modelID).isEmpty {
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

    private func openAIPromptCacheKey(for chatRequest: ChatRequest, instructions: String) -> String {
        let firstStableUserText = chatRequest.messages.first { $0.role == .user }?.content ?? ""
        let rawScope = [
            configuration.id.rawValue,
            chatRequest.modelID.rawValue,
            chatRequest.executionContext.rawValue,
            String(instructions.prefix(2048)),
            String(firstStableUserText.prefix(512)),
        ].joined(separator: "\u{1F}")
        return "pines_" + Self.sha256Hex(rawScope).prefix(48)
    }

    private func openAISafetyIdentifier(for chatRequest: ChatRequest) -> String {
        let rawScope = [
            "pines",
            configuration.id.rawValue,
            chatRequest.executionContext.rawValue,
        ].joined(separator: "\u{1F}")
        return String(Self.sha256Hex(rawScope).prefix(64))
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isOpenAIReasoningModelID(_ modelID: ModelID) -> Bool {
        let id = modelID.rawValue.lowercased()
        let modelName = id
            .split(separator: "/")
            .last
            .map(String.init) ?? id
        return !CloudProviderModelEligibility.openAIReasoningEffortOptions(for: ModelID(rawValue: modelName)).isEmpty
            || CloudProviderModelEligibility.isOpenAIOSeries(modelName)
    }

    private func geminiRequest(apiKey: String, chatRequest: ChatRequest) async throws -> URLRequest {
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
        generationConfig.merge(Self.geminiGenerationConfigStructuredOutput(from: chatRequest.structuredOutput, usesSnakeCase: false)) { _, new in new }
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
        var geminiTools = [[String: Any]]()
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            geminiTools.append([
                "functionDeclarations": chatRequest.availableTools.map {
                    Self.jsonSerializable($0.geminiFunctionDeclarationObject())
                },
            ])
            body["toolConfig"] = [
                "functionCallingConfig": [
                    "mode": "AUTO",
                ],
            ]
        }
        if geminiNativeWebSearchEnabled(for: chatRequest, hasFunctionTools: chatRequest.allowsTools && !chatRequest.availableTools.isEmpty) {
            geminiTools.append(["google_search": [:] as [String: Any]])
        }
        geminiTools.append(contentsOf: try geminiHostedTools(for: chatRequest, usesInteractionsAPI: false))
        if !geminiTools.isEmpty {
            body["tools"] = geminiTools
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await applyExtraHeaders(to: &request)
        return request
    }

    private func geminiInteractionsRequest(apiKey: String, chatRequest: ChatRequest) async throws -> URLRequest {
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
        generationConfig.merge(Self.geminiGenerationConfigStructuredOutput(from: chatRequest.structuredOutput, usesSnakeCase: true)) { _, new in new }

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
        var geminiInteractionTools = chatRequest.allowsTools ? chatRequest.availableTools.map(Self.geminiInteractionFunctionToolObject) : []
        if geminiNativeWebSearchEnabled(for: chatRequest, hasFunctionTools: chatRequest.allowsTools && !chatRequest.availableTools.isEmpty) {
            geminiInteractionTools.append(["type": "google_search"])
        }
        geminiInteractionTools.append(contentsOf: try geminiHostedTools(for: chatRequest, usesInteractionsAPI: true))
        if !geminiInteractionTools.isEmpty {
            body["tools"] = geminiInteractionTools
            body["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await applyExtraHeaders(to: &request)
        return request
    }

    private static func isGeminiDeepResearchAgentID(_ modelID: ModelID) -> Bool {
        modelID.rawValue.lowercased().contains("deep-research")
    }

    private static func geminiGenerationConfigStructuredOutput(from format: StructuredOutputFormat, usesSnakeCase: Bool) -> [String: Any] {
        let mimeTypeKey = usesSnakeCase ? "response_mime_type" : "responseMimeType"
        let schemaKey = usesSnakeCase ? "response_schema" : "responseSchema"
        switch format {
        case .text:
            return [:]
        case .jsonObject:
            return [mimeTypeKey: "application/json"]
        case let .jsonSchema(_, schema, _):
            return [
                mimeTypeKey: "application/json",
                schemaKey: jsonObject(from: schema),
            ]
        }
    }

    private func geminiHostedTools(for chatRequest: ChatRequest, usesInteractionsAPI: Bool) throws -> [[String: Any]] {
        try chatRequest.hostedTools.map { tool in
            try Self.geminiHostedToolObject(tool, executionContext: chatRequest.executionContext, usesInteractionsAPI: usesInteractionsAPI)
        }
    }

    private static func geminiHostedToolObject(
        _ tool: HostedToolConfiguration,
        executionContext: ChatRequest.ExecutionContext,
        usesInteractionsAPI: Bool
    ) throws -> [String: Any] {
        switch tool {
        case .codeInterpreter:
            try requireAgentContext(executionContext, toolName: "Gemini code execution")
            return usesInteractionsAPI ? ["type": "code_execution"] : ["codeExecution": [:] as [String: Any]]
        case .webSearch:
            return usesInteractionsAPI ? ["type": "url_context"] : ["urlContext": [:] as [String: Any]]
        case .fileSearch:
            throw InferenceError.unsupportedCapability("Gemini does not support Pines hosted file search. Use Gemini fileData parts or cached contents instead.")
        case .imageGeneration:
            throw InferenceError.unsupportedCapability("Gemini image generation is not available through Pines hosted tools yet.")
        case .computerUse, .remoteMCP, .toolSearch:
            throw InferenceError.unsupportedCapability("This hosted tool is not supported by Gemini.")
        }
    }

    private func handleSSEEvent(
        _ event: CloudProviderSSEEvent,
        format: CloudProviderStreamFormat,
        parser: inout CloudProviderStreamParser,
        pendingFinish: inout InferenceFinish?,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) {
        let eventTypeField = format == .geminiInteractions ? "event_type" : "type"
        guard let data = event.jsonData(eventTypeField: eventTypeField) else { return }

        let output = parser.parse(data: data, format: format, providerKind: configuration.kind)
        if let finish = output.finish {
            pendingFinish = finish
        }
        for event in output.events {
            continuation.yield(event)
        }
    }

    private func applyExtraHeaders(to request: inout URLRequest) async throws {
        if let url = request.url {
            try EndpointSecurityPolicy().validate(
                url,
                useCase: .cloudProvider,
                allowsExplicitLocalHTTP: configuration.allowInsecureLocalHTTP
            )
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
