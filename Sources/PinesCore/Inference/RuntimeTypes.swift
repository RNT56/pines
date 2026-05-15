import Foundation

public enum ModelModality: String, Codable, Sendable, CaseIterable {
    case text
    case vision
    case embeddings
}

public enum ModelInstallState: String, Codable, Sendable, CaseIterable {
    case remote
    case downloading
    case installed
    case failed
    case unsupported
}

public enum ModelVerificationState: String, Codable, Sendable, CaseIterable {
    case verified
    case installable
    case experimental
    case unsupported
}

public enum QuantizationAlgorithm: String, Codable, Sendable, CaseIterable {
    case none
    case mlxAffine
    case turboQuant
}

public enum TurboQuantPreset: String, Codable, Sendable, CaseIterable {
    case turbo2_5
    case turbo3_5

    public var displayName: String {
        switch self {
        case .turbo2_5:
            "TurboQuant 2.5-bit"
        case .turbo3_5:
            "TurboQuant 3.5-bit"
        }
    }

    public var baseBits: Int {
        switch self {
        case .turbo2_5:
            2
        case .turbo3_5:
            3
        }
    }

    public var outlierBits: Int {
        baseBits + 1
    }
}

public enum TurboQuantRuntimeBackend: String, Codable, Sendable, CaseIterable {
    case mlxPacked
    case polarQJLReference
    case metalPolarQJL

    public var displayName: String {
        switch self {
        case .mlxPacked:
            "MLX packed"
        case .polarQJLReference:
            "Polar/QJL reference"
        case .metalPolarQJL:
            "Polar/QJL Metal"
        }
    }
}

public enum TurboQuantAttentionPath: String, Codable, Sendable, CaseIterable {
    case onlineFused
    case tiledOnlineFused
    case twoStageCompressed
    case mlxPackedFallback
    case baseline

    public var displayName: String {
        switch self {
        case .onlineFused:
            "Online fused compressed"
        case .tiledOnlineFused:
            "Tiled online fused compressed"
        case .twoStageCompressed:
            "Two-stage compressed"
        case .mlxPackedFallback:
            "MLX packed fallback"
        case .baseline:
            "Baseline"
        }
    }
}

public enum TurboQuantKernelProfile: String, Codable, Sendable, CaseIterable {
    case portableA16A17
    case wideA18A19
    case sustainedA19Pro
    case mlxPackedFallback

    public var displayName: String {
        switch self {
        case .portableA16A17:
            "Portable A16/A17"
        case .wideA18A19:
            "Wide A18/A19"
        case .sustainedA19Pro:
            "Sustained A19 Pro"
        case .mlxPackedFallback:
            "MLX packed fallback"
        }
    }
}

public enum TurboQuantSelfTestStatus: String, Codable, Sendable, CaseIterable {
    case notRun
    case passed
    case failed

    public var displayName: String {
        switch self {
        case .notRun:
            "Not run"
        case .passed:
            "Passed"
        case .failed:
            "Failed"
        }
    }
}

public enum TurboQuantOptimizationPolicy: String, Codable, Sendable, CaseIterable {
    case auto
    case conservative
    case preferMemory
    case preferThroughput

    public var displayName: String {
        switch self {
        case .auto:
            "Auto"
        case .conservative:
            "Conservative"
        case .preferMemory:
            "Prefer memory"
        case .preferThroughput:
            "Prefer throughput"
        }
    }
}

public enum KVCacheStrategy: String, Codable, Sendable, CaseIterable {
    case none
    case mlxAffine
    case turboQuant
}

public enum DevicePerformanceClass: String, Codable, Sendable, CaseIterable {
    case a16Compact
    case a17Pro
    case a18Standard
    case a18Pro
    case a19Standard
    case a19ProThin
    case a19ProSustained
    case futureVerified

    public var displayName: String {
        switch self {
        case .a16Compact:
            "A16 compact"
        case .a17Pro:
            "A17 Pro"
        case .a18Standard:
            "A18"
        case .a18Pro:
            "A18 Pro"
        case .a19Standard:
            "A19"
        case .a19ProThin:
            "A19 Pro thin"
        case .a19ProSustained:
            "A19 Pro sustained"
        case .futureVerified:
            "Future verified"
        }
    }
}

