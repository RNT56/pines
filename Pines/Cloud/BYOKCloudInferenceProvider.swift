import Foundation
import PinesCore

struct BYOKCloudInferenceProvider: InferenceProvider {
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
        guard configuration.enabledForAgents else {
            throw CloudProviderError.disabledForAgents
        }
        guard let apiKey = try await secretStore.read(
            service: configuration.keychainService,
            account: configuration.keychainAccount
        ), !apiKey.isEmpty else {
            throw CloudProviderError.missingAPIKey
        }

        let urlRequest = try buildStreamingRequest(apiKey: apiKey, chatRequest: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw CloudProviderError.invalidResponse
                    }

                    var buffer = ""
                    var toolState = CloudToolCallStreamState()
                    for try await byte in bytes {
                        guard !Task.isCancelled else { throw InferenceError.cancelled }
                        if byte == 10 {
                            handleSSELine(buffer, state: &toolState, continuation: continuation)
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(Character(UnicodeScalar(byte)))
                        }
                    }
                    if !buffer.isEmpty {
                        handleSSELine(buffer, state: &toolState, continuation: continuation)
                    }
                    continuation.yield(.finish(InferenceFinish(reason: .stop)))
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

    func validate(modelID: ModelID?) async throws -> ProviderValidationResult {
        guard let apiKey = try await secretStore.read(service: configuration.keychainService, account: configuration.keychainAccount), !apiKey.isEmpty else {
            return ProviderValidationResult(providerID: configuration.id, status: .invalid, message: "Missing API key.")
        }

        var request: URLRequest
        switch configuration.kind {
        case .openAICompatible, .openRouter, .custom:
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

        let (_, http) = try await URLSession.shared.data(for: request)
        if (200..<300).contains(http.statusCode) {
            return ProviderValidationResult(providerID: configuration.id, status: .valid, message: "Provider validated.")
        }
        if http.statusCode == 429 {
            return ProviderValidationResult(providerID: configuration.id, status: .rateLimited, message: "Provider rate limited validation.")
        }
        return ProviderValidationResult(providerID: configuration.id, status: .invalid, message: "Validation failed with HTTP \(http.statusCode).")
    }

    private func buildStreamingRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        switch configuration.kind {
        case .openAICompatible, .openRouter, .custom:
            return try openAICompatibleRequest(apiKey: apiKey, chatRequest: chatRequest)
        case .anthropic:
            return try anthropicRequest(apiKey: apiKey, chatRequest: chatRequest)
        case .gemini:
            return try geminiRequest(apiKey: apiKey, chatRequest: chatRequest)
        }
    }

    private func openAICompatibleRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let url = configuration.baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "messages": chatRequest.messages.map(Self.openAIMessageObject),
            "temperature": chatRequest.sampling.temperature,
            "top_p": chatRequest.sampling.topP,
            "max_tokens": chatRequest.sampling.maxTokens ?? 1024,
        ]
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = chatRequest.availableTools.map { Self.jsonSerializable($0.openAIFunctionToolObject()) }
            body["tool_choice"] = "auto"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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
        return request
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
        ]
        if chatRequest.allowsTools, !chatRequest.availableTools.isEmpty {
            body["tools"] = [[
                "functionDeclarations": chatRequest.availableTools.map {
                    Self.jsonSerializable($0.geminiFunctionDeclarationObject())
                },
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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

    private func handleSSELine(
        _ rawLine: String,
        state: inout CloudToolCallStreamState,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8) else { return }

        for event in Self.extractEvents(from: data, providerKind: configuration.kind, state: &state) {
            continuation.yield(event)
        }
    }

    private static func extractEvents(
        from data: Data,
        providerKind: CloudProviderKind,
        state: inout CloudToolCallStreamState
    ) -> [InferenceStreamEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var events = [InferenceStreamEvent]()
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
        case .openAICompatible, .openRouter, .custom:
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
