import Foundation

public enum CloudProviderKind: String, Codable, Sendable, CaseIterable {
    case openAI
    case openAICompatible
    case anthropic
    case gemini
    case openRouter
    case voyageAI
    case custom
}

public struct CloudProviderModel: Identifiable, Hashable, Codable, Sendable {
    public var id: ModelID
    public var displayName: String
    public var createdAt: Date?
    public var rank: Double
    public var capabilities: ProviderCapabilities?
    public var supportedParameters: [String]
    public var supportedGenerationMethods: [String]

    public init(
        id: ModelID,
        displayName: String,
        createdAt: Date? = nil,
        rank: Double = 0,
        capabilities: ProviderCapabilities? = nil,
        supportedParameters: [String] = [],
        supportedGenerationMethods: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.rank = rank
        self.capabilities = capabilities
        self.supportedParameters = supportedParameters
        self.supportedGenerationMethods = supportedGenerationMethods
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case createdAt
        case rank
        case capabilities
        case supportedParameters
        case supportedGenerationMethods
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ModelID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        rank = try container.decodeIfPresent(Double.self, forKey: .rank) ?? 0
        capabilities = try container.decodeIfPresent(ProviderCapabilities.self, forKey: .capabilities)
        supportedParameters = try container.decodeIfPresent([String].self, forKey: .supportedParameters) ?? []
        supportedGenerationMethods = try container.decodeIfPresent([String].self, forKey: .supportedGenerationMethods) ?? []
    }
}

public struct OpenAIProviderFileID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct OpenAIVectorStoreID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct OpenAIVectorStoreFileID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct OpenAIResponseID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct OpenAIHostedToolCallID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct OpenAIArtifactID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct OpenAIRealtimeSessionID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct OpenAIBatchID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct AnthropicProviderFileID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct AnthropicBatchID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct AnthropicMessageID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct AnthropicRequestID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct AnthropicHostedToolCallID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public typealias ProviderFileID = OpenAIProviderFileID
public typealias ProviderDataStoreID = OpenAIVectorStoreID
public typealias ProviderDataStoreFileID = OpenAIVectorStoreFileID
public typealias ProviderRunID = OpenAIResponseID
public typealias ProviderHostedToolCallID = OpenAIHostedToolCallID
public typealias ProviderArtifactID = OpenAIArtifactID
public typealias ProviderLiveSessionID = OpenAIRealtimeSessionID
public typealias ProviderBatchJobID = OpenAIBatchID

public struct ProviderContextCacheID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public enum CloudProviderHeaderKind: String, Hashable, Codable, Sendable, CaseIterable {
    case publicValue
    case secretReference
}

public struct CloudProviderHeader: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name.lowercased() }
    public var name: String
    public var kind: CloudProviderHeaderKind
    public var value: String?
    public var keychainService: String?
    public var keychainAccount: String?

    public init(
        name: String,
        kind: CloudProviderHeaderKind,
        value: String? = nil,
        keychainService: String? = nil,
        keychainAccount: String? = nil
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.value = value
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }

    public var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var storesSecretInPlaintext: Bool {
        kind == .publicValue && Self.isSecretLikeName(name)
    }

    public static func isSecretLikeName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if ["authorization", "cookie", "proxy-authorization"].contains(normalized) {
            return true
        }
        return ["key", "token", "secret", "credential", "password"].contains { normalized.contains($0) }
    }
}

public struct CloudProviderConfiguration: Identifiable, Hashable, Codable, Sendable {
    public var id: ProviderID
    public var kind: CloudProviderKind
    public var displayName: String
    public var baseURL: URL
    public var defaultModelID: ModelID?
    public var validationStatus: ProviderValidationStatus
    public var lastValidationError: String?
    public var headers: [CloudProviderHeader]
    public var keychainService: String
    public var keychainAccount: String
    public var allowInsecureLocalHTTP: Bool
    public var enabledForAgents: Bool
    public var lastValidatedAt: Date?

