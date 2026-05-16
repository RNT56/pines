import Foundation

public enum CloudProviderKind: String, Codable, Sendable, CaseIterable {
    case openAI
    case openAICompatible
    case anthropic
    case gemini
    case openRouter
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
        toolsJSON: [[String: any Sendable]] = []
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
        let advertisedTools = !toolsJSON.isEmpty
            ? toolsJSON
            : (request.allowsTools ? request.availableTools.map { $0.openAIFunctionToolObject() } : [])
        if !advertisedTools.isEmpty {
            body["tools"] = advertisedTools.map(Self.jsonSerializable)
            body["tool_choice"] = "auto"
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
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
}