public struct RuntimeMemoryCounters: Hashable, Codable, Sendable {
    public var kvCacheBytes: Int64?
    public var quantizedKVCacheBytes: Int64?
    public var vaultIndexBytes: Int64?
    public var physicalMemoryBytes: Int64?
    public var availableMemoryBytes: Int64?
    public var thermalState: String?
    public var hardwareModelIdentifier: String?
    public var lowPowerModeEnabled: Bool?
    public var metalArchitectureName: String?
    public var metalRecommendedWorkingSetBytes: Int64?
    public var devicePerformanceClass: DevicePerformanceClass?
    public var thermalDownshiftActive: Bool?
    public var recommendedContextTokens: Int?
    public var recommendedEmbeddingBatchSize: Int?
    public var recommendedVectorScanLimit: Int?

    public init(
        kvCacheBytes: Int64? = nil,
        quantizedKVCacheBytes: Int64? = nil,
        vaultIndexBytes: Int64? = nil,
        physicalMemoryBytes: Int64? = nil,
        availableMemoryBytes: Int64? = nil,
        thermalState: String? = nil,
        hardwareModelIdentifier: String? = nil,
        lowPowerModeEnabled: Bool? = nil,
        metalArchitectureName: String? = nil,
        metalRecommendedWorkingSetBytes: Int64? = nil,
        devicePerformanceClass: DevicePerformanceClass? = nil,
        thermalDownshiftActive: Bool? = nil,
        recommendedContextTokens: Int? = nil,
        recommendedEmbeddingBatchSize: Int? = nil,
        recommendedVectorScanLimit: Int? = nil
    ) {
        self.kvCacheBytes = kvCacheBytes
        self.quantizedKVCacheBytes = quantizedKVCacheBytes
        self.vaultIndexBytes = vaultIndexBytes
        self.physicalMemoryBytes = physicalMemoryBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.thermalState = thermalState
        self.hardwareModelIdentifier = hardwareModelIdentifier
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.metalArchitectureName = metalArchitectureName
        self.metalRecommendedWorkingSetBytes = metalRecommendedWorkingSetBytes
        self.devicePerformanceClass = devicePerformanceClass
        self.thermalDownshiftActive = thermalDownshiftActive
        self.recommendedContextTokens = recommendedContextTokens
        self.recommendedEmbeddingBatchSize = recommendedEmbeddingBatchSize
        self.recommendedVectorScanLimit = recommendedVectorScanLimit
    }
}

public struct RuntimeMemorySnapshot: Hashable, Codable, Sendable {
    public var physicalMemoryBytes: Int64
    public var availableMemoryBytes: Int64?
    public var thermalState: String
    public var hardwareModelIdentifier: String?
    public var lowPowerModeEnabled: Bool
    public var metalArchitectureName: String?
    public var metalRecommendedWorkingSetBytes: Int64?
    public var metalKernelProfile: TurboQuantKernelProfile?
    public var metalSelfTestStatus: TurboQuantSelfTestStatus?

    public init(
        physicalMemoryBytes: Int64,
        availableMemoryBytes: Int64? = nil,
        thermalState: String = "nominal",
        hardwareModelIdentifier: String? = nil,
        lowPowerModeEnabled: Bool = false,
        metalArchitectureName: String? = nil,
        metalRecommendedWorkingSetBytes: Int64? = nil,
        metalKernelProfile: TurboQuantKernelProfile? = nil,
        metalSelfTestStatus: TurboQuantSelfTestStatus? = nil
    ) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.thermalState = thermalState
        self.hardwareModelIdentifier = hardwareModelIdentifier
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.metalArchitectureName = metalArchitectureName
        self.metalRecommendedWorkingSetBytes = metalRecommendedWorkingSetBytes
        self.metalKernelProfile = metalKernelProfile
        self.metalSelfTestStatus = metalSelfTestStatus
    }
}