    public init(
        id: ProviderID,
        kind: CloudProviderKind,
        displayName: String,
        baseURL: URL,
        defaultModelID: ModelID? = nil,
        validationStatus: ProviderValidationStatus = .unvalidated,
        lastValidationError: String? = nil,
        headers: [CloudProviderHeader] = [],
        keychainService: String = "com.schtack.pines.cloud",
        keychainAccount: String,
        allowInsecureLocalHTTP: Bool = false,
        enabledForAgents: Bool = false,
        lastValidatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.baseURL = baseURL
        self.defaultModelID = defaultModelID
        self.validationStatus = validationStatus
        self.lastValidationError = lastValidationError
        self.headers = headers
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.allowInsecureLocalHTTP = allowInsecureLocalHTTP
        self.enabledForAgents = enabledForAgents
        self.lastValidatedAt = lastValidatedAt
    }
}

public extension CloudProviderConfiguration {
    var capabilities: ProviderCapabilities {
        let officialOpenAI = isOfficialOpenAIAPI
        let imageInputs: Bool
        let audioInputs: Bool
        let audioOutputs: Bool
        let videoInputs: Bool
        let pdfInputs: Bool
        let textDocumentInputs: Bool
        let files: Bool
        let hostedTools: Bool
        let structuredOutputs: Bool
        let contextCache: Bool
        let live: Bool
        let generatedImages: Bool
        let generatedAudio: Bool
        let generatedVideo: Bool
        let batch: Bool
        let tokenCounting: Bool

        switch kind {
        case .openAI:
            imageInputs = officialOpenAI
            audioInputs = officialOpenAI
            audioOutputs = officialOpenAI
            videoInputs = officialOpenAI
            pdfInputs = officialOpenAI
            textDocumentInputs = officialOpenAI
            files = officialOpenAI
            hostedTools = officialOpenAI
            structuredOutputs = officialOpenAI
            contextCache = false
            live = officialOpenAI
            generatedImages = officialOpenAI
            generatedAudio = officialOpenAI
            generatedVideo = officialOpenAI
            batch = officialOpenAI
            tokenCounting = false
        case .anthropic, .gemini:
            imageInputs = true
            audioInputs = kind == .gemini
            audioOutputs = false
            videoInputs = kind == .gemini
            pdfInputs = true
            textDocumentInputs = true
            files = true
            hostedTools = true
            structuredOutputs = true
            contextCache = true
            live = kind == .gemini
            generatedImages = kind == .gemini
            generatedAudio = false
            generatedVideo = kind == .gemini
            batch = true
            tokenCounting = true
        case .openRouter:
            imageInputs = true
            audioInputs = false
            audioOutputs = false
            videoInputs = false
            pdfInputs = true
            textDocumentInputs = false
            files = false
            hostedTools = false
            structuredOutputs = true
            contextCache = false
            live = false
            generatedImages = false
            generatedAudio = false
            generatedVideo = false
            batch = false
            tokenCounting = false
        case .voyageAI:
            imageInputs = false
            audioInputs = false
            audioOutputs = false
            videoInputs = false
            pdfInputs = false
            textDocumentInputs = false
            files = false
            hostedTools = false
            structuredOutputs = false
            contextCache = false
            live = false
            generatedImages = false
            generatedAudio = false
            generatedVideo = false
            batch = false
            tokenCounting = false
        case .openAICompatible, .custom:
            imageInputs = officialOpenAI
            audioInputs = officialOpenAI
            audioOutputs = officialOpenAI
            videoInputs = officialOpenAI
            pdfInputs = officialOpenAI
            textDocumentInputs = officialOpenAI
            files = officialOpenAI
            hostedTools = officialOpenAI
            structuredOutputs = officialOpenAI
            contextCache = false
            live = officialOpenAI
            generatedImages = officialOpenAI
            generatedAudio = officialOpenAI
            generatedVideo = officialOpenAI
            batch = officialOpenAI
            tokenCounting = false
        }

        return ProviderCapabilities(
            local: false,
            streaming: kind != .voyageAI,
            textGeneration: kind != .voyageAI,
            vision: imageInputs,
            imageInputs: imageInputs,
            audioInputs: audioInputs,
            audioOutputs: audioOutputs,
            videoInputs: videoInputs,
            videoOutputs: false,
            pdfInputs: pdfInputs,
            textDocumentInputs: textDocumentInputs,
            files: files,
            embeddings: kind.supportsVaultEmbeddings,
            toolCalling: kind != .custom && kind != .voyageAI,
            hostedTools: hostedTools,
            jsonMode: kind != .custom && kind != .voyageAI,
            structuredOutputs: structuredOutputs,
            contextCache: contextCache,
            live: live,
            generatedImages: generatedImages,
            generatedAudio: generatedAudio,
            generatedVideo: generatedVideo,
            batch: batch,
            tokenCounting: tokenCounting,
            maxContextTokens: nil
        )
    }

