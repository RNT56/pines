import Foundation

public struct VerifiedModelFamilyManifest: Sendable {
    public static let `default` = VerifiedModelFamilyManifest()

    public init() {}

    public func contains(
        repository: String,
        modelType: String?,
        textConfigModelType: String?,
        modalities: Set<ModelModality>,
        cacheTopology: ModelCacheTopology,
        turboQuantFamilySupport: TurboQuantFamilySupport,
        keyHeadDimension: Int?,
        valueHeadDimension: Int?,
        routedExperts: Int?,
        expertsPerToken: Int?,
        runtimeCapabilities: PinesTurboQuantRuntimeCapabilityRegistry = .bundledFallback
    ) -> Bool {
        guard modalities == [.text] else { return false }
        guard turboQuantFamilySupport == .attentionKVFull || turboQuantFamilySupport == .hybridFull else {
            return false
        }

        let lowerRepository = repository.lowercased()
        guard !Self.isExplicitlyExcludedRepository(lowerRepository) else { return false }
        guard TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
            repository: repository,
            modelType: modelType,
            textConfigModelType: textConfigModelType,
            modalities: modalities,
            familySupport: turboQuantFamilySupport,
            runtimeCapabilities: runtimeCapabilities
        ) else {
            return false
        }

        let modelTypes = [
            modelType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            textConfigModelType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ].compactMap { $0 }

        if modelTypes.contains(where: Self.isQwen35Family) {
            return cacheTopology == .hybridAttentionAndNativeState
                && turboQuantFamilySupport == .hybridFull
                && keyHeadDimension == 256
                && valueHeadDimension == 256
        }

        if modelTypes.contains(where: Self.isQwen2Or3Family) {
            return cacheTopology == .standardAttention
                && turboQuantFamilySupport == .attentionKVFull
                && Self.supportedStandardHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
        }

        if modelTypes.contains(where: Self.isGemmaFamily) {
            return turboQuantFamilySupport == .attentionKVFull
                && Self.supportedGemmaHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
        }

        if modelTypes.contains(where: Self.isMistralFamily) {
            if modelTypes.contains("mistral4") {
                return cacheTopology == .standardAttention
                    && turboQuantFamilySupport == .attentionKVFull
                    && keyHeadDimension == 128
                    && valueHeadDimension == 128
                    && routedExperts == 128
                    && expertsPerToken == 4
            }
            return (cacheTopology == .standardAttention || cacheTopology == .slidingAttention)
                && turboQuantFamilySupport == .attentionKVFull
                && Self.supportedStandardHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
        }

        if modelTypes.contains("llama")
            || modelTypes.contains(where: Self.isSmallDenseFamily) {
            return !modalities.contains(.vision)
                && cacheTopology == .standardAttention
                && turboQuantFamilySupport == .attentionKVFull
                && Self.supportedStandardHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
        }

        if modelTypes.contains("exaone4") || modelTypes.contains("exaone") {
            return !modalities.contains(.vision)
                && (cacheTopology == .standardAttention || cacheTopology == .slidingAttention)
                && turboQuantFamilySupport == .attentionKVFull
                && Self.supportedStandardHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
        }

        if modelTypes.contains("lfm2") {
            return !modalities.contains(.vision)
                && (cacheTopology == .standardAttention || cacheTopology == .hybridAttentionAndNativeState)
                && (turboQuantFamilySupport == .attentionKVFull || turboQuantFamilySupport == .hybridFull)
                && Self.supportedStandardHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
        }

        if modelTypes.contains("glm4_moe_lite") {
            return !modalities.contains(.vision)
                && cacheTopology == .standardAttention
                && turboQuantFamilySupport == .attentionKVFull
                && Self.supportedSplitHeadDimension(keyHeadDimension)
                && Self.supportedSplitHeadDimension(valueHeadDimension)
        }

        return false
    }

    private static func isExplicitlyExcludedRepository(_ repository: String) -> Bool {
        repository.contains("llama-4")
            || repository.contains("llama4")
            || repository.contains("mllama")
            || repository.contains("llava")
            || repository.contains("deepseek-v2")
            || repository.contains("deepseek-v3")
            || repository.contains("pixtral")
            || repository.contains("jamba")
            || repository.contains("gpt-oss")
            || repository.contains("rwkv")
    }

    private static func isQwen35Family(_ modelType: String) -> Bool {
        modelType == "qwen3_5"
            || modelType == "qwen3_5_text"
            || modelType == "qwen3_5_moe"
            || modelType == "qwen3_5_moe_text"
    }

    private static func isGemmaFamily(_ modelType: String) -> Bool {
        modelType == "gemma3"
            || modelType == "gemma3_text"
            || modelType == "gemma3n"
            || modelType == "gemma3n_text"
            || modelType == "gemma4"
            || modelType == "gemma4_text"
            || modelType == "gemma4_assistant"
    }

    private static func isQwen2Or3Family(_ modelType: String) -> Bool {
        modelType == "qwen2"
            || modelType == "qwen3"
            || modelType == "qwen3_moe"
            || modelType == "acereason"
    }

    private static func isMistralFamily(_ modelType: String) -> Bool {
        modelType == "mistral"
            || modelType == "mistral3"
            || modelType == "mistral4"
            || modelType == "ministral3"
    }

    private static func isSmallDenseFamily(_ modelType: String) -> Bool {
        modelType == "phi"
            || modelType == "phi3"
            || modelType == "granite"
            || modelType == "smollm3"
    }

    private static func supportedGemmaHeadDimension(_ value: Int?) -> Bool {
        value == 128 || value == 256 || value == 512
    }

    private static func supportedStandardHeadDimension(_ value: Int?) -> Bool {
        value == 64 || value == 80 || value == 96 || value == 112 || value == 128 || value == 160 || value == 192 || value == 256
    }

    private static func supportedSplitHeadDimension(_ value: Int?) -> Bool {
        value == 64 || value == 80 || value == 96 || value == 112 || value == 128 || value == 160 || value == 192 || value == 256 || value == 512
    }
}
