import Foundation

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public enum LocalProviderMetadataKeys {
    public static let turboQuantPreset = "local.turboquant.preset"
    public static let turboQuantRequestedBackend = "local.turboquant.requested_backend"
    public static let turboQuantActiveBackend = "local.turboquant.active_backend"
    public static let turboQuantValueBits = "local.turboquant.value_bits"
    public static let turboQuantAttentionPath = "local.turboquant.attention_path"
    public static let turboQuantKernelProfile = "local.turboquant.kernel_profile"
    public static let turboQuantSelfTestStatus = "local.turboquant.self_test_status"
    public static let turboQuantFallbackReason = "local.turboquant.fallback_reason"
    public static let turboQuantLastUnsupportedShape = "local.turboquant.last_unsupported_shape"
    public static let turboQuantRawFallbackAllocated = "local.turboquant.raw_fallback_allocated"
    public static let turboQuantProfileID = "local.turboquant.profile_id"
    public static let turboQuantProfileSource = "local.turboquant.profile_source"
    public static let turboQuantProfileDiagnostics = "local.turboquant.profile_diagnostics"
    public static let turboQuantAdmissionDecision = "local.turboquant.admission_decision"
    public static let turboQuantAdmissionReason = "local.turboquant.admission_reason"
    public static let turboQuantUserMode = "local.turboquant.user_mode"
    public static let turboQuantSelectedMode = "local.turboquant.selected_mode"
    public static let turboQuantAdmittedContext = "local.turboquant.admitted_context_tokens"
    public static let turboQuantDowngradeReason = "local.turboquant.downgrade_reason"
    public static let turboQuantMemoryMessage = "local.turboquant.memory_message"
    public static let turboQuantRuntimeBudgetBytes = "local.turboquant.runtime_budget_bytes"
    public static let turboQuantRuntimeHeadroomBytes = "local.turboquant.runtime_headroom_bytes"
    public static let turboQuantCompressedKVBytes = "local.turboquant.compressed_kv_bytes"
    public static let turboQuantFallbackReserveBytes = "local.turboquant.fallback_reserve_bytes"
    public static let cacheTopology = "local.cache.topology"
    public static let turboQuantFamilySupport = "local.turboquant.family_support"
    public static let attentionCacheCount = "local.cache.attention_count"
    public static let nativeStateCacheCount = "local.cache.native_state_count"
    public static let hybridStateExplanation = "local.cache.hybrid_state_explanation"
    public static let runtimePressureReason = "local.runtime.pressure_reason"
    public static let runtimeLowPowerMode = "local.runtime.low_power_mode"
    public static let runtimeMaxKVSize = "local.runtime.max_kv_size"
    public static let runtimePrefillStepSize = "local.runtime.prefill_step_size"
    public static let ssdThroughputMBperS = "local.ssd.throughput_mb_per_s"
    public static let ssdTotalBytesRead = "local.ssd.total_bytes_read"
    public static let ssdTotalChunks = "local.ssd.total_chunks"
    public static let ssdAvgChunkLatencyMS = "local.ssd.avg_chunk_latency_ms"
    public static let partitionSummary = "local.partition.summary"
    public static let mtpEnabled = "local.mtp.enabled"
    public static let mtpAcceptanceRate = "local.mtp.acceptance_rate"
    public static let audioEnabled = "local.audio.enabled"
    public static let dflashEnabled = "local.dflash.enabled"
    public static let generationCompletionTokens = "local.generation.completion_tokens"
    public static let generationElapsedSeconds = "local.generation.elapsed_seconds"
    public static let generationTokensPerSecond = "local.generation.tokens_per_second"
    public static let generationFirstTokenLatencySeconds = "local.generation.first_token_latency_seconds"
    public static let generationPrepareElapsedSeconds = "local.generation.prepare_elapsed_seconds"
    public static let generationCacheCreateElapsedSeconds = "local.generation.cache_create_elapsed_seconds"
    public static let generationPreflightAttempts = "local.generation.preflight_attempts"
    public static let generationRequestedMaxTokens = "local.generation.requested_max_tokens"
    public static let generationEffectiveMaxTokens = "local.generation.effective_max_tokens"
    public static let generationMaxTokensClamped = "local.generation.max_tokens_clamped"
    public static let generationPressureCompletionLimit = "local.generation.pressure_completion_limit"
    public static let generationInitialAvailableMemoryBytes = "local.generation.initial_available_memory_bytes"
    public static let generationEffectiveMaxKVSize = "local.generation.effective_max_kv_size"
    public static let generationMaxKVSizeClamped = "local.generation.max_kv_size_clamped"
    public static let generationLastTokenAt = "local.generation.last_token_at"
    public static let generationCancellationReason = "local.generation.cancellation_reason"
    public static let generationIncompleteReason = "local.generation.incomplete_reason"
    public static let generationWatchdogCode = "local.generation.watchdog.code"
    public static let generationWatchdogStage = "local.generation.watchdog.stage"
    public static let generationWatchdogElapsedSeconds = "local.generation.watchdog.elapsed_seconds"
    public static let promptKVCacheStatus = "local.prompt_kv_cache.status"
    public static let promptKVCacheMissReason = "local.prompt_kv_cache.miss_reason"
    public static let promptKVCacheEvictionReason = "local.prompt_kv_cache.eviction_reason"
    public static let promptKVCacheReusedPrefixTokens = "local.prompt_kv_cache.reused_prefix_tokens"
    public static let promptKVCacheSuffixPrefillTokens = "local.prompt_kv_cache.suffix_prefill_tokens"
    public static let promptKVCacheStoredTokens = "local.prompt_kv_cache.stored_tokens"
    public static let mlxCachePressureAction = "local.mlx_cache_pressure.action"
}

public struct ModelID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public enum ChatRole: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public enum AttachmentKind: String, Codable, Sendable, CaseIterable {
    case image
    case document
    case webCapture
    case audio
    case video
}

public struct ChatAttachment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: AttachmentKind
    public var fileName: String
    public var contentType: String
    public var localURL: URL?
    public var byteCount: Int

    public init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        fileName: String,
        contentType: String,
        localURL: URL? = nil,
        byteCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.contentType = contentType
        self.localURL = localURL
        self.byteCount = byteCount
    }
}

public struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var content: String
    public var attachments: [ChatAttachment]
    public var createdAt: Date
    public var toolCallID: String?
    public var toolName: String?
    public var toolCalls: [ToolCallDelta]
    public var providerMetadata: [String: String]

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolCalls: [ToolCallDelta] = [],
        providerMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolCalls = toolCalls
        self.providerMetadata = providerMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
        case createdAt
        case toolCallID
        case toolName
        case toolCalls
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolCalls = try container.decodeIfPresent([ToolCallDelta].self, forKey: .toolCalls) ?? []
        providerMetadata = try container.decodeIfPresent([String: String].self, forKey: .providerMetadata) ?? [:]
    }
}