    var isOfficialOpenAIAPI: Bool {
        if kind == .openAI {
            return true
        }
        guard let host = baseURL.host(percentEncoded: false)?.lowercased() else {
            return false
        }
        return host == "api.openai.com"
    }
}

public extension CloudProviderKind {
    var supportsVaultEmbeddings: Bool {
        switch self {
        case .openAI, .openAICompatible, .gemini, .openRouter, .voyageAI, .custom:
            true
        case .anthropic:
            false
        }
    }
}

public struct CloudEmbeddingRequestBuilder: Sendable {
    public init() {}

    public func openAICompatibleBody(
        providerKind: CloudProviderKind,
        modelID: ModelID,
        inputs: [String],
        dimensions: Int?,
        inputType: EmbeddingInputType?
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID.rawValue),
            "input": .array(inputs.map(JSONValue.string)),
            "encoding_format": .string("float"),
        ]
        if let dimensions, dimensions > 0 {
            body["dimensions"] = .number(Double(dimensions))
        }
        if providerKind == .openRouter, let inputType {
            body["input_type"] = .string(inputType == .query ? "search_query" : "search_document")
        }
        return .object(body)
    }

    public func geminiBatchBody(
        modelID: ModelID,
        inputs: [String],
        dimensions: Int?,
        inputType: EmbeddingInputType?
    ) -> (modelName: String, body: JSONValue) {
        let modelName = modelID.rawValue.hasPrefix("models/")
            ? modelID.rawValue
            : "models/\(modelID.rawValue)"
        let isGeminiEmbedding2 = modelName.hasSuffix("/gemini-embedding-2") || modelName == "models/gemini-embedding-2"
        let requests: [JSONValue] = inputs.map { input in
            let contentText = isGeminiEmbedding2
                ? Self.geminiEmbedding2Content(input, inputType: inputType)
                : input
            var item: [String: JSONValue] = [
                "model": .string(modelName),
                "content": .object([
                    "parts": .array([
                        .object(["text": .string(contentText)]),
                    ]),
                ]),
            ]
            if let dimensions, dimensions > 0 {
                item[isGeminiEmbedding2 ? "output_dimensionality" : "outputDimensionality"] = .number(Double(dimensions))
            }
            if !isGeminiEmbedding2 {
                item["taskType"] = .string(inputType == .query ? "RETRIEVAL_QUERY" : "RETRIEVAL_DOCUMENT")
            }
            return .object(item)
        }
        return (modelName, .object(["requests": .array(requests)]))
    }

    public func voyageBody(
        modelID: ModelID,
        inputs: [String],
        dimensions: Int?,
        inputType: EmbeddingInputType?
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(modelID.rawValue),
            "input": .array(inputs.map(JSONValue.string)),
            "input_type": .string(inputType == .query ? "query" : "document"),
        ]
        if let dimensions, dimensions > 0 {
            body["output_dimension"] = .number(Double(dimensions))
        }
        return .object(body)
    }

    public static func geminiEmbedding2Content(_ input: String, inputType: EmbeddingInputType?) -> String {
        switch inputType {
        case .query:
            return "task: search result | query: \(input)"
        case .document, .none:
            return "title: none | text: \(input)"
        }
    }
}

