import Foundation

public struct ModelRuntimeConfigurationHints: Hashable, Codable, Sendable {
    public var extraEOSTokens: Set<String>
    public var stopStrings: Set<String>

    public init(extraEOSTokens: Set<String> = [], stopStrings: Set<String> = []) {
        self.extraEOSTokens = extraEOSTokens
        self.stopStrings = stopStrings
    }

    public static func infer(
        repository: String,
        modelType: String? = nil,
        processorClass: String? = nil,
        directory: URL
    ) -> ModelRuntimeConfigurationHints {
        var files = [String: Data]()
        for filename in metadataFilenames {
            let url = directory.appending(path: filename)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            files[filename] = data
        }
        return infer(
            repository: repository,
            modelType: modelType,
            processorClass: processorClass,
            metadataFiles: files
        )
    }

    public static func infer(
        repository: String,
        modelType explicitModelType: String? = nil,
        processorClass: String? = nil,
        metadataFiles: [String: Data]
    ) -> ModelRuntimeConfigurationHints {
        let config = metadataJSONObject(named: "config.json", in: metadataFiles)
        let tokenizerConfig = metadataJSONObject(named: "tokenizer_config.json", in: metadataFiles)
        let generationConfig = metadataJSONObject(named: "generation_config.json", in: metadataFiles)
        let specialTokensMap = metadataJSONObject(named: "special_tokens_map.json", in: metadataFiles)
        let modelType = explicitModelType ?? config?["model_type"] as? String

        var stopStrings = Set<String>()
        stopStrings.formUnion(familyStopStrings(repository: repository, modelType: modelType, processorClass: processorClass))
        stopStrings.formUnion(stopStringsFromGenerationConfig(generationConfig))
        stopStrings.formUnion(stopStringsFromTokenizerConfig(tokenizerConfig))
        stopStrings.formUnion(stopStringsFromSpecialTokensMap(specialTokensMap))

        if let chatTemplate = tokenizerConfig?["chat_template"] as? String {
            stopStrings.formUnion(stopStringsFromTemplate(chatTemplate))
        }
        if let chatTemplateData = metadataFiles["chat_template.jinja"],
           let chatTemplate = String(data: chatTemplateData, encoding: .utf8) {
            stopStrings.formUnion(stopStringsFromTemplate(chatTemplate))
        }

        stopStrings = Set(stopStrings.map(normalizedStopString).filter(isUsableStopString))
        return ModelRuntimeConfigurationHints(
            extraEOSTokens: Set(stopStrings.filter(isLikelySingleTokenStop)),
            stopStrings: stopStrings
        )
    }

    private static let metadataFilenames = [
        "config.json",
        "generation_config.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "chat_template.jinja",
    ]

    private static func metadataJSONObject(named filename: String, in files: [String: Data]) -> [String: Any]? {
        guard let data = files[filename] else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func familyStopStrings(
        repository: String,
        modelType: String?,
        processorClass: String?
    ) -> Set<String> {
        let normalizedModelType = modelType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedRepository = repository.lowercased()
        let normalizedProcessor = processorClass?.lowercased() ?? ""
        var stops = Set<String>()

        if normalizedModelType.hasPrefix("gemma") || normalizedRepository.contains("gemma") || normalizedProcessor.contains("gemma") {
            stops.formUnion(["<end_of_turn>", "<turn|>"])
        }
        if normalizedModelType.hasPrefix("phi3") || normalizedModelType == "phimoe" || normalizedRepository.contains("phi-3") {
            stops.insert("<|end|>")
        }
        if normalizedModelType.hasPrefix("llama") || normalizedRepository.contains("llama-3") {
            stops.insert("<|eot_id|>")
        }
        if normalizedModelType.hasPrefix("qwen") || normalizedRepository.contains("qwen") {
            stops.insert("<|im_end|>")
        }

        return stops
    }

    private static func stopStringsFromGenerationConfig(_ json: [String: Any]?) -> Set<String> {
        guard let json else { return [] }
        var stops = Set<String>()
        stops.formUnion(strings(from: json["stop_strings"], acceptArbitraryStrings: true))
        stops.formUnion(strings(from: json["stop"], acceptArbitraryStrings: true))
        stops.formUnion(strings(from: json["stopping_criteria"], acceptArbitraryStrings: true))
        return stops
    }

    private static func stopStringsFromTokenizerConfig(_ json: [String: Any]?) -> Set<String> {
        guard let json else { return [] }
        var stops = Set<String>()
        stops.formUnion(strings(from: json["eos_token"], acceptArbitraryStrings: false))
        stops.formUnion(strings(from: json["additional_special_tokens"], acceptArbitraryStrings: false))
        return Set(stops.filter(isLikelyStopString))
    }

    private static func stopStringsFromSpecialTokensMap(_ json: [String: Any]?) -> Set<String> {
        guard let json else { return [] }
        var stops = Set<String>()
        stops.formUnion(strings(from: json["eos_token"], acceptArbitraryStrings: false))
        stops.formUnion(strings(from: json["additional_special_tokens"], acceptArbitraryStrings: false))
        return Set(stops.filter(isLikelyStopString))
    }

    private static func strings(from value: Any?, acceptArbitraryStrings: Bool) -> Set<String> {
        guard let value else { return [] }
        if let string = value as? String {
            return acceptArbitraryStrings || isLikelyStopString(string) ? [string] : []
        }
        if let values = value as? [Any] {
            return values.reduce(into: Set<String>()) { result, item in
                result.formUnion(strings(from: item, acceptArbitraryStrings: acceptArbitraryStrings))
            }
        }
        if let object = value as? [String: Any] {
            var result = Set<String>()
            for key in ["content", "token", "value"] {
                result.formUnion(strings(from: object[key], acceptArbitraryStrings: acceptArbitraryStrings))
            }
            return result
        }
        return []
    }

    private static func stopStringsFromTemplate(_ template: String) -> Set<String> {
        let patterns = [
            #"<\|[^\s<>]{1,96}\|>"#,
            #"</?[A-Za-z0-9_./|:-]{1,96}>"#,
        ]
        var stops = Set<String>()
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(template.startIndex..<template.endIndex, in: template)
            for match in expression.matches(in: template, range: range) {
                guard let matchRange = Range(match.range, in: template) else { continue }
                let token = String(template[matchRange])
                if isLikelyStopString(token) {
                    stops.insert(token)
                }
            }
        }
        return stops
    }

    private static func normalizedStopString(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsableStopString(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256
    }

    private static func isLikelySingleTokenStop(_ value: String) -> Bool {
        let lower = value.lowercased()
        return value.first == "<"
            || value == "</s>"
            || lower.contains("eos")
            || lower.contains("eot")
            || lower.contains("end")
    }

    private static func isLikelyStopString(_ value: String) -> Bool {
        let stop = normalizedStopString(value)
        guard isUsableStopString(stop) else { return false }
        let lower = stop.lowercased()

        if lower.contains("start")
            || lower.contains("begin")
            || lower.contains("header")
            || lower.contains("system")
            || lower.contains("assistant")
            || lower.contains("user") {
            return false
        }

        if stop == "</s>" || stop == "<turn|>" {
            return true
        }

        return lower.contains("eos")
            || lower.contains("endoftext")
            || lower.contains("end_of_turn")
            || lower.contains("end-of-turn")
            || lower.contains("im_end")
            || lower.contains("eot")
            || lower.contains("eom")
            || lower.contains("<|end|>")
    }
}