public enum ProviderModelCapability: String, Hashable, Codable, Sendable, CaseIterable {
    case streaming
    case textGeneration
    case vision
    case imageInputs
    case audioInputs
    case audioOutputs
    case videoInputs
    case videoOutputs
    case pdfInputs
    case textDocumentInputs
    case files
    case embeddings
    case toolCalling
    case hostedTools
    case jsonMode
    case structuredOutputs
    case contextCache
    case live
    case generatedImages
    case generatedAudio
    case generatedVideo
    case batch
    case tokenCounting
}

public struct ProviderCapabilities: Hashable, Codable, Sendable {
    public var local: Bool
    public var streaming: Bool
    public var textGeneration: Bool
    public var vision: Bool
    public var imageInputs: Bool
    public var audioInputs: Bool
    public var audioOutputs: Bool
    public var videoInputs: Bool
    public var videoOutputs: Bool
    public var pdfInputs: Bool
    public var textDocumentInputs: Bool
    public var files: Bool
    public var embeddings: Bool
    public var toolCalling: Bool
    public var hostedTools: Bool
    public var jsonMode: Bool
    public var structuredOutputs: Bool
    public var contextCache: Bool
    public var live: Bool
    public var generatedImages: Bool
    public var generatedAudio: Bool
    public var generatedVideo: Bool
    public var batch: Bool
    public var tokenCounting: Bool
    public var maxContextTokens: Int?
    public var maxOutputTokens: Int?

    public var modelCapabilities: Set<ProviderModelCapability> {
        var capabilities = Set<ProviderModelCapability>()
        if streaming { capabilities.insert(.streaming) }
        if textGeneration { capabilities.insert(.textGeneration) }
        if vision { capabilities.insert(.vision) }
        if imageInputs { capabilities.insert(.imageInputs) }
        if audioInputs { capabilities.insert(.audioInputs) }
        if audioOutputs { capabilities.insert(.audioOutputs) }
        if videoInputs { capabilities.insert(.videoInputs) }
        if videoOutputs { capabilities.insert(.videoOutputs) }
        if pdfInputs { capabilities.insert(.pdfInputs) }
        if textDocumentInputs { capabilities.insert(.textDocumentInputs) }
        if files { capabilities.insert(.files) }
        if embeddings { capabilities.insert(.embeddings) }
        if toolCalling { capabilities.insert(.toolCalling) }
        if hostedTools { capabilities.insert(.hostedTools) }
        if jsonMode { capabilities.insert(.jsonMode) }
        if structuredOutputs { capabilities.insert(.structuredOutputs) }
        if contextCache { capabilities.insert(.contextCache) }
        if live { capabilities.insert(.live) }
        if generatedImages { capabilities.insert(.generatedImages) }
        if generatedAudio { capabilities.insert(.generatedAudio) }
        if generatedVideo { capabilities.insert(.generatedVideo) }
        if batch { capabilities.insert(.batch) }
        if tokenCounting { capabilities.insert(.tokenCounting) }
        return capabilities
    }

    public init(
        local: Bool,
        streaming: Bool = true,
        textGeneration: Bool = true,
        vision: Bool = false,
        imageInputs: Bool = false,
        audioInputs: Bool = false,
        audioOutputs: Bool = false,
        videoInputs: Bool = false,
        videoOutputs: Bool = false,
        pdfInputs: Bool = false,
        textDocumentInputs: Bool = false,
        files: Bool = false,
        embeddings: Bool = false,
        toolCalling: Bool = false,
        hostedTools: Bool = false,
        jsonMode: Bool = false,
        structuredOutputs: Bool = false,
        contextCache: Bool = false,
        live: Bool = false,
        generatedImages: Bool = false,
        generatedAudio: Bool = false,
        generatedVideo: Bool = false,
        batch: Bool = false,
        tokenCounting: Bool = false,
        maxContextTokens: Int? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.local = local
        self.streaming = streaming
        self.textGeneration = textGeneration
        self.vision = vision
        self.imageInputs = imageInputs
        self.audioInputs = audioInputs
        self.audioOutputs = audioOutputs
        self.videoInputs = videoInputs
        self.videoOutputs = videoOutputs
        self.pdfInputs = pdfInputs
        self.textDocumentInputs = textDocumentInputs
        self.files = files
        self.embeddings = embeddings
        self.toolCalling = toolCalling
        self.hostedTools = hostedTools
        self.jsonMode = jsonMode
        self.structuredOutputs = structuredOutputs
        self.contextCache = contextCache
        self.live = live
        self.generatedImages = generatedImages
        self.generatedAudio = generatedAudio
        self.generatedVideo = generatedVideo
        self.batch = batch
        self.tokenCounting = tokenCounting
        self.maxContextTokens = maxContextTokens
        self.maxOutputTokens = maxOutputTokens
    }

    enum CodingKeys: String, CodingKey {
        case local
        case streaming
        case textGeneration
        case vision
        case imageInputs
        case audioInputs
        case audioOutputs
        case videoInputs
        case videoOutputs
        case pdfInputs
        case textDocumentInputs
        case files
        case embeddings
        case toolCalling
        case hostedTools
        case jsonMode
        case structuredOutputs
        case contextCache
        case live
        case generatedImages
        case generatedAudio
        case generatedVideo
        case batch
        case tokenCounting
        case maxContextTokens
        case maxOutputTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        local = try container.decode(Bool.self, forKey: .local)
        streaming = try container.decodeIfPresent(Bool.self, forKey: .streaming) ?? true
        textGeneration = try container.decodeIfPresent(Bool.self, forKey: .textGeneration) ?? true
        vision = try container.decodeIfPresent(Bool.self, forKey: .vision) ?? false
        imageInputs = try container.decodeIfPresent(Bool.self, forKey: .imageInputs) ?? false
        audioInputs = try container.decodeIfPresent(Bool.self, forKey: .audioInputs) ?? false
        audioOutputs = try container.decodeIfPresent(Bool.self, forKey: .audioOutputs) ?? false
        videoInputs = try container.decodeIfPresent(Bool.self, forKey: .videoInputs) ?? false
        videoOutputs = try container.decodeIfPresent(Bool.self, forKey: .videoOutputs) ?? false
        pdfInputs = try container.decodeIfPresent(Bool.self, forKey: .pdfInputs) ?? false
        textDocumentInputs = try container.decodeIfPresent(Bool.self, forKey: .textDocumentInputs) ?? false
        files = try container.decodeIfPresent(Bool.self, forKey: .files) ?? false
        embeddings = try container.decodeIfPresent(Bool.self, forKey: .embeddings) ?? false
        toolCalling = try container.decodeIfPresent(Bool.self, forKey: .toolCalling) ?? false
        hostedTools = try container.decodeIfPresent(Bool.self, forKey: .hostedTools) ?? false
        jsonMode = try container.decodeIfPresent(Bool.self, forKey: .jsonMode) ?? false
        structuredOutputs = try container.decodeIfPresent(Bool.self, forKey: .structuredOutputs) ?? jsonMode
        contextCache = try container.decodeIfPresent(Bool.self, forKey: .contextCache) ?? false
        live = try container.decodeIfPresent(Bool.self, forKey: .live) ?? false
        generatedImages = try container.decodeIfPresent(Bool.self, forKey: .generatedImages) ?? false
        generatedAudio = try container.decodeIfPresent(Bool.self, forKey: .generatedAudio) ?? false
        generatedVideo = try container.decodeIfPresent(Bool.self, forKey: .generatedVideo) ?? false
        batch = try container.decodeIfPresent(Bool.self, forKey: .batch) ?? false
        tokenCounting = try container.decodeIfPresent(Bool.self, forKey: .tokenCounting) ?? false
        maxContextTokens = try container.decodeIfPresent(Int.self, forKey: .maxContextTokens)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
    }
}

