import Foundation

public enum RuntimeCompatibilityState: String, Hashable, Codable, Sendable, CaseIterable {
    case verified
    case conservative
    case unverified
    case unsupported
    case degraded
    case benchmarkRequired
    case revoked

    public var allowsProductClaim: Bool {
        self == .verified
    }

    public static func resolve(
        installVerification: ModelVerificationState,
        evidence: RuntimeProfileEvidence?,
        admission: TurboQuantAdmission?,
        requestedContextTokens: Int? = nil
    ) -> RuntimeCompatibilityState {
        if evidence?.evidenceLevel == .revoked || evidence?.revokedReason != nil {
            return .revoked
        }
        if evidence?.evidenceLevel.canMakeProductCompatibilityClaim == true {
            if let admission, admission.admitted == false {
                return .degraded
            }
            return .verified
        }
        if installVerification == .unsupported {
            return .unsupported
        }
        if let admission, admission.admitted == false {
            return .unsupported
        }
        if let admission,
           let requestedContextTokens,
           admission.admittedContextLength < requestedContextTokens {
            return .degraded
        }
        if installVerification == .experimental {
            return .benchmarkRequired
        }
        if installVerification == .verified {
            return .conservative
        }
        return .unverified
    }
}