public struct RuntimeQuantizationDiagnostics: Hashable, Codable, Sendable {
    public var requestedAlgorithm: QuantizationAlgorithm
    public var activeAlgorithm: QuantizationAlgorithm
    public var preset: TurboQuantPreset?
    public var requestedBackend: TurboQuantRuntimeBackend?
    public var activeBackend: TurboQuantRuntimeBackend?
    public var metalCodecAvailable: Bool
    public var metalAttentionAvailable: Bool
    public var activeAttentionPath: TurboQuantAttentionPath?
    public var metalKernelProfile: TurboQuantKernelProfile?
    public var metalSelfTestStatus: TurboQuantSelfTestStatus?
    public var metalSelfTestFailureReason: String?
    public var rawFallbackAllocated: Bool?
    public var devicePerformanceClass: DevicePerformanceClass?
    public var turboQuantOptimizationPolicy: TurboQuantOptimizationPolicy?
    public var thermalDownshiftActive: Bool?
    public var lastUnsupportedAttentionShape: String?
    public var activeFallbackReason: String?
    public var memoryCounters: RuntimeMemoryCounters

    public init(
        requestedAlgorithm: QuantizationAlgorithm = .turboQuant,
        activeAlgorithm: QuantizationAlgorithm = .turboQuant,
        preset: TurboQuantPreset? = .turbo3_5,
        requestedBackend: TurboQuantRuntimeBackend? = .metalPolarQJL,
        activeBackend: TurboQuantRuntimeBackend? = .mlxPacked,
        metalCodecAvailable: Bool = false,
        metalAttentionAvailable: Bool = false,
        activeAttentionPath: TurboQuantAttentionPath? = .mlxPackedFallback,
        metalKernelProfile: TurboQuantKernelProfile? = nil,
        metalSelfTestStatus: TurboQuantSelfTestStatus? = nil,
        metalSelfTestFailureReason: String? = nil,
        rawFallbackAllocated: Bool? = nil,
        devicePerformanceClass: DevicePerformanceClass? = nil,
        turboQuantOptimizationPolicy: TurboQuantOptimizationPolicy? = nil,
        thermalDownshiftActive: Bool? = nil,
        lastUnsupportedAttentionShape: String? = nil,
        activeFallbackReason: String? = nil,
        memoryCounters: RuntimeMemoryCounters = RuntimeMemoryCounters()
    ) {
        self.requestedAlgorithm = requestedAlgorithm
        self.activeAlgorithm = activeAlgorithm
        self.preset = preset
        self.requestedBackend = requestedBackend
        self.activeBackend = activeBackend
        self.metalCodecAvailable = metalCodecAvailable
        self.metalAttentionAvailable = metalAttentionAvailable
        self.activeAttentionPath = activeAttentionPath
        self.metalKernelProfile = metalKernelProfile
        self.metalSelfTestStatus = metalSelfTestStatus
        self.metalSelfTestFailureReason = metalSelfTestFailureReason
        self.rawFallbackAllocated = rawFallbackAllocated
        self.devicePerformanceClass = devicePerformanceClass
        self.turboQuantOptimizationPolicy = turboQuantOptimizationPolicy
        self.thermalDownshiftActive = thermalDownshiftActive
        self.lastUnsupportedAttentionShape = lastUnsupportedAttentionShape
        self.activeFallbackReason = activeFallbackReason
        self.memoryCounters = memoryCounters
    }
}

public struct QuantizationProfile: Hashable, Codable, Sendable {
    public var weightBits: Int?
    public var kvBits: Int?
    public var kvGroupSize: Int
    public var quantizedKVStart: Int
    public var maxKVSize: Int?
    public var algorithm: QuantizationAlgorithm
    public var kvCacheStrategy: KVCacheStrategy
    public var preset: TurboQuantPreset?
    public var requestedBackend: TurboQuantRuntimeBackend?
    public var activeBackend: TurboQuantRuntimeBackend?
    public var metalCodecAvailable: Bool
    public var metalAttentionAvailable: Bool
    public var activeAttentionPath: TurboQuantAttentionPath?
    public var metalKernelProfile: TurboQuantKernelProfile?
    public var metalSelfTestStatus: TurboQuantSelfTestStatus?
    public var metalSelfTestFailureReason: String?
    public var rawFallbackAllocated: Bool?
    public var devicePerformanceClass: DevicePerformanceClass?
    public var turboQuantOptimizationPolicy: TurboQuantOptimizationPolicy
    public var thermalDownshiftActive: Bool
    public var lastUnsupportedAttentionShape: String?
    public var activeFallbackReason: String?
    public var memoryCounters: RuntimeMemoryCounters

