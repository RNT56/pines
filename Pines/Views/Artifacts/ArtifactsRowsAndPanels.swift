import SwiftUI
import PinesCore
import AVKit
#if canImport(UIKit)
import UIKit
#endif

struct ArtifactsResourceDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let status: PinesCloudStatus
    var secondaryStatus: PinesCloudStatus?
    var providerKind: CloudProviderKind?
    var providerID: ProviderID?
    var storageKind: PinesProviderStorageKind?
    var metricItems: [PinesMetricPillGroup.Item]
    var fields: [ArtifactsResourceField]
    var isTerminal: Bool

    init(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        status: PinesCloudStatus,
        secondaryStatus: PinesCloudStatus? = nil,
        providerKind: CloudProviderKind? = nil,
        providerID: ProviderID? = nil,
        storageKind: PinesProviderStorageKind? = nil,
        metricItems: [PinesMetricPillGroup.Item] = [],
        fields: [ArtifactsResourceField] = [],
        isTerminal: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.status = status
        self.secondaryStatus = secondaryStatus
        self.providerKind = providerKind
        self.providerID = providerID
        self.storageKind = storageKind
        self.metricItems = metricItems
        self.fields = fields
        self.isTerminal = isTerminal
    }
}

struct ArtifactsResourceField: Identifiable, Hashable {
    var id: String { "\(title)-\(value)-\(systemImage ?? "")" }
    let title: String
    let value: String
    var systemImage: String?
    var tone: PinesCloudStatusTone

    init(_ title: String, _ value: String?, systemImage: String? = nil, tone: PinesCloudStatusTone = .neutral) {
        self.title = title
        self.value = value?.nilIfEmpty ?? "Unspecified"
        self.systemImage = systemImage
        self.tone = tone
    }
}

struct ArtifactsResourceAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var kind: PinesButtonKind
    var isDisabled: Bool
    let perform: () -> Void

    init(
        id: String,
        title: String,
        systemImage: String,
        kind: PinesButtonKind = .secondary,
        isDisabled: Bool = false,
        perform: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.isDisabled = isDisabled
        self.perform = perform
    }
}

struct ArtifactsResourceRow: View {
    @Environment(\.pinesTheme) private var theme
    let resource: ArtifactsResourceDescriptor
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            PinesCapabilityRow(
                title: resource.title,
                detail: resource.detail,
                systemImage: resource.systemImage,
                status: resource.status,
                secondaryStatus: resource.secondaryStatus,
                metricItems: resource.metricItems
            )

            if !actions.isEmpty {
                ArtifactsResourceActionBar(actions: actions)
            }
        }
    }
}

struct ArtifactsResourceActionBar: View {
    let actions: [ArtifactsResourceAction]

