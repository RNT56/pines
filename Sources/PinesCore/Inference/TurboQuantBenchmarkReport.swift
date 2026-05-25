import Foundation

public struct TurboQuantBenchmarkReport: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var compatibilityPairID: String
    public var producer: SchemaProducer
    public var device: TurboQuantBenchmarkDevice
    public var model: TurboQuantBenchmarkModel
    public var runtime: TurboQuantBenchmarkRuntime
    public var metrics: TurboQuantBenchmarkMetrics
    public var qualityGate: TurboQuantQualityGate
    public var memoryCalibrationSample: RuntimeMemoryCalibrationSample?
    public var createdAt: Date

    public init(
        schemaVersion: Int = Self.schemaVersion,
        compatibilityPairID: String,
        producer: SchemaProducer,
        device: TurboQuantBenchmarkDevice,
        model: TurboQuantBenchmarkModel,
        runtime: TurboQuantBenchmarkRuntime,
        metrics: TurboQuantBenchmarkMetrics,
        qualityGate: TurboQuantQualityGate,
        memoryCalibrationSample: RuntimeMemoryCalibrationSample? = nil,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.compatibilityPairID = compatibilityPairID
        self.producer = producer
        self.device = device
        self.model = model
        self.runtime = runtime
        self.metrics = metrics
        self.qualityGate = qualityGate
        self.memoryCalibrationSample = memoryCalibrationSample
        self.createdAt = createdAt
    }
}

public struct TurboQuantBenchmarkDevice: Hashable, Codable, Sendable {
    public var deviceClass: DevicePerformanceClass
    public var hardwareModel: String
    public var osBuild: String
    public var availableMemoryBytesAtStart: Int64
    public var metalDeviceName: String?
    public var lowPowerMode: Bool
    public var thermalState: String

    public init(
        deviceClass: DevicePerformanceClass,
        hardwareModel: String,
        osBuild: String,
        availableMemoryBytesAtStart: Int64,
        metalDeviceName: String? = nil,
        lowPowerMode: Bool = false,
        thermalState: String = "nominal"
    ) {
        self.deviceClass = deviceClass
        self.hardwareModel = hardwareModel
        self.osBuild = osBuild
        self.availableMemoryBytesAtStart = max(0, availableMemoryBytesAtStart)
        self.metalDeviceName = metalDeviceName
        self.lowPowerMode = lowPowerMode
        self.thermalState = thermalState
    }
}

public struct TurboQuantBenchmarkModel: Hashable, Codable, Sendable {
    public var id: String
    public var revision: String?
    public var tokenizerHash: String?
    public var profileHash: String?
    public var architecture: String?
    public var layers: Int?
    public var kvHeads: Int?
    public var headDim: Int?

    public init(
        id: String,
        revision: String? = nil,
        tokenizerHash: String? = nil,
        profileHash: String? = nil,
        architecture: String? = nil,
        layers: Int? = nil,
        kvHeads: Int? = nil,
        headDim: Int? = nil
    ) {
        self.id = id
        self.revision = revision
        self.tokenizerHash = tokenizerHash
        self.profileHash = profileHash
        self.architecture = architecture
        self.layers = layers
        self.kvHeads = kvHeads
        self.headDim = headDim
    }
}

public struct TurboQuantBenchmarkRuntime: Hashable, Codable, Sendable {
    public var userMode: TurboQuantUserMode
    public var fallbackContractHash: String
    public var preset: String?
    public var valueBits: Int?
    public var groupSize: Int?
    public var layoutVersion: Int?
    public var attentionPath: TurboQuantAttentionPath?
    public var kernelProfile: String?
    public var speculativeDimensions: TurboQuantSpeculativeEvidenceDimensions?
    public var admittedContextTokens: Int
    public var reservedCompletionTokens: Int

