import Foundation

public enum ModelModality: String, Codable, Sendable, CaseIterable {
    case text
    case vision
    case audio
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

public enum ModelCacheTopology: String, Codable, Sendable, CaseIterable {
    case standardAttention
    case slidingAttention
    case sharedKVAttention
    case hybridAttentionAndNativeState
    case visionLanguageAttention
    case unsupported

    public var displayName: String {
        switch self {
        case .standardAttention:
            "Standard attention"
        case .slidingAttention:
            "Sliding attention"
        case .sharedKVAttention:
            "Shared KV attention"
        case .hybridAttentionAndNativeState:
            "Hybrid attention + native state"
        case .visionLanguageAttention:
            "Vision-language attention"
        case .unsupported:
            "Unsupported topology"
        }
    }
}

public enum TurboQuantFamilySupport: String, Codable, Sendable, CaseIterable {
    case none
    case attentionKVFull
    case hybridFull
    case unsupportedTopology

    public var displayName: String {
        switch self {
        case .none:
            "None"
        case .attentionKVFull:
            "TurboQuant full"
        case .hybridFull:
            "Hybrid full"
        case .unsupportedTopology:
            "Unsupported topology"
        }
    }
}

public enum PinesTurboQuantCacheTopology: String, Codable, Sendable, CaseIterable {
    case standardAttentionKV
    case hybridAttentionKVAndNativeState
    case gatedVLMOrDualModel
    case unsupported
}

public struct PinesTurboQuantRuntimeModelCapability: Hashable, Codable, Sendable {
    public var modelType: String
    public var supportsThrowingTurboQuantAttention: Bool
    public var cacheTopology: PinesTurboQuantCacheTopology
    public var note: String?

    public init(
        modelType: String,
        supportsThrowingTurboQuantAttention: Bool,
        cacheTopology: PinesTurboQuantCacheTopology,
        note: String? = nil
    ) {
        self.modelType = Self.normalize(modelType)
        self.supportsThrowingTurboQuantAttention = supportsThrowingTurboQuantAttention
        self.cacheTopology = cacheTopology
        self.note = note
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}

public struct PinesTurboQuantRuntimeCapabilityRegistry: Hashable, Codable, Sendable {
    public var capabilitiesByModelType: [String: PinesTurboQuantRuntimeModelCapability]

    public init(capabilities: [PinesTurboQuantRuntimeModelCapability]) {
        capabilitiesByModelType = Dictionary(
            uniqueKeysWithValues: capabilities.map { ($0.modelType, $0) }
        )
    }

    public static let bundledFallback = PinesTurboQuantRuntimeCapabilityRegistry(capabilities: [
        .standard("llama"),
        .standard("mistral"),
        .standard("ministral3"),
        .standard("mistral3"),
        .standard("mistral4"),
        .standard("gemma"),
        .standard("gemma2"),
        .standard("gemma3"),
        .standard("gemma3_text"),
        .standard("gemma3n"),
        .standard("gemma3n_text"),
        .standard("gemma4"),
        .standard("gemma4_text"),
        .gated("gemma4_assistant", note: "Gemma4 assistant is draft-only MTP and requires explicit dual-model orchestration."),
        .standard("qwen2"),
        .standard("qwen3"),
        .standard("qwen3_moe"),
        .hybrid("qwen3_5"),
        .hybrid("qwen3_5_text"),
        .hybrid("qwen3_5_moe"),
        .hybrid("qwen3_5_moe_text"),
        .standard("acereason"),
        .standard("phi"),
        .standard("phi3"),
        .standard("granite"),
        .standard("exaone4"),
        .standard("smollm3"),
        .hybrid("lfm2"),
        .standard("glm4_moe_lite"),
    ])

    public func capability(for modelType: String?) -> PinesTurboQuantRuntimeModelCapability? {
        guard let modelType else { return nil }
        return capabilitiesByModelType[Self.normalize(modelType)]
    }

