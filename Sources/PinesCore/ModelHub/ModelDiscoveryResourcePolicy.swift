import Foundation

public struct ModelResourceLimitDecision: Hashable, Codable, Sendable {
    public var isRejected: Bool
    public var reason: String?
    public var knownDownloadBytes: Int64?
    public var hasUnknownDownloadFileSizes: Bool
    public var inferredParameterCount: Int64?
    public var inferredWeightBits: Int?
    public var inferredWeightBitsAreExplicit: Bool
    public var estimatedWeightBytes: Int64?
    public var maxDownloadBytes: Int64

    public init(
        isRejected: Bool,
        reason: String? = nil,
        knownDownloadBytes: Int64? = nil,
        hasUnknownDownloadFileSizes: Bool = false,
        inferredParameterCount: Int64? = nil,
        inferredWeightBits: Int? = nil,
        inferredWeightBitsAreExplicit: Bool = false,
        estimatedWeightBytes: Int64? = nil,
        maxDownloadBytes: Int64
    ) {
        self.isRejected = isRejected
        self.reason = reason
        self.knownDownloadBytes = knownDownloadBytes
        self.hasUnknownDownloadFileSizes = hasUnknownDownloadFileSizes
        self.inferredParameterCount = inferredParameterCount
        self.inferredWeightBits = inferredWeightBits
        self.inferredWeightBitsAreExplicit = inferredWeightBitsAreExplicit
        self.estimatedWeightBytes = estimatedWeightBytes
        self.maxDownloadBytes = maxDownloadBytes
    }
}

public struct ModelDiscoveryResourcePolicy: Hashable, Codable, Sendable {
    public var maxDownloadBytes: Int64
    public var assumedUnquantizedWeightBits: Int
    public var quantizedBytesPerParameterFloor: Double

    public init(
        maxDownloadBytes: Int64,
        assumedUnquantizedWeightBits: Int = 16,
        quantizedBytesPerParameterFloor: Double = 1.0
    ) {
        self.maxDownloadBytes = maxDownloadBytes
        self.assumedUnquantizedWeightBits = assumedUnquantizedWeightBits
        self.quantizedBytesPerParameterFloor = quantizedBytesPerParameterFloor
    }

    public static func deviceDefault(for profile: DeviceProfile) -> ModelDiscoveryResourcePolicy {
        ModelDiscoveryResourcePolicy(maxDownloadBytes: profile.recommendedMaxModelBytes)
    }

    public func evaluate(
        _ input: ModelPreflightInput,
        modalities: Set<ModelModality> = []
    ) -> ModelResourceLimitDecision {
        let downloadableFiles = Self.downloadCandidateFiles(from: input.files, modalities: modalities)
        let downloadFootprint = Self.knownDownloadFootprint(from: downloadableFiles)
        let parameterCount = Self.inferredParameterCount(
            repository: input.repository,
            tags: input.tags,
            configJSON: input.configJSON
        )
        let explicitWeightBits = Self.inferredWeightBits(repository: input.repository, tags: input.tags)
        let weightBits = explicitWeightBits ?? assumedUnquantizedWeightBits
        let estimatedWeightBytes = parameterCount.map {
            Self.estimatedWeightBytes(
                parameterCount: $0,
                weightBits: weightBits,
                quantizedBytesPerParameterFloor: quantizedBytesPerParameterFloor
            )
        }

        if let knownDownloadBytes = downloadFootprint.knownBytes,
           knownDownloadBytes > maxDownloadBytes {
            return ModelResourceLimitDecision(
                isRejected: true,
                reason: "\(input.repository) is \(Self.byteLabel(knownDownloadBytes)) to download, above the \(Self.byteLabel(maxDownloadBytes)) on-device discovery limit for this device profile.",
                knownDownloadBytes: knownDownloadBytes,
                hasUnknownDownloadFileSizes: downloadFootprint.hasUnknownSizes,
                inferredParameterCount: parameterCount,
                inferredWeightBits: weightBits,
                inferredWeightBitsAreExplicit: explicitWeightBits != nil,
                estimatedWeightBytes: estimatedWeightBytes,
                maxDownloadBytes: maxDownloadBytes
            )
        }

        if let parameterCount,
           let estimatedWeightBytes,
           estimatedWeightBytes > maxDownloadBytes {
            let bitLabel = explicitWeightBits == nil ? "assumed \(weightBits)-bit" : "\(weightBits)-bit"
            return ModelResourceLimitDecision(
                isRejected: true,
                reason: "\(input.repository) looks like \(Self.parameterLabel(parameterCount)) parameters with \(bitLabel) weights, requiring about \(Self.byteLabel(estimatedWeightBytes)); the device profile limit is \(Self.byteLabel(maxDownloadBytes)).",
                knownDownloadBytes: downloadFootprint.knownBytes,
                hasUnknownDownloadFileSizes: downloadFootprint.hasUnknownSizes,
                inferredParameterCount: parameterCount,
                inferredWeightBits: weightBits,
                inferredWeightBitsAreExplicit: explicitWeightBits != nil,
                estimatedWeightBytes: estimatedWeightBytes,
                maxDownloadBytes: maxDownloadBytes
            )
        }

        return ModelResourceLimitDecision(
            isRejected: false,
            knownDownloadBytes: downloadFootprint.knownBytes,
            hasUnknownDownloadFileSizes: downloadFootprint.hasUnknownSizes,
            inferredParameterCount: parameterCount,
            inferredWeightBits: weightBits,
            inferredWeightBitsAreExplicit: explicitWeightBits != nil,
            estimatedWeightBytes: estimatedWeightBytes,
            maxDownloadBytes: maxDownloadBytes
        )
    }

