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
    public var speculativeDimensions: TurboQuantSpeculativeEvidenceDimensions?
    public var speculativeTelemetry: TurboQuantSpeculativeTelemetry?
    public var speculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision?
  public var platformEvidenceDimensions: TurboQuantPlatformEvidenceDimensions?
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
        speculativeDimensions: TurboQuantSpeculativeEvidenceDimensions? = nil,
        speculativeTelemetry: TurboQuantSpeculativeTelemetry? = nil,
        speculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision? = nil,
    platformEvidenceDimensions: TurboQuantPlatformEvidenceDimensions? = nil,
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
        self.speculativeDimensions = speculativeDimensions
        self.speculativeTelemetry = speculativeTelemetry
        self.speculativeAutoDisableDecision = speculativeAutoDisableDecision
    self.platformEvidenceDimensions = platformEvidenceDimensions
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

public struct RuntimeEvidenceRevocation: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var id: UUID
    public var schemaVersion: Int
    public var evidenceID: UUID
    public var revokedAt: Date
    public var reason: String
    public var replacementEvidenceID: UUID?

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = Self.schemaVersion,
        evidenceID: UUID,
        revokedAt: Date = Date(),
        reason: String,
        replacementEvidenceID: UUID? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.evidenceID = evidenceID
        self.revokedAt = revokedAt
        self.reason = reason
        self.replacementEvidenceID = replacementEvidenceID
    }
}

public actor ProfileEvidenceStore {
    private var records: [UUID: RuntimeProfileEvidence] = [:]
    private var revocations: [RuntimeEvidenceRevocation] = []

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

    public func evidence(
        modelID: String,
        modelRevision: String?,
        tokenizerHash: String?,
        profileHash: String?,
        compatibilityPairID: String,
        deviceClass: DevicePerformanceClass,
        hardwareModel: String?,
        osBuild: String?,
        mode: TurboQuantUserMode,
        fallbackContractHash: String,
        layoutVersion: Int?,
        speculativeDimensions: TurboQuantSpeculativeEvidenceDimensions? = nil,
    platformEvidenceDimensions: TurboQuantPlatformEvidenceDimensions? = nil,
        minimumContextTokens: Int
    ) -> RuntimeProfileEvidence? {
        records.values
            .filter {
                $0.modelID == modelID
                    && $0.modelRevision == modelRevision
                    && $0.tokenizerHash == tokenizerHash
                    && $0.profileHash == profileHash
                    && $0.compatibilityPairID == compatibilityPairID
                    && $0.deviceClass == deviceClass
                    && (hardwareModel == nil || $0.hardwareModel == hardwareModel)
                    && (osBuild == nil || $0.osBuild == osBuild)
                    && $0.userMode == mode
                    && $0.fallbackContractHash == fallbackContractHash
                    && $0.layoutVersion == layoutVersion
                    && ($0.speculativeDimensions ?? .disabled).matches(speculativeDimensions)
          && ($0.platformEvidenceDimensions ?? .disabled).matches(platformEvidenceDimensions)
                    && $0.admittedContextTokens >= minimumContextTokens
                    && $0.evidenceLevel.canMakeProductCompatibilityClaim
                    && $0.revokedReason == nil
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    @discardableResult
    public func importBenchmarkReport(
        _ report: TurboQuantBenchmarkReport,
        policy: TurboQuantBenchmarkImportPolicy
    ) throws -> TurboQuantBenchmarkImportResult {
        let result = try TurboQuantBenchmarkImporter().importReport(report, policy: policy)
        let revoked = revokeConflictingEvidence(replacedBy: result.evidence)
        records[result.evidence.id] = result.evidence
        return TurboQuantBenchmarkImportResult(
            evidence: result.evidence,
            memoryCalibrationSample: result.memoryCalibrationSample,
            revocations: revoked
        )
    }

    @discardableResult
    public func revoke(
        id: UUID,
        reason: String,
        replacementEvidenceID: UUID? = nil
    ) -> RuntimeEvidenceRevocation? {
        guard var evidence = records[id] else { return nil }
        evidence.evidenceLevel = .revoked
        evidence.revokedReason = reason
        records[id] = evidence
        let revocation = RuntimeEvidenceRevocation(
            evidenceID: id,
            reason: reason,
            replacementEvidenceID: replacementEvidenceID
        )
        revocations.append(revocation)
        return revocation
    }

    public func allEvidence() -> [RuntimeProfileEvidence] {
        records.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func allRevocations() -> [RuntimeEvidenceRevocation] {
        revocations.sorted { $0.revokedAt > $1.revokedAt }
    }

  private func revokeConflictingEvidence(replacedBy replacement: RuntimeProfileEvidence)
    -> [RuntimeEvidenceRevocation]
  {
        var revoked: [RuntimeEvidenceRevocation] = []
    for record in records.values
    where conflicts(record, replacement) && record.evidenceLevel != .revoked {
            if let revocation = revoke(
                id: record.id,
                reason: "superseded by newer benchmark evidence",
                replacementEvidenceID: replacement.id
            ) {
                revoked.append(revocation)
            }
        }
        return revoked
    }

    private func conflicts(_ lhs: RuntimeProfileEvidence, _ rhs: RuntimeProfileEvidence) -> Bool {
        lhs.modelID == rhs.modelID
            && lhs.modelRevision == rhs.modelRevision
            && lhs.tokenizerHash == rhs.tokenizerHash
            && lhs.profileHash == rhs.profileHash
            && lhs.deviceClass == rhs.deviceClass
            && lhs.hardwareModel == rhs.hardwareModel
            && lhs.osBuild == rhs.osBuild
            && lhs.userMode == rhs.userMode
            && lhs.fallbackContractHash == rhs.fallbackContractHash
            && lhs.compatibilityPairID == rhs.compatibilityPairID
            && lhs.layoutVersion == rhs.layoutVersion
            && lhs.activeAttentionPath == rhs.activeAttentionPath
            && (lhs.speculativeDimensions ?? .disabled).matches(rhs.speculativeDimensions)
      && (lhs.platformEvidenceDimensions ?? .disabled).matches(rhs.platformEvidenceDimensions)
            && lhs.admittedContextTokens == rhs.admittedContextTokens
            && lhs.id != rhs.id
    }
}

public protocol TurboQuantEvidenceRepository: Sendable {
    func upsertTurboQuantProfileEvidence(_ evidence: RuntimeProfileEvidence) async throws
    func turboQuantProfileEvidence(
        modelID: String,
        modelRevision: String?,
        tokenizerHash: String?,
        profileHash: String?,
        compatibilityPairID: String?,
        deviceClass: DevicePerformanceClass,
        hardwareModel: String?,
        osBuild: String?,
        mode: TurboQuantUserMode,
        fallbackContractHash: String?,
        layoutVersion: Int?,
        speculativeDimensions: TurboQuantSpeculativeEvidenceDimensions?,
    platformEvidenceDimensions: TurboQuantPlatformEvidenceDimensions?,
        minimumContextTokens: Int
    ) async throws -> RuntimeProfileEvidence?
    func listTurboQuantProfileEvidence(modelID: String?) async throws -> [RuntimeProfileEvidence]
    func revokeTurboQuantProfileEvidence(
        id: UUID,
        reason: String,
        replacementEvidenceID: UUID?
    ) async throws
    func upsertRuntimeMemoryCalibrationSample(_ sample: RuntimeMemoryCalibrationSample) async throws
    func upsertRuntimeMemoryCalibration(_ calibration: RuntimeMemoryCalibration) async throws
}