    public func supportsThrowingTurboQuantAttention(modelTypes: Set<String>) -> Bool {
        modelTypes.contains {
            capability(for: $0)?.supportsThrowingTurboQuantAttention == true
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}

private extension PinesTurboQuantRuntimeModelCapability {
    static func standard(_ modelType: String) -> Self {
        Self(
            modelType: modelType,
            supportsThrowingTurboQuantAttention: true,
            cacheTopology: .standardAttentionKV
        )
    }

    static func hybrid(_ modelType: String) -> Self {
        Self(
            modelType: modelType,
            supportsThrowingTurboQuantAttention: true,
            cacheTopology: .hybridAttentionKVAndNativeState
        )
    }

    static func gated(_ modelType: String, note: String) -> Self {
        Self(
            modelType: modelType,
            supportsThrowingTurboQuantAttention: false,
            cacheTopology: .gatedVLMOrDualModel,
            note: note
        )
    }
}

public enum TurboQuantRuntimeSupport: Sendable {
    public static let nonThrowingRuntimeReason =
        "TurboQuant profile metadata is available, but the linked MLX runtime model does not yet implement typed throwing TurboQuant attention."

    public static func supportsThrowingAttentionGeneration(
        repository: String,
        modelType: String?,
        textConfigModelType: String?,
        modalities: Set<ModelModality>,
        familySupport: TurboQuantFamilySupport,
        runtimeCapabilities: PinesTurboQuantRuntimeCapabilityRegistry = .bundledFallback
    ) -> Bool {
        _ = repository
        guard modalities == [.text] else { return false }
        guard familySupport == .attentionKVFull || familySupport == .hybridFull else {
            return false
        }

        let modelTypes = normalizedModelTypes(modelType, textConfigModelType)
        return runtimeCapabilities.supportsThrowingTurboQuantAttention(modelTypes: modelTypes)
    }

    public static func defaultDisabledReason(
        repository: String,
        modelType: String?,
        textConfigModelType: String?,
        modalities: Set<ModelModality>,
        familySupport: TurboQuantFamilySupport,
        runtimeCapabilities: PinesTurboQuantRuntimeCapabilityRegistry = .bundledFallback
    ) -> String? {
        guard familySupport == .attentionKVFull || familySupport == .hybridFull else {
            return nil
        }
        guard !supportsThrowingAttentionGeneration(
            repository: repository,
            modelType: modelType,
            textConfigModelType: textConfigModelType,
            modalities: modalities,
            familySupport: familySupport,
            runtimeCapabilities: runtimeCapabilities
        ) else {
            return nil
        }
        return nonThrowingRuntimeReason
    }

    private static func normalizedModelTypes(_ values: String?...) -> Set<String> {
        Set(
            values.compactMap {
                $0?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")
            }.filter { !$0.isEmpty }
        )
    }
}

public enum TurboQuantLayoutVersion: Sendable {
    public static let legacy = 4
    public static let current = 5
}

public enum QuantizationAlgorithm: String, Codable, Sendable, CaseIterable {
    case none
    case mlxAffine
    case turboQuant
}

public enum TurboQuantPreset: String, Codable, Sendable, CaseIterable {
    case turbo2_5
    case turbo3_5
    case turbo4
    case turbo4v2
    case turbo8

    public static let defaultGeneration: Self = .turbo4v2
    public static let conservativeFallback: Self = .turbo3_5
    public static let vaultVectorDefault: Self = .turbo4v2

    public var displayName: String {
        switch self {
        case .turbo2_5:
            "TurboQuant 2.5-bit"
        case .turbo3_5:
            "TurboQuant 3.5-bit"
        case .turbo4:
            "TurboQuant 4-bit"
        case .turbo4v2:
            "TurboQuant 4-bit V2"
        case .turbo8:
            "TurboQuant 8-bit"
        }
    }

    public var effectiveBits: Int {
        switch self {
        case .turbo2_5:
            2
        case .turbo3_5, .turbo4, .turbo4v2:
            4
        case .turbo8:
            8
        }
    }

    public var baseBits: Int {
        switch self {
        case .turbo2_5:
            2
        case .turbo3_5:
            3
        case .turbo4, .turbo4v2:
            4
        case .turbo8:
            8
        }
    }

    public var outlierBits: Int {
        switch self {
        case .turbo2_5:
            3
        case .turbo3_5, .turbo4, .turbo4v2:
            4
        case .turbo8:
            8
        }
    }

    public var targetMagnitudeBits: Float {
        switch self {
        case .turbo2_5:
            2.5
        case .turbo3_5:
            3.5
        case .turbo4, .turbo4v2:
            4
        case .turbo8:
            8
        }
    }

    public var defaultValueBits: Int {
        switch self {
        case .turbo2_5:
            2
        case .turbo3_5, .turbo4, .turbo4v2:
            4
        case .turbo8:
            8
        }
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
    case nativeMLXCompressed
    case onlineFused
    case tiledOnlineFused
    case sparseValueTwoStageCompressed
    case twoStageCompressed
    case affineInt4Native
    case affineK8V4Native
    case affineK8VxNative
    case affineK8VxResidual
    case mlxPackedFallback
    case baseline
    case unavailable

    public var displayName: String {
        switch self {
        case .nativeMLXCompressed:
            "Native MLX compressed"
        case .onlineFused:
            "Online fused compressed"
        case .tiledOnlineFused:
            "Tiled online fused compressed"
        case .sparseValueTwoStageCompressed:
            "Sparse-V two-stage compressed"
        case .twoStageCompressed:
            "Two-stage compressed"
        case .affineInt4Native:
            "Native affine int4"
        case .affineK8V4Native:
            "Native affine K8/V4"
        case .affineK8VxNative:
            "Native affine K8/Vx"
        case .affineK8VxResidual:
            "Native affine K8/Vx residual"
        case .mlxPackedFallback:
            "MLX packed fallback"
        case .baseline:
            "Baseline"
        case .unavailable:
            "Unavailable"
        }
    }
}

public enum TurboQuantKernelProfile: String, Codable, Sendable, CaseIterable {
    case portableA16A17
    case wideA18A19
    case sustainedA19Pro
    case macAppleSilicon
    case mlxPackedFallback

    public var displayName: String {
        switch self {
        case .portableA16A17:
            "Portable A16/A17"
        case .wideA18A19:
            "Wide A18/A19"
        case .sustainedA19Pro:
            "Sustained A19 Pro"
        case .macAppleSilicon:
            "Mac Apple Silicon"
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

public enum TurboQuantUserMode: String, Codable, Sendable, CaseIterable {
    case fastest
    case balanced
    case maxContext
    case batterySaver

    public var displayName: String {
        switch self {
        case .fastest:
            "Fast"
        case .balanced:
            "Balanced"
        case .maxContext:
            "Max Context"
        case .batterySaver:
            "Battery Saver"
        }
    }
}

public enum TurboQuantFallbackPolicy: String, Codable, Sendable, CaseIterable {
    case exactRequired
    case packedAllowed
    case compressedDecodeAllowed
    case fatalOnFailure

    public var displayName: String {
        switch self {
        case .exactRequired:
            "Exact required"
        case .packedAllowed:
            "Packed allowed"
        case .compressedDecodeAllowed:
            "Compressed decode allowed"
        case .fatalOnFailure:
            "Fatal on failure"
        }
    }
}

public enum TurboQuantRuntimeMode: String, Codable, Sendable, CaseIterable {
    case auto
    case rawPreferred
    case throughputTurboQuant
    case capacityTurboQuant
}

public enum TurboQuantKeyPrecision: String, Codable, Sendable, CaseIterable {
    case fp16OrQ8
    case fp16
    case affineQ8
    case turbo8
    case turbo4v2
    case turbo3_5
    case turbo2_5
}

public enum TurboQuantValuePrecision: String, Codable, Sendable, CaseIterable {
    case fp16
    case turbo8
    case turbo4v2
    case turbo3_5
    case turbo2_5
}

public enum TurboQuantBoundaryPolicy: Hashable, Codable, Sendable {
    case profileDefault
    case disabled
    case protectedEdges(first: Int, last: Int)
    case custom([Int])

    private enum CodingKeys: String, CodingKey {
        case kind
        case first
        case last
        case layers
    }

    private enum Kind: String, Codable {
        case profileDefault
        case disabled
        case protectedEdges
        case custom
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let legacy = try? single.decode(String.self) {
            switch legacy {
            case "profileDefault":
                self = .profileDefault
            case "disabled":
                self = .disabled
            default:
                self = .custom([])
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .profileDefault:
            self = .profileDefault
        case .disabled:
            self = .disabled
        case .protectedEdges:
            self = .protectedEdges(
                first: try container.decodeIfPresent(Int.self, forKey: .first) ?? 0,
                last: try container.decodeIfPresent(Int.self, forKey: .last) ?? 0
            )
        case .custom:
            self = .custom(try container.decodeIfPresent([Int].self, forKey: .layers) ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profileDefault:
            try container.encode(Kind.profileDefault, forKey: .kind)
        case .disabled:
            try container.encode(Kind.disabled, forKey: .kind)
        case .protectedEdges(let first, let last):
            try container.encode(Kind.protectedEdges, forKey: .kind)
            try container.encode(max(0, first), forKey: .first)
            try container.encode(max(0, last), forKey: .last)
        case .custom(let layers):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(layers.map { max(0, $0) }, forKey: .layers)
        }
    }
}

public enum TurboQuantSparseValuePolicy: Hashable, Codable, Sendable {
    case off
    case auto(threshold: Float)
    case force(threshold: Float)

    public static let defaultAutoThreshold: Float = 1e-6
    public static let productDefault = TurboQuantSparseValuePolicy.off

    private enum CodingKeys: String, CodingKey {
        case kind
        case threshold
    }

    private enum Kind: String, Codable {
        case off
        case auto
        case force
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let threshold =
            try container.decodeIfPresent(Float.self, forKey: .threshold)
            ?? Self.defaultAutoThreshold
        switch kind {
        case .off:
            self = .off
        case .auto:
            self = .auto(threshold: max(0, threshold))
        case .force:
            self = .force(threshold: max(0, threshold))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .off:
            try container.encode(Kind.off, forKey: .kind)
        case .auto(let threshold):
            try container.encode(Kind.auto, forKey: .kind)
            try container.encode(max(0, threshold), forKey: .threshold)
        case .force(let threshold):
            try container.encode(Kind.force, forKey: .kind)
            try container.encode(max(0, threshold), forKey: .threshold)
        }
    }

    public var threshold: Float? {
        switch self {
        case .off:
            nil
        case .auto(let threshold), .force(let threshold):
            max(0, threshold)
        }
    }

    public func resolvedThreshold(
        runtimeMode: TurboQuantRuntimeMode,
        contextLength: Int,
        minimumAutoContextLength: Int = 16_384
    ) -> Float? {
        switch self {
        case .off:
            nil
        case .auto(let threshold):
            runtimeMode == .capacityTurboQuant && contextLength >= minimumAutoContextLength
                ? max(0, threshold)
                : nil
        case .force(let threshold):
            runtimeMode == .capacityTurboQuant ? max(0, threshold) : nil
        }
    }
}

public enum TurboQuantAttentionBackendEngine: String, Codable, Sendable, CaseIterable {
    case rawSDPA
    case swiftMetalKernel
    case nativeMLX
    case decodedReference
    case unavailable
}

public struct TurboQuantKVPrecisionPolicy: Hashable, Codable, Sendable {
    public var key: TurboQuantKeyPrecision
    public var value: TurboQuantValuePrecision
    public var boundary: TurboQuantBoundaryPolicy

    public init(
        key: TurboQuantKeyPrecision = .fp16OrQ8,
        value: TurboQuantValuePrecision = .turbo4v2,
        boundary: TurboQuantBoundaryPolicy = .profileDefault
    ) {
        self.key = key
        self.value = value
        self.boundary = boundary
    }
}

public enum TurboQuantAdmissionDowngradeReason: String, Codable, Sendable, CaseIterable {
    case releasedRawShadow
    case disabledPackedFallback
    case loweredValueBits
    case loweredValuePrecision
    case keyPrecisionEvidenceRequired
    case movedBalancedToMaxContext
    case reducedContext
    case rollingSummaryMemory
    case thermalOrBatterySaver
    case refusedInsufficientMemory

    public var displayName: String {
        switch self {
        case .releasedRawShadow:
            "Released raw prefill shadow"
        case .disabledPackedFallback:
            "Disabled packed fallback"
        case .loweredValueBits:
            "Lowered value bits"
        case .loweredValuePrecision:
            "Lowered value precision"
        case .keyPrecisionEvidenceRequired:
            "Key precision evidence required"
        case .movedBalancedToMaxContext:
            "Balanced moved to Max Context"
        case .reducedContext:
            "Reduced context"
        case .rollingSummaryMemory:
            "Rolling summary memory"
        case .thermalOrBatterySaver:
            "Thermal or battery saver"
        case .refusedInsufficientMemory:
            "Insufficient memory"
        }
    }
}

public struct TurboQuantAdmissionDowngrade: Hashable, Codable, Sendable {
    public var reason: TurboQuantAdmissionDowngradeReason
    public var message: String

    public init(reason: TurboQuantAdmissionDowngradeReason, message: String) {
        self.reason = reason
        self.message = message
    }
}

public struct RejectedPath: Hashable, Codable, Sendable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct TurboQuantLayerCacheFootprint: Hashable, Codable, Sendable {
    public var layerCount: Int
    public var kvHeadCount: Int
    public var headDimension: Int
    public var groupSize: Int
    public var preset: TurboQuantPreset
    public var valueBits: Int
    public var groupsPerVector: Int
    public var bitsetWordsPerGroup: Int
    public var keyMagnitudeWordsPerGroup: Int
    public var valueMagnitudeWordsPerGroup: Int
    public var keyBytesPerTokenPerLayer: Int
    public var valueBytesPerTokenPerLayer: Int
    public var bytesPerTokenPerLayer: Int
    public var bytesPerTokenAllLayers: Int
    public var actualBitsPerValue: Double

    public init(
        layerCount: Int,
        kvHeadCount: Int,
        headDimension: Int,
        groupSize: Int,
        preset: TurboQuantPreset,
        valueBits: Int,
        groupsPerVector: Int,
        bitsetWordsPerGroup: Int,
        keyMagnitudeWordsPerGroup: Int,
        valueMagnitudeWordsPerGroup: Int,
        keyBytesPerTokenPerLayer: Int,
        valueBytesPerTokenPerLayer: Int,
        bytesPerTokenPerLayer: Int,
        bytesPerTokenAllLayers: Int,
        actualBitsPerValue: Double
    ) {
        self.layerCount = layerCount
        self.kvHeadCount = kvHeadCount
        self.headDimension = headDimension
        self.groupSize = groupSize
        self.preset = preset
        self.valueBits = valueBits
        self.groupsPerVector = groupsPerVector
        self.bitsetWordsPerGroup = bitsetWordsPerGroup
        self.keyMagnitudeWordsPerGroup = keyMagnitudeWordsPerGroup
        self.valueMagnitudeWordsPerGroup = valueMagnitudeWordsPerGroup
        self.keyBytesPerTokenPerLayer = keyBytesPerTokenPerLayer
        self.valueBytesPerTokenPerLayer = valueBytesPerTokenPerLayer
        self.bytesPerTokenPerLayer = bytesPerTokenPerLayer
        self.bytesPerTokenAllLayers = bytesPerTokenAllLayers
        self.actualBitsPerValue = actualBitsPerValue
    }
}

public struct TurboQuantRuntimeMemoryZones: Hashable, Codable, Sendable {
    public var availableAppMemoryBytes: Int
    public var runtimeBudgetBytes: Int
    public var mlxActiveBytes: Int
    public var mlxCacheBytes: Int
    public var modelResidentBytes: Int
    public var compressedKVBytes: Int
    public var rawShadowBytes: Int
    public var fallbackReserveBytes: Int
    public var scratchBytes: Int
    public var promptAndTokenizerBytes: Int
    public var uiReserveBytes: Int
    public var safetyReserveBytes: Int
    public var rollingSummaryBytes: Int
    public var totalRuntimeBytes: Int
    public var headroomBytes: Int

    public init(
        availableAppMemoryBytes: Int,
        runtimeBudgetBytes: Int,
        mlxActiveBytes: Int,
        mlxCacheBytes: Int,
        modelResidentBytes: Int,
        compressedKVBytes: Int,
        rawShadowBytes: Int,
        fallbackReserveBytes: Int,
        scratchBytes: Int,
        promptAndTokenizerBytes: Int,
        uiReserveBytes: Int,
        safetyReserveBytes: Int,
        rollingSummaryBytes: Int = 0,
        totalRuntimeBytes: Int? = nil,
        headroomBytes: Int? = nil
    ) {
        self.availableAppMemoryBytes = max(0, availableAppMemoryBytes)
        self.runtimeBudgetBytes = max(0, runtimeBudgetBytes)
        self.mlxActiveBytes = max(0, mlxActiveBytes)
        self.mlxCacheBytes = max(0, mlxCacheBytes)
        self.modelResidentBytes = max(0, modelResidentBytes)
        self.compressedKVBytes = max(0, compressedKVBytes)
        self.rawShadowBytes = max(0, rawShadowBytes)
        self.fallbackReserveBytes = max(0, fallbackReserveBytes)
        self.scratchBytes = max(0, scratchBytes)
        self.promptAndTokenizerBytes = max(0, promptAndTokenizerBytes)
        self.uiReserveBytes = max(0, uiReserveBytes)
        self.safetyReserveBytes = max(0, safetyReserveBytes)
        self.rollingSummaryBytes = max(0, rollingSummaryBytes)
        let computedTotal =
            self.mlxCacheBytes
            + self.modelResidentBytes
            + self.compressedKVBytes
            + self.rawShadowBytes
            + self.fallbackReserveBytes
            + self.scratchBytes
            + self.promptAndTokenizerBytes
            + self.uiReserveBytes
            + self.safetyReserveBytes
            + self.rollingSummaryBytes
        self.totalRuntimeBytes = max(0, totalRuntimeBytes ?? computedTotal)
        self.headroomBytes = headroomBytes ?? (self.availableAppMemoryBytes - self.totalRuntimeBytes)
    }
}

public struct TurboQuantMemoryPlan: Hashable, Codable, Sendable {
    public var requestedContextLength: Int
    public var admittedContextLength: Int
    public var requestedMode: TurboQuantUserMode
    public var effectiveMode: TurboQuantUserMode
    public var preset: TurboQuantPreset
    public var valueBits: Int
    public var groupSize: Int
    public var fallbackPolicy: TurboQuantFallbackPolicy
    public var requestedRuntimeMode: TurboQuantRuntimeMode?
    public var resolvedRuntimeMode: TurboQuantRuntimeMode?
    public var precisionPolicy: TurboQuantKVPrecisionPolicy?
    public var runtimeFallbackReason: String?
    public var kvLayerPolicyHash: String?
    public var kvLayerPolicySummary: String?
    public var rawBytesPerToken: Int
    public var packedFallbackBytesPerToken: Int
    public var compressedBytesPerToken: Int
    public var compressedKeyBytes: Int?
    public var compressedValueBytes: Int?
    public var decodedActiveKVBytes: Int?
    public var layerFootprint: TurboQuantLayerCacheFootprint?
    public var usesRawShadow: Bool
    public var packedFallbackEnabled: Bool
    public var usesRollingSummaryMemory: Bool
    public var runtimeZones: TurboQuantRuntimeMemoryZones

    public init(
        requestedContextLength: Int,
        admittedContextLength: Int,
        requestedMode: TurboQuantUserMode,
        effectiveMode: TurboQuantUserMode,
        preset: TurboQuantPreset,
        valueBits: Int,
        groupSize: Int,
        fallbackPolicy: TurboQuantFallbackPolicy,
        requestedRuntimeMode: TurboQuantRuntimeMode? = nil,
        resolvedRuntimeMode: TurboQuantRuntimeMode? = nil,
        precisionPolicy: TurboQuantKVPrecisionPolicy? = nil,
        runtimeFallbackReason: String? = nil,
        kvLayerPolicyHash: String? = nil,
        kvLayerPolicySummary: String? = nil,
        rawBytesPerToken: Int,
        packedFallbackBytesPerToken: Int,
        compressedBytesPerToken: Int,
        compressedKeyBytes: Int? = nil,
        compressedValueBytes: Int? = nil,
        decodedActiveKVBytes: Int? = nil,
        layerFootprint: TurboQuantLayerCacheFootprint? = nil,
        usesRawShadow: Bool,
        packedFallbackEnabled: Bool,
        usesRollingSummaryMemory: Bool,
        runtimeZones: TurboQuantRuntimeMemoryZones
    ) {
        self.requestedContextLength = requestedContextLength
        self.admittedContextLength = admittedContextLength
        self.requestedMode = requestedMode
        self.effectiveMode = effectiveMode
        self.preset = preset
        self.valueBits = valueBits
        self.groupSize = groupSize
        self.fallbackPolicy = fallbackPolicy
        self.requestedRuntimeMode = requestedRuntimeMode
        self.resolvedRuntimeMode = resolvedRuntimeMode
        self.precisionPolicy = precisionPolicy
        self.runtimeFallbackReason = runtimeFallbackReason
        self.kvLayerPolicyHash = kvLayerPolicyHash
        self.kvLayerPolicySummary = kvLayerPolicySummary
        self.rawBytesPerToken = rawBytesPerToken
        self.packedFallbackBytesPerToken = packedFallbackBytesPerToken
        self.compressedBytesPerToken = compressedBytesPerToken
        self.compressedKeyBytes = compressedKeyBytes
        self.compressedValueBytes = compressedValueBytes
        self.decodedActiveKVBytes = decodedActiveKVBytes
        self.layerFootprint = layerFootprint
        self.usesRawShadow = usesRawShadow
        self.packedFallbackEnabled = packedFallbackEnabled
        self.usesRollingSummaryMemory = usesRollingSummaryMemory
        self.runtimeZones = runtimeZones
    }
}

public struct TurboQuantAdmission: Hashable, Codable, Sendable {
    public var admitted: Bool
    public var requestedContextLength: Int
    public var admittedContextLength: Int
    /// When true, the admitted context fits an uncompressed FP16 KV cache within the live memory
    /// budget — the runtime should use plain SDPA (faster, higher quality) instead of TurboQuant.
    public var recommendsPlainKVCache: Bool
    public var requestedMode: TurboQuantUserMode
    public var selectedMode: TurboQuantUserMode
    public var memoryPlan: TurboQuantMemoryPlan?
    public var downgradeReasons: [TurboQuantAdmissionDowngrade]
    public var rejectedPaths: [RejectedPath]
    public var userMessage: String

    public var primaryDowngradeReason: TurboQuantAdmissionDowngradeReason? {
        downgradeReasons.first?.reason
    }

    public init(
        admitted: Bool,
        requestedContextLength: Int,
        admittedContextLength: Int,
        requestedMode: TurboQuantUserMode,
        selectedMode: TurboQuantUserMode,
        memoryPlan: TurboQuantMemoryPlan? = nil,
        downgradeReasons: [TurboQuantAdmissionDowngrade] = [],
        rejectedPaths: [RejectedPath] = [],
        userMessage: String,
        recommendsPlainKVCache: Bool = false
    ) {
        self.admitted = admitted
        self.requestedContextLength = requestedContextLength
        self.admittedContextLength = admittedContextLength
        self.recommendsPlainKVCache = recommendsPlainKVCache
        self.requestedMode = requestedMode
        self.selectedMode = selectedMode
        self.memoryPlan = memoryPlan
        self.downgradeReasons = downgradeReasons
        self.rejectedPaths = rejectedPaths
        self.userMessage = userMessage
    }
}

public enum KVCacheStrategy: String, Codable, Sendable, CaseIterable {
    case none
    case mlxAffine
    case turboQuant
}

public enum KVLayerCodec: Hashable, Codable, Sendable {
    case inherit
    case rawFP16
    case mlxAffine(bits: Int, groupSize: Int)
    case affineK8V4
    case affineInt4
    case turboQuant(
        preset: TurboQuantPreset,
        valueBits: Int?,
        groupSize: Int,
        backend: TurboQuantRuntimeBackend
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case bits
        case groupSize
        case preset
        case valueBits
        case backend
    }

    private enum Kind: String, Codable {
        case inherit
        case rawFP16
        case mlxAffine
        case affineK8V4
        case affineInt4
        case turboQuant
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inherit:
            self = .inherit
        case .rawFP16:
            self = .rawFP16
        case .mlxAffine:
            self = .mlxAffine(
                bits: try container.decode(Int.self, forKey: .bits),
                groupSize: try container.decodeIfPresent(Int.self, forKey: .groupSize) ?? 64
            )
        case .affineK8V4:
            self = .affineK8V4
        case .affineInt4:
            self = .affineInt4
        case .turboQuant:
            self = .turboQuant(
                preset: try container.decode(TurboQuantPreset.self, forKey: .preset),
                valueBits: try container.decodeIfPresent(Int.self, forKey: .valueBits),
                groupSize: try container.decodeIfPresent(Int.self, forKey: .groupSize) ?? 64,
                backend: try container.decodeIfPresent(TurboQuantRuntimeBackend.self, forKey: .backend)
                    ?? .metalPolarQJL
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inherit:
            try container.encode(Kind.inherit, forKey: .kind)
        case .rawFP16:
            try container.encode(Kind.rawFP16, forKey: .kind)
        case .mlxAffine(let bits, let groupSize):
            try container.encode(Kind.mlxAffine, forKey: .kind)
            try container.encode(bits, forKey: .bits)
            try container.encode(groupSize, forKey: .groupSize)
        case .affineK8V4:
            try container.encode(Kind.affineK8V4, forKey: .kind)
        case .affineInt4:
            try container.encode(Kind.affineInt4, forKey: .kind)
        case .turboQuant(let preset, let valueBits, let groupSize, let backend):
            try container.encode(Kind.turboQuant, forKey: .kind)
            try container.encode(preset, forKey: .preset)
            try container.encodeIfPresent(valueBits, forKey: .valueBits)
            try container.encode(groupSize, forKey: .groupSize)
            try container.encode(backend, forKey: .backend)
        }
    }

    public var summary: String {
        switch self {
        case .inherit:
            "inherit"
        case .rawFP16:
            "rawFP16"
        case .mlxAffine(let bits, let groupSize):
            "mlxAffine\(bits)g\(groupSize)"
        case .affineK8V4:
            "affineK8V4"
        case .affineInt4:
            "affineInt4"
        case .turboQuant(let preset, let valueBits, let groupSize, let backend):
            "turboQuant(\(preset.rawValue),v\(valueBits.map(String.init) ?? "default"),g\(groupSize),\(backend.rawValue))"
        }
    }

    fileprivate var canonicalString: String {
        switch self {
        case .inherit:
            "inherit"
        case .rawFP16:
            "rawFP16"
        case .mlxAffine(let bits, let groupSize):
            "mlxAffine(bits:\(bits),groupSize:\(groupSize))"
        case .affineK8V4:
            "affineK8V4"
        case .affineInt4:
            "affineInt4"
        case .turboQuant(let preset, let valueBits, let groupSize, let backend):
            "turboQuant(preset:\(preset.rawValue),valueBits:\(valueBits.map(String.init) ?? "nil"),groupSize:\(groupSize),backend:\(backend.rawValue))"
        }
    }
}

public struct KVLayerRule: Hashable, Codable, Sendable {
    public var layerIndex: Int
    public var codec: KVLayerCodec

    public init(layerIndex: Int, codec: KVLayerCodec) {
        self.layerIndex = layerIndex
        self.codec = codec
    }
}

public struct KVLayerPolicy: Hashable, Codable, Sendable {
    public var defaultCodec: KVLayerCodec?
    public var rules: [KVLayerRule]

    public init(defaultCodec: KVLayerCodec? = nil, rules: [KVLayerRule] = []) {
        self.defaultCodec = defaultCodec
        self.rules = rules
    }

    public var stableHash: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in canonicalString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    public func summary(maxRules: Int = 8) -> String {
        let visible = rules.sorted { $0.layerIndex < $1.layerIndex }
            .prefix(max(0, maxRules))
            .map { "\($0.layerIndex):\($0.codec.summary)" }
        let suffix = rules.count > visible.count ? ",+\(rules.count - visible.count)" : ""
        return "default=\(defaultCodec?.summary ?? "inherit");layers=[\(visible.joined(separator: ","))\(suffix)]"
    }

    private var canonicalString: String {
        var parts = ["default:\(defaultCodec?.canonicalString ?? "nil")"]
        for rule in rules.sorted(by: { lhs, rhs in
            lhs.layerIndex == rhs.layerIndex
                ? lhs.codec.canonicalString < rhs.codec.canonicalString
                : lhs.layerIndex < rhs.layerIndex
        }) {
            parts.append("\(rule.layerIndex):\(rule.codec.canonicalString)")
        }
        return parts.joined(separator: "|")
    }
}

public enum DevicePerformanceClass: String, Codable, Sendable, CaseIterable {
    case a16Compact
    case a17Pro
    case a18Standard
    case a18Pro
    case a19Standard
    case a19ProThin
    case a19ProSustained
    case mSeriesTabletBalanced
    case mSeriesTabletPro
    case mSeriesTabletMax
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
        case .mSeriesTabletBalanced:
            "M-series iPad 8 GB"
        case .mSeriesTabletPro:
            "M-series iPad 12 GB"
        case .mSeriesTabletMax:
            "M-series iPad 16 GB"
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
    public var processResidentMemoryBytes: Int64?
    public var processPhysicalFootprintBytes: Int64?
    public var processPeakResidentMemoryBytes: Int64?
    public var thermalState: String?
    public var hardwareModelIdentifier: String?
    public var lowPowerModeEnabled: Bool?
    public var metalArchitectureName: String?
    public var metalRecommendedWorkingSetBytes: Int64?
    public var mlxActiveMemoryBytes: Int64?
    public var mlxCacheMemoryBytes: Int64?
    public var mlxPeakMemoryBytes: Int64?
    public var mlxMemoryLimitBytes: Int64?
    public var mlxCacheLimitBytes: Int64?
    public var devicePerformanceClass: DevicePerformanceClass?
    public var thermalDownshiftActive: Bool?
    public var runtimePressureReason: RuntimePressureReason?
    public var recommendedContextTokens: Int?
    public var recommendedSmallModelContextTokens: Int?
    public var recommendedPrefillStepSize: Int?
    public var recommendedEmbeddingBatchSize: Int?
    public var recommendedVectorScanLimit: Int?

    public init(
        kvCacheBytes: Int64? = nil,
        quantizedKVCacheBytes: Int64? = nil,
        vaultIndexBytes: Int64? = nil,
        physicalMemoryBytes: Int64? = nil,
        availableMemoryBytes: Int64? = nil,
        processResidentMemoryBytes: Int64? = nil,
        processPhysicalFootprintBytes: Int64? = nil,
        processPeakResidentMemoryBytes: Int64? = nil,
        thermalState: String? = nil,
        hardwareModelIdentifier: String? = nil,
        lowPowerModeEnabled: Bool? = nil,
        metalArchitectureName: String? = nil,
        metalRecommendedWorkingSetBytes: Int64? = nil,
        mlxActiveMemoryBytes: Int64? = nil,
        mlxCacheMemoryBytes: Int64? = nil,
        mlxPeakMemoryBytes: Int64? = nil,
        mlxMemoryLimitBytes: Int64? = nil,
        mlxCacheLimitBytes: Int64? = nil,
        devicePerformanceClass: DevicePerformanceClass? = nil,
        thermalDownshiftActive: Bool? = nil,
        runtimePressureReason: RuntimePressureReason? = nil,
        recommendedContextTokens: Int? = nil,
        recommendedSmallModelContextTokens: Int? = nil,
        recommendedPrefillStepSize: Int? = nil,
        recommendedEmbeddingBatchSize: Int? = nil,
        recommendedVectorScanLimit: Int? = nil
    ) {
        self.kvCacheBytes = kvCacheBytes
        self.quantizedKVCacheBytes = quantizedKVCacheBytes
        self.vaultIndexBytes = vaultIndexBytes
        self.physicalMemoryBytes = physicalMemoryBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.processResidentMemoryBytes = processResidentMemoryBytes
        self.processPhysicalFootprintBytes = processPhysicalFootprintBytes
        self.processPeakResidentMemoryBytes = processPeakResidentMemoryBytes
        self.thermalState = thermalState
        self.hardwareModelIdentifier = hardwareModelIdentifier
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.metalArchitectureName = metalArchitectureName
        self.metalRecommendedWorkingSetBytes = metalRecommendedWorkingSetBytes
        self.mlxActiveMemoryBytes = mlxActiveMemoryBytes
        self.mlxCacheMemoryBytes = mlxCacheMemoryBytes
        self.mlxPeakMemoryBytes = mlxPeakMemoryBytes
        self.mlxMemoryLimitBytes = mlxMemoryLimitBytes
        self.mlxCacheLimitBytes = mlxCacheLimitBytes
        self.devicePerformanceClass = devicePerformanceClass
        self.thermalDownshiftActive = thermalDownshiftActive
        self.runtimePressureReason = runtimePressureReason
        self.recommendedContextTokens = recommendedContextTokens
        self.recommendedSmallModelContextTokens = recommendedSmallModelContextTokens
        self.recommendedPrefillStepSize = recommendedPrefillStepSize
        self.recommendedEmbeddingBatchSize = recommendedEmbeddingBatchSize
        self.recommendedVectorScanLimit = recommendedVectorScanLimit
    }
}

public struct RuntimeMemorySnapshot: Hashable, Codable, Sendable {
    public var physicalMemoryBytes: Int64
    public var availableMemoryBytes: Int64?
    public var processResidentMemoryBytes: Int64?
    public var processPhysicalFootprintBytes: Int64?
    public var processPeakResidentMemoryBytes: Int64?
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
        processResidentMemoryBytes: Int64? = nil,
        processPhysicalFootprintBytes: Int64? = nil,
        processPeakResidentMemoryBytes: Int64? = nil,
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
        self.processResidentMemoryBytes = processResidentMemoryBytes
        self.processPhysicalFootprintBytes = processPhysicalFootprintBytes
        self.processPeakResidentMemoryBytes = processPeakResidentMemoryBytes
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
    public var turboQuantValueBits: Int?
    public var turboQuantRuntimeMode: TurboQuantRuntimeMode?
    public var turboQuantResolvedRuntimeMode: TurboQuantRuntimeMode?
    public var turboQuantKeyPrecision: TurboQuantKeyPrecision?
    public var turboQuantValuePrecision: TurboQuantValuePrecision?
    public var turboQuantPrecisionPolicy: TurboQuantKVPrecisionPolicy?
    public var turboQuantSparseValuePolicy: TurboQuantSparseValuePolicy?
    public var turboQuantEffectiveBackend: TurboQuantAttentionBackendEngine?
    public var turboQuantNativeBackendVersion: String?
    public var turboQuantDecodedActiveKVBytes: Int64?
    public var thermalDownshiftActive: Bool?
    public var runtimePressureReason: RuntimePressureReason?
    public var turboQuantProfileID: String?
    public var turboQuantProfileSource: String?
    public var lastUnsupportedAttentionShape: String?
    public var activeFallbackReason: String?
    public var memoryCounters: RuntimeMemoryCounters
    public var ssdThroughputMBperS: Double?
    public var ssdTotalBytesRead: UInt64?
    public var ssdTotalChunks: UInt64?
    public var ssdAvgChunkLatencyMS: Double?
    public var partitionSummary: String?
    public var mtpAcceptanceRate: Double?
    public var audioCapability: Bool?
    public var turboQuantSpeculativeTelemetry: TurboQuantSpeculativeTelemetry?
    public var turboQuantSpeculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision?
    public var turboQuantPlatformFeatureGates: [TurboQuantPlatformFeatureGate]?

    public init(
        requestedAlgorithm: QuantizationAlgorithm = .turboQuant,
        activeAlgorithm: QuantizationAlgorithm = .turboQuant,
        preset: TurboQuantPreset? = .defaultGeneration,
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
        turboQuantValueBits: Int? = nil,
        turboQuantRuntimeMode: TurboQuantRuntimeMode? = nil,
        turboQuantResolvedRuntimeMode: TurboQuantRuntimeMode? = nil,
        turboQuantKeyPrecision: TurboQuantKeyPrecision? = nil,
        turboQuantValuePrecision: TurboQuantValuePrecision? = nil,
        turboQuantPrecisionPolicy: TurboQuantKVPrecisionPolicy? = nil,
        turboQuantSparseValuePolicy: TurboQuantSparseValuePolicy? = nil,
        turboQuantEffectiveBackend: TurboQuantAttentionBackendEngine? = nil,
        turboQuantNativeBackendVersion: String? = nil,
        turboQuantDecodedActiveKVBytes: Int64? = nil,
        thermalDownshiftActive: Bool? = nil,
        runtimePressureReason: RuntimePressureReason? = nil,
        turboQuantProfileID: String? = nil,
        turboQuantProfileSource: String? = nil,
        lastUnsupportedAttentionShape: String? = nil,
        activeFallbackReason: String? = nil,
        memoryCounters: RuntimeMemoryCounters = RuntimeMemoryCounters(),
        ssdThroughputMBperS: Double? = nil,
        ssdTotalBytesRead: UInt64? = nil,
        ssdTotalChunks: UInt64? = nil,
        ssdAvgChunkLatencyMS: Double? = nil,
        partitionSummary: String? = nil,
        mtpAcceptanceRate: Double? = nil,
        audioCapability: Bool? = nil,
        turboQuantSpeculativeTelemetry: TurboQuantSpeculativeTelemetry? = nil,
        turboQuantSpeculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision? = nil,
        turboQuantPlatformFeatureGates: [TurboQuantPlatformFeatureGate]? = nil
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
        self.turboQuantValueBits = turboQuantValueBits
        self.turboQuantRuntimeMode = turboQuantRuntimeMode
        self.turboQuantResolvedRuntimeMode = turboQuantResolvedRuntimeMode
        self.turboQuantKeyPrecision = turboQuantKeyPrecision
        self.turboQuantValuePrecision = turboQuantValuePrecision
        self.turboQuantPrecisionPolicy = turboQuantPrecisionPolicy
        self.turboQuantSparseValuePolicy = turboQuantSparseValuePolicy
        self.turboQuantEffectiveBackend = turboQuantEffectiveBackend
        self.turboQuantNativeBackendVersion = turboQuantNativeBackendVersion
        self.turboQuantDecodedActiveKVBytes = turboQuantDecodedActiveKVBytes.map { max(0, $0) }
        self.thermalDownshiftActive = thermalDownshiftActive
        self.runtimePressureReason = runtimePressureReason
        self.turboQuantProfileID = turboQuantProfileID
        self.turboQuantProfileSource = turboQuantProfileSource
        self.lastUnsupportedAttentionShape = lastUnsupportedAttentionShape
        self.activeFallbackReason = activeFallbackReason
        self.memoryCounters = memoryCounters
        self.ssdThroughputMBperS = ssdThroughputMBperS
        self.ssdTotalBytesRead = ssdTotalBytesRead
        self.ssdTotalChunks = ssdTotalChunks
        self.ssdAvgChunkLatencyMS = ssdAvgChunkLatencyMS
        self.partitionSummary = partitionSummary
        self.mtpAcceptanceRate = mtpAcceptanceRate
        self.audioCapability = audioCapability
        self.turboQuantSpeculativeTelemetry = turboQuantSpeculativeTelemetry
        self.turboQuantSpeculativeAutoDisableDecision = turboQuantSpeculativeAutoDisableDecision
        self.turboQuantPlatformFeatureGates = turboQuantPlatformFeatureGates
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
    public var turboQuantValueBits: Int?
    public var turboQuantRuntimeMode: TurboQuantRuntimeMode
    public var turboQuantResolvedRuntimeMode: TurboQuantRuntimeMode?
    public var turboQuantKeyPrecision: TurboQuantKeyPrecision?
    public var turboQuantValuePrecision: TurboQuantValuePrecision?
    public var turboQuantPrecisionPolicy: TurboQuantKVPrecisionPolicy?
    public var turboQuantKVLayerPolicy: KVLayerPolicy?
    public var turboQuantSparseValuePolicy: TurboQuantSparseValuePolicy?
    public var turboQuantEffectiveBackend: TurboQuantAttentionBackendEngine?
    public var turboQuantNativeBackendVersion: String?
    public var turboQuantDecodedActiveKVBytes: Int64?
    public var turboQuantLayoutVersion: Int?
    public var thermalDownshiftActive: Bool
    public var runtimePressureReason: RuntimePressureReason
    public var turboQuantProfileID: String?
    public var turboQuantProfileSource: String?
    public var turboQuantProfileDiagnostics: [String]
    public var lastUnsupportedAttentionShape: String?
    public var activeFallbackReason: String?
    public var memoryCounters: RuntimeMemoryCounters
    public var turboQuantUserMode: TurboQuantUserMode
    public var turboQuantAdmission: TurboQuantAdmission?
    public var turboQuantSpeculativeSettings: TurboQuantSpeculativeSettings?
    public var turboQuantSpeculativeTelemetry: TurboQuantSpeculativeTelemetry?
    public var turboQuantSpeculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision?
    public var turboQuantPlatformFeatureGates: [TurboQuantPlatformFeatureGate]

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
        case turboQuantValueBits
        case turboQuantRuntimeMode
        case turboQuantResolvedRuntimeMode
        case turboQuantKeyPrecision
        case turboQuantValuePrecision
        case turboQuantPrecisionPolicy
        case turboQuantKVLayerPolicy
        case turboQuantSparseValuePolicy
        case turboQuantEffectiveBackend
        case turboQuantNativeBackendVersion
        case turboQuantDecodedActiveKVBytes
        case turboQuantLayoutVersion
        case thermalDownshiftActive
        case runtimePressureReason
        case turboQuantProfileID
        case turboQuantProfileSource
        case turboQuantProfileDiagnostics
        case lastUnsupportedAttentionShape
        case activeFallbackReason
        case memoryCounters
        case turboQuantUserMode
        case turboQuantAdmission
        case turboQuantSpeculativeSettings
        case turboQuantSpeculativeTelemetry
        case turboQuantSpeculativeAutoDisableDecision
        case turboQuantPlatformFeatureGates
    }

    public init(
        weightBits: Int? = nil,
        kvBits: Int? = nil,
        kvGroupSize: Int = 64,
        quantizedKVStart: Int = 0,
        maxKVSize: Int? = nil,
        algorithm: QuantizationAlgorithm = .turboQuant,
        kvCacheStrategy: KVCacheStrategy = .turboQuant,
        preset: TurboQuantPreset? = .defaultGeneration,
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
        turboQuantValueBits: Int? = nil,
        turboQuantRuntimeMode: TurboQuantRuntimeMode = .auto,
        turboQuantResolvedRuntimeMode: TurboQuantRuntimeMode? = nil,
        turboQuantKeyPrecision: TurboQuantKeyPrecision? = nil,
        turboQuantValuePrecision: TurboQuantValuePrecision? = nil,
        turboQuantPrecisionPolicy: TurboQuantKVPrecisionPolicy? = nil,
        turboQuantKVLayerPolicy: KVLayerPolicy? = nil,
        turboQuantSparseValuePolicy: TurboQuantSparseValuePolicy? = nil,
        turboQuantEffectiveBackend: TurboQuantAttentionBackendEngine? = nil,
        turboQuantNativeBackendVersion: String? = nil,
        turboQuantDecodedActiveKVBytes: Int64? = nil,
        turboQuantLayoutVersion: Int? = nil,
        thermalDownshiftActive: Bool = false,
        runtimePressureReason: RuntimePressureReason = .none,
        turboQuantProfileID: String? = nil,
        turboQuantProfileSource: String? = nil,
        turboQuantProfileDiagnostics: [String] = [],
        lastUnsupportedAttentionShape: String? = nil,
        activeFallbackReason: String? = nil,
        memoryCounters: RuntimeMemoryCounters = RuntimeMemoryCounters(),
        turboQuantUserMode: TurboQuantUserMode = .balanced,
        turboQuantAdmission: TurboQuantAdmission? = nil,
        turboQuantSpeculativeSettings: TurboQuantSpeculativeSettings? = nil,
        turboQuantSpeculativeTelemetry: TurboQuantSpeculativeTelemetry? = nil,
        turboQuantSpeculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision? = nil,
        turboQuantPlatformFeatureGates: [TurboQuantPlatformFeatureGate] = TurboQuantPlatformFeatureGate.wave7DisabledDefaults
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
        self.turboQuantValueBits = turboQuantValueBits
        self.turboQuantRuntimeMode = turboQuantRuntimeMode
        self.turboQuantResolvedRuntimeMode = turboQuantResolvedRuntimeMode
        self.turboQuantKeyPrecision = turboQuantKeyPrecision
        self.turboQuantValuePrecision = turboQuantValuePrecision
        self.turboQuantPrecisionPolicy = turboQuantPrecisionPolicy
        self.turboQuantKVLayerPolicy = turboQuantKVLayerPolicy
        self.turboQuantSparseValuePolicy = turboQuantSparseValuePolicy
        self.turboQuantEffectiveBackend = turboQuantEffectiveBackend
        self.turboQuantNativeBackendVersion = turboQuantNativeBackendVersion
        self.turboQuantDecodedActiveKVBytes = turboQuantDecodedActiveKVBytes.map { max(0, $0) }
        self.turboQuantLayoutVersion = turboQuantLayoutVersion
        self.thermalDownshiftActive = thermalDownshiftActive
        self.runtimePressureReason = runtimePressureReason
        self.turboQuantProfileID = turboQuantProfileID
        self.turboQuantProfileSource = turboQuantProfileSource
        self.turboQuantProfileDiagnostics = turboQuantProfileDiagnostics
        self.lastUnsupportedAttentionShape = lastUnsupportedAttentionShape
        self.activeFallbackReason = activeFallbackReason
        self.memoryCounters = memoryCounters
        self.turboQuantUserMode = turboQuantUserMode
        self.turboQuantAdmission = turboQuantAdmission
        self.turboQuantSpeculativeSettings = turboQuantSpeculativeSettings
        self.turboQuantSpeculativeTelemetry = turboQuantSpeculativeTelemetry
        self.turboQuantSpeculativeAutoDisableDecision = turboQuantSpeculativeAutoDisableDecision
        self.turboQuantPlatformFeatureGates = turboQuantPlatformFeatureGates
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
        preset = try container.decodeIfPresent(TurboQuantPreset.self, forKey: .preset) ?? .conservativeFallback
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
        turboQuantValueBits = try container.decodeIfPresent(Int.self, forKey: .turboQuantValueBits)
        turboQuantRuntimeMode = try container.decodeIfPresent(TurboQuantRuntimeMode.self, forKey: .turboQuantRuntimeMode) ?? .auto
        turboQuantResolvedRuntimeMode = try container.decodeIfPresent(TurboQuantRuntimeMode.self, forKey: .turboQuantResolvedRuntimeMode)
        turboQuantKeyPrecision = try container.decodeIfPresent(TurboQuantKeyPrecision.self, forKey: .turboQuantKeyPrecision)
        turboQuantValuePrecision = try container.decodeIfPresent(TurboQuantValuePrecision.self, forKey: .turboQuantValuePrecision)
        turboQuantPrecisionPolicy = try container.decodeIfPresent(TurboQuantKVPrecisionPolicy.self, forKey: .turboQuantPrecisionPolicy)
        turboQuantKVLayerPolicy = try container.decodeIfPresent(KVLayerPolicy.self, forKey: .turboQuantKVLayerPolicy)
        turboQuantSparseValuePolicy = try container.decodeIfPresent(TurboQuantSparseValuePolicy.self, forKey: .turboQuantSparseValuePolicy)
        turboQuantEffectiveBackend = try container.decodeIfPresent(TurboQuantAttentionBackendEngine.self, forKey: .turboQuantEffectiveBackend)
        turboQuantNativeBackendVersion = try container.decodeIfPresent(String.self, forKey: .turboQuantNativeBackendVersion)
        turboQuantDecodedActiveKVBytes = try container.decodeIfPresent(Int64.self, forKey: .turboQuantDecodedActiveKVBytes)
        turboQuantLayoutVersion = try container.decodeIfPresent(Int.self, forKey: .turboQuantLayoutVersion)
        thermalDownshiftActive = try container.decodeIfPresent(Bool.self, forKey: .thermalDownshiftActive) ?? false
        runtimePressureReason = try container.decodeIfPresent(RuntimePressureReason.self, forKey: .runtimePressureReason) ?? .none
        turboQuantProfileID = try container.decodeIfPresent(String.self, forKey: .turboQuantProfileID)
        turboQuantProfileSource = try container.decodeIfPresent(String.self, forKey: .turboQuantProfileSource)
        turboQuantProfileDiagnostics = try container.decodeIfPresent([String].self, forKey: .turboQuantProfileDiagnostics) ?? []
        lastUnsupportedAttentionShape = try container.decodeIfPresent(String.self, forKey: .lastUnsupportedAttentionShape)
        activeFallbackReason = try container.decodeIfPresent(String.self, forKey: .activeFallbackReason)
        memoryCounters = try container.decodeIfPresent(RuntimeMemoryCounters.self, forKey: .memoryCounters) ?? RuntimeMemoryCounters()
        turboQuantUserMode = try container.decodeIfPresent(TurboQuantUserMode.self, forKey: .turboQuantUserMode) ?? .balanced
        turboQuantAdmission = try container.decodeIfPresent(TurboQuantAdmission.self, forKey: .turboQuantAdmission)
        turboQuantSpeculativeSettings = try container.decodeIfPresent(TurboQuantSpeculativeSettings.self, forKey: .turboQuantSpeculativeSettings)
        turboQuantSpeculativeTelemetry = try container.decodeIfPresent(TurboQuantSpeculativeTelemetry.self, forKey: .turboQuantSpeculativeTelemetry)
        turboQuantSpeculativeAutoDisableDecision = try container.decodeIfPresent(
            TurboQuantSpeculativeAutoDisableDecision.self,
            forKey: .turboQuantSpeculativeAutoDisableDecision
        )
        turboQuantPlatformFeatureGates = try container.decodeIfPresent(
            [TurboQuantPlatformFeatureGate].self,
            forKey: .turboQuantPlatformFeatureGates
        ) ?? TurboQuantPlatformFeatureGate.wave7DisabledDefaults
    }
}

public enum RuntimeExpertStreamingMode: String, Hashable, Codable, Sendable, CaseIterable {
    case disabled
    case mmapPageCache
    case directNVMe
}

public struct RuntimeProfile: Hashable, Codable, Sendable {
    public var name: String
    public var quantization: QuantizationProfile
    public var streamExperts: Bool
    public var expertStreamingMode: RuntimeExpertStreamingMode
    public var gpuLayerCount: Int?
    public var mtpEnabled: Bool
    public var audioEnabled: Bool
    public var dflashEnabled: Bool
    public var prefillStepSize: Int
    public var promptCacheEnabled: Bool
    public var promptCacheIdentifier: String?
    public var speculativeDraftModelID: ModelID?
    public var speculativeDecodingEnabled: Bool
    public var speculativeSettings: TurboQuantSpeculativeSettings?
    public var unloadOnMemoryPressure: Bool
    public var repetitionContextSize: Int
    public var maxConcurrentSessions: Int

    public init(
        name: String = "Balanced",
        quantization: QuantizationProfile = .init(kvBits: 8),
        streamExperts: Bool = false,
        expertStreamingMode: RuntimeExpertStreamingMode = .disabled,
        gpuLayerCount: Int? = nil,
        mtpEnabled: Bool = false,
        audioEnabled: Bool = false,
        dflashEnabled: Bool = false,
        prefillStepSize: Int = 512,
        promptCacheEnabled: Bool = true,
        promptCacheIdentifier: String? = nil,
        speculativeDraftModelID: ModelID? = nil,
        speculativeDecodingEnabled: Bool = false,
        speculativeSettings: TurboQuantSpeculativeSettings? = nil,
        unloadOnMemoryPressure: Bool = true,
        repetitionContextSize: Int = 20,
        maxConcurrentSessions: Int = 1
    ) {
        self.name = name
        self.quantization = quantization
        self.streamExperts = streamExperts
        self.expertStreamingMode = expertStreamingMode
        self.gpuLayerCount = gpuLayerCount
        self.mtpEnabled = mtpEnabled
        self.audioEnabled = audioEnabled
        self.dflashEnabled = dflashEnabled
        self.prefillStepSize = prefillStepSize
        self.promptCacheEnabled = promptCacheEnabled
        self.promptCacheIdentifier = promptCacheIdentifier
        self.speculativeDraftModelID = speculativeDraftModelID
        self.speculativeDecodingEnabled = speculativeDecodingEnabled
        self.speculativeSettings = speculativeSettings
        self.unloadOnMemoryPressure = unloadOnMemoryPressure
        self.repetitionContextSize = repetitionContextSize
        self.maxConcurrentSessions = maxConcurrentSessions
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case quantization
        case streamExperts
        case expertStreamingMode
        case gpuLayerCount
        case mtpEnabled
        case audioEnabled
        case dflashEnabled
        case prefillStepSize
        case promptCacheEnabled
        case promptCacheIdentifier
        case speculativeDraftModelID
        case speculativeDecodingEnabled
        case speculativeSettings
        case unloadOnMemoryPressure
        case repetitionContextSize
        case maxConcurrentSessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Balanced"
        quantization = try container.decodeIfPresent(QuantizationProfile.self, forKey: .quantization) ?? .init(kvBits: 8)
        streamExperts = try container.decodeIfPresent(Bool.self, forKey: .streamExperts) ?? false
        expertStreamingMode = try container.decodeIfPresent(RuntimeExpertStreamingMode.self, forKey: .expertStreamingMode) ?? .disabled
        gpuLayerCount = try container.decodeIfPresent(Int.self, forKey: .gpuLayerCount)
        mtpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mtpEnabled) ?? false
        audioEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? false
        dflashEnabled = try container.decodeIfPresent(Bool.self, forKey: .dflashEnabled) ?? false
        prefillStepSize = try container.decodeIfPresent(Int.self, forKey: .prefillStepSize) ?? 512
        promptCacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .promptCacheEnabled) ?? true
        promptCacheIdentifier = try container.decodeIfPresent(String.self, forKey: .promptCacheIdentifier)
        speculativeDraftModelID = try container.decodeIfPresent(ModelID.self, forKey: .speculativeDraftModelID)
        speculativeDecodingEnabled = try container.decodeIfPresent(Bool.self, forKey: .speculativeDecodingEnabled) ?? false
        speculativeSettings = try container.decodeIfPresent(TurboQuantSpeculativeSettings.self, forKey: .speculativeSettings)
        unloadOnMemoryPressure = try container.decodeIfPresent(Bool.self, forKey: .unloadOnMemoryPressure) ?? true
        repetitionContextSize = try container.decodeIfPresent(Int.self, forKey: .repetitionContextSize) ?? 20
        maxConcurrentSessions = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentSessions) ?? 1
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
    public var textConfigModelType: String?
    public var processorClass: String?
    public var keyHeadDimension: Int?
    public var valueHeadDimension: Int?
    public var routedExperts: Int?
    public var expertsPerToken: Int?
    public var cacheTopology: ModelCacheTopology
    public var turboQuantFamilySupport: TurboQuantFamilySupport
    public var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case modelID
        case displayName
        case repository
        case revision
        case localURL
        case modalities
        case verification
        case state
        case parameterCount
        case estimatedBytes
        case license
        case modelType
        case textConfigModelType
        case processorClass
        case keyHeadDimension
        case valueHeadDimension
        case routedExperts
        case expertsPerToken
        case cacheTopology
        case turboQuantFamilySupport
        case createdAt
    }

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
        textConfigModelType: String? = nil,
        processorClass: String? = nil,
        keyHeadDimension: Int? = nil,
        valueHeadDimension: Int? = nil,
        routedExperts: Int? = nil,
        expertsPerToken: Int? = nil,
        cacheTopology: ModelCacheTopology = .standardAttention,
        turboQuantFamilySupport: TurboQuantFamilySupport = .attentionKVFull,
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
        self.textConfigModelType = textConfigModelType
        self.processorClass = processorClass
        self.keyHeadDimension = keyHeadDimension
        self.valueHeadDimension = valueHeadDimension
        self.routedExperts = routedExperts
        self.expertsPerToken = expertsPerToken
        self.cacheTopology = cacheTopology
        self.turboQuantFamilySupport = turboQuantFamilySupport
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        modelID = try container.decode(ModelID.self, forKey: .modelID)
        displayName = try container.decode(String.self, forKey: .displayName)
        repository = try container.decode(String.self, forKey: .repository)
        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        localURL = try container.decodeIfPresent(URL.self, forKey: .localURL)
        modalities = try container.decodeIfPresent(Set<ModelModality>.self, forKey: .modalities) ?? [.text]
        verification = try container.decodeIfPresent(ModelVerificationState.self, forKey: .verification) ?? .installable
        state = try container.decodeIfPresent(ModelInstallState.self, forKey: .state) ?? .remote
        parameterCount = try container.decodeIfPresent(Int64.self, forKey: .parameterCount)
        estimatedBytes = try container.decodeIfPresent(Int64.self, forKey: .estimatedBytes)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        modelType = try container.decodeIfPresent(String.self, forKey: .modelType)
        textConfigModelType = try container.decodeIfPresent(String.self, forKey: .textConfigModelType)
        processorClass = try container.decodeIfPresent(String.self, forKey: .processorClass)
        keyHeadDimension = try container.decodeIfPresent(Int.self, forKey: .keyHeadDimension)
        valueHeadDimension = try container.decodeIfPresent(Int.self, forKey: .valueHeadDimension)
        routedExperts = try container.decodeIfPresent(Int.self, forKey: .routedExperts)
        expertsPerToken = try container.decodeIfPresent(Int.self, forKey: .expertsPerToken)
        cacheTopology = try container.decodeIfPresent(ModelCacheTopology.self, forKey: .cacheTopology) ?? .standardAttention
        turboQuantFamilySupport = try container.decodeIfPresent(TurboQuantFamilySupport.self, forKey: .turboQuantFamilySupport) ?? .attentionKVFull
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public extension ModelInstall {
    var resolvedParameterCount: Int64? {
        parameterCount
            ?? ModelDiscoveryResourcePolicy.inferredParameterCount(repository: repository, tags: [])
    }

    var effectiveTurboQuantModalities: Set<ModelModality> {
        guard modalities.contains(.text),
              modalities.contains(.vision),
              turboQuantModelTypeHints.contains(where: Self.isQwen35TurboQuantFamily),
              cacheTopology == .hybridAttentionAndNativeState,
              keyHeadDimension == 256,
              valueHeadDimension == 256,
              !hasExplicitVisionInstallSignal
        else {
            return modalities
        }
        return [.text]
    }

    var effectiveTurboQuantFamilySupport: TurboQuantFamilySupport {
        if turboQuantFamilySupport == .attentionKVFull
            || turboQuantFamilySupport == .hybridFull {
            return turboQuantFamilySupport
        }
        if turboQuantFamilySupport == .unsupportedTopology,
           effectiveTurboQuantModalities != [.text] {
            return turboQuantFamilySupport
        }
        guard effectiveTurboQuantModalities == [.text] else { return turboQuantFamilySupport }

        let modelTypes = turboQuantModelTypeHints
        let supportedHeadShape = Self.supportedTurboQuantAttentionHeadShape(
            key: keyHeadDimension,
            value: valueHeadDimension
        )
        switch cacheTopology {
        case .hybridAttentionAndNativeState:
            if modelTypes.contains(where: Self.isQwen35TurboQuantFamily)
                && keyHeadDimension == 256 && valueHeadDimension == 256
            {
                return .hybridFull
            }
            if modelTypes.contains("lfm2"), supportedHeadShape {
                return .hybridFull
            }
            return turboQuantFamilySupport
        case .standardAttention, .slidingAttention, .sharedKVAttention:
            guard supportedHeadShape else { return turboQuantFamilySupport }
            if modelTypes.contains(where: Self.isBroadTurboQuantTextFamily) {
                return .attentionKVFull
            }
            return turboQuantFamilySupport
        case .visionLanguageAttention, .unsupported:
            return turboQuantFamilySupport
        }
    }

    var isSmallTextGenerationModel: Bool {
        guard effectiveTurboQuantModalities == [.text], let resolvedParameterCount else { return false }
        return resolvedParameterCount <= 2_000_000_000
    }

    private var hasExplicitVisionInstallSignal: Bool {
        if cacheTopology == .visionLanguageAttention {
            return true
        }
        for value in [repository, displayName, modelType, textConfigModelType] {
            guard let value else { continue }
            let lowercased = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let normalized = lowercased
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: ".", with: "_")
            if lowercased.contains("vision")
                || lowercased.contains("visual")
                || lowercased.contains("image")
                || lowercased.contains("video")
                || lowercased.contains("omni")
                || lowercased.contains("multimodal")
                || lowercased.contains("vlprocessor")
                || lowercased.contains("qwen2vl")
                || lowercased.contains("qwen3vl")
            {
                return true
            }
            if normalized.contains("_vl")
                || normalized.contains("/vl")
                || normalized.hasPrefix("vl_")
                || normalized.contains("qwen2_vl")
                || normalized.contains("qwen3_vl")
                || normalized.contains("qwen3_5_vl")
            {
                return true
            }
        }
        return false
    }

    private var turboQuantModelTypeHints: Set<String> {
        var hints = Set<String>()
        for value in [modelType, textConfigModelType, repository, displayName] {
            guard let value else { continue }
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: ".", with: "_")
            guard !normalized.isEmpty else { continue }
            hints.insert(normalized)
        }
        return hints
    }

    private static func supportedTurboQuantAttentionHeadShape(key: Int?, value: Int?) -> Bool {
        guard let key, let value, key == value else { return false }
        return [64, 80, 96, 112, 128, 160, 192, 256, 512].contains(key)
    }

    private static func isQwen35TurboQuantFamily(_ value: String) -> Bool {
        value == "qwen3_5"
            || value == "qwen3_5_text"
            || value == "qwen3_5_moe"
            || value == "qwen3_5_moe_text"
            || value.contains("qwen3_5")
    }

    private static func isBroadTurboQuantTextFamily(_ value: String) -> Bool {
        value == "llama"
            || value == "mistral"
            || value == "mistral3"
            || value == "mistral4"
            || value == "ministral3"
            || value == "gemma"
            || value == "gemma2"
            || value == "gemma3"
            || value == "gemma3_text"
            || value == "gemma3n"
            || value == "gemma3n_text"
            || value == "gemma4"
            || value == "gemma4_text"
            || value == "qwen2"
            || value == "qwen3"
            || value == "qwen3_moe"
            || value == "acereason"
            || value == "phi"
            || value == "phi3"
            || value == "granite"
            || value == "exaone"
            || value == "exaone4"
            || value == "smollm3"
            || value == "glm4_moe_lite"
            || isQwen35TurboQuantFamily(value)
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

public enum RuntimePressureReason: String, Codable, Sendable, CaseIterable {
    case none
    case lowPower
    case thermalFair
    case thermalSerious
    case thermalCritical
    case lowMemory
    case thinThermal

    public var displayName: String {
        switch self {
        case .none:
            "None"
        case .lowPower:
            "Low Power Mode"
        case .thermalFair:
            "System thermal fair"
        case .thermalSerious:
            "System thermal serious"
        case .thermalCritical:
            "System thermal critical"
        case .lowMemory:
            "Low memory"
        case .thinThermal:
            "Thin-device thermal constraint"
        }
    }

    public var isThermal: Bool {
        switch self {
        case .thermalFair, .thermalSerious, .thermalCritical, .thinThermal:
            true
        case .none, .lowPower, .lowMemory:
            false
        }
    }
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
    public var runtimePressureReason: RuntimePressureReason

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
        thermalDownshiftActive: Bool = false,
        runtimePressureReason: RuntimePressureReason = .none
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
        self.runtimePressureReason = runtimePressureReason
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
        recommendedMaxModelBytes: 3_800_000_000,
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
        let thermalState = snapshot.thermalState.lowercased()
        let criticalThermal = thermalState == "critical"
        let seriousThermal = thermalState == "serious"
        let fairThermal = thermalState == "fair"
        let thinThermal = profile.performanceClass == .a19ProThin && fairThermal
        let lowMemory = (snapshot.availableMemoryBytes ?? Int64.max) < 750_000_000
        let pressureReason: RuntimePressureReason
        if criticalThermal {
            pressureReason = .thermalCritical
        } else if lowMemory {
            pressureReason = .lowMemory
        } else if seriousThermal {
            pressureReason = .thermalSerious
        } else if thinThermal {
            pressureReason = .thinThermal
        } else if fairThermal {
            pressureReason = .thermalFair
        } else if snapshot.lowPowerModeEnabled {
            pressureReason = .lowPower
        } else {
            pressureReason = .none
        }
        let downshift = criticalThermal || thinThermal

        if criticalThermal {
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
        } else if seriousThermal {
            profile.recommendedPrefillStepSize = min(profile.recommendedPrefillStepSize, 256)
            profile.recommendedEmbeddingBatchSize = min(profile.recommendedEmbeddingBatchSize, 8)
            profile.recommendedVectorScanLimit = min(profile.recommendedVectorScanLimit, 2048)
            profile.turboQuantOptimizationPolicy = .conservative
        } else if snapshot.lowPowerModeEnabled {
            profile.recommendedPrefillStepSize = min(profile.recommendedPrefillStepSize, 256)
            profile.recommendedEmbeddingBatchSize = min(profile.recommendedEmbeddingBatchSize, 4)
            profile.recommendedVectorScanLimit = min(profile.recommendedVectorScanLimit, 1024)
            profile.turboQuantOptimizationPolicy = .conservative
        } else if thinThermal {
            profile.recommendedContextTokens = min(profile.recommendedContextTokens, 16_384)
            profile.recommendedSmallModelContextTokens = min(profile.recommendedSmallModelContextTokens, 16_384)
            profile.recommendedPrefillStepSize = min(profile.recommendedPrefillStepSize, 512)
            profile.turboQuantOptimizationPolicy = .conservative
        }
        profile.thermalDownshiftActive = downshift
        profile.runtimePressureReason = pressureReason

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
        case .mSeriesTabletBalanced:
            return DeviceProfile(
                memoryTier: .balanced,
                performanceClass: .mSeriesTabletBalanced,
                recommendedMaxModelBytes: 3_500_000_000,
                recommendedContextTokens: 16_384,
                recommendedSmallModelContextTokens: 24_576,
                recommendedPrefillStepSize: 512,
                allowsVisionModels: true,
                recommendedEmbeddingBatchSize: 12,
                recommendedVectorScanLimit: 4096
            )
        case .mSeriesTabletPro:
            return DeviceProfile(
                memoryTier: .pro,
                performanceClass: .mSeriesTabletPro,
                recommendedMaxModelBytes: 5_500_000_000,
                recommendedContextTokens: 24_576,
                recommendedSmallModelContextTokens: 32_768,
                recommendedPrefillStepSize: 768,
                allowsVisionModels: true,
                recommendedEmbeddingBatchSize: 16,
                recommendedVectorScanLimit: 8192
            )
        case .mSeriesTabletMax:
            return DeviceProfile(
                memoryTier: .max,
                performanceClass: .mSeriesTabletMax,
                recommendedMaxModelBytes: 8_000_000_000,
                recommendedContextTokens: 32_768,
                recommendedSmallModelContextTokens: 65_536,
                recommendedPrefillStepSize: 1024,
                allowsVisionModels: true,
                recommendedEmbeddingBatchSize: 32,
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
            if let iPadClass = mSeriesIPadPerformanceClass(
                hardware,
                physicalMemoryBytes: snapshot.physicalMemoryBytes
            ) {
                return iPadClass
            }

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

    private static func mSeriesIPadPerformanceClass(
        _ hardware: String,
        physicalMemoryBytes: Int64
    ) -> DevicePerformanceClass? {
        guard let major = ipadIdentifierMajor(hardware), major >= 13 else { return nil }

        switch physicalMemoryBytes {
        case 14_000_000_000...:
            return .mSeriesTabletMax
        case 11_000_000_000...:
            return .mSeriesTabletPro
        case 7_000_000_000...:
            return .mSeriesTabletBalanced
        default:
            return nil
        }
    }

    private static func ipadIdentifierMajor(_ hardware: String) -> Int? {
        guard hardware.hasPrefix("iPad") else { return nil }
        let suffix = hardware.dropFirst("iPad".count)
        let major = suffix.split(separator: ",").first
        return major.flatMap { Int($0) }
    }
}

public struct LocalRuntimeSafetyAssessment: Hashable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case allowed
        case reason
        case pressureReason
        case recommendedMaxContextTokens
        case recommendedPrefillStepSize
        case constrainedModeActive
        case requiresImmediateUnload
    }

    public var allowed: Bool
    public var reason: String?
    public var pressureReason: RuntimePressureReason
    public var recommendedMaxContextTokens: Int
    public var recommendedPrefillStepSize: Int
    public var constrainedModeActive: Bool
    public var requiresImmediateUnload: Bool

    public init(
        allowed: Bool,
        reason: String? = nil,
        pressureReason: RuntimePressureReason = .none,
        recommendedMaxContextTokens: Int,
        recommendedPrefillStepSize: Int,
        requiresImmediateUnload: Bool = false,
        constrainedModeActive: Bool = false
    ) {
        self.allowed = allowed
        self.reason = reason
        self.pressureReason = pressureReason
        self.recommendedMaxContextTokens = max(1_024, recommendedMaxContextTokens)
        self.recommendedPrefillStepSize = max(64, recommendedPrefillStepSize)
        self.constrainedModeActive = constrainedModeActive || requiresImmediateUnload
        self.requiresImmediateUnload = requiresImmediateUnload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let requiresImmediateUnload = try container.decodeIfPresent(Bool.self, forKey: .requiresImmediateUnload) ?? false
        self.init(
            allowed: try container.decode(Bool.self, forKey: .allowed),
            reason: try container.decodeIfPresent(String.self, forKey: .reason),
            pressureReason: try container.decodeIfPresent(RuntimePressureReason.self, forKey: .pressureReason) ?? .none,
            recommendedMaxContextTokens: try container.decode(Int.self, forKey: .recommendedMaxContextTokens),
            recommendedPrefillStepSize: try container.decode(Int.self, forKey: .recommendedPrefillStepSize),
            requiresImmediateUnload: requiresImmediateUnload,
            constrainedModeActive: try container.decodeIfPresent(Bool.self, forKey: .constrainedModeActive)
                ?? requiresImmediateUnload
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allowed, forKey: .allowed)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(pressureReason, forKey: .pressureReason)
        try container.encode(recommendedMaxContextTokens, forKey: .recommendedMaxContextTokens)
        try container.encode(recommendedPrefillStepSize, forKey: .recommendedPrefillStepSize)
        try container.encode(constrainedModeActive, forKey: .constrainedModeActive)
        try container.encode(requiresImmediateUnload, forKey: .requiresImmediateUnload)
    }

    public func constrainedRuntimeProfile(_ profile: RuntimeProfile) -> RuntimeProfile {
        var constrained = profile
        if let maxKVSize = constrained.quantization.maxKVSize {
            constrained.quantization.maxKVSize = min(maxKVSize, recommendedMaxContextTokens)
        } else {
            constrained.quantization.maxKVSize = recommendedMaxContextTokens
        }
        constrained.prefillStepSize = min(constrained.prefillStepSize, recommendedPrefillStepSize)
        constrained.quantization.runtimePressureReason = pressureReason
        if constrainedModeActive {
            constrained.unloadOnMemoryPressure = true
            constrained.streamExperts = false
            constrained.expertStreamingMode = .disabled
            constrained.speculativeDecodingEnabled = false
            constrained.mtpEnabled = false
        }
        return constrained
    }
}

public struct LocalGenerationPipelinePlan: Hashable, Codable, Sendable {
    public static let defaultKVCacheSizeFloorTokens = 1_024
    public static let defaultKVCacheSizeAlignmentTokens = 256

    public var requestedCompletionTokens: Int?
    public var reservedCompletionTokens: Int
    public var effectiveMaxTokens: Int?
    public var maxTokensClamped: Bool
    public var pressureCompletionTokenLimit: Int?
    public var effectiveMaxKVSize: Int?
    public var maxKVSizeClamped: Bool
    public var initialAvailableMemoryBytes: Int64?
    public var pressureReason: RuntimePressureReason
    public var constrainedModeActive: Bool

    public init(
        requestedCompletionTokens: Int?,
        reservedCompletionTokens: Int,
        effectiveMaxTokens: Int?,
        maxTokensClamped: Bool,
        pressureCompletionTokenLimit: Int?,
        effectiveMaxKVSize: Int? = nil,
        maxKVSizeClamped: Bool = false,
        initialAvailableMemoryBytes: Int64?,
        pressureReason: RuntimePressureReason,
        constrainedModeActive: Bool
    ) {
        self.requestedCompletionTokens = requestedCompletionTokens
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
        self.effectiveMaxTokens = effectiveMaxTokens.map { max(1, $0) }
        self.maxTokensClamped = maxTokensClamped
        self.pressureCompletionTokenLimit = pressureCompletionTokenLimit.map { max(1, $0) }
        self.effectiveMaxKVSize = effectiveMaxKVSize.map { max(1, $0) }
        self.maxKVSizeClamped = maxKVSizeClamped
        self.initialAvailableMemoryBytes = initialAvailableMemoryBytes
        self.pressureReason = pressureReason
        self.constrainedModeActive = constrainedModeActive
    }

    public init(
        requestedCompletionTokens: Int?,
        profile: RuntimeProfile,
        safety: LocalRuntimeSafetyAssessment,
        initialAvailableMemoryBytes: Int64?
    ) {
        let pressureLimit = Self.pressureCompletionTokenLimit(
            profile: profile,
            safety: safety,
            availableMemoryBytes: initialAvailableMemoryBytes
        )
        let requested = requestedCompletionTokens.map { max(1, $0) }
        let reserved: Int
        let effective: Int?
        let clamped: Bool
        if let pressureLimit {
            if let requested {
                let capped = min(requested, pressureLimit)
                reserved = capped
                effective = capped
                clamped = capped != requested
            } else {
                reserved = pressureLimit
                effective = pressureLimit
                clamped = true
            }
        } else {
            reserved = requested ?? 0
            effective = requested
            clamped = false
        }

        self.init(
            requestedCompletionTokens: requested,
            reservedCompletionTokens: reserved,
            effectiveMaxTokens: effective,
            maxTokensClamped: clamped,
            pressureCompletionTokenLimit: pressureLimit,
            effectiveMaxKVSize: profile.quantization.maxKVSize,
            maxKVSizeClamped: false,
            initialAvailableMemoryBytes: initialAvailableMemoryBytes,
            pressureReason: safety.pressureReason,
            constrainedModeActive: safety.constrainedModeActive
        )
    }

    public mutating func constrainToContext(
        promptTokenCount: Int,
        maxContextTokens: Int
    ) -> Bool {
        fitPreparedPrompt(
            promptTokenCount: promptTokenCount,
            maxContextTokens: maxContextTokens
        )
    }

    public mutating func fitPreparedPrompt(
        promptTokenCount: Int,
        maxContextTokens: Int,
        minKVCacheSizeTokens: Int = Self.defaultKVCacheSizeFloorTokens,
        kvCacheSizeAlignmentTokens: Int = Self.defaultKVCacheSizeAlignmentTokens
    ) -> Bool {
        let promptTokenCount = max(0, promptTokenCount)
        guard promptTokenCount + reservedCompletionTokens > maxContextTokens else {
            fitKVCacheToPreparedPrompt(
                promptTokenCount: promptTokenCount,
                maxContextTokens: maxContextTokens,
                minKVCacheSizeTokens: minKVCacheSizeTokens,
                kvCacheSizeAlignmentTokens: kvCacheSizeAlignmentTokens
            )
            return true
        }
        let availableCompletionTokens = maxContextTokens - promptTokenCount
        guard availableCompletionTokens > 0 else {
            return false
        }

        reservedCompletionTokens = min(reservedCompletionTokens, availableCompletionTokens)
        effectiveMaxTokens = reservedCompletionTokens
        maxTokensClamped = true
        fitKVCacheToPreparedPrompt(
            promptTokenCount: promptTokenCount,
            maxContextTokens: maxContextTokens,
            minKVCacheSizeTokens: minKVCacheSizeTokens,
            kvCacheSizeAlignmentTokens: kvCacheSizeAlignmentTokens
        )
        return true
    }

    public func providerMetadata() -> [String: String] {
        [
            LocalProviderMetadataKeys.generationRequestedMaxTokens: requestedCompletionTokens
                .map(String.init) ?? "none",
            LocalProviderMetadataKeys.generationEffectiveMaxTokens: effectiveMaxTokens
                .map(String.init) ?? "none",
            LocalProviderMetadataKeys.generationMaxTokensClamped: String(maxTokensClamped),
            LocalProviderMetadataKeys.generationPressureCompletionLimit: pressureCompletionTokenLimit
                .map(String.init) ?? "none",
            LocalProviderMetadataKeys.generationEffectiveMaxKVSize: effectiveMaxKVSize
                .map(String.init) ?? "none",
            LocalProviderMetadataKeys.generationMaxKVSizeClamped: String(maxKVSizeClamped),
            LocalProviderMetadataKeys.generationInitialAvailableMemoryBytes: initialAvailableMemoryBytes
                .map(String.init) ?? "unknown",
        ]
    }

    public static func pressureCompletionTokenLimit(
        profile: RuntimeProfile,
        safety: LocalRuntimeSafetyAssessment,
        availableMemoryBytes: Int64?
    ) -> Int? {
        let pressureLimit: Int?
        switch safety.pressureReason {
        case .lowMemory:
            if let availableMemoryBytes {
                if availableMemoryBytes < 1_000_000_000 {
                    pressureLimit = 128
                } else if availableMemoryBytes < 1_200_000_000 {
                    pressureLimit = 256
                } else if availableMemoryBytes < LocalRuntimeSafetyPolicy.constrainedAvailableMemoryBytes {
                    pressureLimit = 512
                } else {
                    pressureLimit = 1_024
                }
            } else {
                pressureLimit = 512
            }
        case .thermalFair, .thermalSerious, .thinThermal:
            pressureLimit = 768
        case .lowPower:
            pressureLimit = 1_024
        case .none, .thermalCritical:
            pressureLimit = nil
        }

        let loadedTurboQuantHeadroomLimit = Self.loadedTurboQuantHeadroomCompletionLimit(
            profile: profile,
            availableMemoryBytes: availableMemoryBytes
        )
        let policyLimit: Int?
        if safety.constrainedModeActive {
            policyLimit = [pressureLimit, loadedTurboQuantHeadroomLimit]
                .compactMap { $0 }
                .min()
        } else {
            policyLimit = loadedTurboQuantHeadroomLimit
        }
        guard let policyLimit else { return nil }
        return min(profile.quantization.maxKVSize ?? policyLimit, policyLimit)
    }

    private static func loadedTurboQuantHeadroomCompletionLimit(
        profile: RuntimeProfile,
        availableMemoryBytes: Int64?
    ) -> Int? {
        guard profile.quantization.kvCacheStrategy == .turboQuant,
              let availableMemoryBytes else {
            return nil
        }
        let headroomLimit: Int?
        if availableMemoryBytes < 1_000_000_000 {
            headroomLimit = 128
        } else if availableMemoryBytes < 1_200_000_000 {
            headroomLimit = 256
        } else if availableMemoryBytes < 1_800_000_000 {
            headroomLimit = 384
        } else if availableMemoryBytes < 2_600_000_000 {
            headroomLimit = 512
        } else if availableMemoryBytes < 3_000_000_000 {
            headroomLimit = 768
        } else {
            headroomLimit = nil
        }
        return [
            headroomLimit,
            hybridTurboQuantCompletionLimit(profile: profile, availableMemoryBytes: availableMemoryBytes),
            qualityGuardedTurboQuantCompletionLimit(profile: profile, availableMemoryBytes: availableMemoryBytes),
        ]
            .compactMap { $0 }
            .min()
    }

    private static func qualityGuardedTurboQuantCompletionLimit(
        profile: RuntimeProfile,
        availableMemoryBytes: Int64
    ) -> Int? {
        guard profile.quantization.kvCacheStrategy == .turboQuant else { return nil }
        let profileID = profile.quantization.turboQuantProfileID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let profileID, !profileID.isEmpty else { return nil }

        if profileID == "gemma-3-1b" {
            return availableMemoryBytes < 3_000_000_000 ? 256 : 384
        }
        if profileID == "llama-3.2-3b" {
            return availableMemoryBytes < 2_000_000_000 ? 128 : 192
        }
        if (profileID.hasPrefix("qwen3.5-") || profileID.hasPrefix("qwen3.6-")),
           profileID != "qwen3.5-0.8b" {
            return availableMemoryBytes < 3_200_000_000 ? 192 : 256
        }
        return nil
    }

    private static func hybridTurboQuantCompletionLimit(
        profile: RuntimeProfile,
        availableMemoryBytes: Int64
    ) -> Int? {
        guard isHybridTurboQuantRuntimeProfile(profile) else { return nil }
        if availableMemoryBytes < 3_200_000_000 {
            return 256
        }
        if availableMemoryBytes < 4_000_000_000 {
            return 384
        }
        if availableMemoryBytes < 5_000_000_000 {
            return 512
        }
        return nil
    }

    private static func isHybridTurboQuantRuntimeProfile(_ profile: RuntimeProfile) -> Bool {
        guard profile.quantization.kvCacheStrategy == .turboQuant else { return false }
        let profileID = profile.quantization.turboQuantProfileID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let profileID, !profileID.isEmpty else { return false }
        return profileID.contains("qwen3.5")
            || profileID.contains("qwen3.6")
            || profileID.contains("lfm2")
    }

    private mutating func fitKVCacheToPreparedPrompt(
        promptTokenCount: Int,
        maxContextTokens: Int,
        minKVCacheSizeTokens: Int,
        kvCacheSizeAlignmentTokens: Int
    ) {
        guard effectiveMaxTokens != nil else {
            effectiveMaxKVSize = maxContextTokens
            maxKVSizeClamped = false
            return
        }

        let requiredTokens = max(1, promptTokenCount + reservedCompletionTokens)
        let floorTokens = min(max(1, minKVCacheSizeTokens), maxContextTokens)
        let alignmentTokens = max(1, kvCacheSizeAlignmentTokens)
        let flooredTokens = max(requiredTokens, floorTokens)
        let alignedTokens = ((flooredTokens + alignmentTokens - 1) / alignmentTokens)
            * alignmentTokens
        let fittedTokens = min(maxContextTokens, max(requiredTokens, alignedTokens))
        effectiveMaxKVSize = fittedTokens
        maxKVSizeClamped = fittedTokens < maxContextTokens
    }
}

public enum LocalRuntimeSafetyPolicy {
    public static let minimumAvailableMemoryBytes: Int64 = 900_000_000
    public static let constrainedAvailableMemoryBytes: Int64 = 1_500_000_000

    public static func assess(snapshot: RuntimeMemorySnapshot) -> LocalRuntimeSafetyAssessment {
        let profile = DeviceProfile.recommended(for: snapshot)
        return assess(snapshot: snapshot, profile: profile)
    }

    public static func assess(
        snapshot: RuntimeMemorySnapshot,
        profile: DeviceProfile
    ) -> LocalRuntimeSafetyAssessment {
        let thermal = snapshot.thermalState.lowercased()
        let available = snapshot.availableMemoryBytes
        let criticallyThermal = thermal == "critical"
        let memoryExhausted = available.map { $0 < minimumAvailableMemoryBytes } ?? false

        if criticallyThermal {
            return LocalRuntimeSafetyAssessment(
                allowed: false,
                reason: "Local MLX generation is paused because iOS reported critical thermal pressure. Let the device recover or use a cloud model.",
                pressureReason: .thermalCritical,
                recommendedMaxContextTokens: min(profile.recommendedContextTokens, 2_048),
                recommendedPrefillStepSize: min(profile.recommendedPrefillStepSize, 128),
                requiresImmediateUnload: true,
                constrainedModeActive: true
            )
        }

        if memoryExhausted {
            return LocalRuntimeSafetyAssessment(
                allowed: false,
                reason: "Local MLX generation is paused because available memory is critically low. Close other apps, wait a moment, or use a smaller/cloud model.",
                pressureReason: .lowMemory,
                recommendedMaxContextTokens: min(profile.recommendedContextTokens, 2_048),
                recommendedPrefillStepSize: min(profile.recommendedPrefillStepSize, 128),
                requiresImmediateUnload: true,
                constrainedModeActive: true
            )
        }

        let constrainedByMemory = available.map { $0 < constrainedAvailableMemoryBytes } ?? false
        let pressureReason: RuntimePressureReason
        if constrainedByMemory {
            pressureReason = .lowMemory
        } else if profile.runtimePressureReason != .none {
            pressureReason = profile.runtimePressureReason
        } else if thermal == "fair" {
            pressureReason = .thermalFair
        } else if snapshot.lowPowerModeEnabled {
            pressureReason = .lowPower
        } else {
            pressureReason = .none
        }
        let constrained = pressureReason != .none
        let maxContext: Int
        switch pressureReason {
        case .lowMemory:
            let lowMemoryCap: Int
            if let available {
                if available < 1_000_000_000 {
                    lowMemoryCap = 1_024
                } else if available < 1_600_000_000 {
                    lowMemoryCap = 2_048
                } else {
                    lowMemoryCap = 4_096
                }
            } else {
                lowMemoryCap = 2_048
            }
            maxContext = min(profile.recommendedContextTokens, lowMemoryCap)
        case .thinThermal:
            maxContext = min(profile.recommendedContextTokens, 16_384)
        case .none, .lowPower, .thermalFair, .thermalSerious, .thermalCritical:
            maxContext = profile.recommendedContextTokens
        }
        let prefill = constrained
            ? min(profile.recommendedPrefillStepSize, 256)
            : profile.recommendedPrefillStepSize

        return LocalRuntimeSafetyAssessment(
            allowed: true,
            reason: constrained ? "Local runtime using pressure-aware settings for \(pressureReason.rawValue)." : nil,
            pressureReason: pressureReason,
            recommendedMaxContextTokens: maxContext,
            recommendedPrefillStepSize: prefill,
            requiresImmediateUnload: false,
            constrainedModeActive: constrained
        )
    }
}