public struct ProviderInputRequirements: Hashable, Codable, Sendable {
    public var requiresImages: Bool
    public var requiresAudio: Bool
    public var requiresVideo: Bool
    public var requiresPDFs: Bool
    public var requiresTextDocuments: Bool

    public init(
        requiresImages: Bool = false,
        requiresAudio: Bool = false,
        requiresVideo: Bool = false,
        requiresPDFs: Bool = false,
        requiresTextDocuments: Bool = false
    ) {
        self.requiresImages = requiresImages
        self.requiresAudio = requiresAudio
        self.requiresVideo = requiresVideo
        self.requiresPDFs = requiresPDFs
        self.requiresTextDocuments = requiresTextDocuments
    }

    public init(messages: [ChatMessage]) {
        self.init()
        for attachment in messages.flatMap(\.attachments) {
            switch attachment.cloudMediaInputKind {
            case .image:
                requiresImages = true
            case .audio:
                requiresAudio = true
            case .video:
                requiresVideo = true
            case .pdf:
                requiresPDFs = true
            case .textDocument:
                requiresTextDocuments = true
            case .unsupported:
                if attachment.kind == .image {
                    requiresImages = true
                } else if attachment.kind == .document {
                    requiresTextDocuments = true
                }
            }
        }
    }

    public var isEmpty: Bool {
        !requiresImages && !requiresAudio && !requiresVideo && !requiresPDFs && !requiresTextDocuments
    }

    public func isSatisfied(by capabilities: ProviderCapabilities) -> Bool {
        if requiresImages && !(capabilities.imageInputs || capabilities.vision) { return false }
        if requiresAudio && !capabilities.audioInputs { return false }
        if requiresVideo && !capabilities.videoInputs { return false }
        if requiresPDFs && !capabilities.pdfInputs { return false }
        if requiresTextDocuments && !capabilities.textDocumentInputs { return false }
        return true
    }
}

public enum CloudAttachmentInputKind: Hashable, Codable, Sendable {
    case image
    case pdf
    case textDocument
    case unsupported
}

public enum CloudAttachmentMediaInputKind: Hashable, Codable, Sendable {
    case image
    case audio
    case video
    case pdf
    case textDocument
    case unsupported
}

public extension ChatAttachment {
    var normalizedContentType: String {
        let rawValue = contentType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !rawValue.isEmpty {
            return rawValue
        }
        let extensionValue = [localURL?.pathExtension, URL(fileURLWithPath: fileName).pathExtension]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty }
        switch extensionValue {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "heics":
            return "image/heic-sequence"
        case "heifs":
            return "image/heif-sequence"
        case "mp3":
            return "audio/mpeg"
        case "wav", "wave":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "oga", "ogg":
            return "audio/ogg"
        case "opus":
            return "audio/opus"
        case "aif", "aiff":
            return "audio/aiff"
        case "mp4", "m4v":
            return "video/mp4"
        case "mov", "qt":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        case "mpeg", "mpg":
            return "video/mpeg"
        case "avi":
            return "video/x-msvideo"
        case "mkv":
            return "video/x-matroska"
        case "pdf":
            return "application/pdf"
        case "md", "markdown":
            return "text/markdown"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "txt", "text":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }

    var cloudInputKind: CloudAttachmentInputKind {
        switch normalizedContentType {
        case "image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif", "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence":
            return .image
        case "application/pdf":
            return .pdf
        case "text/plain", "text/markdown", "text/x-markdown", "application/json", "text/csv":
            return .textDocument
        default:
            switch kind {
            case .image:
                return .image
            default:
                return .unsupported
            }
        }
    }

    var cloudMediaInputKind: CloudAttachmentMediaInputKind {
        switch normalizedContentType {
        case "image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif", "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence":
            return .image
        case let contentType where contentType.hasPrefix("audio/"):
            return .audio
        case let contentType where contentType.hasPrefix("video/"):
            return .video
        case "application/pdf":
            return .pdf
        case "text/plain", "text/markdown", "text/x-markdown", "application/json", "text/csv":
            return .textDocument
        default:
            switch kind {
            case .image:
                return .image
            case .audio:
                return .audio
            case .video:
                return .video
            default:
                return .unsupported
            }
        }
    }
}

public enum OpenAIReasoningEffort: String, Hashable, Codable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public enum OpenAITextVerbosity: String, Hashable, Codable, Sendable {
    case low
    case medium
    case high
}

public enum AnthropicEffort: String, Hashable, Codable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case max
}

public enum AnthropicThinkingMode: String, Hashable, Codable, Sendable, CaseIterable {
    case off
    case adaptive
    case budgeted
    case effort
}

public struct AnthropicThinkingOptions: Hashable, Codable, Sendable {
    public var mode: AnthropicThinkingMode
    public var budgetTokens: Int?
    public var effort: AnthropicEffort
    public var showSummaries: Bool

    public init(
        mode: AnthropicThinkingMode = .adaptive,
        budgetTokens: Int? = nil,
        effort: AnthropicEffort = .medium,
        showSummaries: Bool = true
    ) {
        self.mode = mode
        self.budgetTokens = budgetTokens
        self.effort = effort
        self.showSummaries = showSummaries
    }

    public func resolvingLegacyEffort(_ legacyEffort: AnthropicEffort) -> AnthropicThinkingOptions {
        var options = self
        if options.effort == .medium {
            options.effort = legacyEffort
        }
        return options
    }
}

public enum AnthropicPromptCacheTTL: String, Hashable, Codable, Sendable, CaseIterable {
    case fiveMinutes = "5m"
    case oneHour = "1h"

    public var betaHeader: String? {
        switch self {
        case .fiveMinutes:
            return nil
        case .oneHour:
            return AnthropicBetaHeaders.extendedCacheTTL
        }
    }
}

public enum AnthropicBetaHeaders {
    public static let extendedCacheTTL = "extended-cache-ttl-2025-04-11"
    public static let filesAPI = "files-api-2025-04-14"
}

public struct AnthropicPromptCacheOptions: Hashable, Codable, Sendable {
    public var enabled: Bool
    public var ttl: AnthropicPromptCacheTTL
    public var cacheSystemPrompt: Bool
    public var cacheTools: Bool
    public var cacheMessages: Bool
    public var cacheFileBlocks: Bool
    public var breakpointLimit: Int

