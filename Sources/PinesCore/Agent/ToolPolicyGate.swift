import Foundation

public struct ToolPolicyGate: Sendable {
    public init() {}

    public func validate(invocation: ToolInvocation, spec: AnyToolSpec, policy: AgentPolicy) throws {
        if spec.explanationRequired {
            guard !invocation.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !invocation.expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !invocation.privacyImpact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw AgentError.missingToolExplanation(spec.name)
            }
        }

        if spec.permissions.contains(.cloudContext), !policy.allowsCloudContext {
            throw AgentError.permissionDenied("Tool \(spec.name) would send context to cloud.")
        }

        if spec.permissions.contains(.network), policy.requiresConsentForNetwork {
            switch spec.networkPolicy {
            case .noNetwork:
                break
            case let .allowListedDomains(domains):
                let requested = Set(domains)
                if !requested.isSubset(of: policy.allowedDomains) {
                    throw AgentError.permissionDenied("Tool \(spec.name) requests domains outside the agent allow-list.")
                }
            case .userApproved:
                throw AgentError.permissionDenied("Tool \(spec.name) requires explicit network approval.")
            }
        }

        if spec.permissions.contains(.browser), policy.requiresConsentForBrowser {
            throw AgentError.permissionDenied("Browser automation requires explicit user approval.")
        }
    }
}
