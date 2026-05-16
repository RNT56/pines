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
        let hasTokenizerJSON = input.files.contains { Self.filename($0.path) == "tokenizer.json" }
        let hasProcessorConfig = input.processorConfigJSON != nil || input.files.contains { file in
            let filename = Self.filename(file.path)
            return filename == "processor_config.json" || filename == "preprocessor_config.json"
        }
        let lowerRepository = input.repository.lowercased()
        let hasEmbeddingSignal = lowerRepository.contains("embedding")
            || input.tags.contains { tag in
                let lowerTag = tag.lowercased()
                return lowerTag == "feature-extraction"
                    || lowerTag == "sentence-similarity"
                    || lowerTag == "sentence-transformers"
                    || lowerTag == "embeddings"
            }
        let hasVisionSignal = hasProcessorConfig
            || processorClass?.localizedCaseInsensitiveContains("processor") == true
            || input.tags.contains { tag in
                let lowerTag = tag.lowercased()
                return lowerTag == "image-text-to-text" || lowerTag == "any-to-any"
            }

        var modalities = Set<ModelModality>()
        var reasons = [String]()

        if let modelType, supportedLLMTypes.contains(modelType), !hasEmbeddingSignal {
            modalities.insert(.text)
        }
        if let modelType,
           supportedVLMTypes.contains(modelType) && (!supportedLLMTypes.contains(modelType) || hasVisionSignal) {
            modalities.insert(.text)
            modalities.insert(.vision)
        }
        if let modelType, supportedEmbedderTypes.contains(modelType), hasEmbeddingSignal || !supportedLLMTypes.contains(modelType) {
            modalities.insert(.embeddings)
        }

        if !hasSafetensors {
            reasons.append("No safetensors weights were found.")
        }
        if !hasTokenizerJSON && !modalities.isEmpty {
            reasons.append("tokenizer.json was not found.")
        }
        if modalities.contains(.vision) && !hasProcessorConfig {
            reasons.append("Vision processor configuration was not found.")
        }
        if modelType == nil {
            reasons.append("config.json does not expose model_type.")
        } else if let modelType,
                  !supportedLLMTypes.contains(modelType),
                  !supportedVLMTypes.contains(modelType),
                  !supportedEmbedderTypes.contains(modelType) {
            reasons.append("model_type \(modelType) is not registered in the linked MLX runtime.")
        }

        let hasExperimentalOneBitSignal = lowerRepository.contains("1bit")
            || lowerRepository.contains("1-bit")
            || lowerRepository.contains("bitnet")
            || input.tags.contains { $0.localizedCaseInsensitiveContains("bitnet") }

        let verification: ModelVerificationState
        if modalities.isEmpty
            || !hasSafetensors
            || (!hasTokenizerJSON && !modalities.isEmpty)
            || (modalities.contains(.vision) && !hasProcessorConfig) {
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

    private static func filename(_ path: String) -> String {
        path.split(separator: "/").last.map { String($0).lowercased() } ?? path.lowercased()
    }

    public static let defaultSupportedLLMTypes: Set<String> = [
        "llama", "llama4", "llama4_text", "mistral", "qwen2", "qwen3", "qwen3_moe", "gemma", "gemma2",
        "gemma3", "gemma3_text", "gemma3n", "gemma4", "gemma4_text", "gemma4_assistant",
        "qwen3_next", "qwen3_5", "qwen3_5_moe", "qwen3_5_text",
        "phi", "phi3", "phimoe", "deepseek_v3", "deepseek_v32", "deepseek_v4", "glm4", "glm4_moe",
        "glm4_moe_lite", "starcoder2", "cohere", "openelm", "internlm2",
        "granite", "granitemoehybrid", "mimo", "mimo_v2_flash", "minimax",
        "minimax_m2", "mistral3", "bitnet", "smollm3", "ernie4_5", "lfm2", "lfm2_moe",
        "baichuan_m1", "exaone4", "olmo2", "olmo3", "olmoe", "falcon_h1",
        "jamba", "gpt_oss", "nanochat", "nemotron_h", "apertus", "afmoe",
        "bailing_moe", "minicpm", "lille-130m", "acereason",
    ]

    public static let defaultSupportedVLMTypes: Set<String> = [
        "qwen2_vl", "qwen2_5_vl", "qwen3_vl", "qwen3_5", "qwen3_5_moe",
        "gemma3", "gemma4", "paligemma", "idefics3", "smolvlm", "fastvlm",
        "llava_qwen2", "pixtral", "mistral3", "lfm2_vl", "lfm2-vl", "glm_ocr",
    ]

    public static let defaultSupportedEmbedderTypes: Set<String> = [
        "bert", "roberta", "xlm-roberta", "distilbert", "nomic_bert", "qwen3",
        "gemma3", "gemma3_text", "gemma3n",
    ]
}
