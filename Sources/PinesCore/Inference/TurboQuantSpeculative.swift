import Foundation

public enum TurboQuantSpeculativeRuntimeState: String, Codable, Sendable, CaseIterable {
    case disabled
    case unavailable
    case eligible
    case active
    case autoDisabled
    case evidenceRequired

    public var displayName: String {
        switch self {
        case .disabled:
            "Disabled"
        case .unavailable:
            "Unavailable"
        case .eligible:
            "Eligible"
        case .active:
            "Active"
        case .autoDisabled:
            "Auto-disabled"
        case .evidenceRequired:
            "Evidence required"
        }
    }
}

public enum TurboQuantSpeculativeDisableReason: String, Codable, Sendable, CaseIterable {
    case none
    case settingsDisabled
    case draftModelMissing
    case tokenizerMismatch
    case evidenceMissing
    case lowAcceptance
    case noDecodeSpeedup
    case rollbackFailure
    case targetMismatch
    case runtimeFailure
    case platformGateDisabled

    public var displayName: String {
        switch self {
        case .none:
            "None"
        case .settingsDisabled:
            "Settings disabled"
        case .draftModelMissing:
            "Draft model missing"
        case .tokenizerMismatch:
            "Tokenizer mismatch"
        case .evidenceMissing:
            "Evidence missing"
        case .lowAcceptance:
            "Low acceptance"
        case .noDecodeSpeedup:
            "No decode speedup"
        case .rollbackFailure:
            "Rollback failure"
        case .targetMismatch:
            "Target mismatch"
        case .runtimeFailure:
            "Runtime failure"
        case .platformGateDisabled:
            "Platform gate disabled"
        }
    }
}

public enum TurboQuantSpeculativeAutoDisableAction: String, Codable, Sendable, CaseIterable {
    case keepEnabled
    case disableTemporarily
    case disableUntilEvidenceRefresh
}

public struct TurboQuantSpeculativeAutoDisableDecision: Hashable, Codable, Sendable {
    public var action: TurboQuantSpeculativeAutoDisableAction
    public var reason: TurboQuantSpeculativeDisableReason
    public var acceptanceRate: Double?
    public var evaluatedProposedTokens: Int
    public var cooldownRunCount: Int
    public var message: String

    public var shouldDisable: Bool {
        action != .keepEnabled
    }

    public init(
        action: TurboQuantSpeculativeAutoDisableAction,
        reason: TurboQuantSpeculativeDisableReason,
        acceptanceRate: Double? = nil,
        evaluatedProposedTokens: Int = 0,
        cooldownRunCount: Int = 0,
        message: String
    ) {
        self.action = action
        self.reason = reason
        self.acceptanceRate = acceptanceRate
        self.evaluatedProposedTokens = max(0, evaluatedProposedTokens)
        self.cooldownRunCount = max(0, cooldownRunCount)
        self.message = message
    }

    public static let keepEnabled = Self(
        action: .keepEnabled,
        reason: .none,
        message: "Speculative decode remains enabled."
    )
}