    var body: some View {
        PinesActionBar {
            ForEach(actions) { action in
                Button(action: action.perform) {
                    Label(action.title, systemImage: action.systemImage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .disabled(action.isDisabled)
                .pinesButtonStyle(action.kind, fillWidth: true)
            }
        }
    }
}

struct ArtifactsResourceList: View {
    @Environment(\.pinesTheme) private var theme
    let summaries: [ArtifactsResourceSummary]
    @Binding var selection: ArtifactsSelection?
    var emptyTitle: String
    var emptyDetail: String

    var body: some View {
        PinesCardSection("Resources", subtitle: "Searchable provider inventory scoped by the page controls.", systemImage: "rectangle.stack") {
            if summaries.isEmpty {
                PinesEmptyState(title: emptyTitle, detail: emptyDetail, systemImage: "rectangle.stack.badge.minus")
                    .pinesSurface(.inset, padding: theme.spacing.small)
            } else {
                LazyVStack(alignment: .leading, spacing: theme.spacing.small) {
                    ForEach(summaries) { summary in
                        Button {
                            selection = summary.selection
                        } label: {
                            ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(summary: summary))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay {
                            RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                                .strokeBorder(
                                    selection == summary.selection ? theme.colors.accent.opacity(0.38) : Color.clear,
                                    lineWidth: theme.stroke.selected
                                )
                        }
                        .accessibilityLabel(summary.title)
                    }
                }
            }
        }
    }
}

struct ArtifactsArtifactGallery: View {
    @Environment(\.pinesTheme) private var theme
    let summaries: [ArtifactsResourceSummary]
    let artifacts: [ProviderArtifactRecord]
    @Binding var selection: ArtifactsSelection?
    var emptyTitle: String
    var emptyDetail: String

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: theme.spacing.small)]
    }

    var body: some View {
        PinesCardSection("Gallery", subtitle: "Viewable reports and generated media.", systemImage: "rectangle.stack") {
            if summaries.isEmpty {
                PinesEmptyState(title: emptyTitle, detail: emptyDetail, systemImage: "rectangle.stack.badge.minus")
                    .pinesSurface(.inset, padding: theme.spacing.small)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: theme.spacing.small) {
                    ForEach(summaries) { summary in
                        if let artifact = artifacts.first(where: { summary.selection == .artifact($0.id) }) {
                            ArtifactsGalleryCard(
                                artifact: artifact,
                                summary: summary,
                                isSelected: selection == summary.selection
                            ) {
                                selection = summary.selection
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ArtifactsGalleryCard: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.openURL) private var openURL
    let artifact: ProviderArtifactRecord
    let summary: ArtifactsResourceSummary
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        PinesArtifactCard(
            isSelected: isSelected,
            minHeight: 260,
            select: select,
            preview: {
            ArtifactsArtifactPreviewSurface(artifact: artifact, maxHeight: 170)
        }, details: {
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(summary.title)
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary.kind.readableArtifactKind)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }
        }, actions: {
            HStack(spacing: theme.spacing.xsmall) {
                PinesStatusChip(status: summary.status, compact: true)
                Spacer(minLength: 0)
                if let url = artifact.galleryURL {
                    PinesCompactIconButton(title: "Open artifact", systemImage: "arrow.up.forward.app") {
                        openURL(url)
                    }
                }
            }
        })
    }
}

struct ArtifactsArtifactPreviewSurface: View {
    @Environment(\.pinesTheme) private var theme
    let artifact: ProviderArtifactRecord
    var maxHeight: CGFloat = 280

    var body: some View {
        Group {
            switch artifact.galleryPresentation {
            case .image:
                imagePreview
            case .video:
                if let url = artifact.galleryURL {
                    VideoPlayer(player: AVPlayer(url: url))
                } else {
                    placeholder(title: "Video", systemImage: "film")
                }
            case .audio:
                if let url = artifact.galleryURL {
                    VideoPlayer(player: AVPlayer(url: url))
                } else {
                    placeholder(title: "Audio", systemImage: "waveform")
                }
            case .report:
                reportPreview
            case .metadata:
                placeholder(title: artifact.kind.readableArtifactKind, systemImage: artifact.kind.providerArtifactSystemImage)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: maxHeight)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let data = artifact.localPreviewImageData {
            ArtifactsLocalImage(data: data) {
                placeholder(title: "Image unavailable", systemImage: "photo")
            }
        } else if let url = artifact.galleryURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    placeholder(title: "Image unavailable", systemImage: "photo")
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            placeholder(title: "Image", systemImage: "photo")
        }
    }

    private var reportPreview: some View {
        ScrollView {
            Text(reportPreviewText)
                .font(.system(.caption, design: .default))
                .foregroundStyle(theme.colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.small)
        }
    }

    private var reportPreviewText: String {
        if let text = artifact.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return String(text.prefix(1200))
        }
        if let content = artifact.content {
            return String(content.prettyJSONString.prefix(1200))
        }
        return artifact.fileName ?? artifact.id
    }

    private func placeholder(title: String, systemImage: String) -> some View {
        VStack(spacing: theme.spacing.xsmall) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
            Text(title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArtifactsLocalImage<Placeholder: View>: View {
    let data: Data
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            placeholder()
        }
        #else
        placeholder()
        #endif
    }
}

struct ArtifactsDetailPanel: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.openURL) private var openURL
    let selection: ArtifactsSelection?
    let providerState: PinesProviderLifecycleState
    var onImportArtifact: (ProviderArtifactRecord) -> Void
    var onDeleteArtifactRecord: (ProviderArtifactRecord) -> Void

    var body: some View {
        Group {
            switch selection {
            case .artifact(let id):
                if let artifact = providerState.providerArtifacts.first(where: { $0.id == id }) {
                    artifactPanel(artifact)
                } else {
                    missingPanel
                }
            case .structuredOutput(let id):
                if let output = providerState.providerStructuredOutputs.first(where: { $0.id == id }) {
                    structuredOutputPanel(output)
                } else {
                    missingPanel
                }
            case .file(let id):
                if let file = providerState.providerFiles.first(where: { $0.id == id }) {
                    ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(file: file))
                } else {
                    missingPanel
                }
            case .cache(let id):
                if let cache = providerState.providerCaches.first(where: { $0.id == id }) {
                    ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(cache: cache))
                } else {
                    missingPanel
                }
            case .batch(let id):
                if let batch = providerState.providerBatches.first(where: { $0.id == id }) {
                    ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(batch: batch))
                } else {
                    missingPanel
                }
            case .research(let id):
                if let run = providerState.providerResearchRuns.first(where: { $0.id == id }) {
                    ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(researchRun: run))
                } else {
                    missingPanel
                }
            case .liveSession(let id):
                if let session = providerState.providerLiveSessions.first(where: { $0.id == id }) {
                    ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(liveSession: session))
                } else {
                    missingPanel
                }
            case .capability(let id):
                if let capability = providerState.providerModelCapabilities.first(where: { $0.id == id }) {
                    ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(modelCapability: capability))
                } else {
                    missingPanel
                }
            case .none:
                PinesCardSection("Details", subtitle: "Select a resource to inspect provider IDs, retention, links, and raw content.", systemImage: "sidebar.right", kind: .glass) {
                    PinesEmptyState(title: "No resource selected", detail: "Choose a row to inspect its provenance and available actions.", systemImage: "sidebar.right")
                        .pinesSurface(.inset, padding: theme.spacing.small)
                }
            }
        }
    }

    private var missingPanel: some View {
        PinesCardSection("Details", subtitle: "The selected record is no longer available.", systemImage: "exclamationmark.triangle", kind: .glass) {
            PinesEmptyState(title: "Record missing", detail: "Refresh provider lifecycle state and select the resource again.", systemImage: "arrow.triangle.2.circlepath")
                .pinesSurface(.inset, padding: theme.spacing.small)
        }
    }

    private func artifactPanel(_ artifact: ProviderArtifactRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            ArtifactsResourceDetailPanel(
                resource: ArtifactsResourceDescriptor(artifact: artifact),
                actions: [
                    ArtifactsResourceAction(
                        id: "import-\(artifact.id)",
                        title: "Import to Vault",
                        systemImage: "square.and.arrow.down",
                        kind: .primary,
                        isDisabled: !artifact.isImportableToVault,
                        perform: { onImportArtifact(artifact) }
                    ),
                    ArtifactsResourceAction(
                        id: "open-\(artifact.id)",
                        title: "Open",
                        systemImage: "arrow.up.forward.app",
                        isDisabled: artifact.galleryURL == nil,
                        perform: {
                            if let url = artifact.galleryURL {
                                openURL(url)
                            }
                        }
                    ),
                    ArtifactsResourceAction(
                        id: "delete-local-\(artifact.id)",
                        title: "Delete local record",
                        systemImage: "trash",
                        kind: .destructive,
                        perform: { onDeleteArtifactRecord(artifact) }
                    ),
                ]
            )

            artifactPreview(artifact)
        }
    }

    @ViewBuilder
    private func artifactPreview(_ artifact: ProviderArtifactRecord) -> some View {
        if artifact.galleryPresentation != .metadata {
            previewSection(title: artifact.galleryPresentation.previewTitle, systemImage: artifact.kind.providerArtifactSystemImage) {
                ArtifactsArtifactPreviewSurface(artifact: artifact, maxHeight: 320)
            }
        } else if let text = artifact.text, !text.isEmpty {
            previewSection(title: "Text Preview", systemImage: "text.alignleft") {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.colors.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let content = artifact.content {
            previewSection(title: "JSON Preview", systemImage: "curlybraces.square") {
                Text(content.prettyJSONString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.colors.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func structuredOutputPanel(_ output: ProviderStructuredOutputRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(structuredOutput: output))

            if let content = output.content {
                previewSection(title: "Output JSON", systemImage: "curlybraces.square") {
                    Text(content.prettyJSONString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.colors.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let schema = output.schema {
                previewSection(title: "Schema", systemImage: "checklist") {
                    Text(schema.prettyJSONString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.colors.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func previewSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        PinesCardSection(title, subtitle: "Local preview from the lifecycle record.", systemImage: systemImage, kind: .glass) {
            ScrollView {
                content()
                    .padding(theme.spacing.small)
            }
            .frame(maxHeight: 320)
            .pinesSurface(.inset, padding: 0)
        }
    }
}

struct ArtifactsResourceDetailPanel: View {
    @Environment(\.pinesTheme) private var theme
    let resource: ArtifactsResourceDescriptor
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        PinesCardSection(resource.title, subtitle: resource.detail, systemImage: resource.systemImage, kind: .glass) {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                HStack(alignment: .top, spacing: theme.spacing.small) {
                    VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                        Text(resource.providerKind?.artifactsDisplayName ?? "Provider resource")
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if let providerID = resource.providerID {
                            Text(providerID.rawValue)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: theme.spacing.small)

                    VStack(alignment: .trailing, spacing: theme.spacing.xxsmall) {
                        PinesStatusChip(status: resource.status, compact: true)

                        if let secondaryStatus = resource.secondaryStatus {
                            PinesStatusChip(status: secondaryStatus, compact: true)
                        }

                        if let storageKind = resource.storageKind {
                            PinesProviderStorageBadge(kind: storageKind, compact: true)
                        }
                    }
                }
                .pinesSurface(.inset, padding: theme.spacing.small)

                if !resource.metricItems.isEmpty {
                    PinesMetricPillGroup(items: resource.metricItems, minimumWidth: 128)
                }

                if !resource.fields.isEmpty {
                    ArtifactsResourceFieldGrid(fields: resource.fields)
                }

                if !actions.isEmpty {
                    ArtifactsResourceActionBar(actions: actions)
                }
            }
        }
    }
}

struct ArtifactsResourceSection<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let subtitle: String
    let systemImage: String
    let isEmpty: Bool
    var emptyTitle: String
    var emptyDetail: String
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        isEmpty: Bool,
        emptyTitle: String = "Nothing stored",
        emptyDetail: String = "Provider records appear after compatible workflows run.",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptyDetail = emptyDetail
        self.content = content
    }

    var body: some View {
        PinesCardSection(title, subtitle: subtitle, systemImage: systemImage) {
            if isEmpty {
                PinesEmptyState(title: emptyTitle, detail: emptyDetail, systemImage: systemImage)
                    .pinesSurface(.inset, padding: theme.spacing.small)
            } else {
                content()
            }
        }
    }
}

struct ArtifactsProviderArtifactRow: View {
    let artifact: PinesProviderArtifactPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(artifact: artifact), actions: actions)
    }
}

struct ArtifactsProviderFileRow: View {
    let file: PinesProviderFilePreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(file: file), actions: actions)
    }
}

struct ArtifactsProviderCacheRow: View {
    let cache: PinesProviderCachePreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(cache: cache), actions: actions)
    }
}

