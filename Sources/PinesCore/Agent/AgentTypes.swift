import Foundation

public enum PinesRunMode: String, Hashable, Codable, Sendable, CaseIterable {
    case chat
    case agent
}

public enum AgentCloudContextScope: String, Hashable, Codable, Sendable {
    case unrestricted
    case selectedRequestContext
}

public struct AgentPolicy: Hashable, Codable, Sendable {
    public var executionMode: AgentExecutionMode
    public var maxSteps: Int
    public var maxToolCalls: Int
    public var maxWallTimeSeconds: Int
    public var allowedDomains: Set<String>
    public var requiresConsentForNetwork: Bool
    public var requiresConsentForBrowser: Bool
    public var allowsCloudContext: Bool
    public var cloudContextScope: AgentCloudContextScope

    public init(
        executionMode: AgentExecutionMode = .localOnly,
        maxSteps: Int = 8,
        maxToolCalls: Int = 6,
        maxWallTimeSeconds: Int = 120,
        allowedDomains: Set<String> = [],
        requiresConsentForNetwork: Bool = true,
        requiresConsentForBrowser: Bool = true,
        allowsCloudContext: Bool = false,
        cloudContextScope: AgentCloudContextScope = .unrestricted
    ) {
        self.executionMode = executionMode
        self.maxSteps = maxSteps
        self.maxToolCalls = maxToolCalls
        self.maxWallTimeSeconds = maxWallTimeSeconds
        self.allowedDomains = allowedDomains
        self.requiresConsentForNetwork = requiresConsentForNetwork
        self.requiresConsentForBrowser = requiresConsentForBrowser
        self.allowsCloudContext = allowsCloudContext
        self.cloudContextScope = cloudContextScope
    }

    private enum CodingKeys: String, CodingKey {
        case executionMode
        case maxSteps
        case maxToolCalls
        case maxWallTimeSeconds
        case allowedDomains
        case requiresConsentForNetwork
        case requiresConsentForBrowser
        case allowsCloudContext
        case cloudContextScope
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.executionMode = try container.decodeIfPresent(AgentExecutionMode.self, forKey: .executionMode) ?? .localOnly
        self.maxSteps = try container.decodeIfPresent(Int.self, forKey: .maxSteps) ?? 8
        self.maxToolCalls = try container.decodeIfPresent(Int.self, forKey: .maxToolCalls) ?? 6
        self.maxWallTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .maxWallTimeSeconds) ?? 120
        self.allowedDomains = try container.decodeIfPresent(Set<String>.self, forKey: .allowedDomains) ?? []
        self.requiresConsentForNetwork = try container.decodeIfPresent(Bool.self, forKey: .requiresConsentForNetwork) ?? true
        self.requiresConsentForBrowser = try container.decodeIfPresent(Bool.self, forKey: .requiresConsentForBrowser) ?? true
        self.allowsCloudContext = try container.decodeIfPresent(Bool.self, forKey: .allowsCloudContext) ?? false
        self.cloudContextScope = try container.decodeIfPresent(AgentCloudContextScope.self, forKey: .cloudContextScope) ?? .unrestricted
    }
}

public struct AgentSession: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var policy: AgentPolicy
    public var providerID: ProviderID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        policy: AgentPolicy = .init(),
        providerID: ProviderID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.policy = policy
        self.providerID = providerID
        self.createdAt = createdAt
    }
}

public struct ToolInvocation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var toolName: String
    public var argumentsJSON: String
    public var reason: String
    public var expectedOutput: String
    public var privacyImpact: String

    public init(
        id: UUID = UUID(),
        toolName: String,
        argumentsJSON: String,
        reason: String,
        expectedOutput: String,
        privacyImpact: String
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.reason = reason
        self.expectedOutput = expectedOutput
        self.privacyImpact = privacyImpact
    }
}

public struct ToolResultEnvelope: Hashable, Codable, Sendable {
    public var invocationID: UUID
    public var toolName: String
    public var outputJSON: String
    public var untrusted: Bool
    public var networkDomains: [String]

    public init(
        invocationID: UUID,
        toolName: String,
        outputJSON: String,
        untrusted: Bool = false,
        networkDomains: [String] = []
    ) {
        self.invocationID = invocationID
        self.toolName = toolName
        self.outputJSON = outputJSON
        self.untrusted = untrusted
        self.networkDomains = networkDomains
    }
}

public enum AgentActivityStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case waitingForApproval
    case running
    case completed
    case failed
    case denied
}

public struct AgentActivityLink: Hashable, Codable, Sendable, Identifiable {
    public var id: String { url }
    public var title: String
    public var url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

public struct AgentActivityEvent: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var toolCallID: String
    public var toolName: String
    public var title: String
    public var detail: String
    public var status: AgentActivityStatus
    public var links: [AgentActivityLink]
    public var startedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        toolCallID: String,
        toolName: String,
        title: String,
        detail: String,
        status: AgentActivityStatus,
        links: [AgentActivityLink] = [],
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.title = title
        self.detail = detail
        self.status = status
        self.links = links
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public enum AgentError: Error, Equatable, Sendable {
    case stepLimitExceeded
    case toolLimitExceeded
    case wallTimeExceeded
    case missingToolExplanation(String)
    case permissionDenied(String)
    case invalidToolArguments(String)
}

extension AgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .stepLimitExceeded:
            return "The agent reached its step limit before completing."
        case .toolLimitExceeded:
            return "The agent reached its tool-call limit before completing."
        case .wallTimeExceeded:
            return "The agent reached its wall-time limit before completing."
        case let .missingToolExplanation(toolName):
            return "The model requested \(toolName) without a usable explanation."
        case let .permissionDenied(message):
            return message
        case let .invalidToolArguments(message):
            return message
        }
    }
}
