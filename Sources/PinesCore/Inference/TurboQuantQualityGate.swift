import Foundation

public enum TurboQuantBenchmarkSuiteID: String, Codable, Sendable, CaseIterable {
    case tinyDeterministicLogitsV1 = "tiny-deterministic-logits-v1"
    case prefillExactnessV1 = "prefill-exactness-v1"
    case fallbackEquivalenceV1 = "fallback-equivalence-v1"
    case longContextNeedleV1 = "long-context-needle-v1"
    case snapshotRoundtripV1 = "snapshot-roundtrip-v1"
    case mobileMemoryAcceptanceV1 = "mobile-memory-acceptance-v1"
}

public struct TurboQuantQualityGate: Hashable, Codable, Sendable {
    public static let schemaVersion = 1
    public static let gateVersion = 1

    public var schemaVersion: Int
    public var gateVersion: Int
    public var benchmarkSuiteID: String
    public var deterministicTop1MatchRate: Double
    public var logitKLDivergenceMean: Double
    public var logitMaxAbsErrorP95: Double
    public var perplexityDeltaPercent: Double?
    public var retrievalNeedlePassRate: Double?
    public var taskEvalDeltaPercent: Double?
    public var attentionOutputCosineMean: Double?
    public var noNaNOrInf: Bool
    public var fallbackEquivalent: Bool
    public var prefillExact: Bool
    public var snapshotRoundtripEquivalent: Bool?
    public var profileQualityThresholdOverride: String?
    public var gateReason: String?
    public var passed: Bool

    public init(
        schemaVersion: Int = Self.schemaVersion,
        gateVersion: Int = Self.gateVersion,
        benchmarkSuiteID: String,
        deterministicTop1MatchRate: Double,
        logitKLDivergenceMean: Double,
        logitMaxAbsErrorP95: Double,
        perplexityDeltaPercent: Double? = nil,
        retrievalNeedlePassRate: Double? = nil,
        taskEvalDeltaPercent: Double? = nil,
        attentionOutputCosineMean: Double? = nil,
        noNaNOrInf: Bool,
        fallbackEquivalent: Bool,
        prefillExact: Bool,
        snapshotRoundtripEquivalent: Bool? = nil,
        profileQualityThresholdOverride: String? = nil,
        gateReason: String? = nil,
        passed: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.gateVersion = gateVersion
        self.benchmarkSuiteID = benchmarkSuiteID
        self.deterministicTop1MatchRate = deterministicTop1MatchRate
        self.logitKLDivergenceMean = logitKLDivergenceMean
        self.logitMaxAbsErrorP95 = logitMaxAbsErrorP95
        self.perplexityDeltaPercent = perplexityDeltaPercent
        self.retrievalNeedlePassRate = retrievalNeedlePassRate
        self.taskEvalDeltaPercent = taskEvalDeltaPercent
        self.attentionOutputCosineMean = attentionOutputCosineMean
        self.noNaNOrInf = noNaNOrInf
        self.fallbackEquivalent = fallbackEquivalent
        self.prefillExact = prefillExact
        self.snapshotRoundtripEquivalent = snapshotRoundtripEquivalent
        self.profileQualityThresholdOverride = profileQualityThresholdOverride
        self.gateReason = gateReason
        self.passed = passed
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        gateVersion: Int = Self.gateVersion,
        benchmarkSuiteID: TurboQuantBenchmarkSuiteID,
        deterministicTop1MatchRate: Double,
        logitKLDivergenceMean: Double,
        logitMaxAbsErrorP95: Double,
        perplexityDeltaPercent: Double? = nil,
        retrievalNeedlePassRate: Double? = nil,
        taskEvalDeltaPercent: Double? = nil,
        attentionOutputCosineMean: Double? = nil,
        noNaNOrInf: Bool,
        fallbackEquivalent: Bool,
        prefillExact: Bool,
        snapshotRoundtripEquivalent: Bool? = nil,
        profileQualityThresholdOverride: String? = nil,
        gateReason: String? = nil,
        passed: Bool
    ) {
        self.init(
            schemaVersion: schemaVersion,
            gateVersion: gateVersion,
            benchmarkSuiteID: benchmarkSuiteID.rawValue,
            deterministicTop1MatchRate: deterministicTop1MatchRate,
            logitKLDivergenceMean: logitKLDivergenceMean,
            logitMaxAbsErrorP95: logitMaxAbsErrorP95,
            perplexityDeltaPercent: perplexityDeltaPercent,
            retrievalNeedlePassRate: retrievalNeedlePassRate,
            taskEvalDeltaPercent: taskEvalDeltaPercent,
            attentionOutputCosineMean: attentionOutputCosineMean,
            noNaNOrInf: noNaNOrInf,
            fallbackEquivalent: fallbackEquivalent,
            prefillExact: prefillExact,
            snapshotRoundtripEquivalent: snapshotRoundtripEquivalent,
            profileQualityThresholdOverride: profileQualityThresholdOverride,
            gateReason: gateReason,
            passed: passed
        )
    }
}