    public init(
        userMode: TurboQuantUserMode,
        fallbackContractHash: String,
        preset: String? = nil,
        valueBits: Int? = nil,
        groupSize: Int? = nil,
        layoutVersion: Int? = nil,
        attentionPath: TurboQuantAttentionPath? = nil,
        kernelProfile: String? = nil,
        speculativeDimensions: TurboQuantSpeculativeEvidenceDimensions? = nil,
        admittedContextTokens: Int,
        reservedCompletionTokens: Int
    ) {
        self.userMode = userMode
        self.fallbackContractHash = fallbackContractHash
        self.preset = preset
        self.valueBits = valueBits
        self.groupSize = groupSize
        self.layoutVersion = layoutVersion
        self.attentionPath = attentionPath
        self.kernelProfile = kernelProfile
        self.speculativeDimensions = speculativeDimensions
        self.admittedContextTokens = max(0, admittedContextTokens)
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
    }
}

public struct TurboQuantBenchmarkMetrics: Hashable, Codable, Sendable {
    public var contextTokens: Int
    public var firstTokenLatencyMS: Double?
    public var prefillTokensPerSecond: Double?
    public var decodeTokensPerSecondP50: Double?
    public var decodeTokensPerSecondP95: Double?
    public var peakMemoryBytes: Int64?
    public var compressedKVBytes: Int64?
    public var rawShadowBytes: Int64?
    public var packedFallbackBytes: Int64?
    public var decodedFallbackScratchBytes: Int64?
    public var memoryWarningsSeen: Int
    public var fallbackUsed: Bool
    public var fallbackReason: String?
    public var jetsamObserved: Bool
    public var speculativeTelemetry: TurboQuantSpeculativeTelemetry?

    public init(
        contextTokens: Int,
        firstTokenLatencyMS: Double? = nil,
        prefillTokensPerSecond: Double? = nil,
        decodeTokensPerSecondP50: Double? = nil,
        decodeTokensPerSecondP95: Double? = nil,
        peakMemoryBytes: Int64? = nil,
        compressedKVBytes: Int64? = nil,
        rawShadowBytes: Int64? = nil,
        packedFallbackBytes: Int64? = nil,
        decodedFallbackScratchBytes: Int64? = nil,
        memoryWarningsSeen: Int = 0,
        fallbackUsed: Bool = false,
        fallbackReason: String? = nil,
        jetsamObserved: Bool = false,
        speculativeTelemetry: TurboQuantSpeculativeTelemetry? = nil
    ) {
        self.contextTokens = max(0, contextTokens)
        self.firstTokenLatencyMS = firstTokenLatencyMS
        self.prefillTokensPerSecond = prefillTokensPerSecond
        self.decodeTokensPerSecondP50 = decodeTokensPerSecondP50
        self.decodeTokensPerSecondP95 = decodeTokensPerSecondP95
        self.peakMemoryBytes = peakMemoryBytes.map { max(0, $0) }
        self.compressedKVBytes = compressedKVBytes.map { max(0, $0) }
        self.rawShadowBytes = rawShadowBytes.map { max(0, $0) }
        self.packedFallbackBytes = packedFallbackBytes.map { max(0, $0) }
        self.decodedFallbackScratchBytes = decodedFallbackScratchBytes.map { max(0, $0) }
        self.memoryWarningsSeen = max(0, memoryWarningsSeen)
        self.fallbackUsed = fallbackUsed
        self.fallbackReason = fallbackReason
        self.jetsamObserved = jetsamObserved
        self.speculativeTelemetry = speculativeTelemetry
    }
}

