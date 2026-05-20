import Foundation
import PinesCore
import SwiftUI

enum ArtifactsWorkspaceMode: String, CaseIterable, Identifiable, Hashable {
    case library
    case generate
    case research
    case storage
    case jobs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .generate: "Generate"
        case .research: "Research"
        case .storage: "Storage"
        case .jobs: "Jobs"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack"
        case .generate: "sparkles"
        case .research: "doc.text.magnifyingglass"
        case .storage: "externaldrive.badge.icloud"
        case .jobs: "tray.full"
        }
    }

    var subtitle: String {
        switch self {
        case .library: "Artifacts and structured outputs"
        case .generate: "Images, video, and speech"
        case .research: "Deep research workspace"
        case .storage: "Files, vector stores, caches"
        case .jobs: "Batches and sessions"
        }
    }
}

enum ArtifactsProviderScope: Hashable, Identifiable {
    case all
    case provider(ProviderID)

    var id: String {
        switch self {
        case .all: "all"
        case .provider(let id): "provider-\(id.rawValue)"
        }
    }

    func title(providers: [CloudProviderConfiguration]) -> String {
        switch self {
        case .all:
            "All providers"
        case .provider(let id):
            providers.first(where: { $0.id == id })?.displayName ?? id.rawValue
        }
    }

    func includes(_ providerID: ProviderID?) -> Bool {
        switch self {
        case .all:
            true
        case .provider(let selected):
            providerID == selected
        }
    }
}

enum ArtifactsSort: String, CaseIterable, Identifiable, Hashable {
    case newest
    case oldest
    case provider
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .provider: "Provider"
        case .kind: "Kind"
        }
    }
}

struct ArtifactsResourceFilter: Hashable {
    var query = ""
    var providerScope: ArtifactsProviderScope = .all
    var kind: String?
    var sort: ArtifactsSort = .newest

    init(
        query: String = "",
        providerScope: ArtifactsProviderScope = .all,
        kind: String? = nil,
        sort: ArtifactsSort = .newest
    ) {
        self.query = query
        self.providerScope = providerScope
        self.kind = kind
        self.sort = sort
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ArtifactsSelection: Hashable, Identifiable {
    case artifact(String)
    case file(String)
    case cache(String)
    case batch(String)
    case research(String)
    case liveSession(String)
    case structuredOutput(UUID)
    case capability(String)

    var id: String {
        switch self {
        case .artifact(let id): "artifact-\(id)"
        case .file(let id): "file-\(id)"
        case .cache(let id): "cache-\(id)"
        case .batch(let id): "batch-\(id)"
        case .research(let id): "research-\(id)"
        case .liveSession(let id): "live-\(id)"
        case .structuredOutput(let id): "structured-\(id.uuidString)"
        case .capability(let id): "capability-\(id)"
        }
    }
}

enum ArtifactsRetentionLabel: Hashable {
    case providerHosted
    case localCopy
    case remoteLink
    case vaultImportCandidate
    case localRecord

    var title: String {
        switch self {
        case .providerHosted: "Provider-hosted"
        case .localCopy: "Local copy"
        case .remoteLink: "Remote link"
        case .vaultImportCandidate: "Vault-importable"
        case .localRecord: "Local record"
        }
    }

    var tone: PinesCloudStatusTone {
        switch self {
        case .providerHosted: .warning
        case .localCopy, .vaultImportCandidate: .success
        case .remoteLink: .info
        case .localRecord: .neutral
        }
    }
}

struct ArtifactsMetricCounts: Hashable {
    var files: Int
    var artifacts: Int
    var structuredOutputs: Int
    var caches: Int
    var batches: Int
    var researchRuns: Int
    var liveSessions: Int
    var capabilities: Int

    var providerResources: Int {
        files + artifacts + structuredOutputs + caches + batches + researchRuns + liveSessions + capabilities
    }
}

struct ArtifactsResourceSummary: Identifiable, Hashable {
    var id: String { selection.id }
    let selection: ArtifactsSelection
    let title: String
    let detail: String
    let providerID: ProviderID?
    let providerKind: CloudProviderKind
    let kind: String
    let status: PinesCloudStatus
    let secondaryStatus: PinesCloudStatus?
    let retention: ArtifactsRetentionLabel
    let createdAt: Date?
    let systemImage: String
    let metricItems: [PinesMetricPillGroup.Item]
}

enum ArtifactsMediaKind: String, CaseIterable, Identifiable, Hashable {
    case image
    case video
    case speech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .speech: "Speech"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .speech: "waveform"
        }
    }
}

