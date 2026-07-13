import SwiftUI
import PinesCore
import UniformTypeIdentifiers

private extension ArtifactsWorkspaceMode {
    static var workspaceSwitcherItems: [PinesWorkspaceSwitcherItem] {
        allCases.map { mode in
            PinesWorkspaceSwitcherItem(
                id: mode.id,
                title: mode.title,
                subtitle: mode.subtitle,
                systemImage: mode.systemImage
            )
        }
    }
}

struct ArtifactsWorkspaceView: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var mode: ArtifactsWorkspaceMode = .library
    @State private var providerScope: ArtifactsProviderScope = .all
    @State private var filter = ArtifactsResourceFilter()
    @State private var assetKind: ArtifactsAssetKindFilter = .all
    @State private var selection: ArtifactsSelection?
    @State private var pendingConfirmation: ArtifactsConfirmation?
    @State private var createReferenceArtifactID: String?
    @State private var requestedCreateKind: ArtifactsMediaKind?

    var body: some View {
        NavigationStack {
            activeWorkspace
            .pinesAppBackground()
            .navigationTitle(mode == .research ? "Deep Research" : mode.title)
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

    @ViewBuilder
    private var activeWorkspace: some View {
        switch mode {
        case .library:
            ArtifactsLibraryWorkspace(
                mode: $mode,
                providerScope: $providerScope,
                filter: $filter,
                assetKind: $assetKind,
                selection: $selection,
                pendingConfirmation: $pendingConfirmation,
                openCreate: { kind in
                    requestedCreateKind = kind
                    mode = .generate
                    selection = nil
                },
                openResearch: {
                    mode = .research
                    selection = nil
                },
                remixArtifact: { artifact in
                    createReferenceArtifactID = artifact.id
                    requestedCreateKind = .image
                    if let providerID = artifact.providerID {
                        providerScope = .provider(providerID)
                    }
                    mode = .generate
                    selection = .artifact(artifact.id)
                }
            )
        case .generate:
            ArtifactsMediaWorkspace(
                mode: $mode,
                providerScope: $providerScope,
                referenceArtifactID: $createReferenceArtifactID,
                requestedKind: $requestedCreateKind,
                selection: $selection,
                pendingConfirmation: $pendingConfirmation,
                openLibrary: {
                    mode = .library
                }
            )
        case .research:
            ArtifactsResearchWorkspace(
                mode: $mode,
                providerScope: providerScope,
                selection: $selection,
                pendingConfirmation: $pendingConfirmation
            )
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
        case .cancelMediaOperation(let artifact):
            Button("Cancel media operation", role: .destructive) {
                Task { await cancelMediaOperation(artifact) }
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

    @MainActor
    private func cancelMediaOperation(_ artifact: ProviderArtifactRecord) async {
        do {
            guard let providerID = artifact.providerID else {
                throw InferenceError.providerUnavailable(ProviderID(rawValue: "unknown"))
            }
            switch artifact.providerKind {
            case .openAI where artifact.kind.lowercased() == "video_job":
                _ = try await appModel.cancelOpenAIVideoArtifact(
                    id: artifact.providerFileID ?? artifact.id,
                    providerID: providerID,
                    services: services
                )
            case .gemini where artifact.kind.lowercased() == "media_operation":
                _ = try await appModel.cancelGeminiGeneratedMediaOperation(
                    id: artifact.responseID ?? artifact.id,
                    providerID: providerID,
                    services: services
                )
            default:
                throw InferenceError.invalidRequest("This artifact does not have a cancellable media operation.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactsLibraryWorkspace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @Binding var mode: ArtifactsWorkspaceMode
    @Binding var providerScope: ArtifactsProviderScope
    @Binding var filter: ArtifactsResourceFilter
    @Binding var assetKind: ArtifactsAssetKindFilter
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    let openCreate: (ArtifactsMediaKind) -> Void
    let openResearch: () -> Void
    let remixArtifact: (ProviderArtifactRecord) -> Void

    private var lifecycleProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.pinesLifecycleProviders
    }

    private var scopedFilter: ArtifactsResourceFilter {
        var copy = filter
        copy.providerScope = providerScope
        copy.kind = nil
        return copy
    }

    private var assets: [ArtifactsAssetViewModel] {
        ArtifactsWorkspaceDeriver.assetViewModels(
            artifacts: providerState.providerArtifacts,
            filter: scopedFilter,
            assetKind: assetKind
        )
    }

    private var selectedArtifact: ProviderArtifactRecord? {
        guard case .artifact(let id) = selection else { return nil }
        return providerState.providerArtifacts.first(where: { $0.id == id })
    }

    private var selectedArtifactSheet: Binding<ProviderArtifactRecord?> {
        Binding(
            get: { horizontalSizeClass == .compact ? selectedArtifact : nil },
            set: { artifact in
                selection = artifact.map { .artifact($0.id) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ArtifactsLibraryTopBar(
                mode: $mode,
                providerScope: $providerScope,
                filter: $filter,
                assetKind: $assetKind,
                providers: lifecycleProviders,
                count: assets.count,
                isRefreshing: providerState.isRefreshingProviderLifecycle,
                refresh: {
                    Task { await appModel.refreshProviderLifecycleState(services: services) }
                },
                openCreate: { openCreate(.image) },
                openResearch: openResearch
            )

            if let error = providerState.providerLifecycleError {
                PinesGlobalErrorBanner(
                    message: error,
                    dismiss: { providerState.providerLifecycleError = nil }
                )
                    .padding(.horizontal, theme.spacing.large)
                    .padding(.top, theme.spacing.small)
            }

            if horizontalSizeClass == .compact {
                ScrollView {
                    libraryContent
                        .padding(theme.spacing.large)
                }
                .pinesExpressiveScrollHaptics()
                .sheet(item: selectedArtifactSheet) { artifact in
                    NavigationStack {
                        ArtifactsAssetInspector(
                            artifact: artifact,
                            providers: lifecycleProviders,
                            importArtifact: { Task { await importArtifact(artifact) } },
                            remixArtifact: { remixArtifact(artifact) },
                            deleteArtifact: { pendingConfirmation = .deleteArtifactRecord(artifact) }
                        )
                        .padding(theme.spacing.large)
                        .navigationTitle("Artifact")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { selection = nil }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            } else {
                HStack(alignment: .top, spacing: theme.spacing.large) {
                    ScrollView {
                        libraryContent
                            .padding(theme.spacing.large)
                    }
                    .pinesExpressiveScrollHaptics()

                    ArtifactsAssetInspectorSlot(
                        artifact: selectedArtifact,
                        providers: lifecycleProviders,
                        importArtifact: { artifact in Task { await importArtifact(artifact) } },
                        remixArtifact: remixArtifact,
                        deleteArtifact: { artifact in pendingConfirmation = .deleteArtifactRecord(artifact) }
                    )
                    .frame(width: 390)
                    .padding(.trailing, theme.spacing.large)
                    .padding(.top, theme.spacing.large)
                }
            }
        }
        .animation(reduceMotion ? nil : theme.motion.fast, value: assetKind)
        .animation(reduceMotion ? nil : theme.motion.fast, value: assets.count)
    }

    @ViewBuilder
    private var libraryContent: some View {
        if assets.isEmpty {
            ArtifactsLibraryEmptyState(
                createImage: { openCreate(.image) },
                createVideo: { openCreate(.video) },
                startResearch: openResearch
            )
        } else {
            ArtifactsAssetGrid(
                assets: assets,
                selection: $selection,
                importArtifact: { artifact in Task { await importArtifact(artifact) } },
                remixArtifact: remixArtifact,
                deleteArtifact: { artifact in pendingConfirmation = .deleteArtifactRecord(artifact) }
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
}

private struct ArtifactsLibraryTopBar: View {
    @Environment(\.pinesTheme) private var theme
    @Binding var mode: ArtifactsWorkspaceMode
    @Binding var providerScope: ArtifactsProviderScope
    @Binding var filter: ArtifactsResourceFilter
    @Binding var assetKind: ArtifactsAssetKindFilter
    let providers: [CloudProviderConfiguration]
    let count: Int
    let isRefreshing: Bool
    let refresh: () -> Void
    let openCreate: () -> Void
    let openResearch: () -> Void

    var body: some View {
        PinesWorkspaceTopBar {
            PinesWorkspaceSwitcher(
                selectionID: modeSelectionID,
                items: ArtifactsWorkspaceMode.workspaceSwitcherItems
            ) { _ in
                filter.query = ""
            }
            .accessibilityLabel("Artifacts workspace")
            .accessibilityValue(mode.title)
            .accessibilityIdentifier("pines.artifacts.workspace.mode")
        } status: {
            HStack(spacing: theme.spacing.small) {
                Text("\(count) visible")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        } actions: {
            HStack(spacing: theme.spacing.small) {
                Button(action: openCreate) {
                    Image(systemName: "sparkles")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Create artifact")
                .help("Create")

                Button(action: openResearch) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Start deep research")
                .help("Deep Research")

                Button(action: refresh) {
                    if isRefreshing {
                        ProgressView()
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: 18, height: 18)
                    }
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Refresh library")
                .help("Refresh")
            }
        } bottom: {
            TextField("Search reports, generated media, sources, or filenames", text: $filter.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pines.artifacts.library.search")
                .pinesFieldChrome()

            HStack(alignment: .center, spacing: theme.spacing.small) {
                ArtifactsAssetKindSelector(selection: $assetKind)

                Spacer(minLength: theme.spacing.small)

                Menu {
                    ForEach(ArtifactsWorkspaceDeriver.providerScopes(from: providers)) { scope in
                        Button {
                            providerScope = scope
                        } label: {
                            Label(scope.title(providers: providers), systemImage: scope == providerScope ? "checkmark" : "cloud")
                        }
                    }
                } label: {
                    PinesMenuChip(title: providerScope.title(providers: providers), systemImage: "cloud", tone: .info)
                }

                Menu {
                    ForEach(ArtifactsSort.allCases) { sort in
                        Button {
                            filter.sort = sort
                        } label: {
                            Label(sort.title, systemImage: sort == filter.sort ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }
                } label: {
                    PinesMenuChip(title: filter.sort.title, systemImage: "arrow.up.arrow.down", tone: .neutral)
                }
            }
        }
    }

    private var modeSelectionID: Binding<String> {
        Binding(
            get: { mode.id },
            set: { id in
                if let selected = ArtifactsWorkspaceMode(rawValue: id) {
                    mode = selected
                }
            }
        )
    }
}

private struct ArtifactsAssetKindSelector: View {
    @Binding var selection: ArtifactsAssetKindFilter

    var body: some View {
        Picker("Artifact type", selection: $selection) {
            ForEach(ArtifactsAssetKindFilter.allCases) { kind in
                Label(kind.title, systemImage: kind.systemImage)
                    .tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 430)
        .pinesSegmentedPickerChrome()
    }
}

private struct ArtifactsMediaWorkspace: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @Binding var mode: ArtifactsWorkspaceMode
    @Binding var providerScope: ArtifactsProviderScope
    @Binding var referenceArtifactID: String?
    @Binding var requestedKind: ArtifactsMediaKind?
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    let openLibrary: () -> Void
    @State private var mediaKind: ArtifactsMediaKind = .image
    @State private var modelID = "gpt-image-2"
    @State private var prompt = ""
    @State private var isCreating = false
    @State private var isSettingsPresented = false
    @State private var newArtifactIDs: [String] = []
    @State private var imageQuality = "auto"
    @State private var imageSize = "auto"
    @State private var imageFormat = "png"
    @State private var speechVoice = "alloy"
    @State private var refreshAfterVideoCreate = true

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .gemini])
    }

    private var lifecycleProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.pinesLifecycleProviders.filter { [.openAI, .gemini].contains($0.kind) }
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

    private var selectedReferenceArtifact: ProviderArtifactRecord? {
        guard let referenceArtifactID else { return nil }
        return providerState.providerArtifacts.first { $0.id == referenceArtifactID }
    }

    private var outputArtifacts: [ProviderArtifactRecord] {
        let mediaKinds = ["image", "generated_image", "video", "audio", "speech", "transcription", "translation", "generated_media", "media_operation", "partial_image", "video_job"]
        let recent = providerState.providerArtifacts
            .filter { artifact in
                artifact.isVisibleInArtifactsGallery
                    && providerScope.includes(artifact.providerID)
                    && mediaKinds.contains(artifact.kind.lowercased())
            }
        let byID = recent.reduce(into: [String: ProviderArtifactRecord]()) { result, artifact in
            result[artifact.id] = artifact
        }
        var ordered = newArtifactIDs.compactMap { byID[$0] }
        var seen = Set(ordered.map(\.id))
        ordered.append(contentsOf: recent
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(18))
        return ordered
    }

    var body: some View {
        VStack(spacing: 0) {
            ArtifactsCreateTopBar(
                mode: $mode,
                providerName: provider?.displayName ?? "Choose provider",
                modelName: selectedModelLabel,
                isCreating: isCreating,
                newPrompt: resetComposer,
                openSettings: { isSettingsPresented = true },
                openLibrary: openLibrary
            )

            if let error = providerState.providerLifecycleError {
                PinesGlobalErrorBanner(
                    message: error,
                    dismiss: { providerState.providerLifecycleError = nil }
                )
                    .padding(.horizontal, theme.spacing.large)
                    .padding(.top, theme.spacing.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    ArtifactsCreateComposer(
                        mediaKind: $mediaKind,
                        prompt: $prompt,
                        referenceArtifact: selectedReferenceArtifact,
                        provider: provider,
                        modelLabel: selectedModelLabel,
                        isCreating: isCreating,
                        clearReference: { referenceArtifactID = nil },
                        create: { Task { await createMedia() } }
                    )

                    ArtifactsCreateOutputRail(
                        artifacts: outputArtifacts,
                        selection: $selection,
                        refreshArtifact: { artifact in Task { await refreshOutputArtifact(artifact) } },
                        cancelArtifact: { artifact in pendingConfirmation = .cancelMediaOperation(artifact) },
                        downloadArtifact: { artifact in Task { await downloadOutputArtifact(artifact) } },
                        deleteArtifact: { artifact in pendingConfirmation = .deleteArtifactRecord(artifact) }
                    )
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .pinesExpressiveScrollHaptics()
        }
        .sheet(isPresented: $isSettingsPresented) {
            ArtifactsCreateSettingsSheet(
                providerScope: $providerScope,
                modelID: $modelID,
                mediaKind: mediaKind,
                imageQuality: $imageQuality,
                imageSize: $imageSize,
                imageFormat: $imageFormat,
                speechVoice: $speechVoice,
                refreshAfterVideoCreate: $refreshAfterVideoCreate,
                providers: lifecycleProviders,
                modelOptions: mediaModelOptions
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            consumeRequestedKind()
            normalizeSelectedModel()
        }
        .onChange(of: provider?.id) { _, _ in normalizeSelectedModel() }
        .onChange(of: mediaKind) { _, _ in normalizeSelectedModel() }
        .onChange(of: requestedKind) { _, _ in consumeRequestedKind() }
        .onChange(of: referenceArtifactID) { _, newValue in
            if newValue != nil {
                mediaKind = .image
            }
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
            let created: [ProviderArtifactRecord]
            switch provider.kind {
            case .openAI:
                switch mediaKind {
                case .video:
                    let artifact = try await appModel.createOpenAIVideoArtifact(OpenAIVideoArtifactRequest(prompt: trimmedPrompt, model: model.rawValue), providerID: provider.id, services: services)
                    created = [artifact]
                    if refreshAfterVideoCreate {
                        _ = try? await appModel.refreshOpenAIVideoArtifact(id: artifact.providerFileID ?? artifact.id, providerID: provider.id, services: services)
                    }
                case .speech:
                    let artifact = try await appModel.createOpenAISpeechArtifact(OpenAISpeechArtifactRequest(model: model.rawValue, input: trimmedPrompt, voice: speechVoice), providerID: provider.id, services: services)
                    created = [artifact]
                case .image:
                    if let reference = selectedReferenceArtifact {
                        created = try await appModel.remixOpenAIImageArtifact(
                            providerID: provider.id,
                            modelID: model,
                            prompt: trimmedPrompt,
                            reference: reference,
                            fields: openAIImageFields(),
                            services: services
                        )
                    } else {
                        created = try await appModel.createOpenAIImageArtifacts(
                            providerID: provider.id,
                            modelID: model,
                            prompt: trimmedPrompt,
                            fields: openAIImageFields(),
                            services: services
                        )
                    }
                }
            case .gemini:
                if mediaKind == .image, let reference = selectedReferenceArtifact {
                    created = try await appModel.remixGeminiImageArtifact(
                        providerID: provider.id,
                        modelID: model,
                        prompt: trimmedPrompt,
                        reference: reference,
                        services: services
                    )
                } else {
                    created = try await appModel.createGeminiGeneratedMedia(providerID: provider.id, modelID: model, prompt: trimmedPrompt, kind: mediaKind.rawValue, services: services)
                }
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) media artifacts are not supported here.")
            }
            newArtifactIDs = (created.map(\.id) + newArtifactIDs).reduce(into: [String]()) { result, id in
                if !result.contains(id) { result.append(id) }
            }
            if let first = created.first {
                selection = .artifact(first.id)
            }
            prompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshOutputArtifact(_ artifact: ProviderArtifactRecord) async {
        do {
            switch artifact.providerKind {
            case .openAI where artifact.kind.lowercased() == "video_job":
                guard let providerID = artifact.providerID else { throw InferenceError.providerUnavailable(ProviderID(rawValue: "unknown")) }
                _ = try await appModel.refreshOpenAIVideoArtifact(id: artifact.providerFileID ?? artifact.id, providerID: providerID, services: services)
            case .gemini where artifact.kind.lowercased() == "media_operation":
                guard let providerID = artifact.providerID else { throw InferenceError.providerUnavailable(ProviderID(rawValue: "unknown")) }
                _ = try await appModel.refreshGeminiGeneratedMediaOperation(id: artifact.responseID ?? artifact.id, providerID: providerID, services: services)
            default:
                await appModel.refreshProviderLifecycleState(services: services)
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func downloadOutputArtifact(_ artifact: ProviderArtifactRecord) async {
        guard artifact.providerKind == .openAI, artifact.kind.lowercased() == "video_job" else { return }
        do {
            guard let providerID = artifact.providerID else { throw InferenceError.providerUnavailable(ProviderID(rawValue: "unknown")) }
            _ = try await appModel.downloadOpenAIVideoContentArtifact(id: artifact.providerFileID ?? artifact.id, providerID: providerID, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func openAIImageFields() -> [String: JSONValue] {
        var fields = [String: JSONValue]()
        if imageQuality != "auto" {
            fields["quality"] = .string(imageQuality)
        }
        if imageSize != "auto" {
            fields["size"] = .string(imageSize)
        }
        if imageFormat != "png" {
            fields["output_format"] = .string(imageFormat)
        }
        return fields
    }

    private func resetComposer() {
        prompt = ""
        referenceArtifactID = nil
        selection = nil
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

    private func consumeRequestedKind() {
        guard let requestedKind else { return }
        mediaKind = requestedKind
        self.requestedKind = nil
    }
}

private struct ArtifactsLibraryEmptyState: View {
    @Environment(\.pinesTheme) private var theme
    let createImage: () -> Void
    let createVideo: () -> Void
    let startResearch: () -> Void

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
            VStack(spacing: theme.spacing.xxsmall) {
                Text("No visible artifacts")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.primaryText)
                Text("Reports, generated images, videos, speech, and imported viewable artifacts appear here.")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PinesAdaptiveButtonRow {
                Button(action: createImage) {
                    Label("Image", systemImage: "photo")
                }
                .pinesButtonStyle(.primary)

                Button(action: createVideo) {
                    Label("Video", systemImage: "film")
                }
                .pinesButtonStyle(.secondary)

                Button(action: startResearch) {
                    Label("Research", systemImage: "doc.text.magnifyingglass")
                }
                .pinesButtonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .pinesSurface(.panel, padding: theme.spacing.large)
    }
}

private struct ArtifactsAssetGrid: View {
    @Environment(\.pinesTheme) private var theme
    let assets: [ArtifactsAssetViewModel]
    @Binding var selection: ArtifactsSelection?
    let importArtifact: (ProviderArtifactRecord) -> Void
    let remixArtifact: (ProviderArtifactRecord) -> Void
    let deleteArtifact: (ProviderArtifactRecord) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 210), spacing: theme.spacing.medium)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: theme.spacing.medium) {
            ForEach(assets) { asset in
                ArtifactsAssetCard(
                    asset: asset,
                    isSelected: selection == asset.selection,
                    select: { selection = asset.selection },
                    importArtifact: { importArtifact(asset.artifact) },
                    remixArtifact: { remixArtifact(asset.artifact) },
                    deleteArtifact: { deleteArtifact(asset.artifact) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
}

private struct ArtifactsAssetCard: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.openURL) private var openURL
    let asset: ArtifactsAssetViewModel
    let isSelected: Bool
    let select: () -> Void
    let importArtifact: () -> Void
    let remixArtifact: () -> Void
    let deleteArtifact: () -> Void

    var body: some View {
        PinesArtifactCard(
            isSelected: isSelected,
            minHeight: 292,
            select: select,
            preview: {
            ArtifactsArtifactPreviewSurface(artifact: asset.artifact, maxHeight: 190)
                .aspectRatio(asset.presentation == .report ? 1.18 : 1.08, contentMode: .fit)
        }, details: {
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(asset.title)
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(asset.kind.readableArtifactKind) · \(asset.providerKind.pinesLifecycleTitle)")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }, actions: {
            HStack(spacing: theme.spacing.xsmall) {
                PinesStatusChip(status: asset.status, compact: true)
                Spacer(minLength: 0)
                PinesCompactIconButton(title: "Open", systemImage: "arrow.up.forward.app", isDisabled: asset.artifact.galleryURL == nil) {
                    if let url = asset.artifact.galleryURL {
                        openURL(url)
                    }
                }
                PinesCompactIconButton(title: "Import to Vault", systemImage: "square.and.arrow.down", isDisabled: !asset.artifact.isImportableToVault, action: importArtifact)
                PinesCompactIconButton(title: "Remix", systemImage: "wand.and.stars", isDisabled: !asset.artifact.isRemixableImageArtifact, action: remixArtifact)
                    .help(asset.artifact.remixDisabledReason ?? "Remix")
                PinesCompactIconButton(title: "Delete local record", systemImage: "trash", role: .destructive, action: deleteArtifact)
            }
        })
    }
}

private struct ArtifactsAssetInspectorSlot: View {
    @Environment(\.pinesTheme) private var theme
    let artifact: ProviderArtifactRecord?
    let providers: [CloudProviderConfiguration]
    let importArtifact: (ProviderArtifactRecord) -> Void
    let remixArtifact: (ProviderArtifactRecord) -> Void
    let deleteArtifact: (ProviderArtifactRecord) -> Void

    var body: some View {
        Group {
            if let artifact {
                ArtifactsAssetInspector(
                    artifact: artifact,
                    providers: providers,
                    importArtifact: { importArtifact(artifact) },
                    remixArtifact: { remixArtifact(artifact) },
                    deleteArtifact: { deleteArtifact(artifact) }
                )
            } else {
                VStack(spacing: theme.spacing.small) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                    Text("Select an artifact")
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text("Preview, provenance, and actions stay here while the grid remains stable.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .pinesSurface(.panel, padding: theme.spacing.large)
            }
        }
    }
}

private struct ArtifactsAssetInspector: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.openURL) private var openURL
    let artifact: ProviderArtifactRecord
    let providers: [CloudProviderConfiguration]
    let importArtifact: () -> Void
    let remixArtifact: () -> Void
    let deleteArtifact: () -> Void

    private var providerName: String {
        if let providerID = artifact.providerID,
           let provider = providers.first(where: { $0.id == providerID }) {
            return provider.displayName
        }
        return artifact.providerKind.pinesLifecycleTitle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                ArtifactsArtifactPreviewSurface(artifact: artifact, maxHeight: 320)

                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    Text(artifact.fileName ?? artifact.kind.readableArtifactKind)
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(providerName)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: theme.spacing.xsmall) {
                    inspectorButton("Open", systemImage: "arrow.up.forward.app", disabled: artifact.galleryURL == nil) {
                        if let url = artifact.galleryURL {
                            openURL(url)
                        }
                    }
                    inspectorButton("Import", systemImage: "square.and.arrow.down", disabled: !artifact.isImportableToVault, action: importArtifact)
                    inspectorButton("Remix", systemImage: "wand.and.stars", disabled: !artifact.isRemixableImageArtifact, action: remixArtifact)
                        .help(artifact.remixDisabledReason ?? "Remix")
                    inspectorButton("Delete", systemImage: "trash", disabled: false, role: .destructive, action: deleteArtifact)
                }

                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    inspectorRow("Kind", artifact.kind.readableArtifactKind, systemImage: "tag")
                    inspectorRow("Created", RelativeDateTimeFormatter.shortLabel(for: artifact.createdAt), systemImage: "clock")
                    inspectorRow("Provider", artifact.providerID?.rawValue ?? artifact.providerKind.pinesLifecycleTitle, systemImage: "cloud")
                    inspectorRow("Size", artifact.byteCount.map(providerByteCountLabel) ?? "Unknown", systemImage: "internaldrive")
                }
                .pinesSurface(.inset, padding: theme.spacing.small)

                if let text = artifact.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(text)
                        .font(.system(.caption, design: artifact.galleryPresentation == .report ? .default : .monospaced))
                        .foregroundStyle(theme.colors.primaryText)
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pinesSurface(.inset, padding: theme.spacing.small)
                }
            }
        }
        .pinesSurface(.panel, padding: theme.spacing.medium)
    }

    private func inspectorButton(_ title: String, systemImage: String, disabled: Bool, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .disabled(disabled)
        .pinesButtonStyle(.icon)
        .accessibilityLabel(title)
        .help(title)
    }

    private func inspectorRow(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: theme.spacing.xsmall) {
            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundStyle(theme.colors.secondaryText)
            Text(title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
            Spacer(minLength: theme.spacing.small)
            Text(value)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct ArtifactsCreateTopBar: View {
    @Environment(\.pinesTheme) private var theme
    @Binding var mode: ArtifactsWorkspaceMode
    let providerName: String
    let modelName: String
    let isCreating: Bool
    let newPrompt: () -> Void
    let openSettings: () -> Void
    let openLibrary: () -> Void

    var body: some View {
        PinesWorkspaceTopBar {
            PinesWorkspaceSwitcher(
                selectionID: modeSelectionID,
                items: ArtifactsWorkspaceMode.workspaceSwitcherItems
            )
            .accessibilityLabel("Artifacts workspace")
            .accessibilityValue(mode.title)
            .accessibilityIdentifier("pines.artifacts.workspace.mode")
        } status: {
            Text("\(providerName) - \(modelName)")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        } actions: {
            HStack(spacing: theme.spacing.small) {
                if isCreating {
                    ProgressView()
                        .frame(width: 34, height: 34)
                }

                Button(action: newPrompt) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("New create prompt")
                .help("New")

                Button(action: openLibrary) {
                    Image(systemName: "rectangle.stack")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Open library")
                .help("Library")

                Button(action: openSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Create settings")
                .help("Settings")
            }
        }
    }

    private var modeSelectionID: Binding<String> {
        Binding(
            get: { mode.id },
            set: { id in
                if let selected = ArtifactsWorkspaceMode(rawValue: id) {
                    mode = selected
                }
            }
        )
    }
}

private struct ArtifactsCreateComposer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pinesTheme) private var theme
    @Binding var mediaKind: ArtifactsMediaKind
    @Binding var prompt: String
    let referenceArtifact: ProviderArtifactRecord?
    let provider: CloudProviderConfiguration?
    let modelLabel: String
    let isCreating: Bool
    let clearReference: () -> Void
    let create: () -> Void

    private var isDisabled: Bool {
        provider == nil || isCreating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        PinesComposerBar(
            kind: .panel,
            padding: theme.spacing.medium,
            supplementary: {
            HStack(alignment: .center, spacing: theme.spacing.small) {
                ArtifactsMediaKindSelector(selection: $mediaKind)
                Spacer(minLength: theme.spacing.small)
                PinesStatusChip(status: provider == nil ? .warning("No provider") : .custom(modelLabel, .info), compact: true)
            }

            if let referenceArtifact {
                HStack(spacing: theme.spacing.small) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(theme.colors.accent)
                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text("Reference")
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                        Text(referenceArtifact.fileName ?? referenceArtifact.id)
                            .font(theme.typography.callout.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: theme.spacing.small)
                    Button(action: clearReference) {
                        Image(systemName: "xmark")
                            .frame(width: 16, height: 16)
                    }
                    .pinesButtonStyle(.icon)
                    .accessibilityLabel("Remove reference")
                }
                .pinesSurface(.inset, padding: theme.spacing.small)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }, leading: {
            EmptyView()
        }, field: {
                TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                    .lineLimit(4...9)
                    .accessibilityIdentifier("pines.artifacts.media.prompt")
                    .pinesFieldChrome()
        }, trailing: {
                Button(action: create) {
                    Image(systemName: isCreating ? "hourglass" : "paperplane.fill")
                        .frame(width: 20, height: 20)
                }
                .disabled(isDisabled)
                .accessibilityIdentifier("pines.artifacts.media.create")
                .accessibilityLabel(referenceArtifact == nil ? "Create artifact" : "Remix artifact")
                .pinesButtonStyle(.primary)
        })
        .animation(reduceMotion ? nil : theme.motion.fast, value: referenceArtifact?.id)
    }

    private var promptPlaceholder: String {
        switch mediaKind {
        case .image:
            referenceArtifact == nil ? "Describe the image to create" : "Describe how to transform the reference image"
        case .video:
            "Describe the scene, movement, and audio cues"
        case .speech:
            "Enter the text to turn into speech"
        }
    }
}

private struct ArtifactsCreateSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinesTheme) private var theme
    @Binding var providerScope: ArtifactsProviderScope
    @Binding var modelID: String
    let mediaKind: ArtifactsMediaKind
    @Binding var imageQuality: String
    @Binding var imageSize: String
    @Binding var imageFormat: String
    @Binding var speechVoice: String
    @Binding var refreshAfterVideoCreate: Bool
    let providers: [CloudProviderConfiguration]
    let modelOptions: [ArtifactsMediaModelOption]

    private let imageQualities = ["auto", "low", "medium", "high"]
    private let imageSizes = ["auto", "1024x1024", "1536x1024", "1024x1536"]
    private let imageFormats = ["png", "jpeg", "webp"]
    private let voices = ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $providerScope) {
                        Text("Auto").tag(ArtifactsProviderScope.all)
                        ForEach(providers) { provider in
                            Text(provider.displayName).tag(ArtifactsProviderScope.provider(provider.id))
                        }
                    }
                    Picker("Model", selection: $modelID) {
                        ForEach(modelOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .disabled(modelOptions.isEmpty)
                }

                if mediaKind == .image {
                    Section("Image") {
                        Picker("Quality", selection: $imageQuality) {
                            ForEach(imageQualities, id: \.self) { Text($0.readableArtifactKind).tag($0) }
                        }
                        Picker("Size", selection: $imageSize) {
                            ForEach(imageSizes, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Format", selection: $imageFormat) {
                            ForEach(imageFormats, id: \.self) { Text($0.uppercased()).tag($0) }
                        }
                    }
                }

                if mediaKind == .video {
                    Section("Video") {
                        Toggle("Refresh after create", isOn: $refreshAfterVideoCreate)
                    }
                }

                if mediaKind == .speech {
                    Section("Speech") {
                        Picker("Voice", selection: $speechVoice) {
                            ForEach(voices, id: \.self) { Text($0.readableArtifactKind).tag($0) }
                        }
                    }
                }
            }
            .pinesThemedForm()
            .navigationTitle("Create Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ArtifactsCreateOutputRail: View {
    @Environment(\.pinesTheme) private var theme
    let artifacts: [ProviderArtifactRecord]
    @Binding var selection: ArtifactsSelection?
    let refreshArtifact: (ProviderArtifactRecord) -> Void
    let cancelArtifact: (ProviderArtifactRecord) -> Void
    let downloadArtifact: (ProviderArtifactRecord) -> Void
    let deleteArtifact: (ProviderArtifactRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            HStack {
                Text("Output")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.primaryText)
                Spacer()
                Text("\(artifacts.count)")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .monospacedDigit()
            }

            if artifacts.isEmpty {
                PinesEmptyState(title: "No generated output yet", detail: "Created images, video jobs, speech, and remix results appear here first.", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .pinesSurface(.panel, padding: theme.spacing.large)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: theme.spacing.medium) {
                        ForEach(artifacts) { artifact in
                            ArtifactsCreateOutputCard(
                                artifact: artifact,
                                isSelected: selection == .artifact(artifact.id),
                                select: { selection = .artifact(artifact.id) },
                                refreshArtifact: { refreshArtifact(artifact) },
                                cancelArtifact: { cancelArtifact(artifact) },
                                downloadArtifact: { downloadArtifact(artifact) },
                                deleteArtifact: { deleteArtifact(artifact) }
                            )
                            .frame(width: 258)
                        }
                    }
                    .padding(.vertical, theme.spacing.xxsmall)
                }
            }
        }
    }
}

private struct ArtifactsCreateOutputCard: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.openURL) private var openURL
    let artifact: ProviderArtifactRecord
    let isSelected: Bool
    let select: () -> Void
    let refreshArtifact: () -> Void
    let cancelArtifact: () -> Void
    let downloadArtifact: () -> Void
    let deleteArtifact: () -> Void

    private var isOperation: Bool {
        let kind = artifact.kind.lowercased()
        return kind == "video_job" || kind == "media_operation"
    }

    private var canDownload: Bool {
        artifact.providerKind == .openAI && artifact.kind.lowercased() == "video_job"
    }

    var body: some View {
        PinesArtifactCard(
            isSelected: isSelected,
            minHeight: 268,
            select: select,
            preview: {
            ArtifactsArtifactPreviewSurface(artifact: artifact, maxHeight: 160)
                .aspectRatio(1.12, contentMode: .fit)
        }, details: {
            Text(artifact.fileName ?? artifact.kind.readableArtifactKind)
                .font(theme.typography.callout.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(artifact.kind.readableArtifactKind) · \(artifact.providerKind.pinesLifecycleTitle)")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }, actions: {
            HStack(spacing: theme.spacing.xsmall) {
                PinesCompactIconButton(title: "Open", systemImage: "arrow.up.forward.app", isDisabled: artifact.galleryURL == nil) {
                    if let url = artifact.galleryURL {
                        openURL(url)
                    }
                }

                Menu {
                    Button(action: refreshArtifact) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!isOperation)

                    Button(action: downloadArtifact) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .disabled(!canDownload)

                    Button(role: .destructive, action: cancelArtifact) {
                        Label("Cancel operation", systemImage: "xmark")
                    }
                    .disabled(!isOperation)

                    Button(role: .destructive, action: deleteArtifact) {
                        Label("Delete local record", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("More artifact actions")
            }
        })
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
    @State private var selectedVaultDocumentID: UUID?
    @State private var purpose = "assistants"

    private var provider: CloudProviderConfiguration? {
        settingsState.cloudProviders.provider(in: providerScope, allowed: [.openAI, .anthropic, .gemini])
    }

    private var summaries: [ArtifactsResourceSummary] {
        ArtifactsWorkspaceDeriver.fileSummaries(files: providerState.providerFiles, filter: .init(providerScope: providerScope))
    }

    private var transfers: [ProviderTransferRecord] {
        providerState.providerTransfers.filter { transfer in
            switch providerScope {
            case .all: true
            case .provider(let providerID): transfer.providerID == providerID
            }
        }
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
                            Label("Create Cloud Copy", systemImage: "square.and.arrow.up")
                        }
                        .disabled(provider == nil)
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

            if !transfers.isEmpty {
                PinesCardSection(
                    "Transfer Queue",
                    subtitle: "Transfers survive relaunch. Cancelled, interrupted, and failed uploads keep their staged source for retry.",
                    systemImage: "arrow.up.arrow.down.circle"
                ) {
                    VStack(spacing: theme.spacing.small) {
                        ForEach(transfers) { transfer in
                            transferRow(transfer)
                        }
                    }
                }
            }

            ArtifactsResourceList(summaries: summaries, selection: $selection, emptyTitle: "No provider files", emptyDetail: "Provider-hosted files appear here after upload or provider refresh.")

            fileActions
        }
    }

    @ViewBuilder
    private var fileActions: some View {
        if case .file(let id) = selection, let file = providerState.providerFiles.first(where: { $0.id == id }) {
            PinesCardSection("Cloud Copy Actions", subtitle: "These operate on the cloud copy, not local Vault source files.", systemImage: "ellipsis.circle") {
                PinesAdaptiveButtonRow {
                    Button {
                        Task { await refreshFile(file) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .pinesButtonStyle(.secondary, fillWidth: true)

                    if file.providerKind == .anthropic {
                        Button {
                            Task { await downloadFile(file) }
                        } label: {
                            Label("Download as artifact", systemImage: "square.and.arrow.down")
                        }
                        .pinesButtonStyle(.secondary, fillWidth: true)
                    }

                    Button(role: .destructive) {
                        pendingConfirmation = .deleteProviderFile(file)
                    } label: {
                        Label("Delete provider file", systemImage: "trash")
                    }
                    .pinesButtonStyle(.destructive, fillWidth: true)
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

    @ViewBuilder
    private func transferRow(_ transfer: ProviderTransferRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.fileName)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                    Text("\(transfer.providerKind.pinesLifecycleTitle) - \(transfer.status.pinesTransferLabel)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
                Spacer(minLength: theme.spacing.small)
                if transfer.status.isActive {
                    Button("Cancel", role: .destructive) {
                        Task { await appModel.cancelProviderTransfer(id: transfer.id, services: services) }
                    }
                    .font(theme.typography.caption.weight(.semibold))
                } else if transfer.status.canRetry {
                    Button("Retry") {
                        Task { await appModel.retryProviderTransfer(id: transfer.id, services: services) }
                    }
                    .font(theme.typography.caption.weight(.semibold))
                    Button("Remove", role: .destructive) {
                        Task { await appModel.removeProviderTransfer(id: transfer.id, services: services) }
                    }
                    .font(theme.typography.caption.weight(.semibold))
                } else {
                    Button("Clear") {
                        Task { await appModel.removeProviderTransfer(id: transfer.id, services: services) }
                    }
                    .font(theme.typography.caption.weight(.semibold))
                }
            }

            if transfer.status.isActive {
                if let progress = transfer.progressFraction,
                   transfer.status == .transferring,
                   transfer.completedBytes > 0 {
                    ProgressView(value: progress)
                        .accessibilityLabel("Upload progress")
                        .accessibilityValue("\(Int(progress * 100)) percent")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(transfer.status.pinesTransferLabel)
                }
            }
            if let total = transfer.totalBytes {
                Text(transfer.completedBytes > 0
                    ? "\(providerByteCountLabel(transfer.completedBytes)) of \(providerByteCountLabel(total)) - attempt \(transfer.retryCount + 1)"
                    : "\(providerByteCountLabel(total)) staged - attempt \(transfer.retryCount + 1)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            if let error = transfer.lastError, !error.isEmpty {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        guard let provider else { return }
        do {
            guard let url = try result.get().first else { return }
            try await appModel.enqueueProviderFileTransfer(
                provider: provider,
                fileURL: url,
                purpose: provider.kind == .openAI ? purpose : nil,
                services: services
            )
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func uploadVaultDocument() async {
        guard let provider, let selectedVaultDocumentID else { return }
        do {
            let title = vaultState.vaultItems.first(where: { $0.id == selectedVaultDocumentID })?.title ?? "Vault document"
            try await appModel.enqueueVaultProviderTransfer(
                provider: provider,
                documentID: selectedVaultDocumentID,
                documentTitle: title,
                purpose: provider.kind == .openAI ? purpose : nil,
                services: services
            )
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

private extension ProviderTransferStatus {
    var pinesTransferLabel: String {
        switch self {
        case .queued: "Queued"
        case .preparing: "Preparing durable source"
        case .transferring: "Uploading"
        case .verifying: "Verifying cloud copy"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .interrupted: "Interrupted"
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
                    PinesAdaptiveButtonRow {
                        Button {
                            Task { await refreshCache(cache) }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .pinesButtonStyle(.secondary, fillWidth: true)

                        Button(role: .destructive) {
                            pendingConfirmation = .deleteProviderCache(cache)
                        } label: {
                            Label("Delete cloud context", systemImage: "trash")
                        }
                        .pinesButtonStyle(.destructive, fillWidth: true)
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
                    PinesAdaptiveButtonRow {
                        Button {
                            Task { await refreshBatch(batch) }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .pinesButtonStyle(.secondary, fillWidth: true)

                        Button(role: .destructive) {
                            pendingConfirmation = .cancelBatch(batch)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .pinesButtonStyle(.destructive, fillWidth: true)
                        .disabled(batch.status.providerIsTerminal)

                        Button {
                            Task { await importResults(batch) }
                        } label: {
                            Label("Import results", systemImage: "square.and.arrow.down")
                        }
                        .pinesButtonStyle(.secondary, fillWidth: true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @Binding var mode: ArtifactsWorkspaceMode
    let providerScope: ArtifactsProviderScope
    @Binding var selection: ArtifactsSelection?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    @State private var prompt = ""
    @State private var followUpPrompt = ""
    @State private var modelID = "gpt-5.5"
    @State private var depth: OpenAIDeepResearchDepth = .standard
    @State private var reportFormat: OpenAIDeepResearchReportFormat = .memo
    @State private var isStarting = false
    @State private var isSendingFollowUp = false
    @State private var selectedThreadID: String?
    @State private var isHistoryPresented = false
    @State private var clarificationDraft: ArtifactsResearchClarificationDraft?
    @State private var clarificationAnswers: [String: String] = [:]
    @FocusState private var isComposerFocused: Bool

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

    private var threads: [ArtifactsResearchThread] {
        ArtifactsResearchThread.threads(
            from: providerState.providerResearchRuns.filter { providerScope.includes($0.providerID) }
        )
    }

    private var selectedThread: ArtifactsResearchThread? {
        if let selectedThreadID,
           let thread = threads.first(where: { $0.id == selectedThreadID }) {
            return thread
        }
        if case .research(let id) = selection,
           let thread = threads.first(where: { $0.runs.contains { $0.id == id } }) {
            return thread
        }
        return nil
    }

    private var composerText: Binding<String> {
        Binding(
            get: { selectedThread == nil ? prompt : followUpPrompt },
            set: { value in
                if selectedThread == nil {
                    prompt = value
                } else {
                    followUpPrompt = value
                }
            }
        )
    }

    private var sendDisabled: Bool {
        if provider == nil || modelID.isEmpty || isStarting || isSendingFollowUp {
            return true
        }
        if selectedThread == nil {
            return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return followUpPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            researchTopBar
            if let error = providerState.providerLifecycleError {
                PinesGlobalErrorBanner(
                    message: error,
                    dismiss: { providerState.providerLifecycleError = nil }
                )
                    .padding(.horizontal, theme.spacing.large)
                    .padding(.top, theme.spacing.small)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            researchConversation
            researchComposer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.appBackground)
        .onAppear { normalizeSelectedModel() }
        .onChange(of: provider?.id) { _, _ in
            selectedThreadID = nil
            selection = nil
            normalizeSelectedModel()
        }
        .sheet(isPresented: $isHistoryPresented) {
            ArtifactsResearchHistorySheet(
                threads: threads,
                selectedThreadID: selectedThread?.id,
                select: { thread in
                    selectedThreadID = thread.id
                    selection = .research(thread.latestRun.id)
                    isHistoryPresented = false
                }
            )
            .presentationDetents([.medium, .large])
            .pinesTheme(theme)
        }
    }

    private var researchTopBar: some View {
        PinesWorkspaceTopBar {
            PinesWorkspaceSwitcher(
                selectionID: modeSelectionID,
                items: ArtifactsWorkspaceMode.workspaceSwitcherItems
            ) { _ in
                selection = nil
            }
            .accessibilityLabel("Artifacts workspace")
            .accessibilityValue(mode.title)
            .accessibilityIdentifier("pines.artifacts.workspace.mode")
        } status: {
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(selectedThread?.title ?? "Deep Research")
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.primaryText)
                    .pinesFittingText()

                Text(researchSubtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            HStack(spacing: theme.spacing.small) {
            Button {
                startNewThread()
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 18, height: 18)
            }
            .pinesButtonStyle(.icon)
            .accessibilityLabel("New research chat")
            .accessibilityIdentifier("pines.artifacts.research.new")

            Button {
                isHistoryPresented = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 18, height: 18)
            }
            .disabled(threads.isEmpty)
            .pinesButtonStyle(.icon)
            .accessibilityLabel("Research history")
            .accessibilityIdentifier("pines.artifacts.research.history")
        }
        }
    }

    private var modeSelectionID: Binding<String> {
        Binding(
            get: { mode.id },
            set: { id in
                if let selected = ArtifactsWorkspaceMode(rawValue: id) {
                    mode = selected
                }
            }
        )
    }

    private var researchSubtitle: String {
        if let thread = selectedThread {
            return "\(thread.providerKind.pinesLifecycleTitle) - \(thread.modelID.rawValue) - \(thread.statusText)"
        }
        if let provider {
            return "\(provider.displayName) - \(selectedModelLabel)"
        }
        return "Choose an OpenAI or Gemini provider in Artifacts scope"
    }

    private var researchConversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.large) {
                    if let selectedThread {
                        ForEach(selectedThread.runs) { run in
                            ArtifactsResearchRunExchange(
                                run: run,
                                finalReport: finalReport(for: run),
                                refresh: { Task { await refreshRun(run) } },
                                cancel: { pendingConfirmation = .cancelResearch(run) },
                                openArtifact: { artifact in selection = .artifact(artifact.id) }
                            )
                            .id(run.id)
                        }
                    } else {
                        researchEmptyState
                    }
                }
                .padding(.horizontal, theme.spacing.large)
                .padding(.vertical, theme.spacing.large)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: selectedThread?.latestRun.id) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : theme.motion.fast) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var researchEmptyState: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            HStack(alignment: .top, spacing: theme.spacing.small) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 34, height: 34)
                    .background(theme.colors.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    Text(provider == nil ? "Connect a research provider" : "What should we research?")
                        .font(theme.typography.title.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(provider == nil ? "Select an OpenAI or Gemini provider scope before starting." : "Ask a broad or specific question. I can pause for up to five clarifications before launching the provider research run.")
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !threads.isEmpty {
                Button {
                    isHistoryPresented = true
                } label: {
                    Label("Open research history", systemImage: "clock.arrow.circlepath")
                }
                .pinesButtonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
    }

    private var researchComposer: some View {
        PinesComposerBar(
            kind: .chrome,
            maxWidth: 860,
            padding: 0,
            showsSurface: false,
            supplementary: {
                if let clarificationDraft {
                ArtifactsResearchClarificationPanel(
                    draft: clarificationDraft,
                    answers: $clarificationAnswers,
                    start: {
                        Task {
                            await startRun(
                                originalPrompt: clarificationDraft.originalPrompt,
                                providerPrompt: clarificationDraft.providerPrompt(answers: clarificationAnswers)
                            )
                        }
                    },
                    skip: {
                        Task {
                            await startRun(
                                originalPrompt: clarificationDraft.originalPrompt,
                                providerPrompt: clarificationDraft.providerPrompt(answers: [:])
                            )
                        }
                    },
                    cancel: {
                        self.clarificationDraft = nil
                        clarificationAnswers = [:]
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }, leading: {
            researchSettingsButton
        }, field: {
                TextField(selectedThread == nil ? "Ask a research question" : "Ask a follow-up", text: composerText, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier(selectedThread == nil ? "pines.artifacts.research.prompt" : "pines.artifacts.research.follow-up")
                    .pinesFieldChrome()
        }, trailing: {
                Button {
                    Task { await commitComposer() }
                } label: {
                    Image(systemName: isStarting || isSendingFollowUp ? "hourglass" : "paperplane.fill")
                        .frame(width: 18, height: 18)
                }
                .disabled(sendDisabled)
                .accessibilityIdentifier(selectedThread == nil ? "pines.artifacts.research.start" : "pines.artifacts.research.follow-up.send")
                .pinesButtonStyle(.primary)
                .accessibilityLabel(selectedThread == nil ? "Start research" : "Send follow-up")
        })
        .padding(.horizontal, theme.spacing.large)
        .padding(.vertical, theme.spacing.small)
        .frame(maxWidth: .infinity)
    }

    private var researchSettingsButton: some View {
        Menu {
            Section("Model") {
                ForEach(modelOptions) { option in
                    Button {
                        modelID = option.id
                    } label: {
                        Label(option.title, systemImage: option.id == modelID ? "checkmark" : "cpu")
                    }
                }
            }
            Section("Depth") {
                ForEach(OpenAIDeepResearchDepth.allCases, id: \.self) { option in
                    Button {
                        depth = option
                    } label: {
                        Label(option.rawValue.readableArtifactKind, systemImage: option == depth ? "checkmark" : "slider.horizontal.3")
                    }
                }
            }
            Section("Report") {
                ForEach(OpenAIDeepResearchReportFormat.allCases, id: \.self) { option in
                    Button {
                        reportFormat = option
                    } label: {
                        Label(option.rawValue.readableArtifactKind, systemImage: option == reportFormat ? "checkmark" : "doc.text")
                    }
                }
            }
            if let provider {
                Button {
                    Task { await resumeRuns(provider) }
                } label: {
                    Label("Refresh running research", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 18, height: 18)
        }
        .disabled(provider == nil || modelOptions.isEmpty)
        .pinesButtonStyle(.icon)
        .accessibilityLabel("Research settings")
    }

    @MainActor
    private func commitComposer() async {
        if let selectedThread {
            await sendFollowUp(in: selectedThread)
            return
        }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        let questions = ArtifactsResearchClarifier.questions(for: trimmedPrompt)
        guard !questions.isEmpty else {
            await startRun(originalPrompt: trimmedPrompt, providerPrompt: trimmedPrompt)
            return
        }
        clarificationDraft = ArtifactsResearchClarificationDraft(originalPrompt: trimmedPrompt, questions: questions)
        clarificationAnswers = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, "") })
    }

    @MainActor
    private func startRun(originalPrompt: String, providerPrompt: String) async {
        guard let provider else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let threadID = UUID().uuidString
            let resolvedTitle = Self.derivedResearchTitle(from: originalPrompt)
            let model = ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            let vectorStoreIDs = providerState.providerVectorStores.filter { $0.providerID == provider.id }.map(\.id)
            let providerFileIDs = providerState.providerFiles.filter { $0.providerID == provider.id }.map(\.id)
            let metadata = researchMetadata(threadID: threadID, userPrompt: originalPrompt)
            let run: ProviderResearchRunRecord
            switch provider.kind {
            case .openAI:
                let request = OpenAIDeepResearchRequest(
                    providerID: provider.id,
                    modelID: model,
                    title: resolvedTitle,
                    prompt: providerPrompt,
                    depth: depth,
                    sourcePolicy: .webAndFiles(
                        vectorStoreIDs: vectorStoreIDs.map { OpenAIVectorStoreID(rawValue: $0) },
                        providerFileIDs: providerFileIDs.map { OpenAIProviderFileID(rawValue: $0) }
                    ),
                    reportFormat: reportFormat,
                    metadata: metadata
                )
                run = try await appModel.startOpenAIDeepResearch(request, services: services)
            case .gemini:
                let request = PinesProviderDeepResearchRequest(
                    providerID: provider.id,
                    providerKind: provider.kind,
                    modelID: model,
                    title: resolvedTitle,
                    prompt: providerPrompt,
                    depth: depth.rawValue,
                    reportFormat: reportFormat.rawValue,
                    vectorStoreIDs: vectorStoreIDs,
                    providerFileIDs: providerFileIDs,
                    metadata: metadata
                )
                run = try await appModel.startGeminiDeepResearch(request, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
            selectedThreadID = threadID
            selection = .research(run.id)
            prompt = ""
            clarificationDraft = nil
            clarificationAnswers = [:]
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func sendFollowUp(in thread: ArtifactsResearchThread) async {
        let question = followUpPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        isSendingFollowUp = true
        defer { isSendingFollowUp = false }
        do {
            let latest = thread.latestRun
            let metadata = researchMetadata(threadID: thread.id, userPrompt: question, followUpOf: latest.id)
            let run: ProviderResearchRunRecord
            switch latest.providerKind {
            case .gemini:
                run = try await appModel.startGeminiDeepResearchFollowUp(
                    prompt: question,
                    previousRunID: latest.id,
                    providerID: latest.providerID,
                    services: services,
                    title: "Follow-up: \(thread.title)",
                    metadata: metadata
                )
            case .openAI:
                let request = OpenAIDeepResearchRequest(
                    providerID: latest.providerID,
                    modelID: latest.modelID,
                    title: "Follow-up: \(thread.title)",
                    prompt: Self.followUpProviderPrompt(question: question, thread: thread, artifacts: providerState.providerArtifacts),
                    depth: depth,
                    sourcePolicy: .webAndFiles(
                        vectorStoreIDs: providerState.providerVectorStores.filter { $0.providerID == latest.providerID }.map { OpenAIVectorStoreID(rawValue: $0.id) },
                        providerFileIDs: providerState.providerFiles.filter { $0.providerID == latest.providerID }.map { OpenAIProviderFileID(rawValue: $0.id) }
                    ),
                    reportFormat: reportFormat,
                    metadata: metadata
                )
                run = try await appModel.startOpenAIDeepResearch(request, services: services)
            default:
                throw InferenceError.invalidRequest("\(latest.providerKind.pinesLifecycleTitle) Deep Research follow-up is not supported here.")
            }
            selectedThreadID = thread.id
            selection = .research(run.id)
            followUpPrompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func researchMetadata(threadID: String, userPrompt: String, followUpOf: String? = nil) -> [String: String] {
        var metadata = [
            "pines.research_thread_id": threadID,
            "pines.user_prompt": String(userPrompt.prefix(512)),
            "pines.research_ui": "chat_pane_v2",
        ]
        if let followUpOf {
            metadata["pines.follow_up_of"] = followUpOf
        }
        return metadata
    }

    private func finalReport(for run: ProviderResearchRunRecord) -> ProviderArtifactRecord? {
        run.finalReportArtifactID.flatMap { id in
            providerState.providerArtifacts.first { $0.id == id }
        }
    }

    private func startNewThread() {
        selectedThreadID = nil
        selection = nil
        prompt = ""
        followUpPrompt = ""
        clarificationDraft = nil
        clarificationAnswers = [:]
        isComposerFocused = true
    }

    @MainActor
    private func resumeRuns(_ provider: CloudProviderConfiguration) async {
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

    private static func followUpProviderPrompt(question: String, thread: ArtifactsResearchThread, artifacts: [ProviderArtifactRecord]) -> String {
        let priorContext = thread.runs.map { run in
            let report = run.finalReportArtifactID
                .flatMap { id in artifacts.first { $0.id == id } }
                .flatMap(ArtifactsResearchReportText.text(from:))
                .map { String($0.prefix(2400)) }
                ?? run.lastError
                ?? run.status
            return """
            Prior prompt:
            \(run.researchDisplayPrompt)

            Prior output excerpt:
            \(report)
            """
        }.joined(separator: "\n\n---\n\n")

        return """
        Follow-up question:
        \(question)

        Use the prior Deep Research context below. Verify new claims with fresh sources where needed, keep citations visible, and answer as a continuation of the same research thread.

        \(priorContext)
        """
    }
}

private struct ArtifactsResearchThread: Identifiable, Hashable {
    var id: String
    var runs: [ProviderResearchRunRecord]

    var latestRun: ProviderResearchRunRecord {
        runs.max { $0.updatedAt < $1.updatedAt } ?? runs[0]
    }

    var title: String { runs.first?.title ?? latestRun.title }
    var providerKind: CloudProviderKind { latestRun.providerKind }
    var modelID: ModelID { latestRun.modelID }
    var updatedAt: Date { latestRun.updatedAt }
    var sourceCount: Int {
        Set(runs.flatMap { ArtifactsWorkspaceDeriver.researchSources(for: $0).map { $0.url ?? $0.title } }).count
    }

    var statusText: String {
        if runs.contains(where: { !$0.status.providerIsTerminal }) {
            return "researching"
        }
        if latestRun.lastError != nil {
            return "needs attention"
        }
        return "ready"
    }

    static func threads(from runs: [ProviderResearchRunRecord]) -> [ArtifactsResearchThread] {
        let grouped = Dictionary(grouping: runs) { run in
            run.providerMetadata["pines.research_thread_id"]
                ?? run.providerMetadata["pines.follow_up_of"]
                ?? run.id
        }
        return grouped.map { key, groupedRuns in
            ArtifactsResearchThread(
                id: key,
                runs: groupedRuns.sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.updatedAt < rhs.updatedAt
                    }
                    return lhs.createdAt < rhs.createdAt
                }
            )
        }
        .sorted { lhs, rhs in
            if lhs.runs.contains(where: { !$0.status.providerIsTerminal }) != rhs.runs.contains(where: { !$0.status.providerIsTerminal }) {
                return lhs.runs.contains(where: { !$0.status.providerIsTerminal })
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

private extension ProviderResearchRunRecord {
    var researchDisplayPrompt: String {
        if let prompt = providerMetadata["pines.user_prompt"], !prompt.isEmpty {
            return prompt
        }
        if let range = prompt.range(of: "Follow-up question for previous Deep Research run", options: .caseInsensitive) {
            let followUp = prompt[range.upperBound...]
            if let separator = followUp.range(of: "Original research request:", options: .caseInsensitive) {
                return String(followUp[..<separator.lowerBound])
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return prompt
    }
}

private struct ArtifactsResearchRunExchange: View {
    @Environment(\.pinesTheme) private var theme
    let run: ProviderResearchRunRecord
    let finalReport: ProviderArtifactRecord?
    let refresh: () -> Void
    let cancel: () -> Void
    let openArtifact: (ProviderArtifactRecord) -> Void

    private var events: [ArtifactsResearchTimelineEvent] {
        ArtifactsWorkspaceDeriver.researchTimeline(for: run)
    }

    private var sources: [ArtifactsResearchSource] {
        ArtifactsWorkspaceDeriver.researchSources(for: run)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesMessageBubble(role: .user, maxWidth: 640) {
                Text(run.researchDisplayPrompt)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            PinesMessageBubble(role: .assistant, isActive: !run.status.providerIsTerminal) {
                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    assistantHeader
                    ArtifactsResearchProgressList(events: events, sources: sources)

                    if let finalReport {
                        ArtifactsResearchFinalReportMessage(artifact: finalReport) {
                            openArtifact(finalReport)
                        }
                    } else if run.status.providerIsTerminal {
                        terminalEmptyMessage
                    }
                }
            }
        }
    }

    private var assistantHeader: some View {
        HStack(alignment: .center, spacing: theme.spacing.small) {
            PinesStatusIndicator(
                color: run.status.providerCloudStatus.tone.color(in: theme),
                isActive: !run.status.providerIsTerminal,
                size: 8
            )
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(run.status.providerCloudStatus.title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                Text("\(run.providerKind.pinesLifecycleTitle) - \(run.modelID.rawValue)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: theme.spacing.small)

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .pinesButtonStyle(.icon)
            .accessibilityLabel("Refresh research")

            if !run.status.providerIsTerminal {
                Button(role: .destructive, action: cancel) {
                    Image(systemName: "xmark")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Cancel research")
            }
        }
    }

    private var terminalEmptyMessage: some View {
        Label {
            Text(run.lastError ?? "The run completed without a saved report artifact.")
                .font(theme.typography.caption)
                .foregroundStyle(run.lastError == nil ? theme.colors.secondaryText : theme.colors.danger)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: run.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(run.lastError == nil ? theme.colors.success : theme.colors.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ArtifactsResearchProgressList: View {
    @Environment(\.pinesTheme) private var theme
    let events: [ArtifactsResearchTimelineEvent]
    let sources: [ArtifactsResearchSource]
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                ForEach(events.prefix(12)) { event in
                    HStack(alignment: .top, spacing: theme.spacing.small) {
                        Image(systemName: event.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(event.tone.color(in: theme))
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            Text(event.title)
                                .font(theme.typography.caption.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)
                            Text(event.detail)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(3)
                        }
                    }
                }

                if sources.isEmpty {
                    Text("Source pages will appear here when the provider returns citations or searched-page metadata.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: theme.spacing.xsmall)], alignment: .leading, spacing: theme.spacing.xsmall) {
                        ForEach(sources.prefix(16)) { source in
                            ArtifactsResearchSourceChip(source: source)
                        }
                    }
                }
            }
            .padding(.top, theme.spacing.small)
        } label: {
            HStack(spacing: theme.spacing.xsmall) {
                Label("Research activity", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer(minLength: theme.spacing.small)
                Text("\(sources.count)")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
                    .monospacedDigit()
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }
}

private struct ArtifactsResearchSourceChip: View {
    @Environment(\.pinesTheme) private var theme
    let source: ArtifactsResearchSource

    var body: some View {
        Group {
            if let urlString = source.url, let url = URL(string: urlString) {
                Link(destination: url) { chipContent }
            } else {
                chipContent
            }
        }
        .buttonStyle(.plain)
    }

    private var chipContent: some View {
        HStack(alignment: .top, spacing: theme.spacing.xsmall) {
            Image(systemName: source.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(source.tone.color(in: theme))
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                Text(source.url ?? source.detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing.xsmall)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
    }
}

private struct ArtifactsResearchFinalReportMessage: View {
    @Environment(\.pinesTheme) private var theme
    let artifact: ProviderArtifactRecord
    let open: () -> Void

    private var reportText: String {
        ArtifactsResearchReportText.text(from: artifact) ?? "Report saved. Open the full report to view the complete output."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.small) {
                Label("Final report", systemImage: "doc.richtext")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.success)
                Spacer()
                Button {
                    open()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .labelStyle(.iconOnly)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Open final report artifact")
            }

            MarkdownMessageView(
                messageID: UUID(),
                content: reportText,
                isStreaming: false
            )
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }
}

private enum ArtifactsResearchReportText {
    static func text(from artifact: ProviderArtifactRecord) -> String? {
        if let text = artifact.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return userFacingText(from: artifact.content)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
}

private struct ArtifactsResearchHistorySheet: View {
    @Environment(\.pinesTheme) private var theme
    let threads: [ArtifactsResearchThread]
    let selectedThreadID: String?
    let select: (ArtifactsResearchThread) -> Void
    @State private var query = ""

    private var filteredThreads: [ArtifactsResearchThread] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return threads }
        return threads.filter { thread in
            thread.title.lowercased().contains(trimmed)
                || thread.runs.contains { $0.researchDisplayPrompt.lowercased().contains(trimmed) }
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredThreads) { thread in
                Button {
                    select(thread)
                } label: {
                    HStack(alignment: .top, spacing: theme.spacing.small) {
                        Image(systemName: thread.id == selectedThreadID ? "checkmark.circle.fill" : "doc.text.magnifyingglass")
                            .foregroundStyle(thread.id == selectedThreadID ? theme.colors.accent : theme.colors.secondaryText)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            Text(thread.title)
                                .font(theme.typography.callout.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(2)
                            Text(thread.latestRun.researchDisplayPrompt)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(2)
                            Text("\(thread.providerKind.pinesLifecycleTitle) - \(thread.statusText) - \(thread.sourceCount) sources - \(RelativeDateTimeFormatter.shortLabel(for: thread.updatedAt))")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, theme.spacing.xxsmall)
                }
            }
            .searchable(text: $query, prompt: "Search research")
            .navigationTitle("Research History")
        }
    }
}

private struct ArtifactsResearchClarificationQuestion: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let placeholder: String
}

private struct ArtifactsResearchClarificationDraft: Identifiable, Hashable {
    var id: String { originalPrompt }
    let originalPrompt: String
    let questions: [ArtifactsResearchClarificationQuestion]

    func providerPrompt(answers: [String: String]) -> String {
        let resolvedAnswers = questions.compactMap { question -> String? in
            let answer = answers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !answer.isEmpty else { return nil }
            return "- \(question.title): \(answer)"
        }
        guard !resolvedAnswers.isEmpty else {
            return """
            \(originalPrompt)

            Proceed with reasonable assumptions. State any important assumptions before the report.
            """
        }
        return """
        \(originalPrompt)

        Clarifications from the user:
        \(resolvedAnswers.joined(separator: "\n"))
        """
    }
}

private enum ArtifactsResearchClarifier {
    static func questions(for prompt: String) -> [ArtifactsResearchClarificationQuestion] {
        let lowercased = prompt.lowercased()
        var questions = [ArtifactsResearchClarificationQuestion]()
        if !containsAny(lowercased, ["202", "today", "yesterday", "last ", "next ", "current", "latest", "q1", "q2", "q3", "q4", "month", "year"]) {
            questions.append(.init(id: "timeframe", title: "Timeframe", detail: "What dates or recency should the research prioritize?", placeholder: "Example: last 12 months, 2024-2026, current as of today"))
        }
        if !containsAny(lowercased, ["us", "u.s.", "usa", "europe", "eu", "global", "uk", "germany", "china", "japan", "india", "market"]) {
            questions.append(.init(id: "scope", title: "Geographic or market scope", detail: "Should the answer focus on a region, market, or audience?", placeholder: "Example: United States consumers, EU regulation, global enterprise buyers"))
        }
        if !containsAny(lowercased, ["compare", "versus", "vs", "rank", "best", "benchmark", "criteria"]) {
            questions.append(.init(id: "decision", title: "Decision criteria", detail: "What should the report optimize for or compare against?", placeholder: "Example: adoption, price, regulation, risk, technical quality"))
        }
        if !containsAny(lowercased, ["primary", "academic", "news", "filing", "official", "source", "citation", "paper"]) {
            questions.append(.init(id: "sources", title: "Source preference", detail: "Are there source types to prefer or avoid?", placeholder: "Example: primary sources and filings; avoid blogs"))
        }
        if !containsAny(lowercased, ["memo", "table", "bullets", "brief", "report", "slides", "executive", "technical"]) {
            questions.append(.init(id: "format", title: "Output format", detail: "How should the final result be shaped?", placeholder: "Example: executive memo with a comparison table"))
        }
        return Array(questions.prefix(5))
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

private struct ArtifactsResearchClarificationPanel: View {
    @Environment(\.pinesTheme) private var theme
    let draft: ArtifactsResearchClarificationDraft
    @Binding var answers: [String: String]
    let start: () -> Void
    let skip: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.small) {
                Label("Clarify before research", systemImage: "questionmark.bubble")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .frame(width: 18, height: 18)
                }
                .pinesButtonStyle(.icon)
                .accessibilityLabel("Dismiss clarification")
            }

            ForEach(draft.questions) { question in
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(question.title)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    TextField(question.placeholder, text: Binding(
                        get: { answers[question.id] ?? "" },
                        set: { answers[question.id] = $0 }
                    ), axis: .vertical)
                    .lineLimit(1...3)
                    .pinesFieldChrome()
                    Text(question.detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.tertiaryText)
                }
            }

            HStack(spacing: theme.spacing.small) {
                Button("Start with answers", action: start)
                    .pinesButtonStyle(.primary)
                Button("Use assumptions", action: skip)
                    .pinesButtonStyle(.secondary)
            }
        }
        .pinesSurface(.panel, padding: theme.spacing.medium)
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

private struct ArtifactsMediaKindSelector: View {
    @Binding var selection: ArtifactsMediaKind

    var body: some View {
        Picker("Media type", selection: $selection) {
            ForEach(ArtifactsMediaKind.allCases) { kind in
                Label(kind.title, systemImage: kind.systemImage)
                    .tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)
        .pinesSegmentedPickerChrome()
    }
}

enum ArtifactsConfirmation: Identifiable {
    case deleteArtifactRecord(ProviderArtifactRecord)
    case deleteProviderFile(ProviderFileRecord)
    case deleteProviderCache(ProviderCacheRecord)
    case cancelBatch(ProviderBatchRecord)
    case cancelResearch(ProviderResearchRunRecord)
    case cancelMediaOperation(ProviderArtifactRecord)

    var id: String {
        switch self {
        case .deleteArtifactRecord(let artifact): "delete-artifact-\(artifact.id)"
        case .deleteProviderFile(let file): "delete-file-\(file.id)"
        case .deleteProviderCache(let cache): "delete-cache-\(cache.id)"
        case .cancelBatch(let batch): "cancel-batch-\(batch.id)"
        case .cancelResearch(let run): "cancel-research-\(run.id)"
        case .cancelMediaOperation(let artifact): "cancel-media-\(artifact.id)"
        }
    }

    var title: String {
        switch self {
        case .deleteArtifactRecord: "Delete local artifact record?"
        case .deleteProviderFile: "Delete cloud copy?"
        case .deleteProviderCache: "Delete cloud context?"
        case .cancelBatch: "Cancel background process?"
        case .cancelResearch: "Cancel research run?"
        case .cancelMediaOperation: "Cancel media operation?"
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
        case .cancelMediaOperation(let artifact):
            "This asks \(artifact.providerKind.pinesLifecycleTitle) to stop \(artifact.fileName ?? artifact.kind.readableArtifactKind). Any output already completed may remain available from the provider."
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