    public init(
        enabled: Bool = false,
        ttl: AnthropicPromptCacheTTL = .fiveMinutes,
        cacheSystemPrompt: Bool = true,
        cacheTools: Bool = true,
        cacheMessages: Bool = true,
        cacheFileBlocks: Bool = true,
        breakpointLimit: Int = 4
    ) {
        self.enabled = enabled
        self.ttl = ttl
        self.cacheSystemPrompt = cacheSystemPrompt
        self.cacheTools = cacheTools
        self.cacheMessages = cacheMessages
        self.cacheFileBlocks = cacheFileBlocks
        self.breakpointLimit = max(0, breakpointLimit)
    }

    public var betaHeaders: [String] {
        ttl.betaHeader.map { [$0] } ?? []
    }
}

public enum GeminiThinkingLevel: String, Hashable, Codable, Sendable {
    case minimal
    case low
    case medium
    case high
}

public enum OpenAIResponseStorage: String, Hashable, Codable, Sendable {
    case stateful
    case statelessEncrypted
}

public enum OpenAIServiceTier: String, Hashable, Codable, Sendable, CaseIterable {
    case auto
    case `default`
    case flex
    case priority
}

public enum OpenAIPromptCacheRetention: String, Hashable, Codable, Sendable, CaseIterable {
    case standard
    case twentyFourHours = "24h"
}

public enum StructuredOutputFormat: Hashable, Codable, Sendable {
    case text
    case jsonObject
    case jsonSchema(name: String, schema: JSONValue, strict: Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case schema
        case strict
    }

    private enum FormatType: String, Codable {
        case text
        case jsonObject
        case jsonSchema
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(FormatType.self, forKey: .type) ?? .text
        switch type {
        case .text:
            self = .text
        case .jsonObject:
            self = .jsonObject
        case .jsonSchema:
            self = .jsonSchema(
                name: try container.decode(String.self, forKey: .name),
                schema: try container.decode(JSONValue.self, forKey: .schema),
                strict: try container.decodeIfPresent(Bool.self, forKey: .strict) ?? true
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text:
            try container.encode(FormatType.text, forKey: .type)
        case .jsonObject:
            try container.encode(FormatType.jsonObject, forKey: .type)
        case let .jsonSchema(name, schema, strict):
            try container.encode(FormatType.jsonSchema, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(schema, forKey: .schema)
            try container.encode(strict, forKey: .strict)
        }
    }
}

public enum HostedToolConfiguration: Hashable, Codable, Sendable {
    case webSearch
    case webFetch(allowedDomains: [String], blockedDomains: [String], maxUses: Int?)
    case fileSearch(vectorStoreIDs: [String], maxResults: Int?)
    case codeInterpreter(containerID: String?, memoryLimit: String?)
    case imageGeneration(action: String?, quality: String?, size: String?, partialImages: Int?)
    case computerUse(displayWidth: Int?, displayHeight: Int?)
    case remoteMCP(serverLabel: String, serverURL: String, requireApproval: String)
    case textEditor
    case bash
    case toolSearch

    private enum CodingKeys: String, CodingKey {
        case type
        case allowedDomains
        case blockedDomains
        case maxUses
        case vectorStoreIDs
        case maxResults
        case containerID
        case memoryLimit
        case action
        case quality
        case size
        case partialImages
        case displayWidth
        case displayHeight
        case serverLabel
        case serverURL
        case requireApproval
    }

    private enum ToolType: String, Codable {
        case webSearch
        case webFetch
        case fileSearch
        case codeInterpreter
        case imageGeneration
        case computerUse
        case remoteMCP
        case textEditor
        case bash
        case toolSearch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ToolType.self, forKey: .type)
        switch type {
        case .webSearch:
            self = .webSearch
        case .webFetch:
            self = .webFetch(
                allowedDomains: try container.decodeIfPresent([String].self, forKey: .allowedDomains) ?? [],
                blockedDomains: try container.decodeIfPresent([String].self, forKey: .blockedDomains) ?? [],
                maxUses: try container.decodeIfPresent(Int.self, forKey: .maxUses)
            )
        case .fileSearch:
            self = .fileSearch(
                vectorStoreIDs: try container.decodeIfPresent([String].self, forKey: .vectorStoreIDs) ?? [],
                maxResults: try container.decodeIfPresent(Int.self, forKey: .maxResults)
            )
        case .codeInterpreter:
            self = .codeInterpreter(
                containerID: try container.decodeIfPresent(String.self, forKey: .containerID),
                memoryLimit: try container.decodeIfPresent(String.self, forKey: .memoryLimit)
            )
        case .imageGeneration:
            self = .imageGeneration(
                action: try container.decodeIfPresent(String.self, forKey: .action),
                quality: try container.decodeIfPresent(String.self, forKey: .quality),
                size: try container.decodeIfPresent(String.self, forKey: .size),
                partialImages: try container.decodeIfPresent(Int.self, forKey: .partialImages)
            )
        case .computerUse:
            self = .computerUse(
                displayWidth: try container.decodeIfPresent(Int.self, forKey: .displayWidth),
                displayHeight: try container.decodeIfPresent(Int.self, forKey: .displayHeight)
            )
        case .remoteMCP:
            self = .remoteMCP(
                serverLabel: try container.decode(String.self, forKey: .serverLabel),
                serverURL: try container.decode(String.self, forKey: .serverURL),
                requireApproval: try container.decodeIfPresent(String.self, forKey: .requireApproval) ?? "always"
            )
        case .textEditor:
            self = .textEditor
        case .bash:
            self = .bash
        case .toolSearch:
            self = .toolSearch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .webSearch:
            try container.encode(ToolType.webSearch, forKey: .type)
        case let .webFetch(allowedDomains, blockedDomains, maxUses):
            try container.encode(ToolType.webFetch, forKey: .type)
            try container.encode(allowedDomains, forKey: .allowedDomains)
            try container.encode(blockedDomains, forKey: .blockedDomains)
            try container.encodeIfPresent(maxUses, forKey: .maxUses)
        case let .fileSearch(vectorStoreIDs, maxResults):
            try container.encode(ToolType.fileSearch, forKey: .type)
            try container.encode(vectorStoreIDs, forKey: .vectorStoreIDs)
            try container.encodeIfPresent(maxResults, forKey: .maxResults)
        case let .codeInterpreter(containerID, memoryLimit):
            try container.encode(ToolType.codeInterpreter, forKey: .type)
            try container.encodeIfPresent(containerID, forKey: .containerID)
            try container.encodeIfPresent(memoryLimit, forKey: .memoryLimit)
        case let .imageGeneration(action, quality, size, partialImages):
            try container.encode(ToolType.imageGeneration, forKey: .type)
            try container.encodeIfPresent(action, forKey: .action)
            try container.encodeIfPresent(quality, forKey: .quality)
            try container.encodeIfPresent(size, forKey: .size)
            try container.encodeIfPresent(partialImages, forKey: .partialImages)
        case let .computerUse(displayWidth, displayHeight):
            try container.encode(ToolType.computerUse, forKey: .type)
            try container.encodeIfPresent(displayWidth, forKey: .displayWidth)
            try container.encodeIfPresent(displayHeight, forKey: .displayHeight)
        case let .remoteMCP(serverLabel, serverURL, requireApproval):
            try container.encode(ToolType.remoteMCP, forKey: .type)
            try container.encode(serverLabel, forKey: .serverLabel)
            try container.encode(serverURL, forKey: .serverURL)
            try container.encode(requireApproval, forKey: .requireApproval)
        case .textEditor:
            try container.encode(ToolType.textEditor, forKey: .type)
        case .bash:
            try container.encode(ToolType.bash, forKey: .type)
        case .toolSearch:
            try container.encode(ToolType.toolSearch, forKey: .type)
        }
    }