public struct TurboQuantSpeculativeAutoDisablePolicy: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var minimumAcceptanceRate: Double
    public var minimumEvaluatedProposedTokens: Int
    public var minimumP50DecodeSpeedup: Double
    public var cooldownRunCount: Int
    public var maximumRollbackCount: Int
    public var requireTokenizerCompatibility: Bool
    public var requireTargetSequenceMatch: Bool

    public init(
        schemaVersion: Int = Self.schemaVersion,
        minimumAcceptanceRate: Double = 0.55,
        minimumEvaluatedProposedTokens: Int = 64,
        minimumP50DecodeSpeedup: Double = 1.05,
        cooldownRunCount: Int = 3,
        maximumRollbackCount: Int = 0,
        requireTokenizerCompatibility: Bool = true,
        requireTargetSequenceMatch: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.minimumAcceptanceRate = min(1, max(0, minimumAcceptanceRate))
        self.minimumEvaluatedProposedTokens = max(1, minimumEvaluatedProposedTokens)
        self.minimumP50DecodeSpeedup = max(1, minimumP50DecodeSpeedup)
        self.cooldownRunCount = max(0, cooldownRunCount)
        self.maximumRollbackCount = max(0, maximumRollbackCount)
        self.requireTokenizerCompatibility = requireTokenizerCompatibility
        self.requireTargetSequenceMatch = requireTargetSequenceMatch
    }

    public static let productDefault = Self()

    public func evaluate(_ telemetry: TurboQuantSpeculativeTelemetry) -> TurboQuantSpeculativeAutoDisableDecision {
        guard telemetry.state == .active || telemetry.state == .eligible else {
            return .keepEnabled
        }
        if requireTokenizerCompatibility, telemetry.tokenizerCompatible == false {
            return disable(.tokenizerMismatch, telemetry, "Draft and target tokenizers are not compatible.")
        }
        if requireTargetSequenceMatch, telemetry.targetSequenceMatched == false {
            return TurboQuantSpeculativeAutoDisableDecision(
                action: .disableUntilEvidenceRefresh,
                reason: .targetMismatch,
                acceptanceRate: telemetry.acceptanceRate,
                evaluatedProposedTokens: telemetry.proposedTokenCount,
                cooldownRunCount: cooldownRunCount,
                message: "Speculative output diverged from the target verifier."
            )
        }
        if telemetry.rollbackCount > maximumRollbackCount {
            return TurboQuantSpeculativeAutoDisableDecision(
                action: .disableUntilEvidenceRefresh,
                reason: .rollbackFailure,
                acceptanceRate: telemetry.acceptanceRate,
                evaluatedProposedTokens: telemetry.proposedTokenCount,
                cooldownRunCount: cooldownRunCount,
                message: "Speculative rollback exceeded the permitted failure count."
            )
        }
        guard telemetry.proposedTokenCount >= minimumEvaluatedProposedTokens else {
            return .keepEnabled
        }
        if let acceptanceRate = telemetry.acceptanceRate, acceptanceRate < minimumAcceptanceRate {
            return disable(.lowAcceptance, telemetry, "Speculative acceptance fell below the policy threshold.")
        }
        if let speedup = telemetry.p50DecodeSpeedup, speedup < minimumP50DecodeSpeedup {
            return disable(.noDecodeSpeedup, telemetry, "Speculative decode did not improve p50 decode throughput.")
        }
        return .keepEnabled
    }

    private func disable(
        _ reason: TurboQuantSpeculativeDisableReason,
        _ telemetry: TurboQuantSpeculativeTelemetry,
        _ message: String
    ) -> TurboQuantSpeculativeAutoDisableDecision {
        TurboQuantSpeculativeAutoDisableDecision(
            action: .disableTemporarily,
            reason: reason,
            acceptanceRate: telemetry.acceptanceRate,
            evaluatedProposedTokens: telemetry.proposedTokenCount,
            cooldownRunCount: cooldownRunCount,
            message: message
        )
    }
}

public struct TurboQuantSpeculativeSettings: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var enabled: Bool
    public var requireEvidenceForFastMode: Bool
    public var draftModelID: String?
    public var draftModelRevision: String?
    public var maxDraftTokens: Int
    public var requireTokenizerCompatibility: Bool
    public var autoDisablePolicy: TurboQuantSpeculativeAutoDisablePolicy

    public init(
        schemaVersion: Int = Self.schemaVersion,
        enabled: Bool = false,
        requireEvidenceForFastMode: Bool = true,
        draftModelID: String? = nil,
        draftModelRevision: String? = nil,
        maxDraftTokens: Int = 4,
        requireTokenizerCompatibility: Bool = true,
        autoDisablePolicy: TurboQuantSpeculativeAutoDisablePolicy = .productDefault
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.requireEvidenceForFastMode = requireEvidenceForFastMode
        self.draftModelID = draftModelID
        self.draftModelRevision = draftModelRevision
        self.maxDraftTokens = max(1, maxDraftTokens)
        self.requireTokenizerCompatibility = requireTokenizerCompatibility
        self.autoDisablePolicy = autoDisablePolicy
    }

    public static let disabled = Self(enabled: false)
}