public enum TurboQuantBenchmarkImportFailure: Error, Hashable, LocalizedError, Sendable {
    case unsupportedSchema(name: String, version: Int)
    case missingCompatibilityPairID
    case unknownCompatibilityPairID(String)
    case missingFallbackContractHash
    case fallbackContractHashMismatch(String)
    case layoutVersionMismatch(expected: [Int], actual: Int?)
    case missingBenchmarkSuiteID
    case qualityGateFailed(String?)
    case memoryGateFailed(String)
    case speculativeGateFailed(String)
    case verifiedEvidenceDisabled

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let name, let version):
            "Unsupported \(name) schema version \(version)."
        case .missingCompatibilityPairID:
            "Benchmark report is missing a compatibility-pair ID."
        case .unknownCompatibilityPairID(let id):
            "Compatibility pair \(id) is not accepted for release evidence."
        case .missingFallbackContractHash:
            "Benchmark report is missing a fallback-contract hash."
        case .fallbackContractHashMismatch(let hash):
            "Fallback-contract hash \(hash) is not accepted for release evidence."
        case .layoutVersionMismatch(let expected, let actual):
            "Benchmark layout version \(actual.map(String.init) ?? "nil") is not accepted for release evidence; expected one of \(expected)."
        case .missingBenchmarkSuiteID:
            "Benchmark report is missing a benchmark suite ID."
        case .qualityGateFailed(let reason):
            reason ?? "Quality gate failed."
        case .memoryGateFailed(let reason):
            reason
        case .speculativeGateFailed(let reason):
            reason
        case .verifiedEvidenceDisabled:
            "Verified evidence import is disabled by policy."
        }
    }
}

public struct TurboQuantBenchmarkImportPolicy: Hashable, Codable, Sendable {
    public var acceptedCompatibilityPairIDs: Set<String>
    public var acceptedFallbackContractHashes: Set<String>
    public var acceptedLayoutVersions: Set<Int>
    public var requestedEvidenceLevel: RuntimeEvidenceLevel
    public var allowVerifiedEvidence: Bool
    public var allowMemoryWarningsForVerified: Bool
    public var speculativeAutoDisablePolicy: TurboQuantSpeculativeAutoDisablePolicy

    public init(
        acceptedCompatibilityPairIDs: Set<String> = [],
        acceptedFallbackContractHashes: Set<String> = [],
        acceptedLayoutVersions: Set<Int> = [],
        requestedEvidenceLevel: RuntimeEvidenceLevel = .smokeTested,
        allowVerifiedEvidence: Bool = false,
        allowMemoryWarningsForVerified: Bool = false,
        speculativeAutoDisablePolicy: TurboQuantSpeculativeAutoDisablePolicy = .productDefault
    ) {
        self.acceptedCompatibilityPairIDs = acceptedCompatibilityPairIDs
        self.acceptedFallbackContractHashes = acceptedFallbackContractHashes
        self.acceptedLayoutVersions = acceptedLayoutVersions
        self.requestedEvidenceLevel = requestedEvidenceLevel
        self.allowVerifiedEvidence = allowVerifiedEvidence
        self.allowMemoryWarningsForVerified = allowMemoryWarningsForVerified
        self.speculativeAutoDisablePolicy = speculativeAutoDisablePolicy
    }
}

public struct TurboQuantBenchmarkImportResult: Hashable, Codable, Sendable {
    public var evidence: RuntimeProfileEvidence
    public var memoryCalibrationSample: RuntimeMemoryCalibrationSample?
    public var revocations: [RuntimeEvidenceRevocation]

    public init(
        evidence: RuntimeProfileEvidence,
        memoryCalibrationSample: RuntimeMemoryCalibrationSample?,
        revocations: [RuntimeEvidenceRevocation] = []
    ) {
        self.evidence = evidence
        self.memoryCalibrationSample = memoryCalibrationSample
        self.revocations = revocations
    }
}