    private enum CodingKeys: String, CodingKey {
        case weightBits
        case kvBits
        case kvGroupSize
        case quantizedKVStart
        case maxKVSize
        case algorithm
        case kvCacheStrategy
        case preset
        case requestedBackend
        case activeBackend
        case metalCodecAvailable
        case metalAttentionAvailable
        case activeAttentionPath
        case metalKernelProfile
        case metalSelfTestStatus
        case metalSelfTestFailureReason
        case rawFallbackAllocated
        case devicePerformanceClass
        case turboQuantOptimizationPolicy
        case thermalDownshiftActive
        case lastUnsupportedAttentionShape
        case activeFallbackReason
        case memoryCounters
    }

    public init(
        weightBits: Int? = nil,
        kvBits: Int? = nil,
        kvGroupSize: Int = 64,
        quantizedKVStart: Int = 0,
        maxKVSize: Int? = nil,
        algorithm: QuantizationAlgorithm = .turboQuant,
        kvCacheStrategy: KVCacheStrategy = .turboQuant,
        preset: TurboQuantPreset? = .turbo3_5,
        requestedBackend: TurboQuantRuntimeBackend? = .metalPolarQJL,
        activeBackend: TurboQuantRuntimeBackend? = .mlxPacked,
        metalCodecAvailable: Bool = false,
        metalAttentionAvailable: Bool = false,
        activeAttentionPath: TurboQuantAttentionPath? = .mlxPackedFallback,
        metalKernelProfile: TurboQuantKernelProfile? = nil,
        metalSelfTestStatus: TurboQuantSelfTestStatus? = nil,
        metalSelfTestFailureReason: String? = nil,
        rawFallbackAllocated: Bool? = nil,
        devicePerformanceClass: DevicePerformanceClass? = nil,
        turboQuantOptimizationPolicy: TurboQuantOptimizationPolicy = .auto,
        thermalDownshiftActive: Bool = false,
        lastUnsupportedAttentionShape: String? = nil,
        activeFallbackReason: String? = nil,
        memoryCounters: RuntimeMemoryCounters = RuntimeMemoryCounters()
    ) {
        self.weightBits = weightBits
        self.kvBits = kvBits
        self.kvGroupSize = kvGroupSize
        self.quantizedKVStart = quantizedKVStart
        self.maxKVSize = maxKVSize
        self.algorithm = algorithm
        self.kvCacheStrategy = kvCacheStrategy
        self.preset = preset
        self.requestedBackend = requestedBackend
        self.activeBackend = activeBackend
        self.metalCodecAvailable = metalCodecAvailable
        self.metalAttentionAvailable = metalAttentionAvailable
        self.activeAttentionPath = activeAttentionPath
        self.metalKernelProfile = metalKernelProfile
        self.metalSelfTestStatus = metalSelfTestStatus
        self.metalSelfTestFailureReason = metalSelfTestFailureReason
        self.rawFallbackAllocated = rawFallbackAllocated
        self.devicePerformanceClass = devicePerformanceClass
        self.turboQuantOptimizationPolicy = turboQuantOptimizationPolicy
        self.thermalDownshiftActive = thermalDownshiftActive
        self.lastUnsupportedAttentionShape = lastUnsupportedAttentionShape
        self.activeFallbackReason = activeFallbackReason
        self.memoryCounters = memoryCounters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weightBits = try container.decodeIfPresent(Int.self, forKey: .weightBits)
        kvBits = try container.decodeIfPresent(Int.self, forKey: .kvBits)
        kvGroupSize = try container.decodeIfPresent(Int.self, forKey: .kvGroupSize) ?? 64
        quantizedKVStart = try container.decodeIfPresent(Int.self, forKey: .quantizedKVStart) ?? 0
        maxKVSize = try container.decodeIfPresent(Int.self, forKey: .maxKVSize)
        algorithm = try container.decodeIfPresent(QuantizationAlgorithm.self, forKey: .algorithm) ?? .turboQuant
        kvCacheStrategy = try container.decodeIfPresent(KVCacheStrategy.self, forKey: .kvCacheStrategy) ?? .turboQuant
        preset = try container.decodeIfPresent(TurboQuantPreset.self, forKey: .preset) ?? .turbo3_5
        requestedBackend = try container.decodeIfPresent(TurboQuantRuntimeBackend.self, forKey: .requestedBackend) ?? .metalPolarQJL
        activeBackend = try container.decodeIfPresent(TurboQuantRuntimeBackend.self, forKey: .activeBackend) ?? .mlxPacked
        metalCodecAvailable = try container.decodeIfPresent(Bool.self, forKey: .metalCodecAvailable) ?? false
        metalAttentionAvailable = try container.decodeIfPresent(Bool.self, forKey: .metalAttentionAvailable) ?? false
        activeAttentionPath = try container.decodeIfPresent(TurboQuantAttentionPath.self, forKey: .activeAttentionPath) ?? .mlxPackedFallback
        metalKernelProfile = try container.decodeIfPresent(TurboQuantKernelProfile.self, forKey: .metalKernelProfile)
        metalSelfTestStatus = try container.decodeIfPresent(TurboQuantSelfTestStatus.self, forKey: .metalSelfTestStatus)
        metalSelfTestFailureReason = try container.decodeIfPresent(String.self, forKey: .metalSelfTestFailureReason)
        rawFallbackAllocated = try container.decodeIfPresent(Bool.self, forKey: .rawFallbackAllocated)
        devicePerformanceClass = try container.decodeIfPresent(DevicePerformanceClass.self, forKey: .devicePerformanceClass)
        turboQuantOptimizationPolicy = try container.decodeIfPresent(TurboQuantOptimizationPolicy.self, forKey: .turboQuantOptimizationPolicy) ?? .auto
        thermalDownshiftActive = try container.decodeIfPresent(Bool.self, forKey: .thermalDownshiftActive) ?? false
        lastUnsupportedAttentionShape = try container.decodeIfPresent(String.self, forKey: .lastUnsupportedAttentionShape)
        activeFallbackReason = try container.decodeIfPresent(String.self, forKey: .activeFallbackReason)
        memoryCounters = try container.decodeIfPresent(RuntimeMemoryCounters.self, forKey: .memoryCounters) ?? RuntimeMemoryCounters()
    }
}

