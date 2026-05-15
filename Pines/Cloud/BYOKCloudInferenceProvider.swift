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
                    for try await byte in bytes {
                        guard !Task.isCancelled else { throw InferenceError.cancelled }
                        if byte == 10 {
                            handleSSELine(buffer, continuation: continuation)
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(Character(UnicodeScalar(byte)))
                        }
                    }
                    if !buffer.isEmpty {
                        handleSSELine(buffer, continuation: continuation)
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
                    continuation.finish(throwing: error)
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
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "messages": chatRequest.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": chatRequest.sampling.temperature,
            "top_p": chatRequest.sampling.topP,
            "max_tokens": chatRequest.sampling.maxTokens ?? 1024,
        ])
        return request
    }

    private func anthropicRequest(apiKey: String, chatRequest: ChatRequest) throws -> URLRequest {
        let url = configuration.baseURL.appending(path: "v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": chatRequest.modelID.rawValue,
            "stream": true,
            "max_tokens": chatRequest.sampling.maxTokens ?? 1024,
            "temperature": chatRequest.sampling.temperature,
            "messages": chatRequest.messages.filter { $0.role != .system }.map {
                ["role": $0.role == .assistant ? "assistant" : "user", "content": $0.content]
            },
            "system": chatRequest.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n"),
        ])
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
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": chatRequest.messages.filter { $0.role != .system }.map {
                [
                    "role": $0.role == .assistant ? "model" : "user",
                    "parts": [["text": $0.content]],
                ]
            },
        ])
        return request
    }

    private func handleSSELine(_ rawLine: String, continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8) else { return }

        let text = Self.extractText(from: data, providerKind: configuration.kind)
        if !text.isEmpty {
            continuation.yield(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
        }
    }

    private static func extractText(from data: Data, providerKind: CloudProviderKind) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        switch providerKind {
        case .anthropic:
            if let delta = json["delta"] as? [String: Any], let text = delta["text"] as? String {
                return text
            }
            if let content = json["content_block"] as? [String: Any], let text = content["text"] as? String {
                return text
            }
        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            return parts?.compactMap { $0["text"] as? String }.joined() ?? ""
        case .openAICompatible, .openRouter, .custom:
            let choices = json["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            return delta?["content"] as? String ?? ""
        }

        return ""
    }
}