    public var requiresAgentExecution: Bool {
        switch self {
        case .computerUse, .remoteMCP, .textEditor, .bash:
            return true
        case .webSearch, .webFetch, .fileSearch, .codeInterpreter, .imageGeneration, .toolSearch:
            return false
        }
    }

    public var requiresApproval: Bool {
        switch self {
        case .computerUse, .textEditor, .bash:
            return true
        case let .remoteMCP(_, _, requireApproval):
            return requireApproval != "never"
        case .webSearch, .webFetch, .fileSearch, .codeInterpreter, .imageGeneration, .toolSearch:
            return false
        }
    }

    public var approvalPolicy: String {
        switch self {
        case .computerUse, .textEditor, .bash:
            return "always"
        case let .remoteMCP(_, _, requireApproval):
            return requireApproval.isEmpty ? "always" : requireApproval
        case .webSearch, .webFetch, .fileSearch, .codeInterpreter, .imageGeneration, .toolSearch:
            return "never"
        }
    }
}

public struct OpenAIResponsesRequestOptions: Hashable, Codable, Sendable {
    public var store: OpenAIResponseStorage
    public var background: Bool
    public var serviceTier: OpenAIServiceTier
    public var promptCacheRetention: OpenAIPromptCacheRetention
    public var safetyIdentifier: String?
    public var promptCacheKey: String?
    public var maxToolCalls: Int?
    public var conversationID: String?
    public var metadata: [String: String]
    public var include: [String]

    public init(
        store: OpenAIResponseStorage = .stateful,
        background: Bool = false,
        serviceTier: OpenAIServiceTier = .auto,
        promptCacheRetention: OpenAIPromptCacheRetention = .standard,
        safetyIdentifier: String? = nil,
        promptCacheKey: String? = nil,
        maxToolCalls: Int? = nil,
        conversationID: String? = nil,
        metadata: [String: String] = [:],
        include: [String] = []
    ) {
        self.store = store
        self.background = background
        self.serviceTier = serviceTier
        self.promptCacheRetention = promptCacheRetention
        self.safetyIdentifier = safetyIdentifier
        self.promptCacheKey = promptCacheKey
        self.maxToolCalls = maxToolCalls
        self.conversationID = conversationID
        self.metadata = metadata
        self.include = include
    }
}

public enum CloudWebSearchMode: String, Hashable, Codable, Sendable, CaseIterable {
    case off
    case automatic
    case required
}

public enum CloudWebSearchContextSize: String, Hashable, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
}

public struct CloudWebSearchUserLocation: Hashable, Codable, Sendable {
    public var city: String?
    public var region: String?
    public var country: String?
    public var timezone: String?

    public init(city: String? = nil, region: String? = nil, country: String? = nil, timezone: String? = nil) {
        self.city = city
        self.region = region
        self.country = country
        self.timezone = timezone
    }

    public var isEmpty: Bool {
        [city, region, country, timezone].allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public struct CloudWebSearchOptions: Hashable, Codable, Sendable {
    public var contextSize: CloudWebSearchContextSize
    public var userLocation: CloudWebSearchUserLocation?
    public var allowedDomains: [String]
    public var blockedDomains: [String]
    public var externalWebAccess: Bool

    public init(
        contextSize: CloudWebSearchContextSize = .medium,
        userLocation: CloudWebSearchUserLocation? = nil,
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        externalWebAccess: Bool = true
    ) {
        self.contextSize = contextSize
        self.userLocation = userLocation
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.externalWebAccess = externalWebAccess
    }
}

public struct ChatSampling: Hashable, Codable, Sendable {
    public var maxTokens: Int?
    public var temperature: Float
    public var topP: Float
    public var topK: Int
    public var minP: Float
    public var repetitionPenalty: Float?
    public var openAIReasoningEffort: OpenAIReasoningEffort
    public var openAITextVerbosity: OpenAITextVerbosity
    public var anthropicEffort: AnthropicEffort
    public var geminiThinkingLevel: GeminiThinkingLevel
    public var openAIResponseStorage: OpenAIResponseStorage
    public var cloudWebSearchMode: CloudWebSearchMode

    private enum CodingKeys: String, CodingKey {
        case maxTokens
        case temperature
        case topP
        case topK
        case minP
        case repetitionPenalty
        case openAIReasoningEffort
        case openAITextVerbosity
        case anthropicEffort
        case geminiThinkingLevel
        case openAIResponseStorage
        case cloudWebSearchMode
    }

    public init(
        maxTokens: Int? = 1024,
        temperature: Float = 0.6,
        topP: Float = 1,
        topK: Int = 0,
        minP: Float = 0,
        repetitionPenalty: Float? = nil,
        openAIReasoningEffort: OpenAIReasoningEffort = .low,
        openAITextVerbosity: OpenAITextVerbosity = .low,
        anthropicEffort: AnthropicEffort = .medium,
        geminiThinkingLevel: GeminiThinkingLevel = .medium,
        openAIResponseStorage: OpenAIResponseStorage = .stateful,
        cloudWebSearchMode: CloudWebSearchMode = .off
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.repetitionPenalty = repetitionPenalty
        self.openAIReasoningEffort = openAIReasoningEffort
        self.openAITextVerbosity = openAITextVerbosity
        self.anthropicEffort = anthropicEffort
        self.geminiThinkingLevel = geminiThinkingLevel
        self.openAIResponseStorage = openAIResponseStorage
        self.cloudWebSearchMode = cloudWebSearchMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxTokens = container.contains(.maxTokens)
            ? try container.decodeIfPresent(Int.self, forKey: .maxTokens)
            : 1024
        temperature = try container.decodeIfPresent(Float.self, forKey: .temperature) ?? 0.6
        topP = try container.decodeIfPresent(Float.self, forKey: .topP) ?? 1
        topK = try container.decodeIfPresent(Int.self, forKey: .topK) ?? 0
        minP = try container.decodeIfPresent(Float.self, forKey: .minP) ?? 0
        repetitionPenalty = try container.decodeIfPresent(Float.self, forKey: .repetitionPenalty)
        openAIReasoningEffort = try container.decodeIfPresent(OpenAIReasoningEffort.self, forKey: .openAIReasoningEffort) ?? .low
        openAITextVerbosity = try container.decodeIfPresent(OpenAITextVerbosity.self, forKey: .openAITextVerbosity) ?? .low
        anthropicEffort = try container.decodeIfPresent(AnthropicEffort.self, forKey: .anthropicEffort) ?? .medium
        geminiThinkingLevel = try container.decodeIfPresent(GeminiThinkingLevel.self, forKey: .geminiThinkingLevel) ?? .medium
        openAIResponseStorage = try container.decodeIfPresent(OpenAIResponseStorage.self, forKey: .openAIResponseStorage) ?? .stateful
        cloudWebSearchMode = try container.decodeIfPresent(CloudWebSearchMode.self, forKey: .cloudWebSearchMode) ?? .off
    }
}

public struct WebSearchCitation: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(url)#\(title)" }
    public var title: String
    public var url: String
    public var source: String

    public init(title: String, url: String, source: String) {
        self.title = title
        self.url = url
        self.source = source
    }
}

public enum ProviderCitationSourceType: String, Hashable, Codable, Sendable, CaseIterable {
    case web
    case file
    case pdf
    case text
    case searchResult
    case vaultChunk
    case unknown
}

public struct ProviderCitation: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerKind: CloudProviderKind?
    public var sourceType: ProviderCitationSourceType
    public var title: String?
    public var url: String?
    public var fileID: String?
    public var page: Int?
    public var chunkID: String?
    public var documentID: String?
    public var startOffset: Int?
    public var endOffset: Int?
    public var citedText: String?
    public var source: String?
    public var raw: JSONValue?