public protocol SecretStore: Sendable {
    func read(service: String, account: String) async throws -> String?
    func write(_ secret: String, service: String, account: String) async throws
    func delete(service: String, account: String) async throws
}

public enum CloudProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case disabledForAgents
    case invalidResponse
    case responseTooLarge(maxBytes: Int)
    case providerRejectedRequest(statusCode: Int, message: String)
}

public enum CloudProviderModelEligibility: Sendable {
    /// Curated chat model visibility policy for the agent model picker.
    ///
    /// This is deliberately narrower than "all valid provider text models." The
    /// provider catalog can contain older, transitional, or capability-specific
    /// models that are technically callable but not approved for Pines' agent
    /// surface. Keep this gate conservative: only expose model families that the
    /// product has explicitly certified for agent use, and continue filtering
    /// embeddings, media, realtime, and other non-chat resources out of the
    /// picker. A provider can validate successfully while returning zero
    /// curated models; the UI should report that as "no curated agent models,"
    /// not as a failed key save.
    public static func isTextOutputModel(
        id rawID: String,
        providerKind: CloudProviderKind,
        supportedGenerationMethods: [String] = []
    ) -> Bool {
        let id = rawID.lowercased()
        let modelName = id
            .split(separator: "/")
            .last
            .map(String.init) ?? id
        let blocked = [
            "embedding", "embed", "moderation", "image", "imagen", "dall-e", "sora",
            "tts", "transcribe", "whisper", "audio", "realtime", "vision-preview"
        ]
        guard !blocked.contains(where: { id.contains($0) }) else { return false }

        switch providerKind {
        case .openAI, .openAICompatible, .openRouter, .custom:
            guard !isOpenAIOSeries(modelName) else { return false }
        case .anthropic, .gemini, .voyageAI:
            break
        }

        if providerKind == .gemini {
            guard supportedGenerationMethods.contains(where: { method in
                method == "generateContent"
                    || method == "streamGenerateContent"
                    || method == "createInteraction"
                    || method == "interactions"
            }) else {
                return false
            }
        }

        switch providerKind {
        case .openAI:
            return isAllowedOpenAITextModel(modelName)
        case .anthropic:
            return isAllowedAnthropicTextModel(modelName)
        case .gemini:
            return isAllowedGeminiTextModel(modelName)
        case .openAICompatible, .openRouter, .custom:
            return isAllowedKnownProviderTextModel(modelName) ?? true
        case .voyageAI:
            return false
        }
    }

    public static func isOpenAIOSeries(_ modelName: String) -> Bool {
        let id = modelName.lowercased()
        guard id.hasPrefix("o") else { return false }
        return id.dropFirst().first?.isNumber == true
    }

    public static func openAIReasoningEffort(for modelID: ModelID, requested: OpenAIReasoningEffort) -> OpenAIReasoningEffort {
        let options = openAIReasoningEffortOptions(for: modelID)
        if !options.isEmpty, !options.contains(requested) {
            return options.contains(.low) ? .low : options[0]
        }
        return requested
    }

    public static func openAIReasoningEffortOptions(for modelID: ModelID) -> [OpenAIReasoningEffort] {
        let id = modelID.rawValue.lowercased()
        let modelName = id
            .split(separator: "/")
            .last
            .map(String.init) ?? id
        guard isOpenAIReasoningFamily(modelName) || isOpenAIOSeries(modelName) else {
            return []
        }
        if modelName.contains("-pro") {
            return [.high]
        }
        if isFutureGPTFamily(modelName) || gpt5MinorVersion(modelName) >= 2 {
            return [.none, .minimal, .low, .medium, .high, .xhigh]
        }
        if modelName.hasPrefix("gpt-5.1") {
            return [.none, .low, .medium, .high]
        }
        if modelName.hasPrefix("gpt-5") {
            return [.minimal, .low, .medium, .high]
        }
        return [.low, .medium, .high]
    }

