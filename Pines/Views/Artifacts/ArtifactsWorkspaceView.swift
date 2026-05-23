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
                    .accessibilityLabel("Refresh cloud resources")
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
        .accessibilityIdentifier("pines.screen.artifacts")
    }

    private var workspaceHeader: some View {
        let counts = ArtifactsWorkspaceDeriver.counts(state: providerState, scope: providerScope)
        return VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.small) {
                Label("Provider resources", systemImage: "rectangle.stack")
                    .font(theme.typography.body.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: theme.spacing.small)

                PinesStatusChip(
                    status: providerState.isRefreshingProviderLifecycle ? .running : .custom("\(counts.providerResources)", .accent),
                    compact: true
                )
            }

            HStack(spacing: theme.spacing.xsmall) {
                Menu {
                    ForEach(ArtifactsWorkspaceDeriver.providerScopes(from: lifecycleProviders)) { scope in
                        Button {
                            providerScope = scope
                            selection = nil
                        } label: {
                            if scope == providerScope {
                                Label(scope.title(providers: lifecycleProviders), systemImage: "checkmark")
                            } else {
                                Text(scope.title(providers: lifecycleProviders))
                            }
                        }
                    }
                } label: {
                    ArtifactsMenuPill(
                        title: providerScope.title(providers: lifecycleProviders),
                        systemImage: "cloud",
                        tone: .info
                    )
                }

                Menu {
                    ForEach(ArtifactsSort.allCases) { sort in
                        Button {
                            filter.sort = sort
                        } label: {
                            if sort == filter.sort {
                                Label(sort.title, systemImage: "checkmark")
                            } else {
                                Text(sort.title)
                            }
                        }
                    }
                } label: {
                    ArtifactsMenuPill(
                        title: filter.sort.title,
                        systemImage: "arrow.up.arrow.down",
                        tone: .neutral
                    )
                }

                Spacer(minLength: theme.spacing.small)

                Text("\(counts.artifacts) artifacts")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .pinesSurface(.panel, padding: theme.spacing.small)
    }

    private var modeSwitcher: some View {
        HStack(spacing: theme.spacing.small) {
            ArtifactsWorkspaceModePicker(selection: $mode) {
                selection = nil
            }
            Spacer(minLength: theme.spacing.small)
        }
    }

    @ViewBuilder
    private var activeWorkspace: some View {
        switch mode {
        case .library:
            ArtifactsLibraryWorkspace(filter: $filter, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .generate:
            ArtifactsMediaWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
        case .research:
            ArtifactsResearchWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
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
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) cloud copies are not supported here.")
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
            Button("Delete cloud copy", role: .destructive) {
                Task { await deleteProviderFile(file) }
            }
        case .deleteProviderCache(let cache):
            Button("Delete cloud context", role: .destructive) {
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
        ArtifactsWorkspaceDeriver.artifactSummaries(
            artifacts: providerState.providerArtifacts.filter(\.isVisibleInArtifactsGallery),
            filter: filter
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
                    ArtifactsArtifactGallery(
                        summaries: summaries,
                        artifacts: providerState.providerArtifacts,
                        selection: $selection,
                        emptyTitle: "No artifacts",
                        emptyDetail: "Deep Research reports, generated images, videos, speech, and other viewable media appear here."
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
        "generated_image",
        "video",
        "audio",
        "speech",
        "deep_research_report",
        "transcription",
        "translation",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            TextField("Search artifacts, IDs, files, providers, or response links", text: $filter.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pines.artifacts.library.search")
                .pinesFieldChrome()

            Menu {
                ForEach(kinds, id: \.self) { kind in
                    Button {
                        filter.kind = kind == "All kinds" ? nil : kind
                    } label: {
                        if (filter.kind ?? "All kinds") == kind {
                            Label(kind.readableArtifactKind, systemImage: "checkmark")
                        } else {
                            Text(kind.readableArtifactKind)
                        }
                    }
                }
            } label: {
                ArtifactsMenuPill(
                    title: (filter.kind ?? "All kinds").readableArtifactKind,
                    systemImage: "tag",
                    tone: .info
                )
            }
        }
        .pinesSurface(.panel, padding: theme.spacing.small)
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
    @State private var mediaKind: ArtifactsMediaKind = .image
    @State private var modelID = "gpt-image-2"
    @State private var prompt = ""
    @State private var isCreating = false

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .gemini])
    }

    private var mediaModelOptions: [ArtifactsMediaModelOption] {
        ArtifactsWorkspaceDeriver.mediaModelOptions(
            provider: provider,
            kind: mediaKind,
            capabilities: providerState.providerModelCapabilities
        )
    }

    private var selectedModelLabel: String {
        mediaModelOptions.first(where: { $0.id == modelID })?.title ?? modelID
    }

    private var mediaSummaries: [ArtifactsResourceSummary] {
        let filter = ArtifactsResourceFilter(query: "", providerScope: providerScope, kind: nil, sort: .newest)
        return ArtifactsWorkspaceDeriver.artifactSummaries(
            artifacts: providerState.providerArtifacts.filter { artifact in
                artifact.isVisibleInArtifactsGallery
                    && ["image", "generated_image", "video", "audio", "speech", "transcription", "translation", "generated_media", "media_operation", "partial_image", "video_job"].contains(artifact.kind)
            },
            filter: filter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Generate Media", subtitle: nil, systemImage: "sparkles") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    providerRequirement(allowed: "OpenAI or Gemini")

                    ArtifactsMediaKindSelector(selection: $mediaKind)

                    Menu {
                        ForEach(mediaModelOptions) { option in
                            Button {
                                modelID = option.id
                            } label: {
                                if option.id == modelID {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        ArtifactsMenuPill(
                            title: selectedModelLabel,
                            systemImage: "cpu",
                            tone: mediaModelOptions.first(where: { $0.id == modelID })?.isFromProviderCapability == true ? .success : .info
                        )
                    }
                    .disabled(mediaModelOptions.isEmpty)

                    TextField("Prompt", text: $prompt, axis: .vertical)
                        .lineLimit(3...7)
                        .accessibilityIdentifier("pines.artifacts.media.prompt")
                        .pinesFieldChrome()

                    Button {
                        Task { await createMedia() }
                    } label: {
                        Label(isCreating ? "Creating" : "Create artifact", systemImage: isCreating ? "hourglass" : "sparkles")
                    }
                    .disabled(isCreating || provider == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("pines.artifacts.media.create")
                    .pinesButtonStyle(.primary)
                }
            }
            .onAppear { normalizeSelectedModel() }
            .onChange(of: provider?.id) { _, _ in normalizeSelectedModel() }
            .onChange(of: mediaKind) { _, _ in normalizeSelectedModel() }

            ArtifactsArtifactGallery(
                summaries: mediaSummaries,
                artifacts: providerState.providerArtifacts,
                selection: $selection,
                emptyTitle: "No media artifacts",
                emptyDetail: "Generated images, videos, and speech appear here after creation."
            )
        }
    }

    @ViewBuilder
    private func providerRequirement(allowed: String) -> some View {
        if provider == nil {
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
                case .video:
                    _ = try await appModel.createOpenAIVideoArtifact(OpenAIVideoArtifactRequest(prompt: trimmedPrompt, model: model.rawValue), providerID: provider.id, services: services)
                case .speech:
                    _ = try await appModel.createOpenAISpeechArtifact(OpenAISpeechArtifactRequest(model: model.rawValue, input: trimmedPrompt, voice: "alloy"), providerID: provider.id, services: services)
                case .image:
                    _ = try await appModel.createOpenAIImageArtifacts(providerID: provider.id, modelID: model, prompt: trimmedPrompt, services: services)
                }
            case .gemini:
                _ = try await appModel.createGeminiGeneratedMedia(providerID: provider.id, modelID: model, prompt: trimmedPrompt, kind: mediaKind.rawValue, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) media artifacts are not supported here.")
            }
            prompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func normalizeSelectedModel() {
        let options = mediaModelOptions
        guard !options.isEmpty else {
            modelID = ""
            return
        }
        if !options.contains(where: { $0.id == modelID }) {
            modelID = options[0].id
        }
    }
}

private struct ArtifactsStorageWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.large) {
            ArtifactsFilesWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
            ArtifactsContextWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
        }
    }
}