public struct TurboQuantSpeculativeEvidenceDimensions: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var enabled: Bool
    public var draftModelID: String?
    public var draftModelRevision: String?
    public var targetTokenizerHash: String?
    public var draftTokenizerHash: String?
    public var pairingHash: String?
    public var tokenizerCompatible: Bool?
    public var maxDraftTokens: Int?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        enabled: Bool = false,
        draftModelID: String? = nil,
        draftModelRevision: String? = nil,
        targetTokenizerHash: String? = nil,
        draftTokenizerHash: String? = nil,
        pairingHash: String? = nil,
        tokenizerCompatible: Bool? = nil,
        maxDraftTokens: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.draftModelID = draftModelID
        self.draftModelRevision = draftModelRevision
        self.targetTokenizerHash = targetTokenizerHash
        self.draftTokenizerHash = draftTokenizerHash
        self.pairingHash = pairingHash
        self.tokenizerCompatible = tokenizerCompatible
        self.maxDraftTokens = maxDraftTokens.map { max(1, $0) }
    }

    public static let disabled = Self(enabled: false)

    public func matches(_ requested: TurboQuantSpeculativeEvidenceDimensions?) -> Bool {
        let requested = requested ?? .disabled
        guard enabled == requested.enabled else { return false }
        guard enabled else { return true }
        return draftModelID == requested.draftModelID
            && draftModelRevision == requested.draftModelRevision
            && targetTokenizerHash == requested.targetTokenizerHash
            && draftTokenizerHash == requested.draftTokenizerHash
            && pairingHash == requested.pairingHash
            && tokenizerCompatible == requested.tokenizerCompatible
            && maxDraftTokens == requested.maxDraftTokens
    }

    public var tupleSummaryParts: [String] {
        guard enabled else { return ["speculative=off"] }
        return [
            "speculative=on",
            draftModelID.map { "draft=\($0)" },
            draftModelRevision.map { "draftRevision=\($0)" },
            pairingHash.map { "pair=\($0)" },
            tokenizerCompatible.map { "tokenizer=\($0 ? "compatible" : "mismatch")" },
            maxDraftTokens.map { "draftTokens=\($0)" },
        ].compactMap(\.self)
    }
}

public struct TurboQuantSpeculativeTelemetry: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var state: TurboQuantSpeculativeRuntimeState
    public var dimensions: TurboQuantSpeculativeEvidenceDimensions
    public var proposedTokenCount: Int
    public var acceptedTokenCount: Int
    public var rejectedTokenCount: Int
    public var targetVerifiedTokenCount: Int
    public var rollbackCount: Int
    public var targetSequenceMatched: Bool?
    public var tokenizerCompatible: Bool?
    public var baselineDecodeTokensPerSecondP50: Double?
    public var speculativeDecodeTokensPerSecondP50: Double?
    public var disabledReason: TurboQuantSpeculativeDisableReason?

    public var acceptanceRate: Double? {
        guard proposedTokenCount > 0 else { return nil }
        return Double(acceptedTokenCount) / Double(proposedTokenCount)
    }

    public var p50DecodeSpeedup: Double? {
        guard let baseline = baselineDecodeTokensPerSecondP50,
              baseline > 0,
              let speculative = speculativeDecodeTokensPerSecondP50
        else {
            return nil
        }
        return speculative / baseline
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        state: TurboQuantSpeculativeRuntimeState,
        dimensions: TurboQuantSpeculativeEvidenceDimensions = .disabled,
        proposedTokenCount: Int = 0,
        acceptedTokenCount: Int = 0,
        rejectedTokenCount: Int = 0,
        targetVerifiedTokenCount: Int = 0,
        rollbackCount: Int = 0,
        targetSequenceMatched: Bool? = nil,
        tokenizerCompatible: Bool? = nil,
        baselineDecodeTokensPerSecondP50: Double? = nil,
        speculativeDecodeTokensPerSecondP50: Double? = nil,
        disabledReason: TurboQuantSpeculativeDisableReason? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.dimensions = dimensions
        self.proposedTokenCount = max(0, proposedTokenCount)
        self.acceptedTokenCount = min(max(0, acceptedTokenCount), self.proposedTokenCount)
        self.rejectedTokenCount = min(
            max(0, rejectedTokenCount),
            max(0, self.proposedTokenCount - self.acceptedTokenCount)
        )
        self.targetVerifiedTokenCount = max(0, targetVerifiedTokenCount)
        self.rollbackCount = max(0, rollbackCount)
        self.targetSequenceMatched = targetSequenceMatched
        self.tokenizerCompatible = tokenizerCompatible
        self.baselineDecodeTokensPerSecondP50 = baselineDecodeTokensPerSecondP50
        self.speculativeDecodeTokensPerSecondP50 = speculativeDecodeTokensPerSecondP50
        self.disabledReason = disabledReason
    }
}