struct ArtifactsMediaModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let isFromProviderCapability: Bool

    init(id: String, title: String? = nil, detail: String, isFromProviderCapability: Bool) {
        self.id = id
        self.title = title ?? id
        self.detail = detail
        self.isFromProviderCapability = isFromProviderCapability
    }
}

struct ArtifactsResearchModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let isFromProviderCapability: Bool

    init(id: String, title: String? = nil, detail: String, isFromProviderCapability: Bool) {
        self.id = id
        self.title = title ?? id
        self.detail = detail
        self.isFromProviderCapability = isFromProviderCapability
    }
}

struct ArtifactsResearchTimelineEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let tone: PinesCloudStatusTone
}

struct ArtifactsResearchSource: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let url: String?
    let systemImage: String
    let tone: PinesCloudStatusTone
}

enum ArtifactsWorkspaceDeriver {
    static func providerScopes(from providers: [CloudProviderConfiguration]) -> [ArtifactsProviderScope] {
        [.all] + providers
            .filter { [.openAI, .anthropic, .gemini].contains($0.kind) }
            .map { .provider($0.id) }
    }

    @MainActor
    static func counts(state: PinesProviderLifecycleState, scope: ArtifactsProviderScope = .all) -> ArtifactsMetricCounts {
        ArtifactsMetricCounts(
            files: state.providerFiles.filter { scope.includes($0.providerID) }.count,
            artifacts: state.providerArtifacts.filter { scope.includes($0.providerID) }.count,
            structuredOutputs: state.providerStructuredOutputs.filter { scope.includes($0.providerID) }.count,
            caches: state.providerCaches.filter { scope.includes($0.providerID) }.count,
            batches: state.providerBatches.filter { scope.includes($0.providerID) }.count,
            researchRuns: state.providerResearchRuns.filter { scope.includes($0.providerID) }.count,
            liveSessions: state.providerLiveSessions.filter { scope.includes($0.providerID) }.count,
            capabilities: state.providerModelCapabilities.filter { scope.includes($0.providerID) }.count
        )
    }

