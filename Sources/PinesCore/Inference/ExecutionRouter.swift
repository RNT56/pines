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
        cloudAccessMode: CloudAccessMode,
        local: (id: ProviderID, capabilities: ProviderCapabilities)?,
        managedCloud: (id: ProviderID, capabilities: ProviderCapabilities)?,
        byokCloud: (id: ProviderID, capabilities: ProviderCapabilities)?,
        requiredInputs: ProviderInputRequirements = .init(),
        requiresTools: Bool,
        prefersBYOKOverride: Bool = false
    ) -> RouteDecision {
        let localMatches = Self.matchingProviderID(local, requiredInputs: requiredInputs, requiresTools: requiresTools)
        let managedMatches = Self.matchingProviderID(managedCloud, requiredInputs: requiredInputs, requiresTools: requiresTools)
        let byokMatches = Self.matchingProviderID(byokCloud, requiredInputs: requiredInputs, requiresTools: requiresTools)

        func denied(_ message: String, explanation: String) -> RouteDecision {
            .init(destination: .denied(reason: .unsupportedCapability(message)), explanation: explanation)
        }

        switch cloudAccessMode {
        case .localOnly:
            if let localMatches {
                return .init(destination: .local(localMatches), explanation: "Local model satisfies the request.")
            }
            return denied("No local model satisfies this request.", explanation: "Cloud routing is disabled for local-only sessions.")
        case .byok:
            return routeChat(
                mode: mode,
                local: local,
                cloud: byokCloud,
                requiredInputs: requiredInputs,
                requiresTools: requiresTools
            )
        case .managedPro:
            switch mode {
            case .localOnly:
                if let localMatches {
                    return .init(destination: .local(localMatches), explanation: "Local model satisfies the request.")
                }
                return denied("No local model satisfies this request.", explanation: "Cloud routing is disabled for local-only sessions.")
            case .preferLocal:
                if let localMatches {
                    return .init(destination: .local(localMatches), explanation: "Local model is preferred and available.")
                }
                if let managedMatches {
                    return .init(destination: .cloud(managedMatches), explanation: "Managed Pro Cloud is opted in and can handle this request.")
                }
            case .cloudAllowed:
                if let managedMatches {
                    return .init(destination: .cloud(managedMatches), explanation: "Managed Pro Cloud is opted in and selected for cloud work.")
                }
                if let localMatches {
                    return .init(destination: .local(localMatches), explanation: "Managed Pro Cloud is unavailable; local model can handle the request.")
                }
            case .cloudRequired:
                if let managedMatches {
                    return .init(destination: .cloud(managedMatches), explanation: "Cloud execution is required and Managed Pro Cloud is available.")
                }
            }
            return denied(
                "Managed Pro Cloud is not available for this request.",
                explanation: "No local or managed Pro provider supports the requested capabilities."
            )
        case .managedProWithBYOKOverride:
            let primaryCloud = prefersBYOKOverride ? byokMatches : managedMatches
            let secondaryCloud = prefersBYOKOverride ? managedMatches : nil
            let primaryExplanation = prefersBYOKOverride
                ? "BYOK override is selected for this request."
                : "Managed Pro Cloud is opted in and selected for cloud work."
            let secondaryExplanation = prefersBYOKOverride
                ? "BYOK override is unavailable; Managed Pro Cloud can handle this request."
                : "Managed Pro Cloud is unavailable."

            switch mode {
            case .localOnly:
                if let localMatches {
                    return .init(destination: .local(localMatches), explanation: "Local model satisfies the request.")
                }
                return denied("No local model satisfies this request.", explanation: "Cloud routing is disabled for local-only sessions.")
            case .preferLocal:
                if let localMatches {
                    return .init(destination: .local(localMatches), explanation: "Local model is preferred and available.")
                }
                if let primaryCloud {
                    return .init(destination: .cloud(primaryCloud), explanation: primaryExplanation)
                }
                if let secondaryCloud {
                    return .init(destination: .cloud(secondaryCloud), explanation: secondaryExplanation)
                }
            case .cloudAllowed:
                if let primaryCloud {
                    return .init(destination: .cloud(primaryCloud), explanation: primaryExplanation)
                }
                if let secondaryCloud {
                    return .init(destination: .cloud(secondaryCloud), explanation: secondaryExplanation)
                }
                if let localMatches {
                    return .init(destination: .local(localMatches), explanation: "Cloud is unavailable; local model can handle the request.")
                }
            case .cloudRequired:
                if let primaryCloud {
                    return .init(destination: .cloud(primaryCloud), explanation: primaryExplanation)
                }
                if let secondaryCloud {
                    return .init(destination: .cloud(secondaryCloud), explanation: secondaryExplanation)
                }
            }
            return denied(
                "No configured cloud provider satisfies this request.",
                explanation: "Managed Pro and BYOK providers are unavailable or incompatible."
            )
        }
    }

    public func routeChat(
        mode: AgentExecutionMode,
        local: (id: ProviderID, capabilities: ProviderCapabilities)?,
        cloud: (id: ProviderID, capabilities: ProviderCapabilities)?,
        requiredInputs: ProviderInputRequirements = .init(),
        requiresTools: Bool
    ) -> RouteDecision {
        let localMatches = Self.matchingProviderID(local, requiredInputs: requiredInputs, requiresTools: requiresTools)
        let cloudMatches = Self.matchingProviderID(cloud, requiredInputs: requiredInputs, requiresTools: requiresTools)

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

    private static func matchingProviderID(
        _ provider: (id: ProviderID, capabilities: ProviderCapabilities)?,
        requiredInputs: ProviderInputRequirements,
        requiresTools: Bool
    ) -> ProviderID? {
        guard let provider else { return nil }
        guard provider.capabilities.textGeneration else { return nil }
        guard requiredInputs.isSatisfied(by: provider.capabilities) else { return nil }
        guard !requiresTools || provider.capabilities.toolCalling else { return nil }
        return provider.id
    }
}
