import Foundation

public enum CloudProviderKind: String, Codable, Sendable, CaseIterable {
    case openAICompatible
    case anthropic
    case gemini
    case openRouter
    case custom
}

public struct CloudProviderConfiguration: Identifiable, Hashable, Codable, Sendable {
    public var id: ProviderID
    public var kind: CloudProviderKind
    public var displayName: String
    public var baseURL: URL
    public var keychainService: String
    public var keychainAccount: String
    public var enabledForAgents: Bool
    public var lastValidatedAt: Date?

    public init(
        id: ProviderID,
        kind: CloudProviderKind,
        displayName: String,
        baseURL: URL,
        keychainService: String = "com.schtack.pines.cloud",
        keychainAccount: String,
        enabledForAgents: Bool = false,
        lastValidatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.baseURL = baseURL
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.enabledForAgents = enabledForAgents
        self.lastValidatedAt = lastValidatedAt
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
}

public struct OpenAICompatibleRequestBuilder: Sendable {
    public init() {}

    public func chatRequest(
        baseURL: URL,
        apiKey: String,
        request: ChatRequest,
        toolsJSON: [[String: String]] = []
    ) throws -> URLRequest {
        let url = baseURL.appending(path: "/v1/chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": request.modelID.rawValue,
            "stream": true,
            "messages": request.messages.map { message in
                [
                    "role": message.role.rawValue,
                    "content": message.content,
                ]
            },
            "temperature": request.sampling.temperature,
            "top_p": request.sampling.topP,
        ]
        if let maxTokens = request.sampling.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if !toolsJSON.isEmpty {
            body["tools"] = toolsJSON
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }
}
