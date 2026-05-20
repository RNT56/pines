import SwiftUI
import PinesCore
import UniformTypeIdentifiers

struct ArtifactsWorkspaceView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var mode: ArtifactsWorkspaceMode = .library
    @State private var providerScope: ArtifactsProviderScope = .all
    @State private var filter = ArtifactsResourceFilter()
    @State private var selection: ArtifactsSelection?
    @State private var pendingConfirmation: ArtifactsConfirmation?

    private var lifecycleProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.pinesLifecycleProviders
    }

    private var effectiveFilter: ArtifactsResourceFilter {
        ArtifactsResourceFilter(
            query: filter.query,
            providerScope: providerScope,
            kind: filter.kind,
            sort: filter.sort
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    workspaceHeader
                    modeSwitcher

                    if let error = providerState.providerLifecycleError {
                        ArtifactsErrorBanner(message: error)
                    }

                    activeWorkspace
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .pinesExpressiveScrollHaptics()
            .pinesAppBackground()
            .navigationTitle("Artifacts")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await appModel.refreshProviderLifecycleState(services: services) }
                    } label: {
                        if providerState.isRefreshingProviderLifecycle {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .accessibilityLabel("Refresh artifacts")

                    Menu {
                        ForEach(lifecycleProviders) { provider in
                            Button(provider.displayName) {
                                Task { await refreshProviderStorage(provider) }
                            }
                        }
                    } label: {
                        Image(systemName: "cloud")
                    }
                    .accessibilityLabel("Refresh provider storage")
                    .disabled(lifecycleProviders.isEmpty)
                }
            }
            .task {
                await appModel.refreshProviderLifecycleState(services: services)
            }
            .confirmationDialog(
                pendingConfirmation?.title ?? "Confirm",
                isPresented: Binding(
                    get: { pendingConfirmation != nil },
                    set: { if !$0 { pendingConfirmation = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingConfirmation,
                actions: confirmationActions,
                message: { confirmation in Text(confirmation.message) }
            )
        }
    }

    private var workspaceHeader: some View {
        let counts = ArtifactsWorkspaceDeriver.counts(state: providerState, scope: providerScope)
        return VStack(alignment: .leading, spacing: theme.spacing.medium) {
            HStack(alignment: .top, spacing: theme.spacing.medium) {
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    PinesSectionHeader(
                        "Provider Artifacts",
                        subtitle: "A focused workspace for provider-hosted files, generated media, jobs, sessions, structured outputs, and model capabilities."
                    )
                    HStack(spacing: theme.spacing.small) {
                        Picker("Provider scope", selection: $providerScope) {
                            ForEach(ArtifactsWorkspaceDeriver.providerScopes(from: lifecycleProviders)) { scope in
                                Text(scope.title(providers: lifecycleProviders)).tag(scope)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Sort", selection: $filter.sort) {
                            ForEach(ArtifactsSort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Spacer(minLength: theme.spacing.small)

                VStack(alignment: .trailing, spacing: theme.spacing.xsmall) {
                    PinesStatusChip(
                        status: providerState.isRefreshingProviderLifecycle ? .running : .custom("\(counts.providerResources) resources", .accent),
                        compact: false
                    )
                    Text(providerScope.title(providers: lifecycleProviders))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            PinesMetricPillGroup(items: [
                .init("Files", value: "\(counts.files)", systemImage: "doc", tone: .warning),
                .init("Artifacts", value: "\(counts.artifacts)", systemImage: "sparkles", tone: .accent),
                .init("Structured", value: "\(counts.structuredOutputs)", systemImage: "curlybraces", tone: .success),
                .init("Context", value: "\(counts.caches)", systemImage: "externaldrive", tone: .info),
                .init("Batches", value: "\(counts.batches)", systemImage: "tray.full", tone: .info),
                .init("Research", value: "\(counts.researchRuns)", systemImage: "doc.text.magnifyingglass", tone: .accent),
                .init("Realtime", value: "\(counts.liveSessions)", systemImage: "dot.radiowaves.left.and.right", tone: .info),
                .init("Capabilities", value: "\(counts.capabilities)", systemImage: "cpu", tone: .neutral),
            ], minimumWidth: 118)
        }
        .pinesSurface(.panel, padding: theme.spacing.medium)
    }

    private var modeSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.xsmall) {
                ForEach(ArtifactsWorkspaceMode.allCases) { item in
                    Button {
                        mode = item
                        selection = nil
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                            .font(theme.typography.caption.weight(.semibold))
                            .padding(.horizontal, theme.spacing.small)
                            .padding(.vertical, theme.spacing.xsmall)
                            .frame(minHeight: 34)
                            .background(
                                mode == item ? theme.colors.accentSoft : theme.colors.controlFill,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(mode == item ? theme.colors.accent.opacity(0.32) : theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(mode == item ? theme.colors.accent : theme.colors.secondaryText)
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.vertical, theme.spacing.xxsmall)
        }
    }

    @ViewBuilder
    private var activeWorkspace: some View {
        switch mode {
        case .library:
            ArtifactsLibraryWorkspace(filter: $filter, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .media:
            ArtifactsMediaWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .files:
            ArtifactsFilesWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .context:
            ArtifactsContextWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .batches:
            ArtifactsBatchesWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .research:
            ArtifactsResearchWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .realtime:
            ArtifactsRealtimeWorkspace(providerScope: providerScope, selection: $selection)
        case .capabilities:
            ArtifactsCapabilitiesWorkspace(providerScope: providerScope, selection: $selection)
        }
    }

    @MainActor
    private func refreshProviderStorage(_ provider: CloudProviderConfiguration) async {
        do {
            switch provider.kind {
            case .openAI:
                _ = try await appModel.refreshOpenAIProviderStorage(providerID: provider.id, services: services)
            case .anthropic:
                _ = try await appModel.refreshAnthropicProviderStorage(providerID: provider.id, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiProviderStorage(providerID: provider.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) provider storage is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func confirmationActions(_ confirmation: ArtifactsConfirmation) -> some View {
        switch confirmation {
        case .deleteArtifactRecord(let artifact):
            Button("Delete local record", role: .destructive) {
                Task { await deleteArtifactRecord(artifact) }
            }
        case .deleteProviderFile(let file):
            Button("Delete provider file", role: .destructive) {
                Task { await deleteProviderFile(file) }
            }
        case .deleteProviderCache(let cache):
            Button("Delete provider context", role: .destructive) {
                Task { await deleteProviderCache(cache) }
            }
        case .cancelBatch(let batch):
            Button("Cancel batch", role: .destructive) {
                Task { await cancelBatch(batch) }
            }
        case .cancelResearch(let run):
            Button("Cancel research run", role: .destructive) {
                Task { await cancelResearch(run) }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    @MainActor
    private func deleteArtifactRecord(_ artifact: ProviderArtifactRecord) async {
        do {
            try await appModel.deleteProviderArtifactRecord(id: artifact.id, services: services)
            selection = nil
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteProviderFile(_ file: ProviderFileRecord) async {
        do {
            switch file.providerKind {
            case .openAI:
                try await appModel.deleteOpenAIProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .anthropic:
                try await appModel.deleteAnthropicProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .gemini:
                try await appModel.deleteGeminiProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(file.providerKind.pinesLifecycleTitle) file deletion is not supported here.")
            }
            selection = nil
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteProviderCache(_ cache: ProviderCacheRecord) async {
        do {
            switch cache.providerKind {
            case .openAI:
                try await appModel.deleteOpenAIVectorStore(providerID: cache.providerID, vectorStoreID: cache.id, services: services)
            case .gemini:
                try await appModel.deleteGeminiContextCache(providerID: cache.providerID, cacheID: cache.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(cache.providerKind.pinesLifecycleTitle) context deletion is not supported here.")
            }
            selection = nil
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func cancelBatch(_ batch: ProviderBatchRecord) async {
        do {
            switch batch.providerKind {
            case .openAI:
                _ = try await appModel.cancelOpenAIBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .anthropic:
                _ = try await appModel.cancelAnthropicBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .gemini:
                _ = try await appModel.cancelGeminiBatch(id: batch.id, providerID: batch.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(batch.providerKind.pinesLifecycleTitle) batch cancellation is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func cancelResearch(_ run: ProviderResearchRunRecord) async {
        do {
            switch run.providerKind {
            case .openAI:
                _ = try await appModel.cancelOpenAIDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            case .gemini:
                _ = try await appModel.cancelGeminiDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(run.providerKind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactsLibraryWorkspace: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @Binding var filter: ArtifactsResourceFilter
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?

    private var summaries: [ArtifactsResourceSummary] {
        (
            ArtifactsWorkspaceDeriver.artifactSummaries(artifacts: providerState.providerArtifacts, filter: filter)
            + ArtifactsWorkspaceDeriver.structuredOutputSummaries(outputs: providerState.providerStructuredOutputs, filter: filter)
        )
        .sorted { lhs, rhs in
            switch filter.sort {
            case .oldest:
                (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
            case .provider:
                lhs.providerKind.pinesLifecycleTitle < rhs.providerKind.pinesLifecycleTitle
            case .kind:
                lhs.kind < rhs.kind
            case .newest:
                (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            ArtifactsLibraryControls(filter: $filter)
            responsiveListAndDetail(
                list: {
                    ArtifactsResourceList(
                        summaries: summaries,
                        selection: $selection,
                        emptyTitle: "No artifacts",
                        emptyDetail: "Generated media, hosted tool outputs, transcripts, batch results, and structured outputs appear here."
                    )
                },
                detail: {
                    ArtifactsDetailPanel(
                        selection: selection,
                        providerState: providerState,
                        onImportArtifact: { artifact in
                            Task { await importArtifact(artifact) }
                        },
                        onDeleteArtifactRecord: { artifact in
                            pendingConfirmation = .deleteArtifactRecord(artifact)
                        }
                    )
                }
            )
        }
    }

    @MainActor
    private func importArtifact(_ artifact: ProviderArtifactRecord) async {
        do {
            _ = try await appModel.importProviderArtifactToVault(id: artifact.id, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func responsiveListAndDetail<ListContent: View, DetailContent: View>(
        @ViewBuilder list: () -> ListContent,
        @ViewBuilder detail: () -> DetailContent
    ) -> some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                list()
                detail()
            }
        } else {
            HStack(alignment: .top, spacing: theme.spacing.medium) {
                VStack { list() }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                detail()
                    .frame(width: 390, alignment: .topLeading)
            }
        }
    }
}

private struct ArtifactsLibraryControls: View {
    @Environment(\.pinesTheme) private var theme
    @Binding var filter: ArtifactsResourceFilter

    private let kinds = [
        "All kinds",
        "image",
        "video",
        "audio",
        "transcription",
        "translation",
        "speech",
        "tool_output",
        "hosted_tool_call",
        "file_reference",
        "structured_output",
        "batch_result",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            TextField("Search artifacts, IDs, files, providers, or response links", text: $filter.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()

            Picker("Kind", selection: Binding(
                get: { filter.kind ?? "All kinds" },
                set: { value in filter.kind = value == "All kinds" ? nil : value }
            )) {
                ForEach(kinds, id: \.self) { kind in
                    Text(kind.readableArtifactKind).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
        .pinesSurface(.panel, padding: theme.spacing.medium)
    }
}

private struct ArtifactsMediaWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    @State private var mediaKind = "image"
    @State private var modelID = "gpt-image-1"
    @State private var prompt = ""
    @State private var isCreating = false

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .gemini])
    }

    private var mediaSummaries: [ArtifactsResourceSummary] {
        let filter = ArtifactsResourceFilter(query: "", providerScope: providerScope, kind: nil, sort: .newest)
        return ArtifactsWorkspaceDeriver.artifactSummaries(
            artifacts: providerState.providerArtifacts.filter { artifact in
                ["image", "video", "audio", "speech", "transcription", "translation", "generated_media", "media_operation", "partial_image"].contains(artifact.kind)
            },
            filter: filter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Media Studio", subtitle: "Create and inspect provider media artifacts without mixing them into every other lifecycle tool.", systemImage: "photo.stack") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    providerRequirement(allowed: "OpenAI or Gemini")
                    Picker("Kind", selection: $mediaKind) {
                        Text("Image").tag("image")
                        Text("Video").tag("video")
                        Text("Speech").tag("speech")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mediaKind) { _, value in applyDefaultModel(for: value) }

                    TextField("Model", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pinesFieldChrome()

                    TextField("Prompt", text: $prompt, axis: .vertical)
                        .lineLimit(3...7)
                        .pinesFieldChrome()

                    Button {
                        Task { await createMedia() }
                    } label: {
                        Label(isCreating ? "Creating" : "Create artifact", systemImage: isCreating ? "hourglass" : "sparkles")
                    }
                    .disabled(isCreating || provider == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pinesButtonStyle(.primary)
                }
            }

            ArtifactsResourceList(
                summaries: mediaSummaries,
                selection: $selection,
                emptyTitle: "No media artifacts",
                emptyDetail: "Generated images, videos, audio, and provider media operations appear here."
            )
        }
    }

    @ViewBuilder
    private func providerRequirement(allowed: String) -> some View {
        if let provider {
            PinesStatusChip(status: .custom("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)", .info))
        } else {
            PinesEmptyState(title: "Choose a provider", detail: "Set the page provider scope to \(allowed) before creating media.", systemImage: "cloud")
                .pinesSurface(.inset, padding: theme.spacing.small)
        }
    }

    @MainActor
    private func createMedia() async {
        guard let provider else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            switch provider.kind {
            case .openAI:
                switch mediaKind {
                case "video":
                    _ = try await appModel.createOpenAIVideoArtifact(OpenAIVideoArtifactRequest(prompt: trimmedPrompt, model: model.rawValue), providerID: provider.id, services: services)
                case "speech":
                    _ = try await appModel.createOpenAISpeechArtifact(OpenAISpeechArtifactRequest(model: model.rawValue, input: trimmedPrompt, voice: "alloy"), providerID: provider.id, services: services)
                default:
                    _ = try await appModel.createOpenAIImageArtifacts(providerID: provider.id, modelID: model, prompt: trimmedPrompt, services: services)
                }
            case .gemini:
                _ = try await appModel.createGeminiGeneratedMedia(providerID: provider.id, modelID: model, prompt: trimmedPrompt, kind: mediaKind, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) media artifacts are not supported here.")
            }
            prompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func applyDefaultModel(for kind: String) {
        switch (provider?.kind, kind) {
        case (.some(.gemini), "video"):
            modelID = "veo-3.1-generate-preview"
        case (.some(.gemini), "speech"):
            modelID = "gemini-2.5-flash-preview-tts"
        case (.some(.gemini), _):
            modelID = "imagen-4.0-generate-preview"
        case (.some(.openAI), "video"):
            modelID = "sora-2"
        case (.some(.openAI), "speech"):
            modelID = "gpt-4o-mini-tts"
        default:
            modelID = "gpt-image-1"
        }
    }
}

private struct ArtifactsFilesWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @EnvironmentObject private var vaultState: PinesVaultState
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    @State private var isImporterPresented = false
    @State private var isUploading = false
    @State private var selectedVaultDocumentID: UUID?
    @State private var purpose = "assistants"

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .anthropic, .gemini])
    }

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.fileSummaries(files: providerState.providerFiles, filter: .init(providerScope: providerScope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Provider Files", subtitle: "Upload, refresh, import from Vault, and delete provider-hosted files separately from local Vault documents.", systemImage: "doc.badge.arrow.up") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    providerRequirement(allowed: "OpenAI, Anthropic, or Gemini")
                    if provider?.kind == .openAI {
                        TextField("OpenAI purpose", text: $purpose)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .pinesFieldChrome()
                    }
                    HStack(spacing: theme.spacing.small) {
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label(isUploading ? "Uploading" : "Upload local file", systemImage: isUploading ? "hourglass" : "square.and.arrow.up")
                        }
                        .disabled(provider == nil || isUploading)
                        .pinesButtonStyle(.primary)

                        Button {
                            Task { await refreshStorage() }
                        } label: {
                            Label("Refresh provider", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(provider == nil)
                    }

                    HStack(spacing: theme.spacing.small) {
                        Picker("Vault document", selection: $selectedVaultDocumentID) {
                            Text("Choose Vault document").tag(Optional<UUID>.none)
                            ForEach(vaultState.vaultItems) { item in
                                Text(item.title).tag(Optional(item.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            Task { await uploadVaultDocument() }
                        } label: {
                            Label("Upload Vault copy", systemImage: "shippingbox")
                        }
                        .disabled(selectedVaultDocumentID == nil || provider == nil || provider?.kind == .gemini)
                    }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                Task { await handleImport(result) }
            }

            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No provider files", emptyDetail: "Provider-hosted files appear here after upload or provider refresh.")

            fileActions
        }
    }

    @ViewBuilder
    private var fileActions: some View {
        if case .file(let id) = selection, let file = providerState.providerFiles.first(where: { $0.id == id }) {
            PinesCardSection("File Actions", subtitle: "These operate on provider-hosted file state, not local Vault source files.", systemImage: "ellipsis.circle") {
                HStack(spacing: theme.spacing.small) {
                    Button("Refresh") {
                        Task { await refreshFile(file) }
                    }
                    .buttonStyle(.borderless)
                    if file.providerKind == .anthropic {
                        Button("Download as artifact") {
                            Task { await downloadFile(file) }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("Delete provider file", role: .destructive) {
                        pendingConfirmation = .deleteProviderFile(file)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func providerRequirement(allowed: String) -> some View {
        if let provider {
            PinesStatusChip(status: .custom("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)", .info))
        } else {
            PinesEmptyState(title: "Choose a provider", detail: "Set the page provider scope to \(allowed).", systemImage: "cloud")
                .pinesSurface(.inset, padding: theme.spacing.small)
        }
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        guard let provider else { return }
        do {
            guard let url = try result.get().first else { return }
            isUploading = true
            defer { isUploading = false }
            let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            switch provider.kind {
            case .openAI:
                let consent = PinesOpenAIProviderStorageConsent(isGranted: true, sourceDescription: url.lastPathComponent, destinationDescription: "OpenAI Files API for \(provider.displayName)", byteCount: byteCount)
                _ = try await appModel.uploadOpenAILocalFile(providerID: provider.id, fileURL: url, purpose: purpose, consent: consent, services: services)
            case .anthropic:
                let consent = PinesAnthropicProviderStorageConsent(isGranted: true, sourceDescription: url.lastPathComponent, destinationDescription: "Anthropic Files API for \(provider.displayName)", byteCount: byteCount)
                _ = try await appModel.uploadAnthropicLocalFile(providerID: provider.id, fileURL: url, consent: consent, services: services)
            case .gemini:
                let consent = PinesGeminiProviderStorageConsent(isGranted: true, sourceDescription: url.lastPathComponent, destinationDescription: "Gemini Files API for \(provider.displayName)", byteCount: byteCount)
                _ = try await appModel.uploadGeminiLocalFile(providerID: provider.id, fileURL: url, consent: consent, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) file upload is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
            isUploading = false
        }
    }

    @MainActor
    private func uploadVaultDocument() async {
        guard let provider, let selectedVaultDocumentID else { return }
        do {
            switch provider.kind {
            case .openAI:
                let consent = PinesOpenAIProviderStorageConsent(isGranted: true, sourceDescription: "Vault document \(selectedVaultDocumentID.uuidString)", destinationDescription: "OpenAI Files API for \(provider.displayName)")
                _ = try await appModel.uploadOpenAIVaultDocument(providerID: provider.id, documentID: selectedVaultDocumentID, purpose: purpose, consent: consent, services: services)
            case .anthropic:
                let consent = PinesAnthropicProviderStorageConsent(isGranted: true, sourceDescription: "Vault document \(selectedVaultDocumentID.uuidString)", destinationDescription: "Anthropic Files API for \(provider.displayName)")
                _ = try await appModel.uploadAnthropicVaultDocument(providerID: provider.id, documentID: selectedVaultDocumentID, consent: consent, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Vault document upload is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshStorage() async {
        guard let provider else { return }
        do {
            switch provider.kind {
            case .openAI:
                _ = try await appModel.refreshOpenAIProviderStorage(providerID: provider.id, services: services)
            case .anthropic:
                _ = try await appModel.refreshAnthropicProviderStorage(providerID: provider.id, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiProviderStorage(providerID: provider.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) refresh is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshFile(_ file: ProviderFileRecord) async {
        do {
            switch file.providerKind {
            case .anthropic:
                _ = try await appModel.refreshAnthropicProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .openAI:
                _ = try await appModel.refreshOpenAIProviderStorage(providerID: file.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(file.providerKind.pinesLifecycleTitle) file refresh is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func downloadFile(_ file: ProviderFileRecord) async {
        do {
            _ = try await appModel.downloadAnthropicProviderFileContent(providerID: file.providerID, fileID: file.id, fileName: file.fileName, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactsContextWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    @State private var name = ""
    @State private var modelID = "gemini-2.5-pro"
    @State private var ttlSeconds = "3600"
    @State private var contextText = ""
    @State private var isCreating = false

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .gemini])
    }

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.cacheSummaries(caches: providerState.providerCaches, filter: .init(providerScope: providerScope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Context Storage", subtitle: "Manage OpenAI vector stores and Gemini cached contexts as explicit provider-hosted resources.", systemImage: "externaldrive.badge.icloud") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    if let provider {
                        PinesStatusChip(status: .custom("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)", .info))
                    } else {
                        PinesEmptyState(title: "Choose OpenAI or Gemini", detail: "Set the page provider scope before creating provider context.", systemImage: "cloud")
                            .pinesSurface(.inset, padding: theme.spacing.small)
                    }
                    HStack(spacing: theme.spacing.small) {
                        TextField(provider?.kind == .openAI ? "Vector store name" : "Cache name", text: $name)
                            .pinesFieldChrome()
                        TextField("Model", text: $modelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .pinesFieldChrome()
                    }
                    if provider?.kind == .gemini {
                        TextField("TTL seconds", text: $ttlSeconds)
                            .pinesFieldChrome()
                        TextField("Context to cache", text: $contextText, axis: .vertical)
                            .lineLimit(3...7)
                            .pinesFieldChrome()
                    }
                    Button {
                        Task { await createContext() }
                    } label: {
                        Label(isCreating ? "Creating" : "Create context resource", systemImage: isCreating ? "hourglass" : "plus.circle")
                    }
                    .disabled(provider == nil || isCreating || (provider?.kind == .gemini && contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .pinesButtonStyle(.primary)
                }
            }

            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No context resources", emptyDetail: "OpenAI vector stores and Gemini context caches appear here.")

            if case .cache(let id) = selection, let cache = providerState.providerCaches.first(where: { $0.id == id }) {
                PinesCardSection("Context Actions", subtitle: "Refresh or remove provider-hosted context storage.", systemImage: "ellipsis.circle") {
                    HStack(spacing: theme.spacing.small) {
                        Button("Refresh") {
                            Task { await refreshCache(cache) }
                        }
                        .buttonStyle(.borderless)
                        Button("Delete provider context", role: .destructive) {
                            pendingConfirmation = .deleteProviderCache(cache)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @MainActor
    private func createContext() async {
        guard let provider else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            switch provider.kind {
            case .openAI:
                _ = try await appModel.createOpenAIVectorStore(providerID: provider.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), services: services)
            case .gemini:
                _ = try await appModel.createGeminiContextCache(
                    providerID: provider.id,
                    modelID: ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                    displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    text: contextText,
                    ttlSeconds: Int(ttlSeconds),
                    services: services
                )
                contextText = ""
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) context storage is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshCache(_ cache: ProviderCacheRecord) async {
        do {
            switch cache.providerKind {
            case .openAI:
                _ = try await appModel.refreshOpenAIVectorStoreFiles(providerID: cache.providerID, vectorStoreID: cache.id, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiContextCache(providerID: cache.providerID, cacheID: cache.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(cache.providerKind.pinesLifecycleTitle) context refresh is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactsBatchesWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    @State private var modelID = "claude-sonnet-4-5"
    @State private var customID = ""
    @State private var prompt = ""
    @State private var maxTokens = "1024"
    @State private var isCreating = false
    @State private var isCounting = false
    @State private var tokenCount: Int?

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .anthropic, .gemini])
    }

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.batchSummaries(batches: providerState.providerBatches, filter: .init(providerScope: providerScope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Batches", subtitle: "Create Anthropic prompt batches and manage provider batch records across OpenAI, Anthropic, and Gemini.", systemImage: "tray.full") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    if let provider {
                        PinesStatusChip(status: .custom("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)", .info))
                    } else {
                        PinesEmptyState(title: "Choose a provider", detail: "Set the page provider scope to create or manage batches.", systemImage: "cloud")
                            .pinesSurface(.inset, padding: theme.spacing.small)
                    }
                    HStack(spacing: theme.spacing.small) {
                        TextField("Model", text: $modelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .pinesFieldChrome()
                        TextField("Max tokens", text: $maxTokens)
                            .pinesFieldChrome()
                            .frame(maxWidth: 130)
                    }
                    TextField("Custom ID", text: $customID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pinesFieldChrome()
                    TextField("Batch prompt", text: $prompt, axis: .vertical)
                        .lineLimit(3...7)
                        .pinesFieldChrome()
                        .onChange(of: prompt) { _, _ in tokenCount = nil }
                    HStack(spacing: theme.spacing.small) {
                        Button {
                            Task { await countTokens() }
                        } label: {
                            Label(isCounting ? "Counting" : "Count tokens", systemImage: isCounting ? "hourglass" : "number")
                        }
                        .disabled(provider?.kind != .anthropic || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCounting)

                        Button {
                            Task { await createBatch() }
                        } label: {
                            Label(isCreating ? "Creating" : "Create batch", systemImage: isCreating ? "hourglass" : "plus.circle")
                        }
                        .disabled(provider?.kind != .anthropic || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                        .pinesButtonStyle(.primary)

                        Spacer()

                        if let tokenCount {
                            Text("\(tokenCount) input tokens")
                                .font(theme.typography.caption.weight(.semibold))
                                .foregroundStyle(theme.colors.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }
            }

            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No batches", emptyDetail: "Provider background jobs appear here after refresh or creation.")

            if case .batch(let id) = selection, let batch = providerState.providerBatches.first(where: { $0.id == id }) {
                PinesCardSection("Batch Actions", subtitle: "Cancel running jobs or import terminal result artifacts where supported.", systemImage: "ellipsis.circle") {
                    HStack(spacing: theme.spacing.small) {
                        Button("Refresh") {
                            Task { await refreshBatch(batch) }
                        }
                        .buttonStyle(.borderless)
                        Button("Cancel", role: .destructive) {
                            pendingConfirmation = .cancelBatch(batch)
                        }
                        .buttonStyle(.borderless)
                        .disabled(batch.status.providerIsTerminal)
                        Button("Import results") {
                            Task { await importResults(batch) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(!batch.status.providerIsTerminal)
                    }
                }
            }
        }
    }

    @MainActor
    private func countTokens() async {
        guard let provider else { return }
        isCounting = true
        defer { isCounting = false }
        do {
            tokenCount = try await appModel.countAnthropicTokens(
                providerID: provider.id,
                modelID: ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                text: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                services: services
            )
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func createBatch() async {
        guard let provider else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            _ = try await appModel.createAnthropicMessageBatch(
                providerID: provider.id,
                modelID: ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                customID: customID,
                maxTokens: Int(maxTokens) ?? 1024,
                services: services
            )
            prompt = ""
            customID = ""
            tokenCount = nil
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshBatch(_ batch: ProviderBatchRecord) async {
        do {
            switch batch.providerKind {
            case .openAI:
                _ = try await appModel.refreshOpenAIBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .anthropic:
                _ = try await appModel.refreshAnthropicBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiBatch(id: batch.id, providerID: batch.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(batch.providerKind.pinesLifecycleTitle) batch refresh is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func importResults(_ batch: ProviderBatchRecord) async {
        do {
            switch batch.providerKind {
            case .openAI:
                _ = try await appModel.importOpenAIBatchResultArtifacts(id: batch.id, providerID: batch.providerID, services: services)
            case .anthropic:
                _ = try await appModel.importAnthropicBatchResults(id: batch.id, providerID: batch.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(batch.providerKind.pinesLifecycleTitle) result import is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactsResearchWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    @State private var title = ""
    @State private var prompt = ""
    @State private var modelID = "gpt-5.5-pro"
    @State private var depth: OpenAIDeepResearchDepth = .standard
    @State private var reportFormat: OpenAIDeepResearchReportFormat = .memo
    @State private var isStarting = false

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .gemini])
    }

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.researchSummaries(runs: providerState.providerResearchRuns, filter: .init(providerScope: providerScope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Deep Research", subtitle: "Start, resume, refresh, and cancel long-running provider research jobs.", systemImage: "doc.text.magnifyingglass") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    if let provider {
                        PinesStatusChip(status: .custom("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)", .info))
                    } else {
                        PinesEmptyState(title: "Choose OpenAI or Gemini", detail: "Set the page provider scope before starting Deep Research.", systemImage: "cloud")
                            .pinesSurface(.inset, padding: theme.spacing.small)
                    }
                    HStack(spacing: theme.spacing.small) {
                        TextField("Title", text: $title)
                            .pinesFieldChrome()
                        TextField("Model", text: $modelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .pinesFieldChrome()
                    }
                    TextField("Research prompt", text: $prompt, axis: .vertical)
                        .lineLimit(3...7)
                        .pinesFieldChrome()
                    HStack(spacing: theme.spacing.small) {
                        Picker("Depth", selection: $depth) {
                            ForEach(OpenAIDeepResearchDepth.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Format", selection: $reportFormat) {
                            ForEach(OpenAIDeepResearchReportFormat.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Button {
                            Task { await startRun() }
                        } label: {
                            Label(isStarting ? "Starting" : "Start", systemImage: isStarting ? "hourglass" : "play.fill")
                        }
                        .disabled(provider == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStarting)
                        .pinesButtonStyle(.primary)
                    }
                    Button("Resume active runs") {
                        Task { await resumeRuns() }
                    }
                    .disabled(provider == nil)
                    .buttonStyle(.borderless)
                }
            }

            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No research runs", emptyDetail: "Provider Deep Research runs appear here.")

            if case .research(let id) = selection, let run = providerState.providerResearchRuns.first(where: { $0.id == id }) {
                PinesCardSection("Research Actions", subtitle: "Refresh progress or cancel non-terminal provider research.", systemImage: "ellipsis.circle") {
                    HStack(spacing: theme.spacing.small) {
                        Button("Refresh") {
                            Task { await refreshRun(run) }
                        }
                        .buttonStyle(.borderless)
                        Button("Cancel", role: .destructive) {
                            pendingConfirmation = .cancelResearch(run)
                        }
                        .buttonStyle(.borderless)
                        .disabled(run.status.providerIsTerminal)
                    }
                }
            }
        }
    }

    @MainActor
    private func startRun() async {
        guard let provider else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = trimmedTitle.isEmpty ? "Deep research" : trimmedTitle
            let model = ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            let vectorStoreIDs = providerState.providerVectorStores.filter { $0.providerID == provider.id }.map(\.id)
            let providerFileIDs = providerState.providerFiles.filter { $0.providerID == provider.id }.map(\.id)
            switch provider.kind {
            case .openAI:
                let request = OpenAIDeepResearchRequest(
                    providerID: provider.id,
                    modelID: model,
                    title: resolvedTitle,
                    prompt: prompt,
                    depth: depth,
                    sourcePolicy: .webAndFiles(
                        vectorStoreIDs: vectorStoreIDs.map { OpenAIVectorStoreID(rawValue: $0) },
                        providerFileIDs: providerFileIDs.map { OpenAIProviderFileID(rawValue: $0) }
                    ),
                    reportFormat: reportFormat
                )
                _ = try await appModel.startOpenAIDeepResearch(request, services: services)
            case .gemini:
                let request = PinesProviderDeepResearchRequest(
                    providerID: provider.id,
                    providerKind: provider.kind,
                    modelID: model,
                    title: resolvedTitle,
                    prompt: prompt,
                    depth: depth.rawValue,
                    reportFormat: reportFormat.rawValue,
                    vectorStoreIDs: vectorStoreIDs,
                    providerFileIDs: providerFileIDs
                )
                _ = try await appModel.startGeminiDeepResearch(request, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
            prompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func resumeRuns() async {
        guard let provider else { return }
        do {
            switch provider.kind {
            case .openAI:
                _ = try await appModel.resumeOpenAIDeepResearchRuns(providerID: provider.id, services: services)
            case .gemini:
                _ = try await appModel.resumeGeminiDeepResearchRuns(providerID: provider.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshRun(_ run: ProviderResearchRunRecord) async {
        do {
            switch run.providerKind {
            case .openAI:
                _ = try await appModel.refreshOpenAIDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(run.providerKind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactsRealtimeWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @State private var modelID = "gpt-4o-realtime-preview"
    @State private var includesAudio = true
    @State private var isCreating = false

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .gemini])
    }

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.liveSessionSummaries(sessions: providerState.providerLiveSessions, filter: .init(providerScope: providerScope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Realtime Sessions", subtitle: "Create and inspect realtime/live session records. Full audio transport remains a separate workflow.", systemImage: "dot.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    if let provider {
                        PinesStatusChip(status: .custom("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)", .info))
                    } else {
                        PinesEmptyState(title: "Choose OpenAI or Gemini", detail: "Set the page provider scope before creating a realtime session record.", systemImage: "cloud")
                            .pinesSurface(.inset, padding: theme.spacing.small)
                    }
                    TextField("Model", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pinesFieldChrome()
                    Toggle("Audio modality", isOn: $includesAudio)
                        .toggleStyle(.switch)
                    Button {
                        Task { await createSession() }
                    } label: {
                        Label(isCreating ? "Creating" : "Create session", systemImage: isCreating ? "hourglass" : "plus.circle")
                    }
                    .disabled(provider == nil || isCreating)
                    .pinesButtonStyle(.primary)
                }
            }

            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No realtime sessions", emptyDetail: "Session records and transcript placeholders appear here.")
        }
    }

    @MainActor
    private func createSession() async {
        guard let provider else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let modalities = includesAudio ? ["text", "audio"] : ["text"]
            let model = ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            let session: JSONValue = .object([
                "type": .string("realtime"),
                "model": .string(model.rawValue),
                "modalities": .array(modalities.map { .string($0) }),
            ])
            switch provider.kind {
            case .openAI:
                let request = OpenAIRealtimeSessionWorkflowRequest(kind: .clientSecret(OpenAIRealtimeClientSecretRequest(session: session), modalities: modalities), fallbackModelID: model)
                _ = try await appModel.createOpenAIRealtimeSessionRecord(request, providerID: provider.id, services: services)
            case .gemini:
                let request = PinesProviderRealtimeSessionRequest(providerID: provider.id, providerKind: provider.kind, modelID: model, modalities: modalities, session: session)
                _ = try await appModel.createGeminiRealtimeSessionRecord(request, providerID: provider.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Realtime is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactsCapabilitiesWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.capabilitySummaries(capabilities: providerState.providerModelCapabilities, filter: .init(providerScope: providerScope, sort: .provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Provider Model Capabilities", subtitle: "Provider metadata powers model picker gating and marks estimated fallbacks clearly.", systemImage: "cpu") {
                PinesMetricPillGroup(items: [
                    .init("Models", value: "\(summaries.count)", systemImage: "cpu", tone: .info),
                    .init("Providers", value: "\(Set(summaries.map(\.providerKind)).count)", systemImage: "cloud", tone: .warning),
                ])
            }
            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No capability metadata", emptyDetail: "Refresh provider storage to populate model capability rows.")
        }
    }
}

private struct ArtifactsErrorBanner: View {
    @Environment(\.pinesTheme) private var theme
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.danger)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.colors.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinesSurface(.inset, padding: theme.spacing.small)
    }
}

enum ArtifactsConfirmation: Identifiable {
    case deleteArtifactRecord(ProviderArtifactRecord)
    case deleteProviderFile(ProviderFileRecord)
    case deleteProviderCache(ProviderCacheRecord)
    case cancelBatch(ProviderBatchRecord)
    case cancelResearch(ProviderResearchRunRecord)

    var id: String {
        switch self {
        case .deleteArtifactRecord(let artifact): "delete-artifact-\(artifact.id)"
        case .deleteProviderFile(let file): "delete-file-\(file.id)"
        case .deleteProviderCache(let cache): "delete-cache-\(cache.id)"
        case .cancelBatch(let batch): "cancel-batch-\(batch.id)"
        case .cancelResearch(let run): "cancel-research-\(run.id)"
        }
    }

    var title: String {
        switch self {
        case .deleteArtifactRecord: "Delete local artifact record?"
        case .deleteProviderFile: "Delete provider-hosted file?"
        case .deleteProviderCache: "Delete provider-hosted context?"
        case .cancelBatch: "Cancel provider batch?"
        case .cancelResearch: "Cancel research run?"
        }
    }

    var message: String {
        switch self {
        case .deleteArtifactRecord(let artifact):
            "This removes only Pines' local lifecycle record for \(artifact.fileName ?? artifact.id). It does not delete provider-hosted files or remote resources."
        case .deleteProviderFile(let file):
            "This asks \(file.providerKind.pinesLifecycleTitle) to delete \(file.fileName). The local Vault source, if any, is not deleted."
        case .deleteProviderCache(let cache):
            "This asks \(cache.providerKind.pinesLifecycleTitle) to delete \(cache.name ?? cache.id). Local Vault documents are not deleted."
        case .cancelBatch(let batch):
            "This asks \(batch.providerKind.pinesLifecycleTitle) to cancel batch \(batch.id). Completed output files are not imported automatically."
        case .cancelResearch(let run):
            "This asks \(run.providerKind.pinesLifecycleTitle) to cancel research run \(run.title). Existing saved artifacts remain local records."
        }
    }
}

private extension Array where Element == CloudProviderConfiguration {
    var pinesLifecycleProviders: [CloudProviderConfiguration] {
        filter { $0.kind == .openAI || $0.kind == .anthropic || $0.kind == .gemini }
    }

    func provider(in scope: ArtifactsProviderScope, allowed kinds: Set<CloudProviderKind>) -> CloudProviderConfiguration? {
        switch scope {
        case .all:
            first { kinds.contains($0.kind) }
        case .provider(let id):
            first { $0.id == id && kinds.contains($0.kind) }
        }
    }
}