    public static func supportsOpenAITextVerbosity(modelID: ModelID) -> Bool {
        !openAIReasoningEffortOptions(for: modelID).isEmpty
    }

    public static func anthropicEffort(for modelID: ModelID, requested: AnthropicEffort) -> AnthropicEffort {
        let options = anthropicEffortOptions(for: modelID)
        if !options.isEmpty, !options.contains(requested) {
            return options.contains(.high) ? .high : options[0]
        }
        return requested
    }

    public static func anthropicEffortOptions(for modelID: ModelID) -> [AnthropicEffort] {
        let modelName = normalizedModelName(modelID)
        if modelName.contains("claude-opus-4-7") || modelName.contains("claude-mythos-preview") {
            return [.low, .medium, .high, .xhigh, .max]
        }
        if modelName.contains("claude-opus-4-6") || modelName.contains("claude-sonnet-4-6") {
            return [.low, .medium, .high, .max]
        }
        if modelName.contains("claude-opus-4-5") {
            return [.low, .medium, .high]
        }
        return []
    }

    public static func usesAnthropicAdaptiveThinking(modelID: ModelID) -> Bool {
        let modelName = normalizedModelName(modelID)
        return modelName.contains("claude-opus-4-7")
            || modelName.contains("claude-opus-4-6")
            || modelName.contains("claude-sonnet-4-6")
            || modelName.contains("claude-mythos-preview")
    }

    public static func anthropicThinkingModes(for modelID: ModelID) -> [AnthropicThinkingMode] {
        let modelName = normalizedModelName(modelID)
        let effortOptions = anthropicEffortOptions(for: modelID)
        guard isAllowedAnthropicTextModel(modelName)
                || !effortOptions.isEmpty
                || usesAnthropicAdaptiveThinking(modelID: modelID)
        else { return [] }

        var modes: [AnthropicThinkingMode] = [.off]
        if usesAnthropicAdaptiveThinking(modelID: modelID) {
            modes.append(.adaptive)
        }
        modes.append(.budgeted)
        if !effortOptions.isEmpty {
            modes.append(.effort)
        }
        return modes
    }

    public static func anthropicThinkingOptions(
        for modelID: ModelID,
        requested: AnthropicThinkingOptions
    ) -> AnthropicThinkingOptions {
        let modes = anthropicThinkingModes(for: modelID)
        guard !modes.isEmpty else {
            return AnthropicThinkingOptions(mode: .off, effort: requested.effort, showSummaries: requested.showSummaries)
        }
        var options = requested
        if !modes.contains(options.mode) {
            options.mode = modes.contains(.adaptive) ? .adaptive : modes[0]
        }
        if options.mode == .effort {
            options.effort = anthropicEffort(for: modelID, requested: options.effort)
        }
        return options
    }

    public static func geminiThinkingLevel(for modelID: ModelID, requested: GeminiThinkingLevel) -> GeminiThinkingLevel {
        let options = geminiThinkingLevelOptions(for: modelID)
        if !options.isEmpty, !options.contains(requested) {
            return options.contains(.low) ? .low : options[0]
        }
        return requested
    }

    public static func geminiThinkingLevelOptions(for modelID: ModelID) -> [GeminiThinkingLevel] {
        let modelName = normalizedModelName(modelID)
        guard isAllowedGeminiTextModel(modelName) else { return [] }
        guard let version = modelVersion(after: "gemini-", in: modelName),
              version.major > 2 || (version.major == 2 && version.minor >= 5)
        else {
            return []
        }
        if modelName.contains("flash") {
            return [.minimal, .low, .medium, .high]
        }
        if modelName.contains("pro") {
            return [.low, .medium, .high]
        }
        return [.low, .medium, .high]
    }

    private static func normalizedModelName(_ modelID: ModelID) -> String {
        let id = modelID.rawValue.lowercased()
        return id
            .split(separator: "/")
            .last
            .map(String.init) ?? id
    }