public struct TurboQuantCoreBenchmarkReport: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var mlxSwiftCommit: String?
    public var storageEstimate: TurboQuantCoreStorageEstimate
    public var pathDecision: TurboQuantCoreAttentionDecision?
    public var metrics: TurboQuantCoreBenchmarkMetrics
    public var hiddenCopyAudit: TurboQuantCoreHiddenCopyAudit

    public init(
        schemaVersion: Int = Self.schemaVersion,
        mlxSwiftCommit: String? = nil,
        storageEstimate: TurboQuantCoreStorageEstimate,
        pathDecision: TurboQuantCoreAttentionDecision? = nil,
        metrics: TurboQuantCoreBenchmarkMetrics,
        hiddenCopyAudit: TurboQuantCoreHiddenCopyAudit
    ) {
        self.schemaVersion = schemaVersion
        self.mlxSwiftCommit = mlxSwiftCommit
        self.storageEstimate = storageEstimate
        self.pathDecision = pathDecision
        self.metrics = metrics
        self.hiddenCopyAudit = hiddenCopyAudit
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mlxSwiftCommit
        case storageEstimate
        case pathDecision
        case metrics
        case hiddenCopyAudit
    }
}

public struct TurboQuantCoreStorageEstimate: Hashable, Codable, Sendable {
    public var totalBytes: Int
    public var actualBitsPerValue: Double

    public init(totalBytes: Int, actualBitsPerValue: Double) {
        self.totalBytes = max(0, totalBytes)
        self.actualBitsPerValue = actualBitsPerValue
    }
}

public struct TurboQuantCoreAttentionDecision: Hashable, Sendable {
    public var selectedPath: TurboQuantAttentionPath
    public var estimatedScratchBytes: Int

    public init(selectedPath: TurboQuantAttentionPath, estimatedScratchBytes: Int = 0) {
        self.selectedPath = selectedPath
        self.estimatedScratchBytes = max(0, estimatedScratchBytes)
    }
}

extension TurboQuantCoreAttentionDecision: Codable {
    private enum CodingKeys: String, CodingKey {
        case selectedPath
        case estimatedScratchBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedPath = try container.decode(TurboQuantAttentionPath.self, forKey: .selectedPath)
        estimatedScratchBytes = try container.decodeIfPresent(Int.self, forKey: .estimatedScratchBytes) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedPath, forKey: .selectedPath)
        try container.encode(estimatedScratchBytes, forKey: .estimatedScratchBytes)
    }
}

public struct TurboQuantCoreBenchmarkMetrics: Hashable, Codable, Sendable {
    public var contextTokens: Int
    public var headDimension: Int
    public var queryLength: Int
    public var preset: String
    public var valueBits: Int?
    public var groupSize: Int
    public var layoutVersion: Int?
    public var scaleStorage: String?
    public var warmupIterations: Int?
    public var firstTokenLatencyMS: Double?
    public var prefillTokensPerSecond: Double?
    public var decodeTokensPerSecondP50: Double?
    public var decodeTokensPerSecondP95: Double?
    public var totalBytes: Int
    public var compressedKVBytes: Int
    public var peakMemoryBytes: Int?
    public var actualBitsPerValue: Double
    public var fallbackUsed: Bool
    public var fallbackReason: String?
    public var memoryWarningsSeen: Int
    public var jetsamObserved: Bool

    public init(
        contextTokens: Int,
        headDimension: Int,
        queryLength: Int,
        preset: String,
        valueBits: Int? = nil,
        groupSize: Int,
        layoutVersion: Int? = nil,
        scaleStorage: String? = nil,
        warmupIterations: Int? = nil,
        firstTokenLatencyMS: Double? = nil,
        prefillTokensPerSecond: Double? = nil,
        decodeTokensPerSecondP50: Double? = nil,
        decodeTokensPerSecondP95: Double? = nil,
        totalBytes: Int,
        compressedKVBytes: Int,
        peakMemoryBytes: Int? = nil,
        actualBitsPerValue: Double,
        fallbackUsed: Bool = false,
        fallbackReason: String? = nil,
        memoryWarningsSeen: Int = 0,
        jetsamObserved: Bool = false
    ) {
        self.contextTokens = max(0, contextTokens)
        self.headDimension = max(0, headDimension)
        self.queryLength = max(0, queryLength)
        self.preset = preset
        self.valueBits = valueBits
        self.groupSize = max(1, groupSize)
        self.layoutVersion = layoutVersion
        self.scaleStorage = scaleStorage
        self.warmupIterations = warmupIterations.map { max(0, $0) }
        self.firstTokenLatencyMS = firstTokenLatencyMS
        self.prefillTokensPerSecond = prefillTokensPerSecond
        self.decodeTokensPerSecondP50 = decodeTokensPerSecondP50
        self.decodeTokensPerSecondP95 = decodeTokensPerSecondP95
        self.totalBytes = max(0, totalBytes)
        self.compressedKVBytes = max(0, compressedKVBytes)
        self.peakMemoryBytes = peakMemoryBytes
        self.actualBitsPerValue = actualBitsPerValue
        self.fallbackUsed = fallbackUsed
        self.fallbackReason = fallbackReason
        self.memoryWarningsSeen = max(0, memoryWarningsSeen)
        self.jetsamObserved = jetsamObserved
    }
}