public struct RuntimeProfile: Hashable, Codable, Sendable {
    public var name: String
    public var quantization: QuantizationProfile
    public var prefillStepSize: Int
    public var promptCacheEnabled: Bool
    public var promptCacheIdentifier: String?
    public var speculativeDraftModelID: ModelID?
    public var speculativeDecodingEnabled: Bool
    public var unloadOnMemoryPressure: Bool
    public var repetitionContextSize: Int
    public var maxConcurrentSessions: Int

    public init(
        name: String = "Balanced",
        quantization: QuantizationProfile = .init(kvBits: 8),
        prefillStepSize: Int = 512,
        promptCacheEnabled: Bool = true,
        promptCacheIdentifier: String? = nil,
        speculativeDraftModelID: ModelID? = nil,
        speculativeDecodingEnabled: Bool = false,
        unloadOnMemoryPressure: Bool = true,
        repetitionContextSize: Int = 20,
        maxConcurrentSessions: Int = 1
    ) {
        self.name = name
        self.quantization = quantization
        self.prefillStepSize = prefillStepSize
        self.promptCacheEnabled = promptCacheEnabled
        self.promptCacheIdentifier = promptCacheIdentifier
        self.speculativeDraftModelID = speculativeDraftModelID
        self.speculativeDecodingEnabled = speculativeDecodingEnabled
        self.unloadOnMemoryPressure = unloadOnMemoryPressure
        self.repetitionContextSize = repetitionContextSize
        self.maxConcurrentSessions = maxConcurrentSessions
    }
}

