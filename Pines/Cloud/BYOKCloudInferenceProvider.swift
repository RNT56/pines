import Foundation
import ImageIO
import PinesCore
import UniformTypeIdentifiers

struct BYOKCloudInferenceProvider: InferenceProvider {
    private static let openAIReasoningDefaultMaxCompletionTokens = 16_384
    fileprivate static let openAIResponseIDMetadataKey = "openai.response_id"
    fileprivate static let openAIRequestIDMetadataKey = "openai.request_id"
    fileprivate static let openAIClientRequestIDMetadataKey = "openai.client_request_id"
    fileprivate static let anthropicMessageIDMetadataKey = "anthropic.message_id"
    fileprivate static let anthropicRequestIDMetadataKey = "anthropic.request_id"
    fileprivate static let geminiResponseIDMetadataKey = "gemini.response_id"
    fileprivate static let geminiModelVersionMetadataKey = "gemini.model_version"
    fileprivate static let geminiRequestIDMetadataKey = "gemini.request_id"
    fileprivate static let geminiModelContentMetadataKey = "gemini.model_content_json"
    fileprivate static let maxInlineImageBytes = 20 * 1024 * 1024
    fileprivate static let maxInlineFileBytes = 50 * 1024 * 1024

    let configuration: CloudProviderConfiguration
    let secretStore: any SecretStore

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
                    var toolState = CloudToolCallStreamState()
                    toolState.recordRequestMetadata(
                        providerKind: configuration.kind,
                        serverRequestID: Self.providerRequestID(from: http, body: nil, providerKind: configuration.kind),
                        clientRequestID: clientRequestID
                    )
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
        }

        try applyExtraHeaders(to: &request)
        let (data, http) = try await URLSession.shared.data(for: request)
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
            return try geminiRequest(apiKey: apiKey, chatRequest: chatRequest)
        }
    }

    private func streamingFormat(for chatRequest: ChatRequest) -> CloudStreamingFormat {
        if usesOpenAIResponsesAPI(chatRequest: chatRequest) {
            return .openAIResponses
        }
        switch configuration.kind {
        case .anthropic:
            return .anthropicMessages
        case .gemini:
            return .geminiGenerateContent
        case .openAI, .openAICompatible, .openRouter, .custom:
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
            body["reasoning_effort"] = "low"
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
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "store": true,
            "input": payload.input,
            "max_output_tokens": openAICompletionTokenLimit(for: chatRequest, usesReasoningParameters: true),
            "reasoning": ["effort": "low"],
            "text": ["verbosity": "low"],
        ]
        if let previousResponseID = payload.previousResponseID {
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
        }

        try applyExtraHeaders(to: &request)
        let (data, http) = try await URLSession.shared.data(for: request)
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
            "temperature": chatRequest.sampling.temperature,
            "messages": try chatRequest.messages.filter { $0.role != .system }.map(Self.anthropicMessageObject),
            "system": chatRequest.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n"),
        ]
        if chatRequest.sampling.topP < 1 {
            body["top_p"] = chatRequest.sampling.topP
        }
        if chatRequest.sampling.topK > 0 {
            body["top_k"] = chatRequest.sampling.topK
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
        usesOfficialOpenAIAPI
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

    private func fallbackFinish(
        format: CloudStreamingFormat,
        state: CloudToolCallStreamState,
        chatRequest: ChatRequest
    ) -> InferenceFinish {
        switch format {
        case .openAIResponses:
            return InferenceFinish(
                reason: .stop,
                message: Self.openAIResponsesEmptyOutputMessage(response: nil, eventTypes: state.openAIResponsesEventTypes),
                providerMetadata: state.openAIProviderMetadata
            )
        case .chatCompletions:
            guard usesOfficialOpenAIAPI,
                  usesOpenAIReasoningChatParameters(modelID: chatRequest.modelID)
            else {
                return InferenceFinish(reason: .stop)
            }
            return InferenceFinish(
                reason: .stop,
                message: "Pines received an empty OpenAI Chat Completions stream for \(chatRequest.modelID.rawValue). Official OpenAI reasoning models should use the Responses API; check that the provider base URL is https://api.openai.com/v1.",
                providerMetadata: state.openAIProviderMetadata
            )
        case .anthropicMessages:
            return InferenceFinish(reason: .stop, providerMetadata: state.anthropicProviderMetadata)
        case .geminiGenerateContent:
            return InferenceFinish(reason: state.geminiCompletedToolCallIDs.isEmpty ? .stop : .toolCall, providerMetadata: state.geminiProviderMetadata)
        }
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
            "temperature": chatRequest.sampling.temperature,
            "topP": chatRequest.sampling.topP,
        ]
        if chatRequest.sampling.topK > 0 {
            generationConfig["topK"] = chatRequest.sampling.topK
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

        var content = [[String: Any]]()
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
        case .openAI, .openAICompatible, .openRouter, .custom:
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
            if type == "message_start",
               let message = json["message"] as? [String: Any] {
                state.recordAnthropicMessage(message)
                if let usage = message["usage"] as? [String: Any],
                   let metrics = anthropicMetrics(from: usage) {
                    events.append(.metrics(metrics))
                }
            }
            if type == "content_block_start",
               let index = json["index"] as? Int,
               let block = json["content_block"] as? [String: Any] {
                if block["type"] as? String == "tool_use" {
                    state.anthropicToolIndex = index
                    state.anthropicToolID = block["id"] as? String
                    state.anthropicToolName = block["name"] as? String
                    state.anthropicArguments = jsonString(from: block["input"]) ?? ""
                }
                if block["type"] as? String == "text",
                   let text = block["text"] as? String,
                   !text.isEmpty {
                    events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                }
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
            if type == "message_delta" {
                if let usage = json["usage"] as? [String: Any],
                   let metrics = anthropicMetrics(from: usage) {
                    events.append(.metrics(metrics))
                }
                if let delta = json["delta"] as? [String: Any],
                   let stopReason = delta["stop_reason"] as? String {
                    pendingFinish = anthropicFinish(from: stopReason, metadata: state.anthropicProviderMetadata)
                }
            }
            if type == "error" {
                let error = json["error"] as? [String: Any]
                pendingFinish = InferenceFinish(
                    reason: .error,
                    message: error?["message"] as? String ?? "Anthropic returned a streaming error.",
                    providerMetadata: state.anthropicProviderMetadata
                )
            }
        case .gemini:
            state.recordGeminiResponse(json)
            if let promptFeedback = json["promptFeedback"] as? [String: Any],
               let finish = geminiPromptFeedbackFinish(from: promptFeedback, metadata: state.geminiProviderMetadata) {
                pendingFinish = finish
            }
            if let usage = json["usageMetadata"] as? [String: Any],
               let metrics = geminiMetrics(from: usage) {
                events.append(.metrics(metrics))
            }
            let candidates = json["candidates"] as? [[String: Any]]
            for candidate in candidates ?? [] {
                if let content = candidate["content"] as? [String: Any] {
                    state.recordGeminiModelContent(content)
                    let parts = content["parts"] as? [[String: Any]]
                    for part in parts ?? [] {
                        if part["thought"] as? Bool == true {
                            continue
                        }
                        if let text = part["text"] as? String, !text.isEmpty {
                            events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                        }
                        if let call = part["functionCall"] as? [String: Any],
                           let name = call["name"] as? String {
                            let toolCall = ToolCallDelta(
                                id: (call["id"] as? String) ?? UUID().uuidString,
                                name: name,
                                argumentsFragment: jsonString(from: call["args"]) ?? "{}",
                                isComplete: true
                            )
                            if state.markGeminiToolCallCompleted(toolCall) {
                                events.append(.toolCall(toolCall))
                            }
                        }
                    }
                }
                if let finishReason = candidate["finishReason"] as? String {
                    pendingFinish = geminiFinish(
                        from: finishReason,
                        hasToolCalls: !state.geminiCompletedToolCallIDs.isEmpty,
                        metadata: state.geminiProviderMetadata
                    )
                }
            }
        case .openAI, .openAICompatible, .openRouter, .custom:
            let choices = json["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            if let text = openAIChatCompletionText(from: delta?["content"]), !text.isEmpty {
                state.openAIChatCompletionTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
            if let text = openAIChatCompletionText(from: delta?["refusal"]), !text.isEmpty {
                state.openAIChatCompletionTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
            let message = choices?.first?["message"] as? [String: Any]
            if !state.openAIChatCompletionTextEmitted,
               let text = openAIChatCompletionText(from: message?["content"]),
               !text.isEmpty {
                state.openAIChatCompletionTextEmitted = true
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
        if let response = json["response"] as? [String: Any] {
            state.recordOpenAIResponse(response)
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
            if !state.openAIResponsesTextEmitted,
               let item = json["item"] as? [String: Any],
               let text = openAIResponsesOutputText(fromOutputItem: item),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                return [.token(TokenDelta(kind: .token, text: text, tokenCount: 1))]
            }
        case "response.output_item.done":
            if let item = json["item"] as? [String: Any] {
                if !state.openAIResponsesTextEmitted,
                   let text = openAIResponsesOutputText(fromOutputItem: item),
                   !text.isEmpty {
                    state.openAIResponsesTextEmitted = true
                    return [.token(TokenDelta(kind: .token, text: text, tokenCount: 1))]
                }
                if let toolCall = openAIResponsesFunctionCall(fromOutputItem: item),
                   state.markOpenAIToolCallCompleted(toolCall) {
                    pendingFinish = InferenceFinish(reason: .toolCall, providerMetadata: state.openAIProviderMetadata)
                    return [.toolCall(toolCall)]
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
        case "response.content_part.added":
            if !state.openAIResponsesTextEmitted,
               let part = json["part"] as? [String: Any],
               let text = openAIResponsesOutputText(fromContentPart: part),
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
                let toolCall = ToolCallDelta(
                    id: state.openAIToolIDs[index] ?? UUID().uuidString,
                    name: name,
                    argumentsFragment: state.openAIArguments[index] ?? "{}",
                    isComplete: true
                )
                state.openAIToolIDs.removeValue(forKey: index)
                state.openAIToolNames.removeValue(forKey: index)
                state.openAIArguments.removeValue(forKey: index)
                if state.markOpenAIToolCallCompleted(toolCall) {
                    pendingFinish = InferenceFinish(reason: .toolCall, providerMetadata: state.openAIProviderMetadata)
                    return [.toolCall(toolCall)]
                }
            }
        case "response.completed", "response.done":
            let response = json["response"] as? [String: Any]
            var events = [InferenceStreamEvent]()
            if !state.openAIResponsesTextEmitted,
               let response,
               let text = openAIResponsesOutputText(from: response),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
            if let response {
                for toolCall in openAIResponsesFunctionCalls(from: response) where state.markOpenAIToolCallCompleted(toolCall) {
                    events.append(.toolCall(toolCall))
                }
                if let metrics = openAIResponsesMetrics(from: response) {
                    events.append(.metrics(metrics))
                }
            }
            let finishReason: InferenceFinishReason = events.contains { event in
                if case .toolCall = event { return true }
                return false
            } ? .toolCall : .stop
            pendingFinish = InferenceFinish(
                reason: finishReason,
                message: finishReason == .stop && events.isEmpty && !state.openAIResponsesTextEmitted
                    ? openAIResponsesEmptyOutputMessage(response: response, eventTypes: state.openAIResponsesEventTypes)
                    : nil,
                providerMetadata: state.openAIProviderMetadata
            )
            return events
        case "response.incomplete":
            let response = json["response"] as? [String: Any]
            let details = response?["incomplete_details"] as? [String: Any]
            let reason = details?["reason"] as? String
            pendingFinish = InferenceFinish(
                reason: reason == "max_output_tokens" ? .length : .error,
                message: reason == "max_output_tokens"
                    ? "The selected OpenAI model used its max output token budget before producing visible output."
                    : "The selected OpenAI model returned an incomplete response.",
                providerMetadata: state.openAIProviderMetadata
            )
        case "response.failed":
            let response = json["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            pendingFinish = InferenceFinish(
                reason: .error,
                message: error?["message"] as? String ?? "The selected OpenAI model failed to produce a response.",
                providerMetadata: state.openAIProviderMetadata
            )
        default:
            break
        }
        return []
    }

    private static func openAIResponsesFunctionCalls(from response: [String: Any]) -> [ToolCallDelta] {
        guard let output = response["output"] as? [[String: Any]] else { return [] }
        return output.compactMap(openAIResponsesFunctionCall(fromOutputItem:))
    }

    private static func openAIResponsesFunctionCall(fromOutputItem item: [String: Any]) -> ToolCallDelta? {
        guard item["type"] as? String == "function_call",
              let name = item["name"] as? String
        else {
            return nil
        }
        return ToolCallDelta(
            id: (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString,
            name: name,
            argumentsFragment: item["arguments"] as? String ?? "{}",
            isComplete: true
        )
    }

    private static func openAIResponsesMetrics(from response: [String: Any]) -> InferenceMetrics? {
        guard let usage = response["usage"] as? [String: Any] else { return nil }
        let inputTokens = usage["input_tokens"] as? Int
            ?? usage["prompt_tokens"] as? Int
            ?? 0
        let outputTokens = usage["output_tokens"] as? Int
            ?? usage["completion_tokens"] as? Int
            ?? 0
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func openAIResponsesOutputText(from response: [String: Any]) -> String? {
        guard let output = response["output"] as? [[String: Any]] else { return nil }
        let parts = output.compactMap(openAIResponsesOutputText(fromOutputItem:))
        let text = parts.joined()
        return text.isEmpty ? nil : text
    }

    private static func openAIResponsesOutputText(fromOutputItem item: [String: Any]) -> String? {
        if let text = openAIResponsesOutputText(fromContentPart: item), !text.isEmpty {
            return text
        }
        guard let content = item["content"] as? [[String: Any]] else { return nil }
        let parts = content.compactMap(openAIResponsesOutputText(fromContentPart:))
        let text = parts.joined()
        return text.isEmpty ? nil : text
    }

    private static func openAIResponsesOutputText(fromContentPart part: [String: Any]) -> String? {
        let type = part["type"] as? String
        guard type == nil || type == "output_text" || type == "text" || type == "refusal" else {
            return nil
        }
        if let text = part["text"] as? String {
            return text
        }
        if let refusal = part["refusal"] as? String {
            return refusal
        }
        return nil
    }

    private static func openAIChatCompletionText(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let parts = value as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                let type = part["type"] as? String
                guard type == nil || type == "text" || type == "output_text" else { return nil }
                return (part["text"] as? String)
                    ?? ((part["text"] as? [String: Any])?["value"] as? String)
            }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
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

    private static func anthropicFinish(from stopReason: String, metadata: [String: String]) -> InferenceFinish {
        switch stopReason {
        case "tool_use":
            return InferenceFinish(reason: .toolCall, providerMetadata: metadata)
        case "max_tokens", "model_context_window_exceeded":
            return InferenceFinish(reason: .length, providerMetadata: metadata)
        case "stop_sequence", "end_turn":
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        case "refusal":
            return InferenceFinish(reason: .error, message: "Anthropic stopped the response with a refusal.", providerMetadata: metadata)
        case "pause_turn":
            return InferenceFinish(reason: .error, message: "Anthropic paused the turn before completing a response.", providerMetadata: metadata)
        default:
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        }
    }

    private static func anthropicMetrics(from usage: [String: Any]) -> InferenceMetrics? {
        let inputTokens = intValue(usage["input_tokens"])
            + intValue(usage["cache_creation_input_tokens"])
            + intValue(usage["cache_read_input_tokens"])
        let outputTokens = intValue(usage["output_tokens"])
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func geminiFinish(
        from finishReason: String,
        hasToolCalls: Bool,
        metadata: [String: String]
    ) -> InferenceFinish {
        if hasToolCalls {
            return InferenceFinish(reason: .toolCall, providerMetadata: metadata)
        }
        switch finishReason {
        case "STOP":
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        case "MAX_TOKENS":
            return InferenceFinish(reason: .length, providerMetadata: metadata)
        case "SAFETY":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because of safety settings.", providerMetadata: metadata)
        case "RECITATION":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because of recitation policy.", providerMetadata: metadata)
        case "LANGUAGE":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because the language is unsupported.", providerMetadata: metadata)
        case "BLOCKLIST":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because the prompt or output matched a blocklist.", providerMetadata: metadata)
        case "PROHIBITED_CONTENT":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because it contained prohibited content.", providerMetadata: metadata)
        case "SPII":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because it contained sensitive personal data.", providerMetadata: metadata)
        case "MALFORMED_FUNCTION_CALL":
            return InferenceFinish(reason: .error, message: "Gemini returned a malformed function call.", providerMetadata: metadata)
        default:
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        }
    }

    private static func geminiPromptFeedbackFinish(
        from promptFeedback: [String: Any],
        metadata: [String: String]
    ) -> InferenceFinish? {
        guard let blockReason = promptFeedback["blockReason"] as? String, !blockReason.isEmpty else {
            return nil
        }
        let message = promptFeedback["blockReasonMessage"] as? String
            ?? "Gemini blocked the prompt with reason: \(blockReason)."
        return InferenceFinish(reason: .error, message: message, providerMetadata: metadata)
    }

    private static func geminiMetrics(from usage: [String: Any]) -> InferenceMetrics? {
        let inputTokens = intValue(usage["promptTokenCount"])
        let outputTokens = intValue(usage["candidatesTokenCount"])
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return 0
    }

    fileprivate static func jsonString(from value: Any?) -> String? {
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
    var openAIChatCompletionTextEmitted = false
    var openAIResponsesTextEmitted = false
    var openAIResponsesEventTypes = Set<String>()
    var openAIProviderMetadata = [String: String]()
    var completedOpenAIToolCallIDs = Set<String>()

    var anthropicToolIndex: Int?
    var anthropicToolID: String?
    var anthropicToolName: String?
    var anthropicArguments = ""
    var anthropicProviderMetadata = [String: String]()

    var geminiProviderMetadata = [String: String]()
    var geminiCompletedToolCallIDs = Set<String>()
    var geminiModelContent: [String: Any]?

    mutating func clearOpenAITools() {
        openAIToolIDs.removeAll(keepingCapacity: true)
        openAIToolNames.removeAll(keepingCapacity: true)
        openAIArguments.removeAll(keepingCapacity: true)
    }

    mutating func recordRequestMetadata(providerKind: CloudProviderKind, serverRequestID: String?, clientRequestID: String?) {
        switch providerKind {
        case .anthropic:
            if let serverRequestID, !serverRequestID.isEmpty {
                anthropicProviderMetadata[BYOKCloudInferenceProvider.anthropicRequestIDMetadataKey] = serverRequestID
            }
        case .gemini:
            if let serverRequestID, !serverRequestID.isEmpty {
                geminiProviderMetadata[BYOKCloudInferenceProvider.geminiRequestIDMetadataKey] = serverRequestID
            }
        case .openAI, .openAICompatible, .openRouter, .custom:
            recordOpenAIRequestMetadata(serverRequestID: serverRequestID, clientRequestID: clientRequestID)
        }
    }

    mutating func recordOpenAIRequestMetadata(serverRequestID: String?, clientRequestID: String?) {
        if let serverRequestID, !serverRequestID.isEmpty {
            openAIProviderMetadata[BYOKCloudInferenceProvider.openAIRequestIDMetadataKey] = serverRequestID
        }
        if let clientRequestID, !clientRequestID.isEmpty {
            openAIProviderMetadata[BYOKCloudInferenceProvider.openAIClientRequestIDMetadataKey] = clientRequestID
        }
    }

    mutating func recordOpenAIResponse(_ response: [String: Any]) {
        if let responseID = response["id"] as? String, !responseID.isEmpty {
            openAIProviderMetadata[BYOKCloudInferenceProvider.openAIResponseIDMetadataKey] = responseID
        }
        if let requestID = response["_request_id"] as? String, !requestID.isEmpty {
            openAIProviderMetadata[BYOKCloudInferenceProvider.openAIRequestIDMetadataKey] = requestID
        }
    }

    mutating func markOpenAIToolCallCompleted(_ toolCall: ToolCallDelta) -> Bool {
        completedOpenAIToolCallIDs.insert(toolCall.id).inserted
    }

    mutating func clearAnthropicTool() {
        anthropicToolIndex = nil
        anthropicToolID = nil
        anthropicToolName = nil
        anthropicArguments.removeAll(keepingCapacity: true)
    }

    mutating func recordAnthropicMessage(_ message: [String: Any]) {
        if let messageID = message["id"] as? String, !messageID.isEmpty {
            anthropicProviderMetadata[BYOKCloudInferenceProvider.anthropicMessageIDMetadataKey] = messageID
        }
    }

    mutating func recordGeminiResponse(_ response: [String: Any]) {
        if let responseID = response["responseId"] as? String, !responseID.isEmpty {
            geminiProviderMetadata[BYOKCloudInferenceProvider.geminiResponseIDMetadataKey] = responseID
        }
        if let modelVersion = response["modelVersion"] as? String, !modelVersion.isEmpty {
            geminiProviderMetadata[BYOKCloudInferenceProvider.geminiModelVersionMetadataKey] = modelVersion
        }
    }

    mutating func recordGeminiModelContent(_ content: [String: Any]) {
        guard let parts = content["parts"] as? [[String: Any]], !parts.isEmpty else { return }
        var existingParts = (geminiModelContent?["parts"] as? [[String: Any]]) ?? []
        for part in parts {
            if let text = part["text"] as? String,
               part["thought"] as? Bool != true,
               !text.isEmpty {
                existingParts.append(["text": text])
                continue
            }
            if let functionCall = part["functionCall"] as? [String: Any] {
                existingParts.append(["functionCall": functionCall])
                continue
            }
            if part["thoughtSignature"] != nil || part["thought"] as? Bool == true {
                existingParts.append(part)
            }
        }
        guard !existingParts.isEmpty else { return }
        geminiModelContent = [
            "role": "model",
            "parts": existingParts,
        ]
        if let json = BYOKCloudInferenceProvider.jsonString(from: geminiModelContent) {
            geminiProviderMetadata[BYOKCloudInferenceProvider.geminiModelContentMetadataKey] = json
        }
    }

    mutating func markGeminiToolCallCompleted(_ toolCall: ToolCallDelta) -> Bool {
        geminiCompletedToolCallIDs.insert(toolCall.id).inserted
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

private enum CloudStreamingFormat {
    case chatCompletions
    case openAIResponses
    case anthropicMessages
    case geminiGenerateContent
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
