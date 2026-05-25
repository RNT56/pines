import Foundation

public enum RuntimeEvidenceLevel: String, Codable, Sendable, CaseIterable {
    case unverified
    case smokeTested
    case verified
    case certified
    case revoked

    public var canMakeProductCompatibilityClaim: Bool {
        self == .verified || self == .certified
    }
}

public struct RuntimeProfileEvidence: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var id: UUID
    public var schemaVersion: Int
    public var evidenceLevel: RuntimeEvidenceLevel
    public var compatibilityPairID: String
    public var modelID: String
    public var modelRevision: String?
    public var tokenizerHash: String?
    public var profileHash: String?
    public var fallbackContractHash: String
    public var deviceClass: DevicePerformanceClass
    public var hardwareModel: String?
    public var osBuild: String
    public var userMode: TurboQuantUserMode
    public var turboQuantPreset: String?
    public var valueBits: Int?
    public var groupSize: Int?
    public var layoutVersion: Int?
    public var activeAttentionPath: TurboQuantAttentionPath?
    public var admittedContextTokens: Int
    public var peakMemoryBytes: Int64
    public var promptTokensPerSecond: Double?
    public var decodeTokensPerSecondP50: Double?
    public var decodeTokensPerSecondP95: Double?
    public var firstTokenLatencyMS: Double?
    public var qualityGate: TurboQuantQualityGate
    public var memoryCalibrationSampleID: UUID?
    public var revokedReason: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = Self.schemaVersion,
        evidenceLevel: RuntimeEvidenceLevel,
        compatibilityPairID: String,
        modelID: String,
        modelRevision: String? = nil,
        tokenizerHash: String? = nil,
        profileHash: String? = nil,
        fallbackContractHash: String,
        deviceClass: DevicePerformanceClass,
        hardwareModel: String? = nil,
        osBuild: String,
        userMode: TurboQuantUserMode,
        turboQuantPreset: String? = nil,
        valueBits: Int? = nil,
        groupSize: Int? = nil,
        layoutVersion: Int? = nil,
        activeAttentionPath: TurboQuantAttentionPath? = nil,
        admittedContextTokens: Int,
        peakMemoryBytes: Int64,
        promptTokensPerSecond: Double? = nil,
        decodeTokensPerSecondP50: Double? = nil,
        decodeTokensPerSecondP95: Double? = nil,
        firstTokenLatencyMS: Double? = nil,
        qualityGate: TurboQuantQualityGate,
        memoryCalibrationSampleID: UUID? = nil,
        revokedReason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.evidenceLevel = evidenceLevel
        self.compatibilityPairID = compatibilityPairID
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.tokenizerHash = tokenizerHash
        self.profileHash = profileHash
        self.fallbackContractHash = fallbackContractHash
        self.deviceClass = deviceClass
        self.hardwareModel = hardwareModel
        self.osBuild = osBuild
        self.userMode = userMode
        self.turboQuantPreset = turboQuantPreset
        self.valueBits = valueBits
        self.groupSize = groupSize
        self.layoutVersion = layoutVersion
        self.activeAttentionPath = activeAttentionPath
        self.admittedContextTokens = max(0, admittedContextTokens)
        self.peakMemoryBytes = max(0, peakMemoryBytes)
        self.promptTokensPerSecond = promptTokensPerSecond
        self.decodeTokensPerSecondP50 = decodeTokensPerSecondP50
        self.decodeTokensPerSecondP95 = decodeTokensPerSecondP95
        self.firstTokenLatencyMS = firstTokenLatencyMS
        self.qualityGate = qualityGate
        self.memoryCalibrationSampleID = memoryCalibrationSampleID
        self.revokedReason = revokedReason
        self.createdAt = createdAt
    }
}

public actor ProfileEvidenceStore {
    private var records: [UUID: RuntimeProfileEvidence] = [:]

    public init(records: [RuntimeProfileEvidence] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    public func upsert(_ evidence: RuntimeProfileEvidence) {
        records[evidence.id] = evidence
    }

    public func evidence(
        modelID: String,
        deviceClass: DevicePerformanceClass,
        mode: TurboQuantUserMode,
        fallbackContractHash: String
    ) -> RuntimeProfileEvidence? {
        records.values
            .filter {
                $0.modelID == modelID
                    && $0.deviceClass == deviceClass
                    && $0.userMode == mode
                    && $0.fallbackContractHash == fallbackContractHash
                    && $0.evidenceLevel != .revoked
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    public func revoke(id: UUID, reason: String) {
        guard var evidence = records[id] else { return }
        evidence.evidenceLevel = .revoked
        evidence.revokedReason = reason
        records[id] = evidence
    }
}