public enum TurboQuantCoreHiddenCopyAuditStatus: String, Codable, Sendable {
    case pass
    case warning
    case fail
    case pending
    case skipped
}

public struct TurboQuantCoreHiddenCopyAudit: Hashable, Codable, Sendable {
    public var status: TurboQuantCoreHiddenCopyAuditStatus
    public var notes: [String]

    public init(status: TurboQuantCoreHiddenCopyAuditStatus, notes: [String] = []) {
        self.status = status
        self.notes = notes
    }
}

public struct TurboQuantCoreBenchmarkAdapterContext: Hashable, Codable, Sendable {
    public var compatibilityPairID: String
    public var device: TurboQuantBenchmarkDevice
    public var model: TurboQuantBenchmarkModel
    public var runtime: TurboQuantBenchmarkRuntime
    public var qualityGate: TurboQuantQualityGate
    public var memoryCalibrationSample: RuntimeMemoryCalibrationSample?
    public var createdAt: Date

    public init(
        compatibilityPairID: String,
        device: TurboQuantBenchmarkDevice,
        model: TurboQuantBenchmarkModel,
        runtime: TurboQuantBenchmarkRuntime,
        qualityGate: TurboQuantQualityGate,
        memoryCalibrationSample: RuntimeMemoryCalibrationSample? = nil,
        createdAt: Date = Date()
    ) {
        self.compatibilityPairID = compatibilityPairID
        self.device = device
        self.model = model
        self.runtime = runtime
        self.qualityGate = qualityGate
        self.memoryCalibrationSample = memoryCalibrationSample
        self.createdAt = createdAt
    }
}

public struct TurboQuantCoreBenchmarkAdapter: Sendable {
    public init() {}

