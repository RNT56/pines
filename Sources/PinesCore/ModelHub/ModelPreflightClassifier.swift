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
        let modelType = config?["model_type"] as? String ?? inferredModelType(from: input.tags)
        let textConfig = config?["text_config"] as? [String: Any]
        let textConfigModelType = textConfig?["model_type"] as? String
        let processorClass = processor?["processor_class"] as? String
        let headDimensions = Self.headDimensions(from: config, modelType: modelType)
        let routedExperts = Self.routedExperts(from: config)
        let expertsPerToken = Self.expertsPerToken(from: config)
        let parameterCount = ModelDiscoveryResourcePolicy.inferredParameterCount(
            repository: input.repository,
            tags: input.tags
        )
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
        let hasAudioSignal = config?["audio_config"] != nil
            || config?["audio_tower"] != nil
            || lowerRepository.contains("audio")
            || input.tags.contains { tag in
                let lowerTag = tag.lowercased()
                return lowerTag == "audio-text-to-text"
                    || lowerTag == "automatic-speech-recognition"
                    || lowerTag == "audio"
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
            if hasAudioSignal {
                modalities.insert(.audio)
            }
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
        let requiresRuntimeCompatibilityGate = Self.requiresRuntimeCompatibilityGate(
            repository: lowerRepository,
            modelType: modelType
        )

        let verification: ModelVerificationState
        if modalities.isEmpty
            || !hasSafetensors
            || (!hasTokenizerJSON && !modalities.isEmpty)
            || (modalities.contains(.vision) && !hasProcessorConfig) {
            verification = .unsupported
        } else if hasExperimentalOneBitSignal || modelType == "bitnet" {
            verification = .experimental
            reasons.append("1-bit/BitNet models require exact-device verification before being marked verified.")
        } else if requiresRuntimeCompatibilityGate {
            verification = .experimental
            reasons.append(Self.runtimeCompatibilityGateReason)
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
            textConfigModelType: textConfigModelType,
            processorClass: processorClass,
            parameterCount: parameterCount,
            keyHeadDimension: headDimensions.key,
            valueHeadDimension: headDimensions.value,
            routedExperts: routedExperts,
            expertsPerToken: expertsPerToken,
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

    private struct HeadDimensions {
        var key: Int?
        var value: Int?
    }

    private static func headDimensions(from config: [String: Any]?, modelType: String?) -> HeadDimensions {
        guard let config else { return HeadDimensions(key: nil, value: nil) }
        if let explicit = positiveInt(config["head_dim"]) {
            return HeadDimensions(key: explicit, value: explicit)
        }
        if let textConfig = config["text_config"] as? [String: Any],
           let explicit = positiveInt(textConfig["head_dim"]) {
            return HeadDimensions(key: explicit, value: explicit)
        }
        if let mistral4 = mistral4HeadDimensions(from: config) {
            return mistral4
        }
        if let runtimeDefault = runtimeDefaultHeadDimension(from: config, modelType: modelType) {
            return HeadDimensions(key: runtimeDefault, value: runtimeDefault)
        }
        if let modelType, modelTypesWithNonInferredHeadDimension.contains(modelType) {
            return HeadDimensions(key: nil, value: nil)
        }
        if let inferred = inferredHeadDimension(from: config)
            ?? (config["text_config"] as? [String: Any]).flatMap(inferredHeadDimension(from:)) {
            return HeadDimensions(key: inferred, value: inferred)
        }
        return HeadDimensions(key: nil, value: nil)
    }

    private static let modelTypesWithNonInferredHeadDimension: Set<String> = [
        "gemma3", "gemma3_text", "gemma3n", "gemma3n_text",
        "gemma4", "gemma4_text", "gemma4_assistant",
    ]

    private static func runtimeDefaultHeadDimension(from config: [String: Any], modelType: String?) -> Int? {
        let textConfig = config["text_config"] as? [String: Any]
        let modelTypes = [
            modelType,
            config["model_type"] as? String,
            textConfig?["model_type"] as? String,
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        if modelTypes.contains(where: { $0 == "gemma3" || $0 == "gemma3_text" }) {
            return 256
        }
        if modelTypes.contains(where: { $0 == "gemma4" || $0 == "gemma4_text" || $0 == "gemma4_assistant" }) {
            return 256
        }
        return nil
    }

    private static func inferredHeadDimension(from config: [String: Any]) -> Int? {
        guard let hiddenSize = positiveInt(config["hidden_size"]),
              let attentionHeads = positiveInt(config["num_attention_heads"]),
              hiddenSize.isMultiple(of: attentionHeads)
        else {
            return nil
        }
        return hiddenSize / attentionHeads
    }

    private static func mistral4HeadDimensions(from config: [String: Any]) -> HeadDimensions? {
        let candidates = [
            config,
            config["text_config"] as? [String: Any],
        ].compactMap { $0 }

        for candidate in candidates {
            let modelType = (candidate["model_type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard modelType == "mistral4" else { continue }
            guard let nope = positiveInt(candidate["qk_nope_head_dim"]),
                  let rope = positiveInt(candidate["qk_rope_head_dim"]),
                  let value = positiveInt(candidate["v_head_dim"])
            else { return nil }
            return HeadDimensions(key: nope + rope, value: value)
        }
        return nil
    }

    private static func routedExperts(from config: [String: Any]?) -> Int? {
        configValue(
            from: config,
            keys: ["n_routed_experts", "num_routed_experts", "num_local_experts", "num_experts"]
        )
    }

    private static func expertsPerToken(from config: [String: Any]?) -> Int? {
        configValue(
            from: config,
            keys: ["num_experts_per_tok", "num_experts_per_token", "moe_top_k"]
        )
    }

    private static func configValue(from config: [String: Any]?, keys: [String]) -> Int? {
        guard let config else { return nil }
        let textConfig = config["text_config"] as? [String: Any]
        for source in [config, textConfig].compactMap({ $0 }) {
            for key in keys {
                if let value = positiveInt(source[key]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        switch value {
        case let int as Int where int > 0:
            return int
        case let int64 as Int64 where int64 > 0 && int64 <= Int64(Int.max):
            return Int(int64)
        case let double as Double where double > 0 && double.rounded(.towardZero) == double && double <= Double(Int.max):
            return Int(double)
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let int = Int(trimmed), int > 0 else { return nil }
            return int
        default:
            return nil
        }
    }

    private func inferredModelType(from tags: [String]) -> String? {
        let supportedModelTypes = supportedLLMTypes
            .union(supportedVLMTypes)
            .union(supportedEmbedderTypes)
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs < rhs
            }

        for tag in tags {
            let normalizedTag = Self.normalizedModelTypeTag(tag)
            if let modelType = supportedModelTypes.first(where: { Self.normalizedModelTypeTag($0) == normalizedTag }) {
                return modelType
            }
        }

        for tag in tags {
            let compactTag = Self.compactModelTypeTag(tag)
            if let modelType = supportedModelTypes.first(where: { Self.compactModelTypeTag($0) == compactTag }) {
                return modelType
            }
        }

        return nil
    }

    private static func normalizedModelTypeTag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    private static func compactModelTypeTag(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    public static let runtimeCompatibilityGateReason = "Qwen3 1.7B MLX 4-bit variants require the fixed MLX TurboQuant UInt32 seed path and a passing on-device TurboQuant Metal self-test before local loading."

    public static func requiresRuntimeCompatibilityGate(repository: String, modelType: String?) -> Bool {
        let normalized = repository.lowercased()
        return modelType == "qwen3"
            && (normalized.contains("qwen3-1.7b") || normalized.contains("qwen3_1.7b") || normalized.contains("qwen3-1_7b"))
            && (normalized.contains("4bit") || normalized.contains("4-bit"))
    }

    public static let defaultSupportedLLMTypes: Set<String> = [
        "llama", "mistral", "qwen2", "qwen3", "qwen3_moe", "gemma", "gemma2",
        "gemma3", "gemma3_text", "gemma3n", "gemma4", "gemma4_text", "gemma4_assistant",
        "qwen3_next", "qwen3_5", "qwen3_5_moe", "qwen3_5_text", "qwen3_5_moe_text",
        "phi", "phi3", "phimoe", "deepseek_v3", "deepseek_v32", "deepseek_v4", "glm4", "glm4_moe",
        "glm4_moe_lite", "starcoder2", "cohere", "openelm", "internlm2",
        "granite", "granitemoehybrid", "mimo", "mimo_v2_flash", "minimax",
        "minimax_m2", "mistral3", "ministral3", "bitnet", "smollm3", "ernie4_5", "lfm2", "lfm2_moe",
        "baichuan_m1", "exaone4", "olmo2", "olmo3", "olmoe", "falcon_h1",
        "jamba", "gpt_oss", "nanochat", "nemotron_h", "apertus", "afmoe",
        "bailing_moe", "minicpm", "lille-130m", "acereason",
    ]

    public static let defaultSupportedVLMTypes: Set<String> = [
        "qwen2_vl", "qwen2_5_vl", "qwen3_vl", "qwen3_5", "qwen3_5_text",
        "qwen3_5_moe", "qwen3_5_moe_text",
        "gemma3", "gemma4", "paligemma", "idefics3", "smolvlm", "fastvlm",
        "llava_qwen2", "pixtral", "mistral3", "lfm2_vl", "lfm2-vl", "glm_ocr",
    ]

    public static let defaultSupportedEmbedderTypes: Set<String> = [
        "bert", "roberta", "xlm-roberta", "distilbert", "nomic_bert", "qwen3",
        "gemma3", "gemma3_text", "gemma3n",
    ]
}