    public init(
        id: String = UUID().uuidString,
        providerKind: CloudProviderKind? = nil,
        sourceType: ProviderCitationSourceType = .unknown,
        title: String? = nil,
        url: String? = nil,
        fileID: String? = nil,
        page: Int? = nil,
        chunkID: String? = nil,
        documentID: String? = nil,
        startOffset: Int? = nil,
        endOffset: Int? = nil,
        citedText: String? = nil,
        source: String? = nil,
        raw: JSONValue? = nil
    ) {
        self.id = id
        self.providerKind = providerKind
        self.sourceType = sourceType
        self.title = title
        self.url = url
        self.fileID = fileID
        self.page = page
        self.chunkID = chunkID
        self.documentID = documentID
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.citedText = citedText
        self.source = source
        self.raw = raw
    }
}

public enum OpenAIStructuredOutputStrictness: String, Hashable, Codable, Sendable, CaseIterable {
    case disabled
    case strict
}

public struct OpenAIStructuredOutputRequest: Hashable, Codable, Sendable {
    public var name: String
    public var description: String?
    public var schema: JSONValue
    public var strictness: OpenAIStructuredOutputStrictness

    public init(
        name: String,
        description: String? = nil,
        schema: JSONValue,
        strictness: OpenAIStructuredOutputStrictness = .strict
    ) {
        self.name = name
        self.description = description
        self.schema = schema
        self.strictness = strictness
    }
}

public enum OpenAIHostedToolKind: String, Hashable, Codable, Sendable, CaseIterable {
    case webSearch
    case webFetch
    case fileSearch
    case computerUse
    case codeInterpreter
    case imageGeneration
    case mcp
    case textEditor
    case bash
    case toolSearch
    case custom
}

public struct OpenAIHostedToolRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name ?? kind.rawValue }
    public var kind: OpenAIHostedToolKind
    public var name: String?
    public var vectorStoreIDs: [OpenAIVectorStoreID]
    public var configuration: JSONValue?

    public init(
        kind: OpenAIHostedToolKind,
        name: String? = nil,
        vectorStoreIDs: [OpenAIVectorStoreID] = [],
        configuration: JSONValue? = nil
    ) {
        self.kind = kind
        self.name = name
        self.vectorStoreIDs = vectorStoreIDs
        self.configuration = configuration
    }
}

public struct OpenAIResponseRequestOptions: Hashable, Codable, Sendable {
    public var previousResponseID: OpenAIResponseID?
    public var background: Bool
    public var store: OpenAIResponseStorage?
    public var structuredOutput: OpenAIStructuredOutputRequest?
    public var hostedTools: [OpenAIHostedToolRequest]
    public var providerFileIDs: [OpenAIProviderFileID]
    public var vectorStoreIDs: [OpenAIVectorStoreID]
    public var metadata: [String: String]

    public init(
        previousResponseID: OpenAIResponseID? = nil,
        background: Bool = false,
        store: OpenAIResponseStorage? = nil,
        structuredOutput: OpenAIStructuredOutputRequest? = nil,
        hostedTools: [OpenAIHostedToolRequest] = [],
        providerFileIDs: [OpenAIProviderFileID] = [],
        vectorStoreIDs: [OpenAIVectorStoreID] = [],
        metadata: [String: String] = [:]
    ) {
        self.previousResponseID = previousResponseID
        self.background = background
        self.store = store
        self.structuredOutput = structuredOutput
        self.hostedTools = hostedTools
        self.providerFileIDs = providerFileIDs
        self.vectorStoreIDs = vectorStoreIDs
        self.metadata = metadata
    }
}

public struct GeminiRequestOptions: Hashable, Codable, Sendable {
    public var cachedContentName: String?
    public var responseMimeType: String?
    public var responseSchema: JSONValue?
    public var safetySettings: [JSONValue]
    public var toolConfig: JSONValue?
    public var generationConfig: JSONValue?
    public var labels: [String: String]

    public init(
        cachedContentName: String? = nil,
        responseMimeType: String? = nil,
        responseSchema: JSONValue? = nil,
        safetySettings: [JSONValue] = [],
        toolConfig: JSONValue? = nil,
        generationConfig: JSONValue? = nil,
        labels: [String: String] = [:]
    ) {
        self.cachedContentName = cachedContentName
        self.responseMimeType = responseMimeType
        self.responseSchema = responseSchema
        self.safetySettings = safetySettings
        self.toolConfig = toolConfig
        self.generationConfig = generationConfig
        self.labels = labels
    }
}

public struct AnthropicCitationOptions: Hashable, Codable, Sendable {
    public var enabled: Bool
    public var includeCitedText: Bool

    public init(enabled: Bool = false, includeCitedText: Bool = true) {
        self.enabled = enabled
        self.includeCitedText = includeCitedText
    }
}

public struct AnthropicBatchRequestOptions: Hashable, Codable, Sendable {
    public var customID: String?
    public var metadata: [String: String]

    public init(customID: String? = nil, metadata: [String: String] = [:]) {
        self.customID = customID
        self.metadata = metadata
    }
}

public struct AnthropicRequestOptions: Hashable, Codable, Sendable {
    public var promptCache: AnthropicPromptCacheOptions
    public var thinking: AnthropicThinkingOptions
    public var citations: AnthropicCitationOptions
    public var hostedTools: [HostedToolConfiguration]
    public var providerFileIDs: [AnthropicProviderFileID]
    public var batch: AnthropicBatchRequestOptions?
    public var countTokensBeforeSend: Bool
    public var betaHeaders: [String]
    public var metadata: [String: String]