    public func benchmarkReport(
        from coreReport: TurboQuantCoreBenchmarkReport,
        context: TurboQuantCoreBenchmarkAdapterContext
    ) throws -> TurboQuantBenchmarkReport {
        guard coreReport.schemaVersion == TurboQuantCoreBenchmarkReport.schemaVersion else {
            throw TurboQuantBenchmarkImportFailure.unsupportedSchema(
                name: "CoreBenchmarkReport",
                version: coreReport.schemaVersion
            )
        }
        guard coreReport.hiddenCopyAudit.status != .fail else {
            throw TurboQuantBenchmarkImportFailure.memoryGateFailed("Core hidden-copy audit failed.")
        }

        var runtime = context.runtime
        runtime.preset = runtime.preset ?? coreReport.metrics.preset
        runtime.valueBits = runtime.valueBits ?? coreReport.metrics.valueBits
        runtime.groupSize = runtime.groupSize ?? coreReport.metrics.groupSize
        runtime.layoutVersion = runtime.layoutVersion ?? coreReport.metrics.layoutVersion
        runtime.attentionPath = runtime.attentionPath ?? coreReport.pathDecision?.selectedPath

        return TurboQuantBenchmarkReport(
            compatibilityPairID: context.compatibilityPairID,
            producer: SchemaProducer(repo: "mlx-swift", commit: coreReport.mlxSwiftCommit ?? "unknown"),
            device: context.device,
            model: context.model,
            runtime: runtime,
            metrics: TurboQuantBenchmarkMetrics(
                contextTokens: coreReport.metrics.contextTokens,
                firstTokenLatencyMS: coreReport.metrics.firstTokenLatencyMS,
                prefillTokensPerSecond: coreReport.metrics.prefillTokensPerSecond,
                decodeTokensPerSecondP50: coreReport.metrics.decodeTokensPerSecondP50,
                decodeTokensPerSecondP95: coreReport.metrics.decodeTokensPerSecondP95,
                peakMemoryBytes: coreReport.metrics.peakMemoryBytes.map(Int64.init),
                compressedKVBytes: Int64(coreReport.metrics.compressedKVBytes),
                decodedFallbackScratchBytes: coreReport.pathDecision.map { Int64($0.estimatedScratchBytes) },
                memoryWarningsSeen: coreReport.metrics.memoryWarningsSeen,
                fallbackUsed: coreReport.metrics.fallbackUsed,
                fallbackReason: coreReport.metrics.fallbackReason,
                jetsamObserved: coreReport.metrics.jetsamObserved
            ),
            qualityGate: context.qualityGate,
            memoryCalibrationSample: context.memoryCalibrationSample,
            createdAt: context.createdAt
        )
    }
}

public struct TurboQuantBenchmarkImporter: Sendable {
    public init() {}

    public func importReport(
        _ report: TurboQuantBenchmarkReport,
        policy: TurboQuantBenchmarkImportPolicy
    ) throws -> TurboQuantBenchmarkImportResult {
        try validate(report, policy: policy)
        let evidenceLevel = try evidenceLevel(for: report, policy: policy)
        let evidence = RuntimeProfileEvidence(
            evidenceLevel: evidenceLevel,
            compatibilityPairID: report.compatibilityPairID,
            modelID: report.model.id,
            modelRevision: report.model.revision,
            tokenizerHash: report.model.tokenizerHash,
            profileHash: report.model.profileHash,
            fallbackContractHash: report.runtime.fallbackContractHash,
            deviceClass: report.device.deviceClass,
            hardwareModel: report.device.hardwareModel,
            osBuild: report.device.osBuild,
            userMode: report.runtime.userMode,
            turboQuantPreset: report.runtime.preset,
            valueBits: report.runtime.valueBits,
            groupSize: report.runtime.groupSize,
            layoutVersion: report.runtime.layoutVersion,
            activeAttentionPath: report.runtime.attentionPath,
            speculativeDimensions: report.runtime.speculativeDimensions,
            speculativeTelemetry: report.metrics.speculativeTelemetry,
            speculativeAutoDisableDecision: report.metrics.speculativeTelemetry.map {
                policy.speculativeAutoDisablePolicy.evaluate($0)
            },
            admittedContextTokens: report.runtime.admittedContextTokens,
            peakMemoryBytes: report.metrics.peakMemoryBytes ?? 0,
            promptTokensPerSecond: report.metrics.prefillTokensPerSecond,
            decodeTokensPerSecondP50: report.metrics.decodeTokensPerSecondP50,
            decodeTokensPerSecondP95: report.metrics.decodeTokensPerSecondP95,
            firstTokenLatencyMS: report.metrics.firstTokenLatencyMS,
            qualityGate: report.qualityGate,
            memoryCalibrationSampleID: report.memoryCalibrationSample?.id,
            createdAt: report.createdAt
        )
        return TurboQuantBenchmarkImportResult(
            evidence: evidence,
            memoryCalibrationSample: report.memoryCalibrationSample
        )
    }