public struct ModelInstall: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var modelID: ModelID
    public var displayName: String
    public var repository: String
    public var revision: String?
    public var localURL: URL?
    public var modalities: Set<ModelModality>
    public var verification: ModelVerificationState
    public var state: ModelInstallState
    public var parameterCount: Int64?
    public var estimatedBytes: Int64?
    public var license: String?
    public var modelType: String?
    public var processorClass: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        modelID: ModelID,
        displayName: String,
        repository: String,
        revision: String? = nil,
        localURL: URL? = nil,
        modalities: Set<ModelModality>,
        verification: ModelVerificationState,
        state: ModelInstallState = .remote,
        parameterCount: Int64? = nil,
        estimatedBytes: Int64? = nil,
        license: String? = nil,
        modelType: String? = nil,
        processorClass: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.modelID = modelID
        self.displayName = displayName
        self.repository = repository
        self.revision = revision
        self.localURL = localURL
        self.modalities = modalities
        self.verification = verification
        self.state = state
        self.parameterCount = parameterCount
        self.estimatedBytes = estimatedBytes
        self.license = license
        self.modelType = modelType
        self.processorClass = processorClass
        self.createdAt = createdAt
    }
}

public protocol LocalModelRunner: Sendable {
    func load(_ install: ModelInstall, profile: RuntimeProfile) async throws
    func unload() async
    func generate(_ request: ChatRequest) async throws -> AsyncThrowingStream<TokenDelta, Error>
}

public enum DeviceMemoryTier: String, Codable, Sendable, CaseIterable {
    case compact
    case balanced
    case pro
    case max
}

public struct DeviceProfile: Hashable, Codable, Sendable {
    public var memoryTier: DeviceMemoryTier
    public var performanceClass: DevicePerformanceClass
    public var recommendedMaxModelBytes: Int64
    public var recommendedContextTokens: Int
    public var recommendedSmallModelContextTokens: Int
    public var recommendedPrefillStepSize: Int
    public var allowsVisionModels: Bool
    public var recommendedEmbeddingBatchSize: Int
    public var recommendedVectorScanLimit: Int
    public var unloadsOnThermalPressure: Bool
    public var turboQuantOptimizationPolicy: TurboQuantOptimizationPolicy
    public var thermalDownshiftActive: Bool

    public init(
        memoryTier: DeviceMemoryTier,
        performanceClass: DevicePerformanceClass,
        recommendedMaxModelBytes: Int64,
        recommendedContextTokens: Int,
        recommendedSmallModelContextTokens: Int? = nil,
        recommendedPrefillStepSize: Int = 512,
        allowsVisionModels: Bool,
        recommendedEmbeddingBatchSize: Int = 16,
        recommendedVectorScanLimit: Int = 4096,
        unloadsOnThermalPressure: Bool = true,
        turboQuantOptimizationPolicy: TurboQuantOptimizationPolicy = .auto,
        thermalDownshiftActive: Bool = false
    ) {
        self.memoryTier = memoryTier
        self.performanceClass = performanceClass
        self.recommendedMaxModelBytes = recommendedMaxModelBytes
        self.recommendedContextTokens = recommendedContextTokens
        self.recommendedSmallModelContextTokens = recommendedSmallModelContextTokens ?? recommendedContextTokens
        self.recommendedPrefillStepSize = recommendedPrefillStepSize
        self.allowsVisionModels = allowsVisionModels
        self.recommendedEmbeddingBatchSize = recommendedEmbeddingBatchSize
        self.recommendedVectorScanLimit = recommendedVectorScanLimit
        self.unloadsOnThermalPressure = unloadsOnThermalPressure
        self.turboQuantOptimizationPolicy = turboQuantOptimizationPolicy
        self.thermalDownshiftActive = thermalDownshiftActive
    }

    public static let compactA16Phone = DeviceProfile(
        memoryTier: .compact,
        performanceClass: .a16Compact,
        recommendedMaxModelBytes: 2_700_000_000,
        recommendedContextTokens: 8192,
        recommendedSmallModelContextTokens: 16_384,
        recommendedPrefillStepSize: 256,
        allowsVisionModels: false,
        recommendedEmbeddingBatchSize: 8,
        recommendedVectorScanLimit: 2048,
        unloadsOnThermalPressure: true
    )