    public init(
        promptCache: AnthropicPromptCacheOptions = .init(),
        thinking: AnthropicThinkingOptions = .init(),
        citations: AnthropicCitationOptions = .init(),
        hostedTools: [HostedToolConfiguration] = [],
        providerFileIDs: [AnthropicProviderFileID] = [],
        batch: AnthropicBatchRequestOptions? = nil,
        countTokensBeforeSend: Bool = false,
        betaHeaders: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.promptCache = promptCache
        self.thinking = thinking
        self.citations = citations
        self.hostedTools = hostedTools
        self.providerFileIDs = providerFileIDs
        self.batch = batch
        self.countTokensBeforeSend = countTokensBeforeSend
        self.betaHeaders = betaHeaders
        self.metadata = metadata
    }

    public func resolvingLegacyEffort(_ legacyEffort: AnthropicEffort) -> AnthropicRequestOptions {
        var options = self
        options.thinking = options.thinking.resolvingLegacyEffort(legacyEffort)
        return options
    }

    public var requiredBetaHeaders: [String] {
        var headers = betaHeaders
        headers.append(contentsOf: promptCache.betaHeaders)
        if !providerFileIDs.isEmpty {
            headers.append(AnthropicBetaHeaders.filesAPI)
        }
        return Array(Set(headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    public var hasAgentOnlyHostedTools: Bool {
        hostedTools.contains { $0.requiresAgentExecution }
    }

    public var hasApprovalGatedHostedTools: Bool {
        hostedTools.contains { $0.requiresApproval }
    }
}

public struct ChatRequest: Hashable, Codable, Sendable {
    public enum ExecutionContext: String, Hashable, Codable, Sendable {
        case chat
        case agent
    }

    public var id: UUID
    public var modelID: ModelID
    public var messages: [ChatMessage]
    public var sampling: ChatSampling
    public var webSearchOptions: CloudWebSearchOptions?
    public var structuredOutput: StructuredOutputFormat
    public var hostedTools: [HostedToolConfiguration]
    public var openAIOptions: OpenAIResponsesRequestOptions?
    public var allowsTools: Bool
    public var availableTools: [AnyToolSpec]
    public var vaultContextIDs: [UUID]
    public var executionContext: ExecutionContext
    public var openAIResponseOptions: OpenAIResponseRequestOptions?
    public var geminiOptions: GeminiRequestOptions?
    public var anthropicOptions: AnthropicRequestOptions?

    public init(
        id: UUID = UUID(),
        modelID: ModelID,
        messages: [ChatMessage],
        sampling: ChatSampling = .init(),
        webSearchOptions: CloudWebSearchOptions? = nil,
        structuredOutput: StructuredOutputFormat = .text,
        hostedTools: [HostedToolConfiguration] = [],
        openAIOptions: OpenAIResponsesRequestOptions? = nil,
        allowsTools: Bool = false,
        availableTools: [AnyToolSpec] = [],
        vaultContextIDs: [UUID] = [],
        executionContext: ExecutionContext = .chat,
        openAIResponseOptions: OpenAIResponseRequestOptions? = nil,
        geminiOptions: GeminiRequestOptions? = nil,
        anthropicOptions: AnthropicRequestOptions? = nil
    ) {
        self.id = id
        self.modelID = modelID
        self.messages = messages
        self.sampling = sampling
        self.webSearchOptions = webSearchOptions
        self.structuredOutput = structuredOutput
        self.hostedTools = hostedTools
        self.openAIOptions = openAIOptions
        self.allowsTools = allowsTools
        self.availableTools = availableTools
        self.vaultContextIDs = vaultContextIDs
        self.executionContext = executionContext
        self.openAIResponseOptions = openAIResponseOptions
        self.geminiOptions = geminiOptions
        self.anthropicOptions = anthropicOptions
    }

    enum CodingKeys: String, CodingKey {
        case id
        case modelID
        case messages
        case sampling
        case webSearchOptions
        case structuredOutput
        case hostedTools
        case openAIOptions
        case allowsTools
        case availableTools
        case vaultContextIDs
        case executionContext
        case openAIResponseOptions
        case geminiOptions
        case anthropicOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        modelID = try container.decode(ModelID.self, forKey: .modelID)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        sampling = try container.decodeIfPresent(ChatSampling.self, forKey: .sampling) ?? .init()
        webSearchOptions = try container.decodeIfPresent(CloudWebSearchOptions.self, forKey: .webSearchOptions)
        structuredOutput = try container.decodeIfPresent(StructuredOutputFormat.self, forKey: .structuredOutput) ?? .text
        hostedTools = try container.decodeIfPresent([HostedToolConfiguration].self, forKey: .hostedTools) ?? []
        openAIOptions = try container.decodeIfPresent(OpenAIResponsesRequestOptions.self, forKey: .openAIOptions)
        allowsTools = try container.decodeIfPresent(Bool.self, forKey: .allowsTools) ?? false
        availableTools = try container.decodeIfPresent([AnyToolSpec].self, forKey: .availableTools) ?? []
        vaultContextIDs = try container.decodeIfPresent([UUID].self, forKey: .vaultContextIDs) ?? []
        executionContext = try container.decodeIfPresent(ExecutionContext.self, forKey: .executionContext) ?? .chat
        openAIResponseOptions = try container.decodeIfPresent(OpenAIResponseRequestOptions.self, forKey: .openAIResponseOptions)
        geminiOptions = try container.decodeIfPresent(GeminiRequestOptions.self, forKey: .geminiOptions)
        anthropicOptions = try container.decodeIfPresent(AnthropicRequestOptions.self, forKey: .anthropicOptions)
    }

    public func replacing(
        messages: [ChatMessage]? = nil,
        allowsTools: Bool? = nil,
        availableTools: [AnyToolSpec]? = nil,
        executionContext: ExecutionContext? = nil
    ) -> ChatRequest {
        ChatRequest(
            id: id,
            modelID: modelID,
            messages: messages ?? self.messages,
            sampling: sampling,
            webSearchOptions: webSearchOptions,
            structuredOutput: structuredOutput,
            hostedTools: hostedTools,
            openAIOptions: openAIOptions,
            allowsTools: allowsTools ?? self.allowsTools,
            availableTools: availableTools ?? self.availableTools,
            vaultContextIDs: vaultContextIDs,
            executionContext: executionContext ?? self.executionContext,
            openAIResponseOptions: openAIResponseOptions,
            geminiOptions: geminiOptions,
            anthropicOptions: anthropicOptions
        )
    }

    public var hasAgentOnlyHostedTools: Bool {
        hostedTools.contains { $0.requiresAgentExecution }
            || openAIResponseOptions?.hostedTools.contains { $0.requiresAgentExecution } == true
            || anthropicOptions?.hasAgentOnlyHostedTools == true
    }

    public var hasApprovalGatedHostedTools: Bool {
        hostedTools.contains { $0.requiresApproval }
            || openAIResponseOptions?.hostedTools.contains { $0.requiresApproval } == true
            || anthropicOptions?.hasApprovalGatedHostedTools == true
    }

    public func hostedToolsAreAllowedForExecutionContext() -> Bool {
        !hasAgentOnlyHostedTools || executionContext == .agent
    }

    public var resolvedAnthropicOptions: AnthropicRequestOptions {
        if let anthropicOptions {
            return anthropicOptions
        }
        return AnthropicRequestOptions(
            thinking: AnthropicThinkingOptions(effort: sampling.anthropicEffort)
        )
    }
}

public extension OpenAIHostedToolRequest {
    var requiresAgentExecution: Bool {
        switch kind {
        case .computerUse, .mcp, .textEditor, .bash:
            return true
        case .webSearch, .webFetch, .fileSearch, .codeInterpreter, .imageGeneration, .toolSearch, .custom:
            return false
        }
    }

    var requiresApproval: Bool {
        switch kind {
        case .computerUse, .textEditor, .bash:
            return true
        case .mcp:
            return configuration?.objectValue?["require_approval"]?.stringValue != "never"
        case .webSearch, .webFetch, .fileSearch, .codeInterpreter, .imageGeneration, .toolSearch, .custom:
            return false
        }
    }
}

public struct TokenDelta: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case token
        case toolCall
        case finish
        case metrics
    }

    public var kind: Kind
    public var text: String
    public var tokenCount: Int
    public var metadata: [String: String]

    public init(
        kind: Kind = .token,
        text: String,
        tokenCount: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.text = text
        self.tokenCount = tokenCount
        self.metadata = metadata
    }
}

public struct ToolCallDelta: Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var argumentsFragment: String
    public var isComplete: Bool