struct ArtifactsProviderBatchRow: View {
    let batch: PinesProviderBatchPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(batch: batch), actions: actions)
    }
}

struct ArtifactsProviderResearchRunRow: View {
    let run: PinesProviderResearchRunPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(researchRun: run), actions: actions)
    }
}

struct ArtifactsProviderLiveSessionRow: View {
    let session: PinesProviderLiveSessionPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(liveSession: session), actions: actions)
    }
}

struct ArtifactsProviderStructuredOutputRow: View {
    let output: PinesProviderStructuredOutputPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(structuredOutput: output), actions: actions)
    }
}

struct ArtifactsProviderModelCapabilityRow: View {
    let capability: PinesProviderModelCapabilityPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceRow(resource: ArtifactsResourceDescriptor(modelCapability: capability), actions: actions)
    }
}

struct ArtifactsProviderArtifactDetailPanel: View {
    let artifact: PinesProviderArtifactPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(artifact: artifact), actions: actions)
    }
}

struct ArtifactsProviderFileDetailPanel: View {
    let file: PinesProviderFilePreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(file: file), actions: actions)
    }
}

struct ArtifactsProviderCacheDetailPanel: View {
    let cache: PinesProviderCachePreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(cache: cache), actions: actions)
    }
}

struct ArtifactsProviderBatchDetailPanel: View {
    let batch: PinesProviderBatchPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(batch: batch), actions: actions)
    }
}

struct ArtifactsProviderResearchRunDetailPanel: View {
    let run: PinesProviderResearchRunPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(researchRun: run), actions: actions)
    }
}

struct ArtifactsProviderLiveSessionDetailPanel: View {
    let session: PinesProviderLiveSessionPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(liveSession: session), actions: actions)
    }
}

struct ArtifactsProviderStructuredOutputDetailPanel: View {
    let output: PinesProviderStructuredOutputPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(structuredOutput: output), actions: actions)
    }
}

struct ArtifactsProviderModelCapabilityDetailPanel: View {
    let capability: PinesProviderModelCapabilityPreview
    var actions: [ArtifactsResourceAction] = []

    var body: some View {
        ArtifactsResourceDetailPanel(resource: ArtifactsResourceDescriptor(modelCapability: capability), actions: actions)
    }
}