public struct TurboQuantSpeculativeAdmissionBudget: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var enabled: Bool
    public var draftModelBytes: Int64
    public var draftKVBytesPerToken: Int64
    public var rollbackReserveBytes: Int64
    public var contextTokens: Int
    public var maxDraftTokens: Int

    public var draftKVBytes: Int64 {
        guard enabled else { return 0 }
        return Int64(max(0, contextTokens)) * draftKVBytesPerToken
    }

    public var totalReserveBytes: Int64 {
        guard enabled else { return 0 }
        return draftModelBytes + draftKVBytes + rollbackReserveBytes
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        enabled: Bool = false,
        draftModelBytes: Int64 = 0,
        draftKVBytesPerToken: Int64 = 0,
        rollbackReserveBytes: Int64 = 0,
        contextTokens: Int = 0,
        maxDraftTokens: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.draftModelBytes = max(0, draftModelBytes)
        self.draftKVBytesPerToken = max(0, draftKVBytesPerToken)
        self.rollbackReserveBytes = max(0, rollbackReserveBytes)
        self.contextTokens = max(0, contextTokens)
        self.maxDraftTokens = max(1, maxDraftTokens)
    }
}

public enum TurboQuantPlatformFeatureID: String, Codable, Sendable, CaseIterable {
    case adaptivePrecision
    case semanticMemory
    case multimodalMemory
    case agentWorkingMemory
    case openKVFormat
    case deviceMesh
    case personalizationAdapters
    case platformKillSwitches

    public var displayName: String {
        switch self {
        case .adaptivePrecision:
            "Adaptive precision"
        case .semanticMemory:
            "Semantic memory"
        case .multimodalMemory:
            "Multimodal memory"
        case .agentWorkingMemory:
            "Agent working memory"
        case .openKVFormat:
            "Open KV format"
        case .deviceMesh:
            "Device mesh"
        case .personalizationAdapters:
            "Personalization adapters"
        case .platformKillSwitches:
            "Platform kill switches"
        }
    }
}

public enum TurboQuantPlatformFeatureActivationState: String, Codable, Sendable, CaseIterable {
    case disabledDesignOnly
    case evidenceRequired
    case active
}

public struct TurboQuantPlatformFeatureGate: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var featureID: TurboQuantPlatformFeatureID
    public var activationState: TurboQuantPlatformFeatureActivationState
    public var killSwitchEnabled: Bool
    public var evidenceRequired: Bool
    public var notes: String?

    public var isProductActive: Bool {
        activationState == .active && !killSwitchEnabled && !evidenceRequired
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        featureID: TurboQuantPlatformFeatureID,
        activationState: TurboQuantPlatformFeatureActivationState = .disabledDesignOnly,
        killSwitchEnabled: Bool = true,
        evidenceRequired: Bool = true,
        notes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.featureID = featureID
        self.activationState = activationState
        self.killSwitchEnabled = killSwitchEnabled
        self.evidenceRequired = evidenceRequired
        self.notes = notes
    }

    public static let wave6DisabledDefaults: [Self] = TurboQuantPlatformFeatureID.allCases.map {
        Self(
            featureID: $0,
            notes: "Wave 6 design/schema gate only; product activation requires explicit evidence gates."
        )
    }
}