    private static func isAllowedOpenAITextModel(_ modelName: String) -> Bool {
        guard modelName.hasPrefix("gpt-") else { return false }
        guard let version = modelVersion(after: "gpt-", in: modelName) else { return false }
        if version.major > 5 { return true }
        guard version.major == 5 else { return false }
        if version.minor >= 5 { return true }
        if version.minor == 4 {
            return modelName == "gpt-5.4"
                || modelName.hasPrefix("gpt-5.4-2026")
                || modelName.hasPrefix("gpt-5.4-mini")
                || modelName.hasPrefix("gpt-5.4-nano")
        }
        return false
    }

    private static func isAllowedAnthropicTextModel(_ modelName: String) -> Bool {
        let parts = modelName.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts[0] == "claude" else { return false }
        let family = parts[1]
        guard let major = Int(parts[2]) else { return false }
        let minor = parts.dropFirst(3).first.flatMap { Int($0) } ?? 0
        if major > 4 { return ["opus", "sonnet", "haiku"].contains(family) }
        guard major == 4 else { return false }
        switch family {
        case "opus":
            return minor >= 7
        case "sonnet":
            return minor >= 6
        case "haiku":
            return minor >= 5
        default:
            return false
        }
    }

    private static func isAllowedGeminiTextModel(_ modelName: String) -> Bool {
        guard modelName.hasPrefix("gemini-") else { return false }
        if modelName.hasPrefix("gemini-3-flash-preview") {
            return true
        }
        guard let version = modelVersion(after: "gemini-", in: modelName) else { return false }
        if version.major > 3 { return true }
        return version.major == 3 && version.minor >= 1
    }

    private static func isAllowedKnownProviderTextModel(_ modelName: String) -> Bool? {
        if modelName.hasPrefix("gpt-") {
            return isAllowedOpenAITextModel(modelName)
        }
        if modelName.hasPrefix("claude-") {
            return isAllowedAnthropicTextModel(modelName)
        }
        if modelName.hasPrefix("gemini-") {
            return isAllowedGeminiTextModel(modelName)
        }
        return nil
    }

    private static func isOpenAIReasoningFamily(_ modelName: String) -> Bool {
        guard let version = modelVersion(after: "gpt-", in: modelName) else { return false }
        return version.major >= 5
    }

    private static func isFutureGPTFamily(_ modelName: String) -> Bool {
        guard let version = modelVersion(after: "gpt-", in: modelName) else { return false }
        return version.major > 5
    }

    private static func modelVersion(after prefix: String, in modelName: String) -> (major: Int, minor: Int)? {
        guard modelName.hasPrefix(prefix) else { return nil }
        let suffix = modelName.dropFirst(prefix.count)
        let components = suffix.split { character in
            character == "." || character == "-"
        }
        guard let majorString = components.first, let major = Int(majorString) else {
            return nil
        }
        let minor = components.dropFirst().first.flatMap { Int($0) } ?? 0
        return (major, minor)
    }

    private static func gpt5MinorVersion(_ modelName: String) -> Int {
        let prefix = "gpt-5"
        guard modelName.hasPrefix(prefix) else { return -1 }
        let suffix = modelName.dropFirst(prefix.count)
        guard suffix.first == "." else { return 0 }
        let digits = suffix.dropFirst().prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}

public struct OpenAICompatibleRequestBuilder: Sendable {
    private static let reasoningDefaultMaxCompletionTokens = 16_384

    public init() {}