private struct ArtifactsResourceFieldGrid: View {
    @Environment(\.pinesTheme) private var theme
    let fields: [ArtifactsResourceField]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: theme.spacing.xsmall)], alignment: .leading, spacing: theme.spacing.xsmall) {
            ForEach(fields) { field in
                HStack(alignment: .top, spacing: theme.spacing.xsmall) {
                    if let systemImage = field.systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(field.tone.color(in: theme))
                            .frame(width: 18, height: 18)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(field.title)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(field.value)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.78)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                .pinesSurface(.inset, padding: theme.spacing.small)
            }
        }
    }
}

extension ArtifactsResourceDescriptor {
    init(summary: ArtifactsResourceSummary) {
        self.init(
            id: summary.id,
            title: summary.title,
            detail: summary.detail,
            systemImage: summary.systemImage,
            status: summary.status,
            secondaryStatus: summary.secondaryStatus,
            providerKind: summary.providerKind,
            providerID: summary.providerID,
            storageKind: summary.retention.storageKind,
            metricItems: summary.metricItems + [
                .init("Retention", value: summary.retention.title, systemImage: "externaldrive.badge.icloud", tone: summary.retention.tone),
            ],
            fields: [
                .init("Provider", summary.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", summary.providerID?.rawValue, systemImage: "key", tone: .neutral),
                .init("Kind", summary.kind.readableArtifactKind, systemImage: "tag", tone: .info),
                .init("Retention", summary.retention.title, systemImage: "externaldrive.badge.icloud", tone: summary.retention.tone),
            ],
            isTerminal: true
        )
    }

    init(artifact: ProviderArtifactRecord) {
        self.init(
            id: "artifact-\(artifact.id)",
            title: artifact.fileName ?? artifact.kind.readableArtifactKind,
            detail: artifact.galleryDetail,
            systemImage: artifact.kind.providerArtifactSystemImage,
            status: artifact.responseID == nil ? .custom("Stored", .success) : .custom("Linked", .accent),
            secondaryStatus: artifact.byteCount.map { .custom(providerByteCountLabel($0), .neutral) },
            providerKind: artifact.providerKind,
            providerID: artifact.providerID,
            storageKind: artifact.retentionLabel.storageKind,
            metricItems: [
                .init("Provider", value: artifact.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Kind", value: artifact.kind.readableArtifactKind, systemImage: "tag", tone: .info),
                .init("Retention", value: artifact.retentionLabel.title, systemImage: "externaldrive.badge.icloud", tone: artifact.retentionLabel.tone),
            ],
            fields: [
                .init("Artifact ID", artifact.id, systemImage: "number", tone: .neutral),
                .init("Provider", artifact.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", artifact.providerID?.rawValue, systemImage: "key", tone: .neutral),
                .init("Kind", artifact.kind.readableArtifactKind, systemImage: "tag", tone: .info),
                .init("Retention", artifact.retentionLabel.title, systemImage: "externaldrive.badge.icloud", tone: artifact.retentionLabel.tone),
                .init("Response ID", artifact.responseID, systemImage: "bubble.left.and.text.bubble.right", tone: .neutral),
                .init("Provider File ID", artifact.providerFileID, systemImage: "doc", tone: .neutral),
                .init("Content Type", artifact.contentType, systemImage: "tag", tone: .neutral),
                .init("Size", artifact.byteCount.map(providerByteCountLabel), systemImage: "internaldrive", tone: .neutral),
                .init("Local URL", artifact.localURL?.path, systemImage: "internaldrive", tone: .success),
                .init("Remote URL", artifact.remoteURL?.absoluteString, systemImage: "link", tone: .info),
                .init("Created", RelativeDateTimeFormatter.shortLabel(for: artifact.createdAt), systemImage: "clock", tone: .neutral),
            ],
            isTerminal: true
        )
    }

    init(file: ProviderFileRecord) {
        self.init(
            id: "file-\(file.id)",
            title: file.fileName,
            detail: "\(file.providerID.rawValue) - \(file.purpose)",
            systemImage: "doc",
            status: file.status.providerCloudStatus,
            secondaryStatus: file.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
            providerKind: file.providerKind,
            providerID: file.providerID,
            storageKind: .providerHosted,
            metricItems: [
                .init("Purpose", value: file.purpose, systemImage: "tag", tone: .info),
                .init("Size", value: providerByteCountLabel(file.byteCount), systemImage: "internaldrive", tone: .neutral),
                .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: file.createdAt), systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("File ID", file.id, systemImage: "number", tone: .neutral),
                .init("Provider", file.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", file.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Purpose", file.purpose, systemImage: "tag", tone: .info),
                .init("Status", file.status.readableArtifactKind, systemImage: "circle.dashed", tone: file.status.providerCloudStatus.tone),
                .init("Content Type", file.contentType, systemImage: "tag", tone: .neutral),
                .init("Size", providerByteCountLabel(file.byteCount), systemImage: "internaldrive", tone: .neutral),
                .init("Object", file.providerObject, systemImage: "cube", tone: .neutral),
                .init("Local URL", file.localURL?.path, systemImage: "internaldrive", tone: .success),
                .init("Created", RelativeDateTimeFormatter.shortLabel(for: file.createdAt), systemImage: "clock", tone: .neutral),
                .init("Expires", file.expiresAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "timer", tone: .warning),
                .init("Last Error", file.lastError, systemImage: "exclamationmark.triangle", tone: .danger),
            ],
            isTerminal: file.status.providerIsTerminal
        )
    }

    init(cache: ProviderCacheRecord) {
        let storageKind: PinesProviderStorageKind = cache.kind == "cached_content" ? .cachedContext : .vectorStore
        self.init(
            id: "cache-\(cache.id)",
            title: cache.name ?? cache.id,
            detail: cache.modelID?.rawValue ?? cache.providerID.rawValue,
            systemImage: storageKind.systemImage,
            status: cache.status.providerCloudStatus,
            secondaryStatus: cache.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
            providerKind: cache.providerKind,
            providerID: cache.providerID,
            storageKind: storageKind,
            metricItems: [
                .init("Kind", value: cache.kind.readableArtifactKind, systemImage: "tag", tone: .info),
                .init("Usage", value: providerByteCountLabel(cache.usageBytes), systemImage: "number", tone: .neutral),
                .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: cache.createdAt), systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Context ID", cache.id, systemImage: "number", tone: .neutral),
                .init("Provider", cache.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", cache.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Kind", cache.kind.readableArtifactKind, systemImage: storageKind.systemImage, tone: storageKind.tone),
                .init("Name", cache.name, systemImage: "textformat", tone: .neutral),
                .init("Model", cache.modelID?.rawValue, systemImage: "cpu", tone: .info),
                .init("Status", cache.status.readableArtifactKind, systemImage: "circle.dashed", tone: cache.status.providerCloudStatus.tone),
                .init("Usage", providerByteCountLabel(cache.usageBytes), systemImage: "number", tone: .neutral),
                .init("Created", RelativeDateTimeFormatter.shortLabel(for: cache.createdAt), systemImage: "clock", tone: .neutral),
                .init("Last Active", cache.lastActiveAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "clock.arrow.circlepath", tone: .neutral),
                .init("Expires", cache.expiresAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "timer", tone: .warning),
                .init("Last Error", cache.lastError, systemImage: "exclamationmark.triangle", tone: .danger),
            ],
            isTerminal: cache.status.providerIsTerminal
        )
    }

    init(batch: ProviderBatchRecord) {
        self.init(
            id: "batch-\(batch.id)",
            title: batch.endpoint,
            detail: batch.fileSummary,
            systemImage: "tray.full",
            status: batch.status.providerCloudStatus,
            secondaryStatus: batch.completedAt.map { .custom(RelativeDateTimeFormatter.shortLabel(for: $0), .success) },
            providerKind: batch.providerKind,
            providerID: batch.providerID,
            storageKind: .providerHosted,
            metricItems: [
                .init("Endpoint", value: batch.endpoint, systemImage: "arrow.left.arrow.right", tone: .info),
                .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: batch.createdAt), systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Batch ID", batch.id, systemImage: "number", tone: .neutral),
                .init("Provider", batch.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", batch.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Endpoint", batch.endpoint, systemImage: "arrow.left.arrow.right", tone: .info),
                .init("Status", batch.status.readableArtifactKind, systemImage: "circle.dashed", tone: batch.status.providerCloudStatus.tone),
                .init("Files", batch.fileSummary, systemImage: "doc.on.doc", tone: .neutral),
                .init("Window", batch.completionWindow, systemImage: "timer", tone: .neutral),
                .init("Created", RelativeDateTimeFormatter.shortLabel(for: batch.createdAt), systemImage: "clock", tone: .neutral),
                .init("Completed", batch.completedAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "checkmark.circle", tone: .success),
                .init("Expires", batch.expiresAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "timer", tone: .warning),
                .init("Last Error", batch.lastError, systemImage: "exclamationmark.triangle", tone: .danger),
            ],
            isTerminal: batch.status.providerIsTerminal
        )
    }

