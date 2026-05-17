import Foundation

public enum AgentExecutionMode: String, Codable, Sendable, CaseIterable {
    case localOnly
    case preferLocal
    case cloudAllowed
    case cloudRequired
}

public struct RouteDecision: Equatable, Sendable {
    public enum Destination: Equatable, Sendable {
        case local(ProviderID)
        case cloud(ProviderID)
        case denied(reason: InferenceError)
    }

    public var destination: Destination
    public var explanation: String

    public init(destination: Destination, explanation: String) {
        self.destination = destination
        self.explanation = explanation
    }
}

public struct ExecutionRouter: Sendable {
    public init() {}

    public func routeChat(
        mode: AgentExecutionMode,
        local: (id: ProviderID, capabilities: ProviderCapabilities)?,
        cloud: (id: ProviderID, capabilities: ProviderCapabilities)?,
        requiredInputs: ProviderInputRequirements = .init(),
        requiresTools: Bool
    ) -> RouteDecision {
        let localMatches = local.flatMap { provider -> ProviderID? in
            guard provider.capabilities.textGeneration else { return nil }
            guard requiredInputs.isSatisfied(by: provider.capabilities) else { return nil }
            guard !requiresTools || provider.capabilities.toolCalling else { return nil }
            return provider.id
        }

        let cloudMatches = cloud.flatMap { provider -> ProviderID? in
            guard provider.capabilities.textGeneration else { return nil }
            guard requiredInputs.isSatisfied(by: provider.capabilities) else { return nil }
            guard !requiresTools || provider.capabilities.toolCalling else { return nil }
            return provider.id
        }

        switch mode {
        case .localOnly:
            if let localMatches {
                return .init(destination: .local(localMatches), explanation: "Local model satisfies the request.")
            }
            return .init(
                destination: .denied(reason: .unsupportedCapability("No local model satisfies this request.")),
                explanation: "Cloud routing is disabled for local-only sessions."
            )
        case .preferLocal:
            if let localMatches {
                return .init(destination: .local(localMatches), explanation: "Local model is preferred and available.")
            }
            if let cloudMatches {
                return .init(destination: .cloud(cloudMatches), explanation: "Local model is unavailable; cloud is explicitly allowed for this agent.")
            }
            return .init(
                destination: .denied(reason: .unsupportedCapability("No configured provider satisfies this request.")),
                explanation: "Neither local nor configured cloud providers support the requested capabilities."
            )
        case .cloudAllowed:
            if let cloudMatches {
                return .init(destination: .cloud(cloudMatches), explanation: "Cloud provider is explicitly enabled for this agent.")
            }
            if let localMatches {
                return .init(destination: .local(localMatches), explanation: "Cloud provider is unavailable; local model can handle the request.")
            }
            return .init(
                destination: .denied(reason: .unsupportedCapability("No configured provider satisfies this request.")),
                explanation: "No configured provider supports the requested capabilities."
            )
        case .cloudRequired:
            if let cloudMatches {
                return .init(destination: .cloud(cloudMatches), explanation: "Agent requires cloud execution and a configured cloud provider is available.")
            }
            return .init(
                destination: .denied(reason: .cloudNotAllowed),
                explanation: "This agent requires cloud execution, but no matching BYOK provider is configured."
            )
        }
    }
}
