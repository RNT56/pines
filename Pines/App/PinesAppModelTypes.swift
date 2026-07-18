import Foundation
import SwiftUI
import PinesCore

extension ModelInstall {
    func enriched(with preflight: ModelPreflightResult) -> ModelInstall {
        var copy = self
        if !preflight.modalities.isEmpty {
            copy.modalities = preflight.modalities
        }
        copy.verification = CuratedModelManifest.default.contains(repository: repository) ? .verified : preflight.verification
        if copy.state == .remote, preflight.verification == .unsupported {
            copy.state = .unsupported
        }
        if preflight.estimatedBytes > 0 {
            copy.estimatedBytes = preflight.estimatedBytes
        }
        copy.parameterCount = preflight.parameterCount ?? copy.parameterCount
        copy.license = preflight.license ?? copy.license
        copy.modelType = preflight.modelType ?? copy.modelType
        copy.textConfigModelType = preflight.textConfigModelType ?? copy.textConfigModelType
        copy.processorClass = preflight.processorClass ?? copy.processorClass
        copy.keyHeadDimension = preflight.keyHeadDimension ?? copy.keyHeadDimension
        copy.valueHeadDimension = preflight.valueHeadDimension ?? copy.valueHeadDimension
        copy.routedExperts = preflight.routedExperts ?? copy.routedExperts
        copy.expertsPerToken = preflight.expertsPerToken ?? copy.expertsPerToken
        copy.cacheTopology = preflight.cacheTopology
        copy.turboQuantFamilySupport = preflight.turboQuantFamilySupport
        return copy
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension String {
    var pinesNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum PinesGeminiMediaTransport: String, Codable, Hashable, Sendable {
    case inlineData
    case fileData
}

struct PinesGeminiMediaDisposition: Codable, Hashable, Sendable {
    static let maxInlineImageBytes: Int64 = 20 * 1024 * 1024
    static let maxInlineFileBytes: Int64 = 50 * 1024 * 1024

    var transport: PinesGeminiMediaTransport
    var contentType: String
    var byteCount: Int64?
    var inlineLimitBytes: Int64
    var reason: String

    var shouldUploadToFiles: Bool {
        transport == .fileData
    }

    static func decision(
        contentType: String,
        byteCount: Int64?,
        hasProviderURI: Bool = false
    ) -> PinesGeminiMediaDisposition {
        let normalizedContentType = contentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let limit = normalizedContentType.hasPrefix("image/") ? maxInlineImageBytes : maxInlineFileBytes
        if hasProviderURI {
            return PinesGeminiMediaDisposition(
                transport: .fileData,
                contentType: normalizedContentType,
                byteCount: byteCount,
                inlineLimitBytes: limit,
                reason: "provider_uri"
            )
        }
        guard let byteCount else {
            return PinesGeminiMediaDisposition(
                transport: .fileData,
                contentType: normalizedContentType,
                byteCount: nil,
                inlineLimitBytes: limit,
                reason: "unknown_size"
            )
        }
        let transport: PinesGeminiMediaTransport = byteCount <= limit ? .inlineData : .fileData
        return PinesGeminiMediaDisposition(
            transport: transport,
            contentType: normalizedContentType,
            byteCount: byteCount,
            inlineLimitBytes: limit,
            reason: transport == .inlineData ? "within_inline_limit" : "exceeds_inline_limit"
        )
    }

    static func decision(for attachment: ChatAttachment) -> PinesGeminiMediaDisposition {
        decision(
            contentType: attachment.normalizedContentType,
            byteCount: attachment.byteCount > 0 ? Int64(attachment.byteCount) : nil,
            hasProviderURI: attachment.localURL?.isFileURL == false
        )
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values = [T]()
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }

    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var values = [T]()
        values.reserveCapacity(count)
        for element in self {
            if let value = await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}

extension RelativeDateTimeFormatter {
    static func shortLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PinesThreadPreview: Identifiable, Hashable {
    let id: UUID
    let projectID: UUID?
    let title: String
    let modelName: String
    let modelID: ModelID
    let providerID: ProviderID?
    let lastMessage: String
    let messages: [ChatMessage]
    let status: PinesThreadStatus
    let isPinned: Bool
    let updatedLabel: String
    let tokenCount: Int

}

struct PinesProjectPreview: Identifiable, Hashable {
    let id: UUID
    let name: String
    let vaultEnabled: Bool
    let updatedLabel: String
}

struct ModelPickerSection: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let models: [ModelPickerOption]
}

struct ModelPickerOption: Identifiable, Hashable {
    var id: String { "\(providerID.rawValue)::\(modelID.rawValue)" }
    let providerID: ProviderID
    let providerName: String
    let providerKind: CloudProviderKind?
    let modelID: ModelID
    let displayName: String
    let isLocal: Bool
    let rank: Double
    var capabilities: ProviderCapabilities? = nil
    var modelMetadata: CloudProviderModelMetadata? = nil
}

struct ChatQuickSettingsAvailability: Hashable {
    let providerID: ProviderID
    let modelID: ModelID
    let openAIReasoningEfforts: [OpenAIReasoningEffort]
    let supportsOpenAITextVerbosity: Bool
    let anthropicEfforts: [AnthropicEffort]
    let anthropicThinkingModes: [AnthropicThinkingMode]
    let geminiThinkingLevels: [GeminiThinkingLevel]
    let cloudWebSearchModes: [CloudWebSearchMode]

    var isEmpty: Bool {
        openAIReasoningEfforts.isEmpty
            && !supportsOpenAITextVerbosity
            && anthropicEfforts.isEmpty
            && anthropicThinkingModes.isEmpty
            && geminiThinkingLevels.isEmpty
            && cloudWebSearchModes.isEmpty
    }
}

enum PinesThreadStatus: String, Hashable {
    case local
    case streaming
    case archived

    var title: String {
        switch self {
        case .local:
            "Ready"
        case .streaming:
            "Live"
        case .archived:
            "Archived"
        }
    }

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .local:
            theme.colors.success
        case .streaming:
            theme.colors.info
        case .archived:
            theme.colors.tertiaryText
        }
    }
}

struct MCPSamplingResultReview: Identifiable, Hashable {
    let id = UUID()
    let serverID: MCPServerID
    let result: MCPSamplingResult
    let summary: String
}

struct CloudVaultEmbeddingApprovalRequest: Identifiable, Hashable {
    let id = UUID()
    let profile: VaultEmbeddingProfile
    let reason: String
}

struct MCPModelPreferenceProfile: Hashable {
    var hints: [String]
    var costPriority: Double
    var speedPriority: Double
    var intelligencePriority: Double

    init(json: JSONValue?) {
        let object = json?.objectValue ?? [:]
        hints = Self.hints(from: object["hints"])
        costPriority = Self.priority(from: object["costPriority"])
        speedPriority = Self.priority(from: object["speedPriority"])
        intelligencePriority = Self.priority(from: object["intelligencePriority"])
    }

    private static func hints(from value: JSONValue?) -> [String] {
        guard case let .array(items)? = value else { return [] }
        return items.compactMap { item in
            switch item {
            case let .string(name):
                return name
            case let .object(object):
                if case let .string(name)? = object["name"] {
                    return name
                }
                return nil
            default:
                return nil
            }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func priority(from value: JSONValue?) -> Double {
        guard case let .number(priority)? = value else { return 0 }
        return min(max(priority, 0), 1)
    }
}

struct PinesModelPreview: Identifiable, Hashable, Sendable {
    var id: String { install.repository.lowercased() }

    let install: ModelInstall
    let runtimeProfile: RuntimeProfile
    let name: String
    let family: String
    let footprint: String
    let contextWindow: String
    let runtime: String
    let status: PinesModelStatus
    let capabilities: [String]
    let readiness: Double
    let downloadProgress: ModelDownloadProgress?
    let compatibilityWarnings: [String]
    let runtimeProfileEvidence: RuntimeProfileEvidence?
    let runtimeCompatibilityState: RuntimeCompatibilityState
    let compatibilityExplanation: PinesRuntimeCompatibilityExplanation
}

struct PinesRuntimeCompatibilityExplanation: Hashable, Sendable {
    struct Fact: Identifiable, Hashable, Sendable {
        var id: String { label }
        let label: String
        let value: String
    }

    let headline: String
    let summary: String
    let claimBasis: String
    let facts: [Fact]
    let nextAction: String?
}

extension PinesModelPreview {
    var isDownloadActive: Bool {
        downloadProgress?.isPinesDownloadActive == true || install.state == .downloading || status == .indexing
    }
}

extension ModelDownloadProgress {
    var isPinesDownloadActive: Bool {
        switch status {
        case .queued, .downloading, .verifying, .installing:
            true
        case .installed, .failed, .cancelled:
            false
        }
    }
}

enum PinesModelStatus: String, Hashable, Sendable {
    case ready
    case available
    case indexing
    case failed
    case unsupported

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .available:
            "Available"
        case .indexing:
            "Downloading"
        case .failed:
            "Failed"
        case .unsupported:
            "Unsupported"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.seal.fill"
        case .available:
            "arrow.down.circle.fill"
        case .indexing:
            "waveform.path.ecg"
        case .failed:
            "exclamationmark.triangle.fill"
        case .unsupported:
            "slash.circle.fill"
        }
    }
}

struct PinesVaultItemPreview: Identifiable, Hashable {
    let id: UUID
    let projectID: UUID?
    let title: String
    let kind: PinesVaultKind
    let detail: String
    let updatedLabel: String
    let sensitivity: PinesVaultSensitivity
    let linkedThreads: Int
    let activeProfileEmbeddedChunks: Int
    let activeProfileTotalChunks: Int
    let sourceContentType: String?
    let sourceRevision: String
}

struct PinesVaultItemDetail: Identifiable, Hashable {
    let id: UUID
    let chunks: [VaultChunk]
    let totalChunkCount: Int
    let chunkUTF8ByteCount: Int64
    let linkedThreads: Int
    let activeProfileEmbeddedChunks: Int
    let sourceContentType: String?
    let sourceRevision: String
    let sourceData: Data?

    var hasMoreChunks: Bool {
        chunks.count < totalChunkCount
    }
}

struct PinesProviderFilePreview: Identifiable, Hashable {
    let id: String
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let title: String
    let detail: String
    let purpose: String
    let status: String
    let byteCountLabel: String
    let createdLabel: String
    let expiresLabel: String?
}

struct PinesProviderArtifactPreview: Identifiable, Hashable {
    let id: String
    let providerID: ProviderID?
    let providerKind: CloudProviderKind
    let title: String
    let detail: String
    let kind: String
    let status: String
    let byteCountLabel: String?
    let createdLabel: String
}

struct PinesProviderCachePreview: Identifiable, Hashable {
    let id: String
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let title: String
    let detail: String
    let kind: String
    let status: String
    let usageLabel: String
    let createdLabel: String
    let expiresLabel: String?
}

struct PinesProviderBatchPreview: Identifiable, Hashable {
    let id: String
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let title: String
    let endpoint: String
    let status: String
    let fileSummary: String
    let createdLabel: String
    let completedLabel: String?
}

struct PinesProviderLiveSessionPreview: Identifiable, Hashable {
    let id: String
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let title: String
    let modelID: ModelID
    let status: String
    let modalitySummary: String
    let createdLabel: String
    let expiresLabel: String?
}

struct PinesProviderStructuredOutputPreview: Identifiable, Hashable {
    let id: UUID
    let providerID: ProviderID?
    let providerKind: CloudProviderKind
    let title: String
    let detail: String
    let status: String
    let validationSummary: String
    let createdLabel: String
}

struct PinesProviderModelCapabilityPreview: Identifiable, Hashable {
    let id: String
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let modelID: ModelID
    let title: String
    let detail: String
    let capabilitySummary: String
    let fetchedLabel: String
    let expiresLabel: String?
}

struct PinesProviderResearchRunPreview: Identifiable, Hashable {
    let id: String
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let title: String
    let modelID: ModelID
    let status: String
    let detail: String
    let activitySummary: String
    let updatedLabel: String
}

struct PinesProviderDeepResearchRequest: Hashable, Sendable {
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let modelID: ModelID
    let title: String
    let prompt: String
    let depth: String
    let reportFormat: String
    let vectorStoreIDs: [String]
    let providerFileIDs: [String]
    let metadata: [String: String]

    init(
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        modelID: ModelID,
        title: String,
        prompt: String,
        depth: String,
        reportFormat: String,
        vectorStoreIDs: [String],
        providerFileIDs: [String],
        metadata: [String: String] = [:]
    ) {
        self.providerID = providerID
        self.providerKind = providerKind
        self.modelID = modelID
        self.title = title
        self.prompt = prompt
        self.depth = depth
        self.reportFormat = reportFormat
        self.vectorStoreIDs = vectorStoreIDs
        self.providerFileIDs = providerFileIDs
        self.metadata = metadata
    }
}

struct PinesProviderRealtimeSessionRequest: Hashable, Sendable {
    let providerID: ProviderID
    let providerKind: CloudProviderKind
    let modelID: ModelID
    let modalities: [String]
    let session: JSONValue
}

enum PinesVaultKind: String, Hashable {
    case note
    case document
    case image
    case key

    var title: String {
        switch self {
        case .note:
            "Note"
        case .document:
            "Document"
        case .image:
            "Image"
        case .key:
            "Key"
        }
    }

    var systemImage: String {
        switch self {
        case .note:
            "note.text"
        case .document:
            "doc.text"
        case .image:
            "photo"
        case .key:
            "key.fill"
        }
    }
}

enum PinesVaultSensitivity: String, Hashable {
    case local
    case privateCloud
    case locked

    var title: String {
        switch self {
        case .local:
            "On Device"
        case .privateCloud:
            "Private Cloud"
        case .locked:
            "Locked"
        }
    }

    var systemImage: String {
        switch self {
        case .local:
            "iphone"
        case .privateCloud:
            "icloud.fill"
        case .locked:
            "lock.fill"
        }
    }
}

enum PinesSettingsDestination: String, CaseIterable, Hashable {
    case appearance
    case aiModels
    case cloudProviders
    case privacyData
    case toolsIntegrations
    case diagnostics
}

struct PinesSettingsSection: Identifiable, Hashable {
    let id: UUID
    let destination: PinesSettingsDestination
    let title: String
    let subtitle: String
    let systemImage: String

    var isSupportDestination: Bool {
        destination == .diagnostics
    }
}

enum PinesStaticSettings {
    static let sections: [PinesSettingsSection] = [
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20000")!,
            destination: .appearance,
            title: "Appearance",
            subtitle: "Theme, interface appearance, and feedback.",
            systemImage: "paintpalette"
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20005")!,
            destination: .aiModels,
            title: "AI & Models",
            subtitle: "Default routing, response limits, and model access.",
            systemImage: "cpu"
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20001")!,
            destination: .cloudProviders,
            title: "Cloud & Providers",
            subtitle: "Pro Cloud, personal API providers, routing, and usage.",
            systemImage: "cloud"
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20002")!,
            destination: .privacyData,
            title: "Privacy & Data",
            subtitle: "App lock, local storage, private sync, and deletion.",
            systemImage: "lock.shield"
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20003")!,
            destination: .toolsIntegrations,
            title: "Tools & Integrations",
            subtitle: "Web search, MCP servers, tools, and context sources.",
            systemImage: "wrench.and.screwdriver"
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20004")!,
            destination: .diagnostics,
            title: "Help & Diagnostics",
            subtitle: "Health, runtime details, and the local privacy log.",
            systemImage: "stethoscope"
        )
    ]

}
