import Foundation
import PinesCore
import SwiftUI

enum ArtifactsWorkspaceMode: String, CaseIterable, Identifiable, Hashable {
    case library
    case media
    case files
    case context
    case batches
    case research
    case realtime
    case capabilities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .media: "Media"
        case .files: "Files"
        case .context: "Context"
        case .batches: "Batches"
        case .research: "Research"
        case .realtime: "Realtime"
        case .capabilities: "Capabilities"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack"
        case .media: "photo.stack"
        case .files: "doc.badge.arrow.up"
        case .context: "externaldrive.badge.icloud"
        case .batches: "tray.full"
        case .research: "doc.text.magnifyingglass"
        case .realtime: "dot.radiowaves.left.and.right"
        case .capabilities: "cpu"
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

func providerByteCountLabel(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