    public init(
        id: String,
        name: String,
        argumentsFragment: String = "",
        isComplete: Bool = false
    ) {
        self.id = id
        self.name = name
        self.argumentsFragment = argumentsFragment
        self.isComplete = isComplete
    }
}

public enum InferenceFinishReason: String, Hashable, Codable, Sendable {
    case stop
    case length
    case cancelled
    case toolCall
    case error
}

public struct InferenceFinish: Hashable, Codable, Sendable {
    public var reason: InferenceFinishReason
    public var message: String?
    public var providerMetadata: [String: String]

    public init(reason: InferenceFinishReason, message: String? = nil, providerMetadata: [String: String] = [:]) {
        self.reason = reason
        self.message = message
        self.providerMetadata = providerMetadata
    }

    enum CodingKeys: String, CodingKey {
        case reason
        case message
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decode(InferenceFinishReason.self, forKey: .reason)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        providerMetadata = try container.decodeIfPresent([String: String].self, forKey: .providerMetadata) ?? [:]
    }
}

public struct InferenceMetrics: Hashable, Codable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var promptTokensPerSecond: Double?
    public var completionTokensPerSecond: Double?
    public var latencyMilliseconds: Int?

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        promptTokensPerSecond: Double? = nil,
        completionTokensPerSecond: Double? = nil,
        latencyMilliseconds: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.promptTokensPerSecond = promptTokensPerSecond
        self.completionTokensPerSecond = completionTokensPerSecond
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public struct InferenceStreamFailure: Hashable, Codable, Sendable {
    public var code: String
    public var message: String
    public var recoverable: Bool

    public init(code: String, message: String, recoverable: Bool = false) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
    }
}

public enum InferenceStreamEvent: Hashable, Codable, Sendable {
    case token(TokenDelta)
    case toolCall(ToolCallDelta)
    case finish(InferenceFinish)
    case metrics(InferenceMetrics)
    case failure(InferenceStreamFailure)
}

public struct EmbeddingRequest: Hashable, Codable, Sendable {
    public var modelID: ModelID
    public var inputs: [String]
    public var normalize: Bool
    public var dimensions: Int?
    public var inputType: EmbeddingInputType?

    public init(
        modelID: ModelID,
        inputs: [String],
        normalize: Bool = true,
        dimensions: Int? = nil,
        inputType: EmbeddingInputType? = nil
    ) {
        self.modelID = modelID
        self.inputs = inputs
        self.normalize = normalize
        self.dimensions = dimensions
        self.inputType = inputType
    }
}

public enum EmbeddingInputType: String, Hashable, Codable, Sendable, CaseIterable {
    case document
    case query
}

public struct EmbeddingResult: Hashable, Codable, Sendable {
    public var modelID: ModelID
    public var vectors: [[Float]]
    public var dimensions: Int

    public init(modelID: ModelID, vectors: [[Float]]) {
        self.modelID = modelID
        self.vectors = vectors
        self.dimensions = vectors.first?.count ?? 0
    }
}

public enum InferenceError: Error, Equatable, Sendable {
    case providerUnavailable(ProviderID)
    case modelNotLoaded(ModelID)
    case unsupportedCapability(String)
    case cloudNotAllowed
    case invalidRequest(String)
    case localRuntimeFailure(String)
    case cancelled
}

extension InferenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .providerUnavailable(providerID):
            "Provider \(providerID.rawValue) is unavailable."
        case let .modelNotLoaded(modelID):
            "Model \(modelID.rawValue) is not loaded."
        case let .unsupportedCapability(message):
            message
        case .cloudNotAllowed:
            "Cloud inference is not allowed for this request."
        case let .invalidRequest(message):
            message
        case let .localRuntimeFailure(diagnostic):
            "Local MLX runtime failure: \(diagnostic)"
        case .cancelled:
            "The inference request was cancelled."
        }
    }
}

public protocol InferenceProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<TokenDelta, Error>
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult
}

public extension InferenceProvider {
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<TokenDelta, Error> {
        let eventStream = try await streamEvents(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in eventStream {
                        switch event {
                        case let .token(delta):
                            continuation.yield(delta)
                        case let .toolCall(delta):
                            continuation.yield(
                                TokenDelta(
                                    kind: .toolCall,
                                    text: delta.argumentsFragment,
                                    tokenCount: 0,
                                    metadata: [
                                        "id": delta.id,
                                        "name": delta.name,
                                        "complete": String(delta.isComplete),
                                    ]
                                )
                            )
                        case let .finish(finish):
                            var metadata = finish.providerMetadata
                            metadata["reason"] = finish.reason.rawValue
                            continuation.yield(
                                TokenDelta(
                                    kind: .finish,
                                    text: finish.message ?? "",
                                    metadata: metadata
                                )
                            )
                            continuation.finish()
                            return
                        case let .metrics(metrics):
                            continuation.yield(
                                TokenDelta(
                                    kind: .metrics,
                                    text: "",
                                    tokenCount: metrics.completionTokens,
                                    metadata: [
                                        "promptTokens": String(metrics.promptTokens),
                                        "completionTokens": String(metrics.completionTokens),
                                    ]
                                )
                            )
                        case let .failure(failure):
                            continuation.yield(
                                TokenDelta(
                                    kind: .finish,
                                    text: failure.message,
                                    metadata: [
                                        "reason": InferenceFinishReason.error.rawValue,
                                        "code": failure.code,
                                        "recoverable": String(failure.recoverable),
                                    ]
                                )
                            )
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