    public func chatRequest(
        baseURL: URL,
        apiKey: String,
        request: ChatRequest,
        toolsJSON: [[String: any Sendable]] = []
    ) throws -> URLRequest {
        let url = Self.v1BaseURL(from: baseURL).appending(path: "chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let usesReasoningChatParameters = Self.usesReasoningChatParameters(modelID: request.modelID)
        var body: [String: Any] = [
            "model": request.modelID.rawValue,
            "stream": true,
            "stream_options": ["include_usage": true],
            "messages": try request.messages.map(Self.messageObject),
        ]
        if let maxTokens = request.sampling.maxTokens {
            body[usesReasoningChatParameters ? "max_completion_tokens" : "max_tokens"] = usesReasoningChatParameters
                ? max(maxTokens, Self.reasoningDefaultMaxCompletionTokens)
                : maxTokens
        }
        if !usesReasoningChatParameters {
            body["temperature"] = request.sampling.temperature
            body["top_p"] = request.sampling.topP
        } else {
            body["reasoning_effort"] = CloudProviderModelEligibility.openAIReasoningEffort(
                for: request.modelID,
                requested: request.sampling.openAIReasoningEffort
            ).rawValue
            body["verbosity"] = request.sampling.openAITextVerbosity.rawValue
        }
        let advertisedTools = !toolsJSON.isEmpty
            ? toolsJSON
            : (request.allowsTools ? request.availableTools.map { $0.openAIFunctionToolObject() } : [])
        if !advertisedTools.isEmpty {
            body["tools"] = advertisedTools.map(Self.jsonSerializable)
            body["tool_choice"] = "auto"
            body["parallel_tool_calls"] = false
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private static func v1BaseURL(from url: URL) -> URL {
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.split(separator: "/").last?.lowercased() == "v1" {
            return url
        }
        return url.appending(path: "v1")
    }

    private static func jsonSerializable(_ dictionary: [String: any Sendable]) -> [String: Any] {
        dictionary.mapValues { jsonSerializable($0) }
    }

    private static func messageObject(_ message: ChatMessage) throws -> [String: Any] {
        guard message.role != .tool else {
            return [
                "role": "tool",
                "tool_call_id": message.toolCallID ?? "",
                "content": message.content,
            ]
        }
        var object: [String: Any] = [
            "role": message.role.rawValue,
            "content": try chatContent(from: message),
        ]
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = message.toolCalls.map { toolCall in
                [
                    "id": toolCall.id,
                    "type": "function",
                    "function": [
                        "name": toolCall.name,
                        "arguments": toolCall.argumentsFragment,
                    ],
                ] as [String: Any]
            }
        }
        return object
    }

    private static func chatContent(from message: ChatMessage) throws -> Any {
        guard !message.attachments.isEmpty else {
            return message.content
        }
        guard message.role == .user else {
            throw InferenceError.invalidRequest("OpenAI-compatible attachments are only supported on user messages.")
        }
        var parts = [[String: Any]]()
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        for attachment in message.attachments {
            guard attachment.cloudInputKind == .image else {
                throw InferenceError.unsupportedCapability("OpenAI-compatible chat completions only support image attachments.")
            }
            guard let localURL = attachment.localURL, localURL.isFileURL else {
                throw InferenceError.invalidRequest("Image attachment \(attachment.fileName) must have a local file URL.")
            }
            let data = try Data(contentsOf: localURL)
            let contentType = attachment.normalizedContentType == "image/jpg" ? "image/jpeg" : attachment.normalizedContentType
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:\(contentType);base64,\(data.base64EncodedString())"],
            ])
        }
        return parts
    }

    private static func jsonSerializable(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: any Sendable]:
            return jsonSerializable(dictionary)
        case let array as [any Sendable]:
            return array.map { jsonSerializable($0) }
        default:
            return value
        }
    }

    private static func usesReasoningChatParameters(modelID: ModelID) -> Bool {
        let id = modelID.rawValue.lowercased()
        return id.hasPrefix("o") || id.hasPrefix("gpt-5")
    }
}

extension CloudProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No API key is saved for this cloud provider."
        case .disabledForAgents:
            "This cloud provider is disabled for agent execution."
        case .invalidResponse:
            "The cloud provider returned an invalid response."
        case let .responseTooLarge(maxBytes):
            "The cloud provider response exceeded the \(maxBytes)-byte safety limit."
        case let .providerRejectedRequest(statusCode, message):
            "The cloud provider rejected the request with HTTP \(statusCode): \(message)"
        }
    }
}
