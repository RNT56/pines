import Foundation

public struct TurboQuantRunDecision: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var decisionID: String
    public var compatibilityPairID: String?
    public var admission: LocalRuntimeAdmissionPlan?
    public var selectedAttentionPath: TurboQuantAttentionPath?
    public var rejectedPaths: [RejectedPath]
    public var cacheLifecycle: String?
    public var actualKeyBitsPerValue: Double?
    public var actualValueBitsPerValue: Double?
    public var fallbackUsed: Bool
    public var fallbackReason: String?
    public var rawShadowAllocated: Bool?
    public var packedFallbackAllocated: Bool?
    public var compressedKeyBytes: Int64?
    public var compressedValueBytes: Int64?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var speculativeTelemetry: TurboQuantSpeculativeTelemetry?
    public var speculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision?
  public var platformEvidenceDimensions: TurboQuantPlatformEvidenceDimensions?
  public var platformUnlockPolicy: TurboQuantPlatformUnlockPolicy?
    public var contextAssemblyPlanID: String?
    public var memoryCalibrationSampleID: String?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        decisionID: String = UUID().uuidString,
        compatibilityPairID: String? = nil,
        admission: LocalRuntimeAdmissionPlan? = nil,
        selectedAttentionPath: TurboQuantAttentionPath? = nil,
        rejectedPaths: [RejectedPath] = [],
        cacheLifecycle: String? = nil,
        actualKeyBitsPerValue: Double? = nil,
        actualValueBitsPerValue: Double? = nil,
        fallbackUsed: Bool = false,
        fallbackReason: String? = nil,
        rawShadowAllocated: Bool? = nil,
        packedFallbackAllocated: Bool? = nil,
        compressedKeyBytes: Int64? = nil,
        compressedValueBytes: Int64? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        speculativeTelemetry: TurboQuantSpeculativeTelemetry? = nil,
        speculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision? = nil,
    platformEvidenceDimensions: TurboQuantPlatformEvidenceDimensions? = nil,
    platformUnlockPolicy: TurboQuantPlatformUnlockPolicy? = nil,
        contextAssemblyPlanID: String? = nil,
        memoryCalibrationSampleID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.decisionID = decisionID
        self.compatibilityPairID = compatibilityPairID
        self.admission = admission
        self.selectedAttentionPath = selectedAttentionPath
        self.rejectedPaths = rejectedPaths
        self.cacheLifecycle = cacheLifecycle
        self.actualKeyBitsPerValue = actualKeyBitsPerValue
        self.actualValueBitsPerValue = actualValueBitsPerValue
        self.fallbackUsed = fallbackUsed
        self.fallbackReason = fallbackReason
        self.rawShadowAllocated = rawShadowAllocated
        self.packedFallbackAllocated = packedFallbackAllocated
        self.compressedKeyBytes = compressedKeyBytes.map { max(0, $0) }
        self.compressedValueBytes = compressedValueBytes.map { max(0, $0) }
        self.inputTokens = inputTokens.map { max(0, $0) }
        self.outputTokens = outputTokens.map { max(0, $0) }
        self.speculativeTelemetry = speculativeTelemetry
        self.speculativeAutoDisableDecision = speculativeAutoDisableDecision
    self.platformEvidenceDimensions = platformEvidenceDimensions
    self.platformUnlockPolicy = platformUnlockPolicy
        self.contextAssemblyPlanID = contextAssemblyPlanID
        self.memoryCalibrationSampleID = memoryCalibrationSampleID
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if fallbackUsed, fallbackReason?.isEmpty != false {
            errors.append("fallbackUsed requires fallbackReason")
        }
        if rejectedPaths.contains(where: { $0.reason.isEmpty }) {
            errors.append("rejected paths require reasons")
        }
        if speculativeTelemetry?.targetSequenceMatched == false,
      speculativeAutoDisableDecision?.shouldDisable != true
    {
            errors.append("target mismatch requires speculative auto-disable decision")
        }
    if let platformUnlockPolicy {
      errors.append(contentsOf: platformUnlockPolicy.validationErrors)
    }
        return errors
    }
}
