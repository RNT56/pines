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
        expertsPerToken: Int?
    ) -> Bool {
        guard modalities.contains(.text) else { return false }
        guard turboQuantFamilySupport == .attentionKVFull || turboQuantFamilySupport == .hybridFull else {
            return false
        }

        let lowerRepository = repository.lowercased()
        guard !Self.isExplicitlyExcludedRepository(lowerRepository) else { return false }

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

        if modelTypes.contains(where: Self.isGemmaFamily) {
            return turboQuantFamilySupport == .attentionKVFull
                && Self.supportedGemmaHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
        }

        if modelTypes.contains("llama") {
            return !modalities.contains(.vision)
                && cacheTopology == .standardAttention
                && turboQuantFamilySupport == .attentionKVFull
                && Self.supportedLlamaHeadDimension(keyHeadDimension)
                && keyHeadDimension == valueHeadDimension
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
            || repository.contains("glm")
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

    private static func supportedGemmaHeadDimension(_ value: Int?) -> Bool {
        value == 128 || value == 256 || value == 512
    }

    private static func supportedLlamaHeadDimension(_ value: Int?) -> Bool {
        value == 64 || value == 80 || value == 96 || value == 112 || value == 128 || value == 160 || value == 192 || value == 256
    }
}