    public func rejectionReason(repository: String, knownDownloadBytes: Int64) -> String? {
        guard knownDownloadBytes > maxDownloadBytes else { return nil }
        return "\(repository) is \(Self.byteLabel(knownDownloadBytes)) to download, above the \(Self.byteLabel(maxDownloadBytes)) on-device discovery limit for this device profile."
    }

    public static func inferredParameterCount(repository: String, tags: [String]) -> Int64? {
        let candidates = ([repository] + tags.compactMap(parameterHintSource(from:)))
            .flatMap { parameterCandidates(in: $0) }
        guard let largest = candidates.max(), largest.isFinite, largest > 0 else { return nil }
        return Int64(largest.rounded())
    }

    public static func inferredParameterCount(
        repository: String,
        tags: [String],
        configJSON: Data?
    ) -> Int64? {
        inferredParameterCount(repository: repository, tags: tags)
            ?? configJSON
                .flatMap(decodeJSONObject)
                .flatMap(inferredParameterCount(from:))
    }

    public static func inferredWeightBits(repository: String, tags: [String]) -> Int? {
        let sources = [repository] + tags
        var candidates = [Int]()

        for source in sources {
            let normalized = source.lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .replacingOccurrences(of: " ", with: "-")
            let tokens = lexicalTokens(in: source)

            if normalized.contains("bitnet") || normalized.contains("1-bit") || normalized.contains("1bit") {
                candidates.append(1)
            }
            if normalized.contains("2-bit") || normalized.contains("2bit") {
                candidates.append(2)
            }
            if normalized.contains("3-bit") || normalized.contains("3bit") {
                candidates.append(3)
            }
            if normalized.contains("4-bit") || normalized.contains("4bit")
                || normalized.contains("mxfp4") || normalized.contains("nf4") {
                candidates.append(4)
            }
            if normalized.contains("5-bit") || normalized.contains("5bit") {
                candidates.append(5)
            }
            if normalized.contains("6-bit") || normalized.contains("6bit") {
                candidates.append(6)
            }
            if normalized.contains("8-bit") || normalized.contains("8bit")
                || normalized.contains("mxfp8") || normalized.contains("fp8") {
                candidates.append(8)
            }
            if normalized.contains("bf16") || normalized.contains("fp16")
                || normalized.contains("float16") || normalized.contains("f16") {
                candidates.append(16)
            }
            if normalized.contains("fp32") || normalized.contains("float32") || normalized.contains("f32") {
                candidates.append(32)
            }

            for token in tokens {
                if token == "q1" || token == "int1" {
                    candidates.append(1)
                } else if token == "q2" || token == "int2" {
                    candidates.append(2)
                } else if token == "q3" || token == "int3" {
                    candidates.append(3)
                } else if token == "q4" || token == "int4" || token == "uint4" || token.hasPrefix("q4") {
                    candidates.append(4)
                } else if token == "q5" || token == "int5" || token.hasPrefix("q5") {
                    candidates.append(5)
                } else if token == "q6" || token == "int6" || token.hasPrefix("q6") {
                    candidates.append(6)
                } else if token == "q8" || token == "int8" || token.hasPrefix("q8") {
                    candidates.append(8)
                }
            }
        }

        return candidates.min()
    }

