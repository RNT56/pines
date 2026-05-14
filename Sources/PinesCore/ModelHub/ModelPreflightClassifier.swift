import Foundation

public struct ModelPreflightClassifier: Sendable {
    public var supportedLLMTypes: Set<String>
    public var supportedVLMTypes: Set<String>
    public var supportedEmbedderTypes: Set<String>

    public init(
        supportedLLMTypes: Set<String> = Self.defaultSupportedLLMTypes,
        supportedVLMTypes: Set<String> = Self.defaultSupportedVLMTypes,
        supportedEmbedderTypes: Set<String> = Self.defaultSupportedEmbedderTypes
    ) {
        self.supportedLLMTypes = supportedLLMTypes
        self.supportedVLMTypes = supportedVLMTypes
        self.supportedEmbedderTypes = supportedEmbedderTypes
    }

    public func classify(_ input: ModelPreflightInput) -> ModelPreflightResult {
        let config = input.configJSON.flatMap(Self.decodeJSONObject)
        let processor = input.processorConfigJSON.flatMap(Self.decodeJSONObject)
        let modelType = config?["model_type"] as? String
        let processorClass = processor?["processor_class"] as? String
        let size = input.files.compactMap(\.size).reduce(Int64(0), +)
        let hasSafetensors = input.files.contains { $0.path.hasSuffix(".safetensors") }
        let hasTokenizer = input.files.contains { file in
            file.path == "tokenizer.json" || file.path == "tokenizer.model" || file.path == "tokenizer_config.json"
        }

        var modalities = Set<ModelModality>()
        var reasons = [String]()

        if let modelType, supportedLLMTypes.contains(modelType) {
            modalities.insert(.text)
        }
        if let modelType, supportedVLMTypes.contains(modelType) || processorClass?.localizedCaseInsensitiveContains("processor") == true {
            modalities.insert(.vision)
        }
        if let modelType, supportedEmbedderTypes.contains(modelType) {
            modalities.insert(.embeddings)
        }

        if !hasSafetensors {
            reasons.append("No safetensors weights were found.")
        }
        if !hasTokenizer && modalities.contains(.text) {
            reasons.append("Tokenizer files were not found.")
        }
        if modelType == nil {
            reasons.append("config.json does not expose model_type.")
        }

        let lowerRepository = input.repository.lowercased()
        let hasExperimentalOneBitSignal = lowerRepository.contains("1bit")
            || lowerRepository.contains("1-bit")
            || lowerRepository.contains("bitnet")
            || input.tags.contains { $0.localizedCaseInsensitiveContains("bitnet") }

        let verification: ModelVerificationState
        if modalities.isEmpty || !hasSafetensors {
            verification = .unsupported
        } else if hasExperimentalOneBitSignal || modelType == "bitnet" {
            verification = .experimental
            reasons.append("1-bit/BitNet models require exact-device verification before being marked verified.")
        } else if CuratedModelManifest.default.contains(repository: input.repository) {
            verification = .verified
        } else {
            verification = .installable
        }

        return ModelPreflightResult(
            repository: input.repository,
            verification: verification,
            modalities: modalities,
            modelType: modelType,
            processorClass: processorClass,
            estimatedBytes: size,
            reasons: reasons,
            license: input.license
        )
    }

    private static func decodeJSONObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static let defaultSupportedLLMTypes: Set<String> = [
        "llama", "mistral", "qwen2", "qwen3", "qwen3_moe", "gemma", "gemma2",
        "gemma3", "gemma3_text", "gemma3n", "phi", "phi3", "phimoe", "deepseek_v3",
        "glm4", "glm4_moe", "glm4_moe_lite", "starcoder2", "cohere", "openelm",
        "internlm2", "granite", "granitemoehybrid", "mimo", "mimo_v2_flash",
        "minimax", "bitnet", "smollm3", "ernie4_5", "lfm2", "lfm2_moe",
        "exaone4", "olmo2", "olmo3", "olmoe", "falcon_h1", "jamba", "gpt_oss",
        "nanochat", "nemotron_h", "apertus",
    ]

    public static let defaultSupportedVLMTypes: Set<String> = [
        "qwen2_vl", "qwen2_5_vl", "qwen3_vl", "gemma3", "paligemma",
        "idefics3", "smolvlm", "fastvlm", "llava_qwen2", "pixtral", "mistral3",
        "lfm2_vl", "lfm2-vl",
    ]

    public static let defaultSupportedEmbedderTypes: Set<String> = [
        "bert", "roberta", "xlm-roberta", "distilbert", "nomic_bert", "qwen3",
        "gemma3", "gemma3_text", "gemma3n",
    ]
}