    init(researchRun run: ProviderResearchRunRecord) {
        self.init(
            id: "research-\(run.id)",
            title: run.title,
            detail: "\(run.depth) - \(run.reportFormat)",
            systemImage: "doc.text.magnifyingglass",
            status: run.status.providerCloudStatus,
            secondaryStatus: .custom(RelativeDateTimeFormatter.shortLabel(for: run.updatedAt), .neutral),
            providerKind: run.providerKind,
            providerID: run.providerID,
            storageKind: .providerHosted,
            metricItems: [
                .init("Model", value: run.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Sources", value: "\(run.citationCount)", systemImage: "quote.bubble", tone: .neutral),
                .init("Tools", value: "\(run.toolCallCount)", systemImage: "wrench.and.screwdriver", tone: .neutral),
            ],
            fields: [
                .init("Run ID", run.id, systemImage: "number", tone: .neutral),
                .init("Provider", run.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", run.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Model", run.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Status", run.status.readableArtifactKind, systemImage: "circle.dashed", tone: run.status.providerCloudStatus.tone),
                .init("Depth", run.depth, systemImage: "slider.horizontal.3", tone: .neutral),
                .init("Report", run.reportFormat, systemImage: "doc.text", tone: .neutral),
                .init("Response ID", run.responseID, systemImage: "bubble.left.and.text.bubble.right", tone: .neutral),
                .init("Final Artifact", run.finalReportArtifactID, systemImage: "doc.richtext", tone: .success),
                .init("Updated", RelativeDateTimeFormatter.shortLabel(for: run.updatedAt), systemImage: "clock.arrow.circlepath", tone: .neutral),
                .init("Completed", run.completedAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "checkmark.circle", tone: .success),
                .init("Last Error", run.lastError, systemImage: "exclamationmark.triangle", tone: .danger),
            ],
            isTerminal: run.status.providerIsTerminal
        )
    }

    init(liveSession session: ProviderLiveSessionRecord) {
        self.init(
            id: "live-session-\(session.id)",
            title: session.id,
            detail: session.modalities.joined(separator: ", "),
            systemImage: "dot.radiowaves.left.and.right",
            status: session.status.providerCloudStatus,
            secondaryStatus: session.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
            providerKind: session.providerKind,
            providerID: session.providerID,
            storageKind: .providerHosted,
            metricItems: [
                .init("Model", value: session.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: session.createdAt), systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Session ID", session.id, systemImage: "number", tone: .neutral),
                .init("Provider", session.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", session.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Model", session.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Status", session.status.readableArtifactKind, systemImage: "circle.dashed", tone: session.status.providerCloudStatus.tone),
                .init("Modalities", session.modalities.joined(separator: ", "), systemImage: "waveform", tone: .info),
                .init("Created", RelativeDateTimeFormatter.shortLabel(for: session.createdAt), systemImage: "clock", tone: .neutral),
                .init("Expires", session.expiresAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "timer", tone: .warning),
                .init("Closed", session.closedAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "xmark.circle", tone: .neutral),
                .init("Last Error", session.lastError, systemImage: "exclamationmark.triangle", tone: .danger),
            ],
            isTerminal: session.status.providerIsTerminal
        )
    }

    init(structuredOutput output: ProviderStructuredOutputRecord) {
        let validationTone: PinesCloudStatusTone = output.validationErrors.isEmpty ? .success : .warning
        self.init(
            id: "structured-output-\(output.id.uuidString)",
            title: output.schemaName ?? "Structured output",
            detail: output.responseID ?? output.messageID?.uuidString ?? output.id.uuidString,
            systemImage: "curlybraces.square",
            status: output.status.providerCloudStatus,
            secondaryStatus: .custom(output.validationErrors.isEmpty ? "Valid" : "\(output.validationErrors.count) issues", validationTone),
            providerKind: output.providerKind,
            providerID: output.providerID,
            storageKind: .localOnly,
            metricItems: [
                .init("Provider", value: output.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Validation", value: output.validationErrors.isEmpty ? "Valid" : "\(output.validationErrors.count) issues", systemImage: "checkmark.seal", tone: validationTone),
                .init("Created", value: RelativeDateTimeFormatter.shortLabel(for: output.createdAt), systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Output ID", output.id.uuidString, systemImage: "number", tone: .neutral),
                .init("Provider", output.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", output.providerID?.rawValue, systemImage: "key", tone: .neutral),
                .init("Response ID", output.responseID, systemImage: "bubble.left.and.text.bubble.right", tone: .neutral),
                .init("Message ID", output.messageID?.uuidString, systemImage: "message", tone: .neutral),
                .init("Schema", output.schemaName, systemImage: "checklist", tone: .info),
                .init("Status", output.status.readableArtifactKind, systemImage: "circle.dashed", tone: output.status.providerCloudStatus.tone),
                .init("Validation", output.validationErrors.isEmpty ? "Valid" : output.validationErrors.joined(separator: ", "), systemImage: "checkmark.seal", tone: validationTone),
                .init("Refusal", output.refusal, systemImage: "hand.raised", tone: .warning),
                .init("Incomplete", output.incompleteReason, systemImage: "hourglass", tone: .warning),
                .init("Created", RelativeDateTimeFormatter.shortLabel(for: output.createdAt), systemImage: "clock", tone: .neutral),
            ],
            isTerminal: output.status.providerIsTerminal
        )
    }

    init(modelCapability capability: ProviderModelCapabilityRecord) {
        self.init(
            id: "model-capability-\(capability.id)",
            title: capability.modelID.rawValue,
            detail: capability.capabilities.artifactsSummary,
            systemImage: "cpu",
            status: .custom("Metadata", .success),
            secondaryStatus: capability.expiresAt.map { .custom("Expires \(RelativeDateTimeFormatter.shortLabel(for: $0))", .warning) },
            providerKind: capability.providerKind,
            providerID: capability.providerID,
            metricItems: [
                .init("Provider", value: capability.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Capabilities", value: capability.capabilities.artifactsSummary, systemImage: "checklist", tone: .info),
                .init("Fetched", value: RelativeDateTimeFormatter.shortLabel(for: capability.fetchedAt), systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Capability ID", capability.id, systemImage: "number", tone: .neutral),
                .init("Provider", capability.providerKind.pinesLifecycleTitle, systemImage: "cloud", tone: .info),
                .init("Provider ID", capability.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Model", capability.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Capabilities", capability.capabilities.artifactsSummary, systemImage: "checklist", tone: .info),
                .init("Context", capability.contextWindowTokens.map(String.init), systemImage: "text.word.spacing", tone: .neutral),
                .init("Inputs", capability.inputModalities.joined(separator: ", "), systemImage: "square.and.arrow.down", tone: .info),
                .init("Outputs", capability.outputModalities.joined(separator: ", "), systemImage: "square.and.arrow.up", tone: .info),
                .init("Fetched", RelativeDateTimeFormatter.shortLabel(for: capability.fetchedAt), systemImage: "clock", tone: .neutral),
                .init("Expires", capability.expiresAt.map { RelativeDateTimeFormatter.shortLabel(for: $0) }, systemImage: "timer", tone: .warning),
            ],
            isTerminal: true
        )
    }

    init(artifact: PinesProviderArtifactPreview) {
        self.init(
            id: "artifact-\(artifact.providerKind.rawValue)-\(artifact.id)",
            title: artifact.title,
            detail: artifact.detail,
            systemImage: artifact.kind.artifactsProviderArtifactSystemImage,
            status: .custom(artifact.status.artifactsDisplayStatusTitle, .accent),
            secondaryStatus: artifact.byteCountLabel.map { .custom($0, .neutral) },
            providerKind: artifact.providerKind,
            providerID: artifact.providerID,
            storageKind: artifact.providerID == nil ? .localOnly : .providerHosted,
            metricItems: [
                .init("Provider", value: artifact.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Kind", value: artifact.kind, systemImage: "tag", tone: .info),
                .init("Created", value: artifact.createdLabel, systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Artifact ID", artifact.id, systemImage: "number", tone: .neutral),
                .init("Provider", artifact.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", artifact.providerID?.rawValue, systemImage: "key", tone: .neutral),
                .init("Kind", artifact.kind, systemImage: "tag", tone: .info),
                .init("Size", artifact.byteCountLabel, systemImage: "internaldrive", tone: .neutral),
                .init("Created", artifact.createdLabel, systemImage: "clock", tone: .neutral),
                .init("Storage", artifact.providerID == nil ? "Local artifact record" : "Provider-hosted", systemImage: "externaldrive.badge.icloud", tone: artifact.providerID == nil ? .success : .warning),
            ],
            isTerminal: true
        )
    }

    init(file: PinesProviderFilePreview) {
        self.init(
            id: "file-\(file.providerKind.rawValue)-\(file.id)",
            title: file.title,
            detail: file.detail,
            systemImage: file.providerKind == .gemini ? "waveform.badge.magnifyingglass" : "doc",
            status: file.status.artifactsProviderCloudStatus,
            secondaryStatus: file.expiresLabel.map { .custom("Expires \($0)", .warning) },
            providerKind: file.providerKind,
            providerID: file.providerID,
            storageKind: .providerHosted,
            metricItems: [
                .init("Provider", value: file.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Purpose", value: file.purpose, systemImage: "tag", tone: .info),
                .init("Size", value: file.byteCountLabel, systemImage: "internaldrive", tone: .neutral),
                .init("Created", value: file.createdLabel, systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("File ID", file.id, systemImage: "number", tone: .neutral),
                .init("Provider", file.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", file.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Purpose", file.purpose, systemImage: "tag", tone: .info),
                .init("Status", file.status.artifactsDisplayStatusTitle, systemImage: "circle.dashed", tone: file.status.artifactsProviderCloudStatus.tone),
                .init("Size", file.byteCountLabel, systemImage: "internaldrive", tone: .neutral),
                .init("Created", file.createdLabel, systemImage: "clock", tone: .neutral),
                .init("Expires", file.expiresLabel, systemImage: "timer", tone: .warning),
            ],
            isTerminal: file.status.artifactsProviderIsTerminal
        )
    }

    init(cache: PinesProviderCachePreview) {
        let storageKind: PinesProviderStorageKind = cache.kind == "cached_content" ? .cachedContext : .vectorStore
        self.init(
            id: "cache-\(cache.providerKind.rawValue)-\(cache.id)",
            title: cache.title,
            detail: cache.detail,
            systemImage: cache.kind == "cached_content" ? "externaldrive.badge.icloud" : "square.stack.3d.up",
            status: cache.status.artifactsProviderCloudStatus,
            secondaryStatus: cache.expiresLabel.map { .custom("Expires \($0)", .warning) },
            providerKind: cache.providerKind,
            providerID: cache.providerID,
            storageKind: storageKind,
            metricItems: [
                .init("Provider", value: cache.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Kind", value: cache.kind, systemImage: "tag", tone: .info),
                .init("Usage", value: cache.usageLabel, systemImage: "number", tone: .neutral),
                .init("Created", value: cache.createdLabel, systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Cache ID", cache.id, systemImage: "number", tone: .neutral),
                .init("Provider", cache.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", cache.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Kind", cache.kind, systemImage: storageKind.systemImage, tone: storageKind.tone),
                .init("Status", cache.status.artifactsDisplayStatusTitle, systemImage: "circle.dashed", tone: cache.status.artifactsProviderCloudStatus.tone),
                .init("Usage", cache.usageLabel, systemImage: "number", tone: .neutral),
                .init("Created", cache.createdLabel, systemImage: "clock", tone: .neutral),
                .init("Expires", cache.expiresLabel, systemImage: "timer", tone: .warning),
            ],
            isTerminal: cache.status.artifactsProviderIsTerminal
        )
    }

    init(batch: PinesProviderBatchPreview) {
        self.init(
            id: "batch-\(batch.providerKind.rawValue)-\(batch.id)",
            title: batch.title,
            detail: batch.fileSummary,
            systemImage: "tray.full",
            status: batch.status.artifactsProviderCloudStatus,
            secondaryStatus: batch.completedLabel.map { .custom($0, .success) },
            providerKind: batch.providerKind,
            providerID: batch.providerID,
            metricItems: [
                .init("Provider", value: batch.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Endpoint", value: batch.endpoint, systemImage: "arrow.left.arrow.right", tone: .info),
                .init("Created", value: batch.createdLabel, systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Batch ID", batch.id, systemImage: "number", tone: .neutral),
                .init("Provider", batch.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", batch.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Endpoint", batch.endpoint, systemImage: "arrow.left.arrow.right", tone: .info),
                .init("Status", batch.status.artifactsDisplayStatusTitle, systemImage: "circle.dashed", tone: batch.status.artifactsProviderCloudStatus.tone),
                .init("Files", batch.fileSummary, systemImage: "doc.on.doc", tone: .neutral),
                .init("Created", batch.createdLabel, systemImage: "clock", tone: .neutral),
                .init("Completed", batch.completedLabel, systemImage: "checkmark.circle", tone: .success),
            ],
            isTerminal: batch.status.artifactsProviderIsTerminal
        )
    }

    init(researchRun run: PinesProviderResearchRunPreview) {
        self.init(
            id: "research-\(run.providerKind.rawValue)-\(run.id)",
            title: run.title,
            detail: "\(run.detail) - \(run.activitySummary)",
            systemImage: "doc.text.magnifyingglass",
            status: run.status.artifactsProviderCloudStatus,
            secondaryStatus: .custom(run.updatedLabel, .neutral),
            providerKind: run.providerKind,
            providerID: run.providerID,
            metricItems: [
                .init("Provider", value: run.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Model", value: run.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Updated", value: run.updatedLabel, systemImage: "clock.arrow.circlepath", tone: .neutral),
            ],
            fields: [
                .init("Run ID", run.id, systemImage: "number", tone: .neutral),
                .init("Provider", run.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", run.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Model", run.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Status", run.status.artifactsDisplayStatusTitle, systemImage: "circle.dashed", tone: run.status.artifactsProviderCloudStatus.tone),
                .init("Request", run.detail, systemImage: "slider.horizontal.3", tone: .neutral),
                .init("Activity", run.activitySummary, systemImage: "point.3.connected.trianglepath.dotted", tone: .accent),
                .init("Updated", run.updatedLabel, systemImage: "clock.arrow.circlepath", tone: .neutral),
            ],
            isTerminal: run.status.artifactsProviderIsTerminal
        )
    }

    init(liveSession session: PinesProviderLiveSessionPreview) {
        self.init(
            id: "live-session-\(session.providerKind.rawValue)-\(session.id)",
            title: session.title,
            detail: "Transcript placeholder - \(session.modalitySummary)",
            systemImage: "dot.radiowaves.left.and.right",
            status: session.status.artifactsProviderCloudStatus,
            secondaryStatus: session.expiresLabel.map { .custom("Expires \($0)", .warning) },
            providerKind: session.providerKind,
            providerID: session.providerID,
            metricItems: [
                .init("Provider", value: session.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Model", value: session.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Created", value: session.createdLabel, systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Session ID", session.id, systemImage: "number", tone: .neutral),
                .init("Provider", session.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", session.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Model", session.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Status", session.status.artifactsDisplayStatusTitle, systemImage: "circle.dashed", tone: session.status.artifactsProviderCloudStatus.tone),
                .init("Modalities", session.modalitySummary, systemImage: "waveform", tone: .info),
                .init("Created", session.createdLabel, systemImage: "clock", tone: .neutral),
                .init("Expires", session.expiresLabel, systemImage: "timer", tone: .warning),
            ],
            isTerminal: session.status.artifactsProviderIsTerminal
        )
    }

    init(structuredOutput output: PinesProviderStructuredOutputPreview) {
        let validationTone: PinesCloudStatusTone = output.validationSummary == "Valid" ? .success : .warning
        self.init(
            id: "structured-output-\(output.providerKind.rawValue)-\(output.id.uuidString)",
            title: output.title,
            detail: output.detail,
            systemImage: "curlybraces.square",
            status: output.status.artifactsProviderCloudStatus,
            secondaryStatus: .custom(output.validationSummary, validationTone),
            providerKind: output.providerKind,
            providerID: output.providerID,
            storageKind: .localOnly,
            metricItems: [
                .init("Provider", value: output.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Validation", value: output.validationSummary, systemImage: "checkmark.seal", tone: validationTone),
                .init("Created", value: output.createdLabel, systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Output ID", output.id.uuidString, systemImage: "number", tone: .neutral),
                .init("Provider", output.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", output.providerID?.rawValue, systemImage: "key", tone: .neutral),
                .init("Status", output.status.artifactsDisplayStatusTitle, systemImage: "circle.dashed", tone: output.status.artifactsProviderCloudStatus.tone),
                .init("Validation", output.validationSummary, systemImage: "checkmark.seal", tone: validationTone),
                .init("Created", output.createdLabel, systemImage: "clock", tone: .neutral),
            ],
            isTerminal: output.status.artifactsProviderIsTerminal
        )
    }

    init(modelCapability capability: PinesProviderModelCapabilityPreview) {
        self.init(
            id: "model-capability-\(capability.providerKind.rawValue)-\(capability.id)",
            title: capability.title,
            detail: capability.detail,
            systemImage: "cpu",
            status: .custom("Metadata", .success),
            secondaryStatus: capability.expiresLabel.map { .custom("Expires \($0)", .warning) },
            providerKind: capability.providerKind,
            providerID: capability.providerID,
            metricItems: [
                .init("Provider", value: capability.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Capabilities", value: capability.capabilitySummary, systemImage: "checklist", tone: .info),
                .init("Fetched", value: capability.fetchedLabel, systemImage: "clock", tone: .neutral),
            ],
            fields: [
                .init("Capability ID", capability.id, systemImage: "number", tone: .neutral),
                .init("Provider", capability.providerKind.artifactsDisplayName, systemImage: "cloud", tone: .info),
                .init("Provider ID", capability.providerID.rawValue, systemImage: "key", tone: .neutral),
                .init("Model", capability.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Capabilities", capability.capabilitySummary, systemImage: "checklist", tone: .info),
                .init("Fetched", capability.fetchedLabel, systemImage: "clock", tone: .neutral),
                .init("Expires", capability.expiresLabel, systemImage: "timer", tone: .warning),
            ],
            isTerminal: true
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var artifactsDisplayStatusTitle: String {
        split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    var artifactsProviderCloudStatus: PinesCloudStatus {
        switch lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "") {
        case "completed", "complete", "processed", "closed":
            .complete
        case "stored", "linked":
            .custom(artifactsDisplayStatusTitle, .accent)
        case "failed", "error":
            .failed
        case "cancelled", "canceled", "expired", "deleted":
            .warning(artifactsDisplayStatusTitle)
        case "queued", "pending", "created", "validating":
            .pending
        case "inprogress", "running", "active", "finalizing", "uploaded":
            .running
        case "requiresaction", "cancelling", "deleting", "closing":
            .needsValidation
        default:
            .custom(nilIfEmpty.map { _ in artifactsDisplayStatusTitle } ?? "Unknown", .neutral)
        }
    }

    var artifactsProviderIsTerminal: Bool {
        switch lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "") {
        case "completed", "complete", "processed", "closed", "stored", "linked", "failed", "error", "cancelled", "canceled", "expired", "deleted":
            true
        default:
            false
        }
    }

    var artifactsProviderArtifactSystemImage: String {
        switch lowercased() {
        case "image":
            "photo"
        case "audio", "transcript":
            "waveform"
        case "video":
            "film"
        case "structuredoutput", "structured_output":
            "curlybraces.square"
        case "code":
            "chevron.left.forwardslash.chevron.right"
        case "tooloutput", "tool_output":
            "wrench.and.screwdriver"
        default:
            "doc"
        }
    }
}

private extension ArtifactsRetentionLabel {
    var storageKind: PinesProviderStorageKind {
        switch self {
        case .providerHosted:
            .providerHosted
        case .localCopy, .vaultImportCandidate, .localRecord:
            .localOnly
        case .remoteLink:
            .inlineThisTurn
        }
    }
}

private extension ArtifactsGalleryPresentation {
    var previewTitle: String {
        switch self {
        case .image: "Image Preview"
        case .video: "Video Preview"
        case .audio: "Audio Preview"
        case .report: "Report Preview"
        case .metadata: "Preview"
        }
    }
}

extension JSONValue {
    var prettyJSONString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: self)
        }
        return string
    }
}