    public static func downloadCandidateFiles(
        from files: [ModelFileInfo],
        modalities: Set<ModelModality> = []
    ) -> [ModelFileInfo] {
        files.filter { file in
            let components = file.path.split(separator: "/")
            guard !components.contains(where: { $0.hasPrefix(".") }) else { return false }
            let filename = components.last.map { String($0).lowercased() } ?? file.path.lowercased()
            let pathExtension = filename.split(separator: ".").last.map(String.init) ?? ""
            guard ["safetensors", "json", "jinja", "model", "txt", "tiktoken"].contains(pathExtension) else {
                return false
            }
            guard !modalities.contains(.vision) else { return true }
            return ![
                "processor_config.json",
                "preprocessor_config.json",
                "image_processor_config.json",
                "video_preprocessor_config.json",
            ].contains(filename)
        }
    }

    private static func knownDownloadFootprint(
        from files: [ModelFileInfo]
    ) -> (knownBytes: Int64?, hasUnknownSizes: Bool) {
        var knownBytes: Int64 = 0
        var hasKnownBytes = false
        var hasUnknownSizes = false

        for file in files {
            guard let size = file.size, size > 0 else {
                hasUnknownSizes = true
                continue
            }
            knownBytes += size
            hasKnownBytes = true
        }

        return (hasKnownBytes ? knownBytes : nil, hasUnknownSizes)
    }

    private static func estimatedWeightBytes(
        parameterCount: Int64,
        weightBits: Int,
        quantizedBytesPerParameterFloor: Double
    ) -> Int64 {
        let bytesPerParameter: Double
        if weightBits <= 4 {
            bytesPerParameter = max(Double(weightBits) / 8.0, quantizedBytesPerParameterFloor)
        } else {
            bytesPerParameter = Double(weightBits) / 8.0
        }
        let bytes = Double(parameterCount) * bytesPerParameter
        guard bytes.isFinite, bytes < Double(Int64.max) else { return Int64.max }
        return Int64(bytes.rounded(.up))
    }

    private static func parameterCandidates(in text: String) -> [Double] {
        let tokens = lexicalTokens(in: text)
        var candidates = [Double]()

        for token in tokens {
            if let product = expertProductParameterCount(from: token) {
                candidates.append(product)
            }
            if let count = parameterCount(from: token) {
                candidates.append(count)
            }
        }

        return candidates
    }

    private static func parameterHintSource(from tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("dataset:")
            || lower.hasPrefix("license:")
            || lower.hasPrefix("region:")
            || lower.hasPrefix("language:")
            || lower.hasPrefix("arxiv:")
        {
            return nil
        }
        if lower.hasPrefix("base_model:") {
            return String(trimmed.dropFirst("base_model:".count))
        }
        return trimmed
    }

    private static func expertProductParameterCount(from token: String) -> Double? {
        let parts = token.split(whereSeparator: { $0 == "x" || $0 == "×" }).map(String.init)
        guard parts.count == 2,
              let multiplier = Double(parts[0]),
              let expertParameters = parameterCount(from: parts[1])
        else {
            return nil
        }
        return multiplier * expertParameters
    }

    private static func parameterCount(from token: String) -> Double? {
        guard token.count >= 2,
              let unit = token.last,
              unit == "b" || unit == "m",
              !token.hasSuffix("bit")
        else {
            return nil
        }

        var number = String(token.dropLast())
        if let first = number.first, first.isLetter {
            guard number.count > 1, first == "a" || first == "e" else { return nil }
            number.removeFirst()
        }
        number = number.replacingOccurrences(of: "_", with: ".")
        guard let value = Double(number), value.isFinite, value > 0 else { return nil }
        return value * (unit == "b" ? 1_000_000_000 : 1_000_000)
    }

    private static func inferredParameterCount(from config: [String: Any]) -> Int64? {
        let configs = [
            config,
            config["text_config"] as? [String: Any],
        ].compactMap { $0 }

        for candidate in configs {
            if let explicit = explicitParameterCount(from: candidate) {
                return explicit
            }
        }
        for candidate in configs {
            if let estimated = estimatedDenseTransformerParameterCount(from: candidate) {
                return estimated
            }
        }
        return nil
    }