    private func validate(
        _ report: TurboQuantBenchmarkReport,
        policy: TurboQuantBenchmarkImportPolicy
    ) throws {
        guard report.schemaVersion == TurboQuantBenchmarkReport.schemaVersion else {
            throw TurboQuantBenchmarkImportFailure.unsupportedSchema(
                name: TurboQuantSchemaName.benchmarkReport.rawValue,
                version: report.schemaVersion
            )
        }
        guard !report.compatibilityPairID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TurboQuantBenchmarkImportFailure.missingCompatibilityPairID
        }
        guard !report.runtime.fallbackContractHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TurboQuantBenchmarkImportFailure.missingFallbackContractHash
        }
        guard !report.qualityGate.benchmarkSuiteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TurboQuantBenchmarkImportFailure.missingBenchmarkSuiteID
        }

        if policy.requestedEvidenceLevel.canMakeProductCompatibilityClaim {
            guard policy.allowVerifiedEvidence else {
                throw TurboQuantBenchmarkImportFailure.verifiedEvidenceDisabled
            }
            guard policy.acceptedCompatibilityPairIDs.contains(report.compatibilityPairID) else {
                throw TurboQuantBenchmarkImportFailure.unknownCompatibilityPairID(report.compatibilityPairID)
            }
            guard policy.acceptedFallbackContractHashes.contains(report.runtime.fallbackContractHash) else {
                throw TurboQuantBenchmarkImportFailure.fallbackContractHashMismatch(report.runtime.fallbackContractHash)
            }
            guard let layoutVersion = report.runtime.layoutVersion,
                  policy.acceptedLayoutVersions.contains(layoutVersion) else {
                throw TurboQuantBenchmarkImportFailure.layoutVersionMismatch(
                    expected: Array(policy.acceptedLayoutVersions).sorted(),
                    actual: report.runtime.layoutVersion
                )
            }
            guard report.qualityGate.passed else {
                throw TurboQuantBenchmarkImportFailure.qualityGateFailed(report.qualityGate.gateReason)
            }
            guard !report.metrics.jetsamObserved else {
                throw TurboQuantBenchmarkImportFailure.memoryGateFailed("Jetsam was observed during the benchmark.")
            }
            if !policy.allowMemoryWarningsForVerified, report.metrics.memoryWarningsSeen > 0 {
                throw TurboQuantBenchmarkImportFailure.memoryGateFailed("Memory warnings were observed during the benchmark.")
            }
            if report.runtime.speculativeDimensions?.enabled == true {
                guard let telemetry = report.metrics.speculativeTelemetry else {
                    throw TurboQuantBenchmarkImportFailure.speculativeGateFailed("Speculative evidence requires acceptance telemetry.")
                }
                let decision = policy.speculativeAutoDisablePolicy.evaluate(telemetry)
                guard !decision.shouldDisable else {
                    throw TurboQuantBenchmarkImportFailure.speculativeGateFailed(decision.message)
                }
                guard telemetry.targetSequenceMatched == true else {
                    throw TurboQuantBenchmarkImportFailure.speculativeGateFailed("Accepted speculative tokens must match the target verifier.")
                }
                guard telemetry.tokenizerCompatible == true else {
                    throw TurboQuantBenchmarkImportFailure.speculativeGateFailed("Draft and target tokenizers must be compatible.")
                }
                guard telemetry.p50DecodeSpeedup != nil else {
                    throw TurboQuantBenchmarkImportFailure.speculativeGateFailed("Speculative verified evidence requires p50 decode speedup evidence.")
                }
            }
        }
    }

    private func evidenceLevel(
        for report: TurboQuantBenchmarkReport,
        policy: TurboQuantBenchmarkImportPolicy
    ) throws -> RuntimeEvidenceLevel {
        guard report.qualityGate.passed,
              !report.metrics.jetsamObserved,
              policy.allowMemoryWarningsForVerified || report.metrics.memoryWarningsSeen == 0
        else {
            return .unverified
        }

        if policy.requestedEvidenceLevel.canMakeProductCompatibilityClaim {
            return policy.requestedEvidenceLevel
        }
        return .smokeTested
    }
}
