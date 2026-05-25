import Foundation

public enum LocalInferenceFailureKind: String, Codable, Sendable, CaseIterable {
    case memoryAdmissionFailed
    case turboQuantPathUnavailable
    case turboQuantFallbackUnavailable
    case fallbackBudgetExceeded
    case modelProfileUnverified
    case modelProfileMismatch
    case unsupportedAttentionShape
    case unsupportedAttentionMask
    case unsupportedTensorDType
    case cacheLayoutInvalid
    case cacheLifecycleInvalid
    case contextWindowExceeded
    case snapshotInvalid
    case snapshotCorrupt
    case schemaIncompatible
    case mlxRuntimeFailure
    case cloudRouteDisallowed
}

public enum LocalInferenceFailureBehavior: String, Codable, Sendable, CaseIterable {
    case reject
    case downgrade
    case retryShorter
    case fallback
    case cancel
    case releaseOptionalCaches
    case quarantine
    case revokeEvidence
    case typedError
}

public struct LocalInferenceFailureEvent: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var kind: LocalInferenceFailureKind
    public var sourceRepo: String
    public var sourceType: String?
    public var message: String
    public var recoverable: Bool
    public var recommendedAction: String?
    public var admissionPlanID: String?
    public var runDecisionID: String?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        kind: LocalInferenceFailureKind,
        sourceRepo: String,
        sourceType: String? = nil,
        message: String,
        recoverable: Bool,
        recommendedAction: String? = nil,
        admissionPlanID: String? = nil,
        runDecisionID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.sourceRepo = sourceRepo
        self.sourceType = sourceType
        self.message = message
        self.recoverable = recoverable
        self.recommendedAction = recommendedAction
        self.admissionPlanID = admissionPlanID
        self.runDecisionID = runDecisionID
    }
}

public struct LocalInferenceFailureBehaviorRule: Hashable, Codable, Sendable {
    public var kind: LocalInferenceFailureKind
    public var behaviors: [LocalInferenceFailureBehavior]
    public var productMessage: String

    public init(
        kind: LocalInferenceFailureKind,
        behaviors: [LocalInferenceFailureBehavior],
        productMessage: String
    ) {
        self.kind = kind
        self.behaviors = behaviors
        self.productMessage = productMessage
    }
}

public enum LocalInferenceFailureMatrix {
    public static let canonicalRules: [LocalInferenceFailureBehaviorRule] = [
        .init(
            kind: .memoryAdmissionFailed,
            behaviors: [.downgrade, .reject, .typedError],
            productMessage: "This model/context needs more memory than is safely available."
        ),
        .init(
            kind: .turboQuantPathUnavailable,
            behaviors: [.downgrade, .fallback, .typedError],
            productMessage: "Compressed attention is unavailable for this request."
        ),
        .init(
            kind: .turboQuantFallbackUnavailable,
            behaviors: [.reject, .typedError],
            productMessage: "Safe fallback cannot be budgeted for this context."
        ),
        .init(
            kind: .fallbackBudgetExceeded,
            behaviors: [.typedError],
            productMessage: "Fallback would exceed memory budget."
        ),
        .init(
            kind: .modelProfileUnverified,
            behaviors: [.downgrade, .typedError],
            productMessage: "This model is not verified on this device yet."
        ),
        .init(
            kind: .modelProfileMismatch,
            behaviors: [.reject, .typedError],
            productMessage: "This model profile does not match the installed model."
        ),
        .init(
            kind: .unsupportedAttentionShape,
            behaviors: [.reject, .fallback, .typedError],
            productMessage: "Model attention shape is unsupported by this TurboQuant path."
        ),
        .init(
            kind: .unsupportedAttentionMask,
            behaviors: [.fallback, .typedError],
            productMessage: "Attention mask is unsupported by compressed path."
        ),
        .init(
            kind: .unsupportedTensorDType,
            behaviors: [.fallback, .reject, .typedError],
            productMessage: "Tensor dtype is unsupported by compressed path."
        ),
        .init(
            kind: .cacheLayoutInvalid,
            behaviors: [.typedError],
            productMessage: "Compressed cache layout is invalid."
        ),
        .init(
            kind: .cacheLifecycleInvalid,
            behaviors: [.typedError],
            productMessage: "Cache state is inconsistent."
        ),
        .init(
            kind: .contextWindowExceeded,
            behaviors: [.retryShorter, .reject, .typedError],
            productMessage: "The requested context exceeds the local runtime window."
        ),
        .init(
            kind: .snapshotInvalid,
            behaviors: [.reject, .quarantine, .typedError],
            productMessage: "Saved session state is no longer valid."
        ),
        .init(
            kind: .snapshotCorrupt,
            behaviors: [.quarantine, .typedError],
            productMessage: "Saved session state is corrupt and cannot be restored."
        ),
        .init(
            kind: .schemaIncompatible,
            behaviors: [.reject, .typedError],
            productMessage: "Saved runtime data was created by a newer incompatible version."
        ),
        .init(
            kind: .mlxRuntimeFailure,
            behaviors: [.typedError],
            productMessage: "Local runtime failed before it could complete the request."
        ),
        .init(
            kind: .cloudRouteDisallowed,
            behaviors: [.reject, .typedError],
            productMessage: "Cloud retry is disabled for this request."
        ),
    ]

    public static let rulesByKind: [LocalInferenceFailureKind: LocalInferenceFailureBehaviorRule] = Dictionary(
        uniqueKeysWithValues: canonicalRules.map { ($0.kind, $0) }
    )
}