    private static func explicitParameterCount(from config: [String: Any]) -> Int64? {
        let keys = [
            "num_parameters",
            "parameter_count",
            "parameters",
            "total_parameters",
            "num_params",
            "n_params",
        ]
        for key in keys {
            if let count = positiveInt64(config[key]) {
                return count
            }
            if let text = config[key] as? String,
               let largest = parameterCandidates(in: text).max(),
               largest.isFinite,
               largest > 0 {
                return Int64(largest.rounded())
            }
        }
        return nil
    }

    private static func estimatedDenseTransformerParameterCount(from config: [String: Any]) -> Int64? {
        guard let hiddenSize = positiveInt64(config["hidden_size"]) ?? positiveInt64(config["dim"]),
              let layers = positiveInt64(config["num_hidden_layers"]) ?? positiveInt64(config["n_layers"]),
              let intermediateSize = positiveInt64(config["intermediate_size"])
                ?? positiveInt64(config["hidden_dim"])
                ?? positiveInt64(config["ffn_dim"])
        else {
            return nil
        }

        let attentionHeads = positiveInt64(config["num_attention_heads"])
            ?? positiveInt64(config["n_heads"])
        let keyValueHeads = positiveInt64(config["num_key_value_heads"])
            ?? positiveInt64(config["n_kv_heads"])
            ?? attentionHeads
        let headDimension = positiveInt64(config["head_dim"])
            ?? {
                guard let attentionHeads, attentionHeads > 0, hiddenSize.isMultiple(of: attentionHeads) else {
                    return nil
                }
                return hiddenSize / attentionHeads
            }()

        let queryDimension = attentionHeads.map { $0 * (headDimension ?? (hiddenSize / max($0, 1))) } ?? hiddenSize
        let keyValueDimension = keyValueHeads.map { $0 * (headDimension ?? (hiddenSize / max($0, 1))) }
            ?? queryDimension
        let attentionParameters = hiddenSize
            * (queryDimension + keyValueDimension + keyValueDimension + hiddenSize)
        let mlpParameters = Int64(3) * hiddenSize * intermediateSize
        let perLayerParameters = attentionParameters + mlpParameters

        let vocabSize = positiveInt64(config["vocab_size"]) ?? 0
        let embeddingParameters = vocabSize * hiddenSize
        let tiedEmbeddings = (config["tie_word_embeddings"] as? Bool) == true
        let outputParameters = tiedEmbeddings ? 0 : embeddingParameters
        let total = layers * perLayerParameters + embeddingParameters + outputParameters
        guard total > 0 else { return nil }
        return total
    }

    private static func decodeJSONObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func positiveInt64(_ value: Any?) -> Int64? {
        switch value {
        case let value as Int:
            return value > 0 ? Int64(value) : nil
        case let value as Int64:
            return value > 0 ? value : nil
        case let value as Double:
            return value.isFinite && value > 0 ? Int64(value.rounded()) : nil
        case let value as NSNumber:
            let intValue = value.int64Value
            return intValue > 0 ? intValue : nil
        case let value as String:
            guard let parsed = Double(value), parsed.isFinite, parsed > 0 else { return nil }
            return Int64(parsed.rounded())
        default:
            return nil
        }
    }

    private static func lexicalTokens(in text: String) -> [String] {
        var tokens = [String]()
        var current = ""

        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "x"
                || scalar == "×" {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func byteLabel(_ bytes: Int64) -> String {
        let absolute = Double(max(bytes, 0))
        if absolute >= 1_000_000_000 {
            return "\(oneDecimal(absolute / 1_000_000_000)) GB"
        }
        if absolute >= 1_000_000 {
            return "\(oneDecimal(absolute / 1_000_000)) MB"
        }
        return "\(bytes) bytes"
    }

    private static func parameterLabel(_ count: Int64) -> String {
        let absolute = Double(max(count, 0))
        if absolute >= 1_000_000_000 {
            return "\(oneDecimal(absolute / 1_000_000_000))B"
        }
        if absolute >= 1_000_000 {
            return "\(oneDecimal(absolute / 1_000_000))M"
        }
        return "\(count)"
    }

    private static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        if tenths % 10 == 0 {
            return "\(tenths / 10)"
        }
        return "\(tenths / 10).\(abs(tenths % 10))"
    }
}