private struct ArtifactsJobsWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.large) {
            ArtifactsBatchesWorkspace(providerScope: providerScope, selection: $selection, pendingConfirmation: $pendingConfirmation)
            ArtifactsRealtimeWorkspace(providerScope: providerScope, selection: $selection)
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
            PinesCardSection("Cloud Copies", subtitle: "Reusable remote copies for large files and background work. Local Vault files stay separate.", systemImage: "doc.badge.arrow.up") {
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
                            Label(isUploading ? "Uploading" : "Create Cloud Copy", systemImage: isUploading ? "hourglass" : "square.and.arrow.up")
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
            PinesCardSection("Cloud Copy Actions", subtitle: "These operate on the cloud copy, not local Vault source files.", systemImage: "ellipsis.circle") {
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
            PinesCardSection("Reusable Context", subtitle: "Optimized repeated context for search, file analysis, and long conversations.", systemImage: "externaldrive.badge.icloud") {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    if let provider {
                        PinesStatusChip(status: .custom("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)", .info))
                    } else {
                        PinesEmptyState(title: "Choose OpenAI or Gemini", detail: "Set the page provider scope before creating reusable context.", systemImage: "cloud")
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
                        Label(isCreating ? "Creating" : "Create reusable context", systemImage: isCreating ? "hourglass" : "plus.circle")
                    }
                    .disabled(provider == nil || isCreating || (provider?.kind == .gemini && contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .pinesButtonStyle(.primary)
                }
            }

            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No reusable context", emptyDetail: "Reusable cloud context appears here.")

            if case .cache(let id) = selection, let cache = providerState.providerCaches.first(where: { $0.id == id }) {
                PinesCardSection("Reusable Context Actions", subtitle: "Refresh or remove the cloud context separately from local data.", systemImage: "ellipsis.circle") {
                    HStack(spacing: theme.spacing.small) {
                        Button("Refresh") {
                            Task { await refreshCache(cache) }
                        }
                        .buttonStyle(.borderless)
                        Button("Delete cloud context", role: .destructive) {
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
            PinesCardSection("Background Processing", subtitle: "Run long reports, multiple files, transcription queues, and Vault enrichment outside the chat stream.", systemImage: "tray.full") {
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
    @State private var prompt = ""
    @State private var modelID = "gpt-5.5-pro"
    @State private var depth: OpenAIDeepResearchDepth = .standard
    @State private var reportFormat: OpenAIDeepResearchReportFormat = .memo
    @State private var isStarting = false
    @State private var followUpPrompt = ""
    @State private var isSendingFollowUp = false

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .gemini])
    }

    private var modelOptions: [ArtifactsResearchModelOption] {
        ArtifactsWorkspaceDeriver.researchModelOptions(
            provider: provider,
            capabilities: providerState.providerModelCapabilities
        )
    }

    private var selectedModelLabel: String {
        modelOptions.first(where: { $0.id == modelID })?.title ?? modelID
    }

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.researchSummaries(runs: providerState.providerResearchRuns, filter: .init(providerScope: providerScope))
    }

    private var selectedRun: ProviderResearchRunRecord? {
        if case .research(let id) = selection,
           let run = providerState.providerResearchRuns.first(where: { $0.id == id }) {
            return run
        }
        return providerState.providerResearchRuns
            .filter { providerScope.includes($0.providerID) }
            .sorted { lhs, rhs in
                if lhs.status.providerIsTerminal != rhs.status.providerIsTerminal {
                    return !lhs.status.providerIsTerminal
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesCardSection("Deep Research", subtitle: provider?.displayName, systemImage: "doc.text.magnifyingglass", kind: .glass) {
                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    if let run = selectedRun {
                        researchChatHeader(for: run)
                        Divider()
                            .overlay(theme.colors.separator)
                        researchChatTranscript(for: run)
                    } else {
                        researchEmptyTranscript
                    }

                    Divider()
                        .overlay(theme.colors.separator)
                    researchChatComposer(for: selectedRun)
                }
            }
            .onAppear { normalizeSelectedModel() }
            .onChange(of: provider?.id) { _, _ in normalizeSelectedModel() }

            if case .artifact = selection {
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
        }
    }

    private func researchChatHeader(for run: ProviderResearchRunRecord) -> some View {
        HStack(alignment: .center, spacing: theme.spacing.small) {
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(run.title)
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                Text("\(run.providerKind.pinesLifecycleTitle) · \(run.modelID.rawValue)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: theme.spacing.small)

            Menu {
                ForEach(summaries) { summary in
                    Button {
                        selection = summary.selection
                    } label: {
                        Label(summary.title, systemImage: summary.systemImage)
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 18, height: 18)
            }
            .disabled(summaries.isEmpty)
            .pinesButtonStyle(.icon)
            .accessibilityLabel("Research threads")

            Button {
                Task { await refreshRun(run) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .pinesButtonStyle(.icon)
            .accessibilityLabel("Refresh research")

            if !run.status.providerIsTerminal {
                Button(role: .destructive) {
                    pendingConfirmation = .cancelResearch(run)
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Cancel research")
            }
        }
    }

    private var researchEmptyTranscript: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            ArtifactsResearchBubble(
                role: .agent,
                title: provider?.displayName ?? "Deep Research",
                text: provider == nil
                    ? "Choose an OpenAI or Gemini provider to start a research chat."
                    : "Ask a research question to start."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func researchChatTranscript(for run: ProviderResearchRunRecord) -> some View {
        let sources = ArtifactsWorkspaceDeriver.researchSources(for: run)
        let events = ArtifactsWorkspaceDeriver.researchTimeline(for: run)
        let finalReport = run.finalReportArtifactID.flatMap { id in
            providerState.providerArtifacts.first { $0.id == id }
        }

        return VStack(alignment: .leading, spacing: theme.spacing.medium) {
            ArtifactsResearchBubble(role: .user, title: "You", text: run.prompt)

            ForEach(events) { event in
                ArtifactsResearchBubble(
                    role: .agent,
                    title: event.title,
                    text: event.detail,
                    systemImage: event.systemImage,
                    tone: event.tone
                )
            }

            if !sources.isEmpty {
                ArtifactsResearchSourcesMessage(sources: sources)
            }

            if let finalReport {
                ArtifactsResearchReportPreview(artifact: finalReport) {
                    selection = .artifact(finalReport.id)
                }
            } else if run.status.providerIsTerminal {
                ArtifactsResearchBubble(
                    role: .agent,
                    title: "Finished",
                    text: run.lastError ?? "The run completed without a saved report artifact.",
                    systemImage: run.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle",
                    tone: run.lastError == nil ? .success : .warning
                )
            } else {
                ArtifactsResearchBubble(
                    role: .agent,
                    title: "Working",
                    text: "I'll keep this thread updated as searches, sources, and report output arrive.",
                    systemImage: "ellipsis.message",
                    tone: .info
                )
            }
        }
    }

    private func researchChatComposer(for run: ProviderResearchRunRecord?) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.xsmall) {
                Menu {
                    ForEach(modelOptions) { option in
                        Button {
                            modelID = option.id
                        } label: {
                            Label(option.title, systemImage: option.id == modelID ? "checkmark" : "cpu")
                        }
                    }
                } label: {
                    Image(systemName: "cpu")
                        .frame(width: 18, height: 18)
                }
                .disabled(modelOptions.isEmpty)
                .pinesButtonStyle(.icon)
                .accessibilityLabel(selectedModelLabel)

                Menu {
                    ForEach(OpenAIDeepResearchDepth.allCases, id: \.self) { option in
                        Button {
                            depth = option
                        } label: {
                            Label(option.rawValue.readableArtifactKind, systemImage: option == depth ? "checkmark" : "slider.horizontal.3")
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel(depth.rawValue.readableArtifactKind)

                Menu {
                    ForEach(OpenAIDeepResearchReportFormat.allCases, id: \.self) { option in
                        Button {
                            reportFormat = option
                        } label: {
                            Label(option.rawValue.readableArtifactKind, systemImage: option == reportFormat ? "checkmark" : "doc.text")
                        }
                    }
                } label: {
                    Image(systemName: "doc.text")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel(reportFormat.rawValue.readableArtifactKind)

                Spacer(minLength: theme.spacing.small)

                Button {
                    Task { await resumeRuns() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 18, height: 18)
                }
                .disabled(provider == nil)
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Resume research")
            }

            researchInputRow(for: run)
        }
    }

    @ViewBuilder
    private func researchInputRow(for run: ProviderResearchRunRecord?) -> some View {
        HStack(alignment: .bottom, spacing: theme.spacing.small) {
            if run == nil {
                TextField("Ask a research question", text: $prompt, axis: .vertical)
                    .lineLimit(1...5)
                    .accessibilityIdentifier("pines.artifacts.research.prompt")
                    .pinesFieldChrome()
            } else {
                TextField("Ask follow-up or clarify", text: $followUpPrompt, axis: .vertical)
                    .lineLimit(1...5)
                    .accessibilityIdentifier("pines.artifacts.research.follow-up")
                    .pinesFieldChrome()
            }

            Button {
                if let run {
                    Task { await sendFollowUp(to: run) }
                } else {
                    Task { await startRun() }
                }
            } label: {
                Image(systemName: isStarting || isSendingFollowUp ? "hourglass" : "paperplane.fill")
                    .frame(width: 18, height: 18)
            }
            .disabled(sendDisabled(for: run))
            .accessibilityIdentifier(run == nil ? "pines.artifacts.research.start" : "pines.artifacts.research.follow-up.send")
            .pinesButtonStyle(.primary)
            .accessibilityLabel(run == nil ? "Start research" : "Send follow-up")
        }
    }

    private func sendDisabled(for run: ProviderResearchRunRecord?) -> Bool {
        if provider == nil || modelID.isEmpty {
            return true
        }
        if run == nil {
            return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStarting
        }
        return followUpPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingFollowUp
    }

    @MainActor
    private func startRun() async {
        guard let provider else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = Self.derivedResearchTitle(from: trimmedPrompt)
            let model = ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            let vectorStoreIDs = providerState.providerVectorStores.filter { $0.providerID == provider.id }.map(\.id)
            let providerFileIDs = providerState.providerFiles.filter { $0.providerID == provider.id }.map(\.id)
            switch provider.kind {
            case .openAI:
                let request = OpenAIDeepResearchRequest(
                    providerID: provider.id,
                    modelID: model,
                    title: resolvedTitle,
                    prompt: trimmedPrompt,
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
                    prompt: trimmedPrompt,
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
    private func importArtifact(_ artifact: ProviderArtifactRecord) async {
        do {
            _ = try await appModel.importProviderArtifactToVault(id: artifact.id, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func sendFollowUp(to run: ProviderResearchRunRecord) async {
        let question = followUpPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        isSendingFollowUp = true
        defer { isSendingFollowUp = false }
        do {
            switch run.providerKind {
            case .gemini:
                _ = try await appModel.startGeminiDeepResearchFollowUp(
                    prompt: question,
                    previousRunID: run.id,
                    providerID: run.providerID,
                    services: services,
                    title: "Follow-up: \(run.title)"
                )
            case .openAI:
                let request = OpenAIDeepResearchRequest(
                    providerID: run.providerID,
                    modelID: run.modelID,
                    title: "Follow-up: \(run.title)",
                    prompt: """
                    Follow-up question for previous Deep Research run \(run.id):

                    \(question)

                    Original research request:
                    \(run.prompt)
                    """,
                    depth: depth,
                    sourcePolicy: .webAndFiles(
                        vectorStoreIDs: providerState.providerVectorStores.filter { $0.providerID == run.providerID }.map { OpenAIVectorStoreID(rawValue: $0.id) },
                        providerFileIDs: providerState.providerFiles.filter { $0.providerID == run.providerID }.map { OpenAIProviderFileID(rawValue: $0.id) }
                    ),
                    reportFormat: reportFormat,
                    metadata: ["pines.follow_up_of": run.id]
                )
                _ = try await appModel.startOpenAIDeepResearch(request, services: services)
            default:
                throw InferenceError.invalidRequest("\(run.providerKind.pinesLifecycleTitle) Deep Research follow-up is not supported here.")
            }
            followUpPrompt = ""
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

    private func normalizeSelectedModel() {
        let options = modelOptions
        guard !options.isEmpty else {
            modelID = ""
            return
        }
        if !options.contains(where: { $0.id == modelID }) {
            modelID = options[0].id
        }
    }

    private static func derivedResearchTitle(from prompt: String) -> String {
        let trimmed = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !trimmed.isEmpty else { return "Deep research" }
        let clipped = String(trimmed.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.last == "?" ? String(clipped.dropLast()) : clipped
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
            PinesCardSection("Capability Diagnostics", subtitle: "Advanced metadata that powers model picker gating and attachment compatibility.", systemImage: "cpu") {
                PinesMetricPillGroup(items: [
                    .init("Models", value: "\(summaries.count)", systemImage: "cpu", tone: .info),
                    .init("Providers", value: "\(Set(summaries.map(\.providerKind)).count)", systemImage: "cloud", tone: .warning),
                ])
            }
            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No capability metadata", emptyDetail: "Refresh cloud resources to populate diagnostic rows.")
        }
    }
}

private struct ArtifactsMenuPill: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let systemImage: String
    var tone: PinesCloudStatusTone = .neutral

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
        }
        .font(theme.typography.caption.weight(.semibold))
        .foregroundStyle(tone.color(in: theme))
        .padding(.horizontal, theme.spacing.small)
        .padding(.vertical, theme.spacing.xsmall)
        .frame(minHeight: 32)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .strokeBorder(tone.color(in: theme).opacity(0.24), lineWidth: theme.stroke.hairline)
        }
    }
}

private struct ArtifactsWorkspaceModePicker: View {
    @Environment(\.pinesTheme) private var theme
    @Binding var selection: ArtifactsWorkspaceMode
    let onSelect: () -> Void
    private static let labelWidth: CGFloat = 264
    private static let labelMinHeight: CGFloat = 52

    var body: some View {
        Menu {
            ForEach(ArtifactsWorkspaceMode.allCases) { mode in
                Button {
                    selection = mode
                    onSelect()
                } label: {
                    if mode == selection {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            }
        } label: {
            pickerLabel
        }
        .accessibilityLabel("Artifacts workspace")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("pines.artifacts.workspace.mode")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var pickerLabel: some View {
        let shape = Capsule()
        return HStack(spacing: theme.spacing.xsmall) {
            Image(systemName: selection.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(selection.title)
                    .font(theme.typography.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(selection.subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .padding(.leading, theme.spacing.xxsmall)
        }
        .foregroundStyle(theme.colors.accent)
        .padding(.horizontal, theme.spacing.medium)
        .frame(width: Self.labelWidth, alignment: .leading)
        .frame(minHeight: Self.labelMinHeight, alignment: .leading)
        .background(pickerBackgroundStyle, in: shape)
        .overlay {
            shape.strokeBorder(pickerBorderStyle, lineWidth: theme.stroke.hairline)
        }
        .overlay {
            shape
                .strokeBorder(theme.colors.surfaceHighlight.opacity(0.68), lineWidth: theme.stroke.hairline)
                .blendMode(.plusLighter)
        }
        .shadow(color: theme.shadow.panelColor.opacity(theme.colorScheme == .dark ? 0.12 : 0.18), radius: theme.shadow.panelRadius * 0.22, x: 0, y: theme.shadow.panelY * 0.16)
        .contentShape(shape)
    }

    private var pickerBackgroundStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    theme.colors.elevatedSurface.opacity(theme.colorScheme == .dark ? 0.92 : 0.96),
                    theme.colors.controlFill.opacity(0.86),
                    theme.colors.accentSoft.opacity(0.56),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var pickerBorderStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.46 : 0.34),
                    theme.colors.controlBorder.opacity(0.94),
                    theme.colors.surfaceHighlight.opacity(theme.colorScheme == .dark ? 0.28 : 0.72),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private enum ArtifactsResearchBubbleRole: Equatable {
    case user
    case agent

    var systemImage: String {
        switch self {
        case .user: "person.crop.circle"
        case .agent: "sparkles"
        }
    }
}

private struct ArtifactsResearchBubble: View {
    @Environment(\.pinesTheme) private var theme
    let role: ArtifactsResearchBubbleRole
    let title: String
    let text: String
    var systemImage: String?
    var tone: PinesCloudStatusTone?

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            Image(systemName: systemImage ?? role.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .background(theme.colors.controlFill, in: Circle())

            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                Text(text)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing.small)
        .background(role == .user ? theme.colors.accentSoft.opacity(0.62) : theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                .strokeBorder(role == .user ? theme.colors.accent.opacity(0.22) : theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
        }
    }

    private var iconColor: Color {
        if let tone {
            return tone.color(in: theme)
        }
        return role == .user ? theme.colors.accent : theme.colors.success
    }
}

private struct ArtifactsResearchTimeline: View {
    @Environment(\.pinesTheme) private var theme
    let events: [ArtifactsResearchTimelineEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            Text("Activity")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)

            ForEach(events) { event in
                HStack(alignment: .top, spacing: theme.spacing.small) {
                    Image(systemName: event.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(event.tone.color(in: theme))
                        .frame(width: 22, height: 22)
                        .background(theme.colors.controlFill, in: Circle())

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(event.title)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        Text(event.detail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, theme.spacing.xxsmall)
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }
}

private struct ArtifactsResearchActivityDisclosure: View {
    @Environment(\.pinesTheme) private var theme
    let events: [ArtifactsResearchTimelineEvent]
    let sources: [ArtifactsResearchSource]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                ArtifactsResearchTimeline(events: events)
                ArtifactsResearchSourcesPanel(sources: sources)
            }
            .padding(.top, theme.spacing.xsmall)
        } label: {
            HStack(spacing: theme.spacing.xsmall) {
                Label("Research Activity", systemImage: "safari")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer(minLength: theme.spacing.small)
                Text("\(sources.count) sources")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
                    .monospacedDigit()
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }
}

private struct ArtifactsResearchSourcesPanel: View {
    @Environment(\.pinesTheme) private var theme
    let sources: [ArtifactsResearchSource]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack {
                Text("Sources")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer()
                Text("\(sources.count)")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
                    .monospacedDigit()
            }

            if sources.isEmpty {
                Text("No captured sources yet.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, theme.spacing.xsmall)
            } else {
                ForEach(sources.prefix(12)) { source in
                    sourceRow(source)
                }
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    @ViewBuilder
    private func sourceRow(_ source: ArtifactsResearchSource) -> some View {
        let row = HStack(alignment: .top, spacing: theme.spacing.small) {
            Image(systemName: source.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(source.tone.color(in: theme))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(source.title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                Text(source.url ?? source.detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, theme.spacing.xxsmall)

        if let urlString = source.url, let url = URL(string: urlString) {
            Link(destination: url) { row }
        } else {
            row
        }
    }
}

private struct ArtifactsResearchSourcesMessage: View {
    @Environment(\.pinesTheme) private var theme
    let sources: [ArtifactsResearchSource]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.xsmall) {
                Label("Sources", systemImage: "quote.bubble")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer(minLength: theme.spacing.small)
                Text("\(sources.count)")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
                    .monospacedDigit()
            }

            ForEach(sources.prefix(6)) { source in
                sourceRow(source)
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    @ViewBuilder
    private func sourceRow(_ source: ArtifactsResearchSource) -> some View {
        let row = HStack(alignment: .top, spacing: theme.spacing.small) {
            Image(systemName: source.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(source.tone.color(in: theme))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(source.title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                Text(source.url ?? source.detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, theme.spacing.xxsmall)

        if let urlString = source.url, let url = URL(string: urlString) {
            Link(destination: url) { row }
        } else {
            row
        }
    }
}

private struct ArtifactsResearchReportPreview: View {
    @Environment(\.pinesTheme) private var theme
    let artifact: ProviderArtifactRecord
    let open: () -> Void

    private var previewText: String {
        if let text = artifact.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return String(Self.userFacingExcerpt(from: text).prefix(900))
        }
        if let text = Self.userFacingText(from: artifact.content) {
            return String(Self.userFacingExcerpt(from: text).prefix(900))
        }
        return "Report saved. Open the full report to view the complete output."
    }

    private static func userFacingExcerpt(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: "Executive summary", options: [.caseInsensitive, .diacriticInsensitive]) {
            return String(cleaned[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private static func userFacingText(from json: JSONValue?) -> String? {
        switch json {
        case let .object(object):
            if let type = object["type"]?.stringValue,
               ["reasoning", "web_search_call", "file_search_call", "code_interpreter_call", "image_generation_call", "function_call", "computer_call"].contains(type) {
                return nil
            }
            if let outputText = object["output_text"]?.stringValue, !outputText.isEmpty {
                return outputText
            }
            if let type = object["type"]?.stringValue,
               ["output_text", "text", "message"].contains(type),
               let text = object["text"]?.stringValue,
               !text.isEmpty {
                return text
            }
            if object["type"]?.stringValue == "message", let content = object["content"] {
                return userFacingText(from: content)
            }
            if let output = object["output"] {
                return userFacingText(from: output)
            }
            return nil
        case let .array(values):
            let text = values.compactMap(userFacingText(from:)).joined(separator: "\n\n")
            return text.isEmpty ? nil : text
        case let .string(value):
            return value
        case .number, .bool, .null, nil:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.small) {
                Label("Final Report", systemImage: "doc.richtext")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.success)
                Spacer()
                Button("Open") { open() }
                    .buttonStyle(.borderless)
            }

            Text(previewText)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }
}

private struct ArtifactsMediaKindSelector: View {
    @Environment(\.pinesTheme) private var theme
    @Binding var selection: ArtifactsMediaKind

    var body: some View {
        HStack(spacing: theme.spacing.xsmall) {
            ForEach(ArtifactsMediaKind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                        .font(theme.typography.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == kind ? theme.colors.accent : theme.colors.secondaryText)
                .background(selection == kind ? theme.colors.accentSoft : theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                        .strokeBorder(selection == kind ? theme.colors.accent.opacity(0.34) : theme.colors.controlBorder, lineWidth: selection == kind ? theme.stroke.selected : theme.stroke.hairline)
                }
            }
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
        case .deleteProviderFile: "Delete cloud copy?"
        case .deleteProviderCache: "Delete cloud context?"
        case .cancelBatch: "Cancel background process?"
        case .cancelResearch: "Cancel research run?"
        }
    }

    var message: String {
        switch self {
        case .deleteArtifactRecord(let artifact):
            "This removes only Pines' local lifecycle record for \(artifact.fileName ?? artifact.id). It does not delete cloud copies or remote resources."
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