    static func artifactSummaries(artifacts: [ProviderArtifactRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        artifacts
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { filter.kind == nil || $0.kind.caseInsensitiveCompare(filter.kind ?? "") == .orderedSame }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { artifact in
                ArtifactsResourceSummary(
                    selection: .artifact(artifact.id),
                    title: artifact.fileName ?? artifact.kind.readableArtifactKind,
                    detail: artifact.responseID ?? artifact.toolCallID ?? artifact.providerFileID ?? artifact.id,
                    providerID: artifact.providerID,
                    providerKind: artifact.providerKind,
                    kind: artifact.kind,
                    status: artifact.responseID == nil ? .custom("Stored", .success) : .custom("Linked", .accent),
                    secondaryStatus: artifact.byteCount.map { .custom(providerByteCountLabel($0), .neutral) },
                    retention: artifact.retentionLabel,
                    createdAt: artifact.createdAt,
                    systemImage: artifact.kind.providerArtifactSystemImage,
                    metricItems: [
                        .init("Kind", value: artifact.kind.readableArtifactKind, systemImage: "tag", tone: .info),
                        .init("Provider", value: artifact.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .warning),
                        .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: artifact.createdAt), systemImage: "clock", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func fileSummaries(files: [ProviderFileRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        files
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { file in
                ArtifactsResourceSummary(
                    selection: .file(file.id),
                    title: file.fileName,
                    detail: "\(file.providerID.rawValue) - \(file.purpose)",
                    providerID: file.providerID,
                    providerKind: file.providerKind,
                    kind: file.purpose,
                    status: file.status.providerCloudStatus,
                    secondaryStatus: file.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
                    retention: .providerHosted,
                    createdAt: file.createdAt,
                    systemImage: "doc",
                    metricItems: [
                        .init("Purpose", value: file.purpose, systemImage: "tag", tone: .info),
                        .init("Size", value: providerByteCountLabel(file.byteCount), systemImage: "internaldrive", tone: .neutral),
                        .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: file.createdAt), systemImage: "clock", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func cacheSummaries(caches: [ProviderCacheRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        caches
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { cache in
                ArtifactsResourceSummary(
                    selection: .cache(cache.id),
                    title: cache.name ?? cache.id,
                    detail: cache.modelID?.rawValue ?? cache.providerID.rawValue,
                    providerID: cache.providerID,
                    providerKind: cache.providerKind,
                    kind: cache.kind,
                    status: cache.status.providerCloudStatus,
                    secondaryStatus: cache.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
                    retention: .providerHosted,
                    createdAt: cache.createdAt,
                    systemImage: cache.kind == "cached_content" ? "externaldrive.badge.icloud" : "square.stack.3d.up",
                    metricItems: [
                        .init("Kind", value: cache.kind.readableArtifactKind, systemImage: "tag", tone: .info),
                        .init("Usage", value: providerByteCountLabel(cache.usageBytes), systemImage: "number", tone: .neutral),
                        .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: cache.createdAt), systemImage: "clock", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func batchSummaries(batches: [ProviderBatchRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        batches
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { batch in
                ArtifactsResourceSummary(
                    selection: .batch(batch.id),
                    title: batch.endpoint,
                    detail: batch.fileSummary,
                    providerID: batch.providerID,
                    providerKind: batch.providerKind,
                    kind: "batch",
                    status: batch.status.providerCloudStatus,
                    secondaryStatus: batch.completedAt.map { .custom(RelativeDateTimeFormatter.shortLabel(for: $0), .success) },
                    retention: .providerHosted,
                    createdAt: batch.createdAt,
                    systemImage: "tray.full",
                    metricItems: [
                        .init("Endpoint", value: batch.endpoint, systemImage: "arrow.left.arrow.right", tone: .info),
                        .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: batch.createdAt), systemImage: "clock", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func researchSummaries(runs: [ProviderResearchRunRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        runs
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { run in
                ArtifactsResourceSummary(
                    selection: .research(run.id),
                    title: run.title,
                    detail: run.prompt,
                    providerID: run.providerID,
                    providerKind: run.providerKind,
                    kind: "research",
                    status: run.status.providerCloudStatus,
                    secondaryStatus: .custom(RelativeDateTimeFormatter.shortLabel(for: run.updatedAt), .neutral),
                    retention: .providerHosted,
                    createdAt: run.createdAt,
                    systemImage: "doc.text.magnifyingglass",
                    metricItems: [
                        .init("Model", value: run.modelID.rawValue, systemImage: "cpu", tone: .info),
                        .init("Sources", value: "\(run.citationCount)", systemImage: "quote.bubble", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func liveSessionSummaries(sessions: [ProviderLiveSessionRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        sessions
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { session in
                ArtifactsResourceSummary(
                    selection: .liveSession(session.id),
                    title: session.id,
                    detail: session.modalities.joined(separator: ", "),
                    providerID: session.providerID,
                    providerKind: session.providerKind,
                    kind: "realtime",
                    status: session.status.providerCloudStatus,
                    secondaryStatus: session.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
                    retention: .providerHosted,
                    createdAt: session.createdAt,
                    systemImage: "dot.radiowaves.left.and.right",
                    metricItems: [
                        .init("Model", value: session.modelID.rawValue, systemImage: "cpu", tone: .info),
                        .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: session.createdAt), systemImage: "clock", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func structuredOutputSummaries(outputs: [ProviderStructuredOutputRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        outputs
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { output in
                ArtifactsResourceSummary(
                    selection: .structuredOutput(output.id),
                    title: output.schemaName ?? "Structured output",
                    detail: output.responseID ?? output.messageID?.uuidString ?? output.id.uuidString,
                    providerID: output.providerID,
                    providerKind: output.providerKind,
                    kind: "structured_output",
                    status: output.status.providerCloudStatus,
                    secondaryStatus: .custom(output.validationErrors.isEmpty ? "Valid" : "\(output.validationErrors.count) issues", output.validationErrors.isEmpty ? .success : .warning),
                    retention: .localRecord,
                    createdAt: output.createdAt,
                    systemImage: "curlybraces.square",
                    metricItems: [
                        .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: output.createdAt), systemImage: "clock", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func capabilitySummaries(capabilities: [ProviderModelCapabilityRecord], filter: ArtifactsResourceFilter) -> [ArtifactsResourceSummary] {
        capabilities
            .filter { filter.providerScope.includes($0.providerID) }
            .filter { matches($0.searchText, query: filter.trimmedQuery) }
            .map { capability in
                ArtifactsResourceSummary(
                    selection: .capability(capability.id),
                    title: capability.modelID.rawValue,
                    detail: capability.capabilities.artifactsSummary,
                    providerID: capability.providerID,
                    providerKind: capability.providerKind,
                    kind: "capability",
                    status: .custom("Metadata", .success),
                    secondaryStatus: capability.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
                    retention: .localRecord,
                    createdAt: capability.fetchedAt,
                    systemImage: "cpu",
                    metricItems: [
                        .init("Capabilities", value: capability.capabilities.artifactsSummary, systemImage: "checklist", tone: .info),
                        .init("Fetched", value: RelativeDateTimeFormatter.shortLabel(for: capability.fetchedAt), systemImage: "clock", tone: .neutral),
                    ]
                )
            }
            .sorted(by: sorter(filter.sort))
    }

    static func mediaModelOptions(
        provider: CloudProviderConfiguration?,
        kind: ArtifactsMediaKind,
        capabilities: [ProviderModelCapabilityRecord]
    ) -> [ArtifactsMediaModelOption] {
        guard let provider else { return [] }

        let capabilityOptions = capabilities
            .filter { $0.providerID == provider.id }
            .filter { capability in
                switch kind {
                case .image:
                    capability.capabilities.generatedImages
                case .video:
                    capability.capabilities.generatedVideo || capability.capabilities.videoOutputs
                case .speech:
                    capability.capabilities.generatedAudio || capability.capabilities.audioOutputs
                }
            }
            .map {
                ArtifactsMediaModelOption(
                    id: $0.modelID.rawValue,
                    detail: $0.capabilities.artifactsSummary,
                    isFromProviderCapability: true
                )
            }

        let curatedOptions = curatedMediaModels(providerKind: provider.kind, kind: kind)
        return stableMergedMediaModels(capabilityOptions + curatedOptions)
    }

    static func researchModelOptions(
        provider: CloudProviderConfiguration?,
        capabilities: [ProviderModelCapabilityRecord]
    ) -> [ArtifactsResearchModelOption] {
        guard let provider else { return [] }

        let capabilityOptions = capabilities
            .filter { $0.providerID == provider.id }
            .filter { capability in
                let model = capability.modelID.rawValue.lowercased()
                guard capability.capabilities.textGeneration else { return false }
                switch provider.kind {
                case .openAI:
                    return model.contains("deep-research")
                        || model.contains("gpt-5.5")
                        || model.contains("gpt-5-pro")
                case .gemini:
                    return model.contains("deep-research")
                default:
                    return false
                }
            }
            .map {
                ArtifactsResearchModelOption(
                    id: $0.modelID.rawValue,
                    detail: $0.capabilities.artifactsSummary,
                    isFromProviderCapability: true
                )
            }

        return stableMergedResearchModels(curatedResearchModels(providerKind: provider.kind) + capabilityOptions)
    }

    static func researchTimeline(for run: ProviderResearchRunRecord) -> [ArtifactsResearchTimelineEvent] {
        var events: [ArtifactsResearchTimelineEvent] = [
            .init(
                id: "status-\(run.id)-\(run.status)",
                title: run.status.providerCloudStatus.title,
                detail: run.lastError ?? run.providerMetadata["activity"] ?? run.providerMetadata["status"] ?? run.depth,
                systemImage: run.status.providerIsTerminal ? "checkmark.circle" : "point.3.connected.trianglepath.dotted",
                tone: run.status.providerCloudStatus.tone
            ),
        ]

        for (index, query) in decodedStrings(run.providerMetadata[CloudProviderMetadataKeys.webSearchQueriesJSON]).prefix(8).enumerated() {
            events.append(.init(
                id: "query-\(run.id)-\(index)-\(query)",
                title: "Search query",
                detail: query,
                systemImage: "magnifyingglass",
                tone: .info
            ))
        }

        let hostedToolEvents = run.providerMetadata.hostedToolAuditEntries.prefix(8).map { entry in
            ArtifactsResearchTimelineEvent(
                id: "tool-\(run.id)-\(entry.id)",
                title: entry.kind.deepResearchDisplayTitle,
                detail: entry.name ?? entry.serverLabel ?? entry.status?.rawValue ?? entry.type,
                systemImage: entry.kind.deepResearchSystemImage,
                tone: entry.status?.rawValue.providerCloudStatus.tone ?? .warning
            )
        }
        events.append(contentsOf: hostedToolEvents)

        for (index, object) in decodedJSONObjects(run.providerMetadata["gemini.deep_research.tool_calls_json"]).prefix(8).enumerated() {
            let type = object.string(for: "type") ?? "tool"
            let name = object.string(for: "name") ?? object.string(for: "language") ?? type
            events.append(.init(
                id: "gemini-tool-\(run.id)-\(index)-\(name)",
                title: type.readableArtifactKind,
                detail: name,
                systemImage: "wrench.and.screwdriver",
                tone: .warning
            ))
        }

        for source in researchSources(for: run).prefix(5) {
            events.append(.init(
                id: "source-event-\(source.id)",
                title: "Source captured",
                detail: source.title,
                systemImage: source.systemImage,
                tone: source.tone
            ))
        }

        if let artifactID = run.finalReportArtifactID {
            events.append(.init(
                id: "final-\(run.id)-\(artifactID)",
                title: "Final report artifact",
                detail: artifactID,
                systemImage: "doc.richtext",
                tone: .success
            ))
        }

        return events
    }

    static func researchSources(for run: ProviderResearchRunRecord) -> [ArtifactsResearchSource] {
        var sources = [ArtifactsResearchSource]()

        for citation in decodedWebSearchCitations(run.providerMetadata[CloudProviderMetadataKeys.webSearchCitationsJSON]) {
            sources.append(.init(
                id: "web-\(citation.id)",
                title: citation.title,
                detail: citation.source,
                url: citation.url,
                systemImage: "safari",
                tone: .info
            ))
        }

        for (index, object) in decodedJSONObjects(run.providerMetadata[CloudProviderMetadataKeys.webSearchCitationsJSON]).enumerated() {
            let url = object.string(for: "url") ?? object.string(for: "uri")
            let title = object.string(for: "title") ?? object.string(for: "file_id") ?? url ?? "Source"
            let detail = object.string(for: "quote") ?? object.string(for: "source") ?? run.providerKind.pinesLifecycleTitle
            sources.append(.init(
                id: "generic-\(run.id)-\(index)-\(url ?? title)",
                title: title,
                detail: detail,
                url: url,
                systemImage: url == nil ? "doc" : "safari",
                tone: url == nil ? .neutral : .info
            ))
        }

        for citation in run.providerMetadata.providerCitations {
            let url = citation.url
            let title = citation.title ?? citation.fileID ?? citation.documentID ?? url ?? "Provider source"
            let detail = citation.citedText ?? citation.source ?? citation.sourceType.rawValue.readableArtifactKind
            sources.append(.init(
                id: "provider-\(citation.id)",
                title: title,
                detail: detail,
                url: url,
                systemImage: citation.sourceType == .web ? "safari" : "doc.text",
                tone: citation.sourceType == .web ? .info : .neutral
            ))
        }

        var seen = Set<String>()
        return sources.filter { source in
            seen.insert(source.url ?? source.title).inserted
        }
    }

    private static func curatedMediaModels(providerKind: CloudProviderKind, kind: ArtifactsMediaKind) -> [ArtifactsMediaModelOption] {
        switch (providerKind, kind) {
        case (.openAI, .image):
            [
                .init(id: "gpt-image-2", title: "GPT Image 2", detail: "Latest OpenAI image model", isFromProviderCapability: false),
                .init(id: "gpt-image-1.5", title: "GPT Image 1.5", detail: "High fidelity image generation", isFromProviderCapability: false),
                .init(id: "gpt-image-1", title: "GPT Image 1", detail: "General image generation", isFromProviderCapability: false),
                .init(id: "gpt-image-1-mini", title: "GPT Image 1 mini", detail: "Lower-cost image generation", isFromProviderCapability: false),
                .init(id: "dall-e-3", title: "DALL-E 3", detail: "Legacy image generation", isFromProviderCapability: false),
            ]
        case (.openAI, .video):
            [
                .init(id: "sora-2", title: "Sora 2", detail: "Video with synced audio", isFromProviderCapability: false),
                .init(id: "sora-2-pro", title: "Sora 2 Pro", detail: "Highest quality Sora video", isFromProviderCapability: false),
            ]
        case (.openAI, .speech):
            [
                .init(id: "gpt-4o-mini-tts", title: "GPT-4o mini TTS", detail: "Fast text-to-speech", isFromProviderCapability: false),
                .init(id: "tts-1", title: "TTS 1", detail: "Legacy fast speech", isFromProviderCapability: false),
                .init(id: "tts-1-hd", title: "TTS 1 HD", detail: "Legacy high quality speech", isFromProviderCapability: false),
            ]
        case (.gemini, .image):
            [
                .init(id: "gemini-3.1-flash-image-preview", title: "Gemini 3.1 Flash Image", detail: "Fast Gemini 3 image generation", isFromProviderCapability: false),
                .init(id: "gemini-3-pro-image-preview", title: "Gemini 3 Pro Image", detail: "Professional Gemini image generation", isFromProviderCapability: false),
                .init(id: "gemini-2.5-flash-image", title: "Gemini 2.5 Flash Image", detail: "Fast native Gemini image generation", isFromProviderCapability: false),
                .init(id: "imagen-4.0-generate-001", title: "Imagen 4", detail: "General Imagen generation", isFromProviderCapability: false),
                .init(id: "imagen-4.0-ultra-generate-001", title: "Imagen 4 Ultra", detail: "Highest quality Imagen generation", isFromProviderCapability: false),
                .init(id: "imagen-4.0-fast-generate-001", title: "Imagen 4 Fast", detail: "Fast Imagen generation", isFromProviderCapability: false),
                .init(id: "imagen-3.0-generate-002", title: "Imagen 3", detail: "Previous high-quality Imagen generation", isFromProviderCapability: false),
            ]
        case (.gemini, .video):
            [
                .init(id: "veo-3.1-generate-preview", title: "Veo 3.1", detail: "Latest Gemini video generation", isFromProviderCapability: false),
                .init(id: "veo-3.1-fast-generate-preview", title: "Veo 3.1 Fast", detail: "Fast Gemini video generation", isFromProviderCapability: false),
                .init(id: "veo-3.1-lite-generate-preview", title: "Veo 3.1 Lite", detail: "Lowest-cost Gemini video generation", isFromProviderCapability: false),
                .init(id: "veo-3.0-generate-001", title: "Veo 3", detail: "Stable Gemini video generation", isFromProviderCapability: false),
                .init(id: "veo-3.0-fast-generate-001", title: "Veo 3 Fast", detail: "Fast stable Gemini video generation", isFromProviderCapability: false),
            ]
        case (.gemini, .speech):
            [
                .init(id: "gemini-3.1-flash-tts-preview", title: "Gemini 3.1 Flash TTS", detail: "Latest Gemini speech preview", isFromProviderCapability: false),
                .init(id: "gemini-2.5-flash-preview-tts", title: "Gemini 2.5 Flash TTS", detail: "Fast Gemini speech", isFromProviderCapability: false),
                .init(id: "gemini-2.5-pro-preview-tts", title: "Gemini 2.5 Pro TTS", detail: "Higher quality Gemini speech", isFromProviderCapability: false),
            ]
        default:
            []
        }
    }

    private static func curatedResearchModels(providerKind: CloudProviderKind) -> [ArtifactsResearchModelOption] {
        switch providerKind {
        case .openAI:
            [
                .init(id: "gpt-5.5-pro", title: "GPT-5.5 Pro", detail: "Deep research with highest reasoning budget", isFromProviderCapability: false),
                .init(id: "gpt-5.5", title: "GPT-5.5", detail: "Deep research with high reasoning", isFromProviderCapability: false),
                .init(id: "o3-deep-research-2025-06-26", title: "o3 Deep Research", detail: "Specialized OpenAI deep research model", isFromProviderCapability: false),
                .init(id: "o4-mini-deep-research-2025-06-26", title: "o4 mini Deep Research", detail: "Faster specialized OpenAI research model", isFromProviderCapability: false),
            ]
        case .gemini:
            [
                .init(id: "deep-research-pro-preview-12-2025", title: "Gemini Deep Research Pro", detail: "Gemini 3 Pro Deep Research agent", isFromProviderCapability: false),
            ]
        default:
            []
        }
    }

    private static func stableMergedMediaModels(_ options: [ArtifactsMediaModelOption]) -> [ArtifactsMediaModelOption] {
        var seen = Set<String>()
        var merged = [ArtifactsMediaModelOption]()
        for option in options where seen.insert(option.id).inserted {
            merged.append(option)
        }
        return merged
    }

    private static func stableMergedResearchModels(_ options: [ArtifactsResearchModelOption]) -> [ArtifactsResearchModelOption] {
        var seen = Set<String>()
        var merged = [ArtifactsResearchModelOption]()
        for option in options where seen.insert(option.id).inserted {
            merged.append(option)
        }
        return merged
    }

    private static func decodedWebSearchCitations(_ raw: String?) -> [WebSearchCitation] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WebSearchCitation].self, from: data)) ?? []
    }

    private static func decodedStrings(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func decodedJSONObjects(_ raw: String?) -> [[String: JSONValue]] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        if let values = try? JSONDecoder().decode([JSONValue].self, from: data) {
            return values.compactMap(\.objectValue)
        }
        return []
    }

    private static func sorter(_ sort: ArtifactsSort) -> (ArtifactsResourceSummary, ArtifactsResourceSummary) -> Bool {
        { lhs, rhs in
            switch sort {
            case .newest:
                (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            case .oldest:
                (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
            case .provider:
                lhs.providerKind.pinesLifecycleTitle == rhs.providerKind.pinesLifecycleTitle
                    ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    : lhs.providerKind.pinesLifecycleTitle < rhs.providerKind.pinesLifecycleTitle
            case .kind:
                lhs.kind == rhs.kind
                    ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    : lhs.kind < rhs.kind
            }
        }
    }

    private static func matches(_ haystack: String, query: String) -> Bool {
        query.isEmpty || haystack.localizedCaseInsensitiveContains(query)
    }
}

extension CloudProviderKind {
    var pinesLifecycleTitle: String {
        switch self {
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .openRouter: "OpenRouter"
        case .voyageAI: "Voyage AI"
        case .custom: "Custom"
        }
    }

    var artifactsDisplayName: String {
        pinesLifecycleTitle
    }
}

extension String {
    var providerCloudStatus: PinesCloudStatus {
        switch lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "") {
        case "completed", "complete", "processed", "closed":
            .complete
        case "failed", "error":
            .failed
        case "cancelled", "canceled", "expired", "deleted":
            .warning(displayStatusTitle)
        case "queued", "pending", "created", "validating":
            .pending
        case "inprogress", "running", "active", "finalizing", "uploaded":
            .running
        case "requiresaction", "cancelling", "deleting", "closing":
            .needsValidation
        default:
            .custom(isEmpty ? "Unknown" : displayStatusTitle, .neutral)
        }
    }

    var providerIsTerminal: Bool {
        switch lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "") {
        case "completed", "complete", "processed", "closed", "failed", "error", "cancelled", "canceled", "expired", "deleted":
            true
        default:
            false
        }
    }

    var providerArtifactSystemImage: String {
        switch lowercased() {
        case "image", "generated_image", "partial_image":
            "photo"
        case "audio", "transcript", "transcription", "translation", "speech":
            "waveform"
        case "video", "generated_video", "media_operation":
            "film"
        case "structuredoutput", "structured_output":
            "curlybraces.square"
        case "code", "code_execution":
            "chevron.left.forwardslash.chevron.right"
        case "tooloutput", "tool_output", "hosted_tool_call":
            "wrench.and.screwdriver"
        case "file_reference", "container_file":
            "doc"
        default:
            "doc"
        }
    }

    var readableArtifactKind: String {
        displayStatusTitle
    }

    private var displayStatusTitle: String {
        split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

extension ProviderArtifactRecord {
    var retentionLabel: ArtifactsRetentionLabel {
        if localURL != nil { return .localCopy }
        if remoteURL != nil { return .remoteLink }
        if text != nil || content != nil { return .vaultImportCandidate }
        return .providerHosted
    }

    var isImportableToVault: Bool {
        localURL != nil || text != nil || content != nil
    }

    var searchText: String {
        [
            id,
            providerID?.rawValue,
            providerKind.rawValue,
            responseID,
            toolCallID,
            providerFileID,
            kind,
            fileName,
            contentType,
            text,
            remoteURL?.absoluteString,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

extension ProviderFileRecord {
    var searchText: String {
        [id, providerID.rawValue, providerKind.rawValue, purpose, fileName, contentType, status, providerObject, lastError]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension ProviderCacheRecord {
    var searchText: String {
        [id, providerID.rawValue, providerKind.rawValue, kind, name, modelID?.rawValue, status, lastError]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension ProviderBatchRecord {
    var fileSummary: String {
        let files = [inputFileID, outputFileID, errorFileID].compactMap { $0 }
        return files.isEmpty ? "No linked files" : files.joined(separator: " -> ")
    }

    var searchText: String {
        [id, providerID.rawValue, providerKind.rawValue, endpoint, status, inputFileID, outputFileID, errorFileID, completionWindow, lastError]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension ProviderResearchRunRecord {
    var searchText: String {
        [id, providerID.rawValue, providerKind.rawValue, modelID.rawValue, title, prompt, depth, reportFormat, status, responseID, finalReportArtifactID, lastError]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension ProviderLiveSessionRecord {
    var searchText: String {
        [id, providerID.rawValue, providerKind.rawValue, modelID.rawValue, status, modalities.joined(separator: " "), lastError]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension ProviderStructuredOutputRecord {
    var searchText: String {
        [id.uuidString, providerID?.rawValue, providerKind.rawValue, responseID, messageID?.uuidString, schemaName, status, refusal, incompleteReason, validationErrors.joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension ProviderModelCapabilityRecord {
    var searchText: String {
        [providerID.rawValue, providerKind.rawValue, modelID.rawValue, capabilities.artifactsSummary]
            .joined(separator: " ")
    }
}

extension ProviderCapabilities {
    var artifactsSummary: String {
        var values = [String]()
        if files { values.append("Files") }
        if hostedTools { values.append("Hosted tools") }
        if structuredOutputs { values.append("Structured") }
        if generatedImages { values.append("Images") }
        if generatedAudio || audioOutputs { values.append("Audio") }
        if generatedVideo || videoOutputs { values.append("Video") }
        if contextCache { values.append("Context") }
        if live { values.append("Realtime") }
        if batch { values.append("Batches") }
        return values.isEmpty ? "Metadata" : values.joined(separator: ", ")
    }
}

private extension OpenAIHostedToolKind {
    var deepResearchDisplayTitle: String {
        switch self {
        case .webSearch: "Web search"
        case .fileSearch: "File search"
        case .codeInterpreter: "Code analysis"
        case .mcp: "MCP source"
        case .computerUse: "Computer use"
        case .imageGeneration: "Image generation"
        case .toolSearch: "Tool search"
        case .webFetch: "Web fetch"
        case .textEditor: "Text edit"
        case .bash: "Shell tool"
        case .custom: "Tool call"
        }
    }

    var deepResearchSystemImage: String {
        switch self {
        case .webSearch, .webFetch: "safari"
        case .fileSearch: "doc.text.magnifyingglass"
        case .codeInterpreter: "chevron.left.forwardslash.chevron.right"
        case .mcp: "network"
        case .computerUse: "display"
        case .imageGeneration: "photo"
        case .toolSearch: "wrench.and.screwdriver"
        case .textEditor: "text.cursor"
        case .bash: "terminal"
        case .custom: "gearshape"
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(for key: String) -> String? {
        self[key]?.stringValue
    }
}

func providerByteCountLabel(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