    public static let balancedPhone = DeviceProfile(
        memoryTier: .balanced,
        performanceClass: .a17Pro,
        recommendedMaxModelBytes: 3_500_000_000,
        recommendedContextTokens: 16_384,
        recommendedSmallModelContextTokens: 24_576,
        recommendedPrefillStepSize: 512,
        allowsVisionModels: true,
        recommendedEmbeddingBatchSize: 12,
        recommendedVectorScanLimit: 4096,
        unloadsOnThermalPressure: true
    )

    public static let proPhone = DeviceProfile(
        memoryTier: .pro,
        performanceClass: .a18Pro,
        recommendedMaxModelBytes: 5_000_000_000,
        recommendedContextTokens: 16_384,
        recommendedSmallModelContextTokens: 32_768,
        recommendedPrefillStepSize: 768,
        allowsVisionModels: true,
        recommendedEmbeddingBatchSize: 16,
        recommendedVectorScanLimit: 8192,
        unloadsOnThermalPressure: true
    )

    public static let maxTabletOrMac = DeviceProfile(
        memoryTier: .max,
        performanceClass: .futureVerified,
        recommendedMaxModelBytes: 8_000_000_000,
        recommendedContextTokens: 32_768,
        recommendedSmallModelContextTokens: 65_536,
        recommendedPrefillStepSize: 1024,
        allowsVisionModels: true,
        recommendedEmbeddingBatchSize: 32,
        recommendedVectorScanLimit: 16_384,
        unloadsOnThermalPressure: false
    )

    public static func recommended(for snapshot: RuntimeMemorySnapshot) -> DeviceProfile {
        var profile = baseProfile(for: performanceClass(for: snapshot), physicalMemoryBytes: snapshot.physicalMemoryBytes)
        let severeThermal = snapshot.thermalState == "serious" || snapshot.thermalState == "critical"
        let thinThermal = profile.performanceClass == .a19ProThin && snapshot.thermalState == "fair"
        let lowMemory = (snapshot.availableMemoryBytes ?? Int64.max) < 750_000_000
        let downshift = severeThermal || thinThermal || lowMemory || snapshot.lowPowerModeEnabled

        if severeThermal || snapshot.lowPowerModeEnabled {
            profile.recommendedContextTokens = min(profile.recommendedContextTokens, 4096)
            profile.recommendedSmallModelContextTokens = min(profile.recommendedSmallModelContextTokens, 4096)
            profile.recommendedPrefillStepSize = min(profile.recommendedPrefillStepSize, 256)
            profile.recommendedEmbeddingBatchSize = min(profile.recommendedEmbeddingBatchSize, 4)
            profile.recommendedVectorScanLimit = min(profile.recommendedVectorScanLimit, 1024)
            profile.allowsVisionModels = false
            profile.unloadsOnThermalPressure = true
            profile.turboQuantOptimizationPolicy = .conservative
        } else if lowMemory {
            profile.recommendedContextTokens = min(profile.recommendedContextTokens, 4096)
            profile.recommendedSmallModelContextTokens = min(profile.recommendedSmallModelContextTokens, 4096)
            profile.recommendedPrefillStepSize = min(profile.recommendedPrefillStepSize, 256)
            profile.recommendedEmbeddingBatchSize = min(profile.recommendedEmbeddingBatchSize, 4)
            profile.recommendedVectorScanLimit = min(profile.recommendedVectorScanLimit, 1024)
            profile.turboQuantOptimizationPolicy = .preferMemory
        } else if thinThermal {
            profile.recommendedContextTokens = min(profile.recommendedContextTokens, 16_384)
            profile.recommendedSmallModelContextTokens = min(profile.recommendedSmallModelContextTokens, 16_384)
            profile.recommendedPrefillStepSize = min(profile.recommendedPrefillStepSize, 512)
            profile.turboQuantOptimizationPolicy = .conservative
        }
        profile.thermalDownshiftActive = downshift

        return profile
    }

    private static func baseProfile(
        for performanceClass: DevicePerformanceClass,
        physicalMemoryBytes: Int64
    ) -> DeviceProfile {
        switch performanceClass {
        case .a16Compact:
            return .compactA16Phone
        case .a17Pro:
            var profile = balancedPhone
            profile.performanceClass = .a17Pro
            return profile
        case .a18Standard:
            return DeviceProfile(
                memoryTier: .balanced,
                performanceClass: .a18Standard,
                recommendedMaxModelBytes: 3_800_000_000,
                recommendedContextTokens: 16_384,
                recommendedSmallModelContextTokens: 24_576,
                recommendedPrefillStepSize: 512,
                allowsVisionModels: true,
                recommendedEmbeddingBatchSize: 12,
                recommendedVectorScanLimit: 4096
            )
        case .a18Pro:
            return .proPhone
        case .a19Standard:
            return DeviceProfile(
                memoryTier: .pro,
                performanceClass: .a19Standard,
                recommendedMaxModelBytes: 5_500_000_000,
                recommendedContextTokens: 16_384,
                recommendedSmallModelContextTokens: 32_768,
                recommendedPrefillStepSize: 1024,
                allowsVisionModels: true,
                recommendedEmbeddingBatchSize: 16,
                recommendedVectorScanLimit: 8192
            )
        case .a19ProThin:
            return DeviceProfile(
                memoryTier: .pro,
                performanceClass: .a19ProThin,
                recommendedMaxModelBytes: 5_500_000_000,
                recommendedContextTokens: 16_384,
                recommendedSmallModelContextTokens: 32_768,
                recommendedPrefillStepSize: 1024,
                allowsVisionModels: true,
                recommendedEmbeddingBatchSize: 16,
                recommendedVectorScanLimit: 8192
            )
        case .a19ProSustained:
            return DeviceProfile(
                memoryTier: .max,
                performanceClass: .a19ProSustained,
                recommendedMaxModelBytes: 7_000_000_000,
                recommendedContextTokens: 32_768,
                recommendedSmallModelContextTokens: 65_536,
                recommendedPrefillStepSize: 1024,
                allowsVisionModels: true,
                recommendedEmbeddingBatchSize: 24,
                recommendedVectorScanLimit: 16_384,
                unloadsOnThermalPressure: false
            )
        case .futureVerified:
            var profile = maxTabletOrMac
            if physicalMemoryBytes < 14_000_000_000 {
                profile.recommendedMaxModelBytes = 5_500_000_000
            }
            return profile
        }
    }

    private static func performanceClass(for snapshot: RuntimeMemorySnapshot) -> DevicePerformanceClass {
        if let hardware = snapshot.hardwareModelIdentifier {
            switch hardware {
            case "iPhone16,1", "iPhone16,2":
                return .a17Pro
            case "iPhone17,1", "iPhone17,2":
                return .a18Pro
            case "iPhone17,3", "iPhone17,4", "iPhone17,5":
                return .a18Standard
            case "iPhone18,1", "iPhone18,2":
                return .a19ProSustained
            case "iPhone18,4":
                return .a19ProThin
            case "iPhone18,3", "iPhone18,5":
                return .a19Standard
            default:
                if hardware.hasPrefix("iPhone15,") {
                    return .a16Compact
                }
                if let major = iphoneIdentifierMajor(hardware), major > 18,
                    snapshot.metalSelfTestStatus == .passed,
                    snapshot.metalKernelProfile != .mlxPackedFallback
                {
                    return .futureVerified
                }
            }
        }

        switch snapshot.physicalMemoryBytes {
        case ..<7_000_000_000:
            return .a16Compact
        case ..<9_000_000_000:
            return .a17Pro
        case ..<14_000_000_000:
            return .a18Pro
        default:
            return snapshot.metalSelfTestStatus == .passed ? .futureVerified : .a18Pro
        }
    }

    private static func iphoneIdentifierMajor(_ hardware: String) -> Int? {
        guard hardware.hasPrefix("iPhone") else { return nil }
        let suffix = hardware.dropFirst("iPhone".count)
        let major = suffix.split(separator: ",").first
        return major.flatMap { Int($0) }
    }
}
