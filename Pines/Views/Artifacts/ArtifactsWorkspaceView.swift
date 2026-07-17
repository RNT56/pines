import SwiftUI
import PinesCore

struct ArtifactsWorkspaceView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openPinesProviderSettings) private var openProviderSettings
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var query = ArtifactsLibraryQuery()
    @State private var presentedSheet: ArtifactSheet?
    @State private var pendingConfirmation: ArtifactsConfirmation?

    private var artifactProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.artifactProviders
    }

    var body: some View {
        NavigationStack {
            ArtifactsLibraryView(
                query: $query,
                pendingConfirmation: $pendingConfirmation,
                openArtifact: { id in present(.artifact(id)) },
                createArtifact: { kind in present(.create(kind: kind, referenceArtifactID: nil)) },
                openResearch: { threadID in present(.research(threadID: threadID)) },
                remix: { artifactID in present(.create(kind: .image, referenceArtifactID: artifactID)) },
                openProviderSettings: showProviderSettings
            )
            .navigationTitle("Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query.text, prompt: "Search artifacts")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    filterMenu
                    newArtifactMenu
                }
            }
            .task {
                await appModel.refreshProviderLifecycleState(services: services)
            }
            .pinesNavigationChrome()
        }
        .sheet(item: $presentedSheet) { sheet in
            NavigationStack {
                sheetContent(sheet)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                presentedSheet = nil
                            }
                            .accessibilityIdentifier("pines.artifacts.sheet.close")
                        }
                }
                .pinesNavigationChrome()
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
            .presentationBackground(theme.colors.sheetBackground)
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
        .accessibilityIdentifier("pines.screen.artifacts")
    }

    private var filterMenu: some View {
        Menu {
            Section("Type") {
                ForEach(ArtifactsAssetKindFilter.allCases) { category in
                    Button {
                        query.category = category
                    } label: {
                        Label(category.title, systemImage: query.category == category ? "checkmark" : category.systemImage)
                    }
                }
            }

            Section("Provider") {
                Button {
                    query.providerScope = .all
                } label: {
                    Label("All providers", systemImage: query.providerScope == .all ? "checkmark" : "cloud")
                }
                ForEach(artifactProviders) { provider in
                    Button {
                        query.providerScope = .provider(provider.id)
                    } label: {
                        Label(
                            provider.displayName,
                            systemImage: query.providerScope == .provider(provider.id) ? "checkmark" : "cloud"
                        )
                    }
                }
            }

            Section("Sort") {
                ForEach(ArtifactsSort.allCases) { sort in
                    Button {
                        query.sort = sort
                    } label: {
                        Label(sort.title, systemImage: query.sort == sort ? "checkmark" : "arrow.up.arrow.down")
                    }
                }
            }

            if query.hasActiveFilters {
                Divider()
                Button("Reset filters", systemImage: "arrow.counterclockwise") {
                    query.resetFilters()
                }
            }
        } label: {
            Image(systemName: query.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(query.hasActiveFilters ? "Artifact filters, active" : "Artifact filters")
        .accessibilityIdentifier("pines.artifacts.filter")
    }

    private var newArtifactMenu: some View {
        Menu {
            Section("Create") {
                Button("Image", systemImage: "photo") {
                    present(.create(kind: .image, referenceArtifactID: nil))
                }
                .accessibilityIdentifier("pines.artifacts.new.image")

                Button("Video", systemImage: "film") {
                    present(.create(kind: .video, referenceArtifactID: nil))
                }
                .accessibilityIdentifier("pines.artifacts.new.video")

                Button("Speech", systemImage: "waveform") {
                    present(.create(kind: .speech, referenceArtifactID: nil))
                }
                .accessibilityIdentifier("pines.artifacts.new.speech")
            }

            Button("Research", systemImage: "doc.text.magnifyingglass") {
                present(.research(threadID: nil))
            }
            .accessibilityIdentifier("pines.artifacts.new.research")
        } label: {
            Label("New", systemImage: "plus")
        }
        .accessibilityLabel("New artifact")
        .accessibilityIdentifier("pines.artifacts.new")
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ArtifactSheet) -> some View {
        switch sheet {
        case .artifact(let id):
            if let artifact = providerState.providerArtifacts.first(where: { $0.id == id }) {
                ArtifactQuickLookView(
                    artifact: artifact,
                    pendingConfirmation: $pendingConfirmation,
                    open: handle
                )
            } else {
                ArtifactsMissingRecordView()
            }
        case .create(let kind, let referenceArtifactID):
            ArtifactCreateView(
                initialKind: kind,
                referenceArtifactID: referenceArtifactID,
                pendingConfirmation: $pendingConfirmation,
                open: handle
            )
        case .research(let threadID):
            ArtifactResearchView(
                initialThreadID: threadID,
                pendingConfirmation: $pendingConfirmation,
                open: handle
            )
        }
    }

    private func handle(_ route: ArtifactsRoute) {
        switch route {
        case .artifact(let id):
            present(.artifact(id))
        case .create(let kind, let referenceArtifactID):
            present(.create(kind: kind, referenceArtifactID: referenceArtifactID))
        case .research(let threadID):
            present(.research(threadID: threadID))
        case .providerSetup:
            showProviderSettings()
        }
    }

    private func present(_ sheet: ArtifactSheet) {
        guard presentedSheet != nil else {
            presentedSheet = sheet
            return
        }
        presentedSheet = nil
        Task { @MainActor in
            await Task.yield()
            presentedSheet = sheet
        }
    }

    private func showProviderSettings() {
        presentedSheet = nil
        Task { @MainActor in
            await Task.yield()
            openProviderSettings()
        }
    }

    @ViewBuilder
    private func confirmationActions(_ confirmation: ArtifactsConfirmation) -> some View {
        switch confirmation {
        case .deleteArtifactRecord(let artifact):
            Button("Remove from Pines", role: .destructive) {
                Task { await deleteArtifactRecord(artifact) }
            }
        case .cancelResearch(let run):
            Button("Cancel research", role: .destructive) {
                Task { await cancelResearch(run) }
            }
        case .cancelMediaOperation(let artifact):
            Button("Cancel operation", role: .destructive) {
                Task { await cancelMediaOperation(artifact) }
            }
        }
        Button("Keep", role: .cancel) {}
    }

    @MainActor
    private func deleteArtifactRecord(_ artifact: ProviderArtifactRecord) async {
        do {
            try await appModel.deleteProviderArtifactRecord(id: artifact.id, services: services)
            pendingConfirmation = nil
            if presentedSheet == .artifact(artifact.id) { presentedSheet = nil }
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
            pendingConfirmation = nil
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
            pendingConfirmation = nil
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private enum ArtifactSheet: Hashable, Identifiable {
    case artifact(String)
    case create(kind: ArtifactsMediaKind, referenceArtifactID: String?)
    case research(threadID: String?)

    var id: String {
        switch self {
        case .artifact(let id):
            "artifact-\(id)"
        case .create(let kind, let referenceArtifactID):
            "create-\(kind.rawValue)-\(referenceArtifactID ?? "new")"
        case .research(let threadID):
            "research-\(threadID ?? "new")"
        }
    }
}

private struct ArtifactsLibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @Binding var query: ArtifactsLibraryQuery
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    @State private var libraryIndex = ArtifactLibraryIndex.empty
    @State private var libraryProjection = ArtifactLibraryProjection.empty
    @State private var sourceDerivationTask: Task<Void, Never>?
    @State private var queryProjectionTask: Task<Void, Never>?
    @State private var sourceGeneration = 0
    @State private var queryGeneration = 0
    @State private var hasBuiltLibraryIndex = false
    @State private var galleryToFirstThumbnailInterval: PinesPerformanceInterval?
    @State private var hasMeasuredFirstGalleryThumbnail = false
    let openArtifact: (String) -> Void
    let createArtifact: (ArtifactsMediaKind) -> Void
    let openResearch: (String?) -> Void
    let remix: (String) -> Void
    let openProviderSettings: () -> Void

    private var providers: [CloudProviderConfiguration] {
        settingsState.cloudProviders.artifactProviders
    }

    private var activeResearchThreads: [ArtifactsResearchThread] {
        libraryProjection.activeResearchThreads
    }

    private var activeItems: [ArtifactLibraryItem] {
        libraryProjection.activeItems
    }

    private var completedItems: [ArtifactLibraryItem] {
        libraryProjection.completedItems
    }

    private var activityOperations: [ArtifactActivityPollOperation] {
        libraryIndex.activityOperations
    }

    private var activitySignature: [String] {
        ArtifactActivityPollOperation.stableSignature(for: activityOperations)
    }

    private var usesAccessibilityList: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var galleryColumns: [GridItem] {
        if horizontalSizeClass == .compact {
            return [
                GridItem(.flexible(), spacing: theme.spacing.medium),
                GridItem(.flexible(), spacing: theme.spacing.medium),
            ]
        }
        return [
            GridItem(.adaptive(minimum: 205, maximum: 270), spacing: theme.spacing.large),
        ]
    }

    private var activeCount: Int {
        activeItems.count + activeResearchThreads.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                activityStrip
                collectionHeader
                libraryContent
            }
            .padding(.horizontal, horizontalSizeClass == .compact ? theme.spacing.medium : theme.spacing.large)
            .padding(.top, theme.spacing.small)
            .padding(.bottom, theme.spacing.xlarge)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .pinesExpressiveScrollHaptics()
        .refreshable {
            await appModel.refreshProviderLifecycleState(services: services)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = providerState.providerLifecycleError {
                PinesGlobalErrorBanner(
                    message: error,
                    dismiss: { providerState.providerLifecycleError = nil }
                )
                .padding(.horizontal, theme.spacing.large)
                .padding(.top, theme.spacing.xsmall)
                .background(theme.colors.appBackground)
            }
        }
        .task(id: activitySignature) {
            await monitorActivity(activityOperations)
        }
        .task {
            scheduleSourceDerivation()
        }
        .onChange(of: providerState.snapshot.artifactLibraryRevision) { _, _ in
            scheduleSourceDerivation()
        }
        .onChange(of: settingsState.cloudProviders) { _, _ in
            scheduleSourceDerivation()
        }
        .onChange(of: query) { previous, current in
            scheduleQueryProjection(debounced: previous.text != current.text)
        }
        .onDisappear {
            sourceDerivationTask?.cancel()
            queryProjectionTask?.cancel()
            finishGalleryToFirstThumbnailMeasurement()
        }
        .pinesAppBackground()
        .accessibilityIdentifier("pines.artifacts.library")
    }

    @ViewBuilder
    private var activityStrip: some View {
        if activeCount > 0 {
            Menu {
                Section("Running now") {
                    ForEach(activeResearchThreads) { thread in
                        Button {
                            openResearch(thread.id)
                        } label: {
                            Label(
                                "\(thread.title) — \(thread.statusText)",
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }
                    }

                    ForEach(activeItems) { item in
                        Button {
                            openArtifact(item.id)
                        } label: {
                            Label(
                                "\(item.title) — \(item.operationState.title)",
                                systemImage: item.contentKind.systemImage
                            )
                        }
                    }
                }
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.spacing.small) {
                        activityLead
                        Spacer(minLength: theme.spacing.small)
                        Text(activitySummary)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.tertiaryText)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        activityLead
                        Text(activitySummary)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .pinesBareButtonStyle()
            .padding(.vertical, theme.spacing.xsmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { PinesDivider() }
            .accessibilityLabel("\(activeCount) running. \(activitySummary)")
            .accessibilityIdentifier("pines.artifacts.activity")
        }
    }

    private var activityLead: some View {
        HStack(spacing: theme.spacing.xsmall) {
            PinesStatusIndicator(color: theme.colors.accent, isActive: true, size: 8)
                .frame(width: 16, height: 16)
            Text("\(activeCount) running")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var activitySummary: String {
        if let thread = activeResearchThreads.first {
            return "\(thread.title) · \(thread.statusText)"
        }
        if let item = activeItems.first {
            return "\(item.title) · \(item.operationState.title)"
        }
        return "Open running work"
    }

    private var collectionHeader: some View {
        HStack(alignment: .center, spacing: theme.spacing.xsmall) {
            Text(query.category == .all ? "All artifacts" : query.category.title)
                .font(theme.typography.headline)
                .foregroundStyle(theme.colors.primaryText)
            Text("\(completedItems.count)")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.tertiaryText)
                .monospacedDigit()
            Spacer(minLength: 0)

            if query.hasActiveFilters {
                Button("Clear") {
                    query.resetFilters()
                }
                .font(theme.typography.caption.weight(.semibold))
                .pinesBareButtonStyle()
                .foregroundStyle(theme.colors.accent)
                .accessibilityLabel("Clear artifact filters")
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if !hasBuiltLibraryIndex
            || (providerState.isRefreshingProviderLifecycle && libraryProjection.matchingItemCount == 0) {
            ArtifactsLoadingState()
        } else if completedItems.isEmpty {
            ArtifactsLibraryEmptyState(
                hasProviders: !providers.isEmpty,
                hasQuery: !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || query.hasActiveFilters,
                clearFilters: {
                    query.text = ""
                    query.resetFilters()
                },
                create: { createArtifact(.image) },
                research: { openResearch(nil) },
                connectProvider: openProviderSettings
            )
        } else if usesAccessibilityList {
            LazyVStack(spacing: 0) {
                ForEach(completedItems) { item in
                    ArtifactLibraryRow(
                        item: item,
                        onThumbnailReady: {
                            if item.id == completedItems.first?.id {
                                finishGalleryToFirstThumbnailMeasurement()
                            }
                        },
                        open: { openArtifact(item.id) },
                        importToVault: { Task { await importToVault(item.artifact) } },
                        remix: { remix(item.id) },
                        remove: { pendingConfirmation = .deleteArtifactRecord(item.artifact) }
                    )
                }
            }
        } else {
            LazyVGrid(
                columns: galleryColumns,
                alignment: .leading,
                spacing: theme.spacing.large
            ) {
                ForEach(completedItems) { item in
                    ArtifactGalleryTile(
                        item: item,
                        onThumbnailReady: {
                            if item.id == completedItems.first?.id {
                                finishGalleryToFirstThumbnailMeasurement()
                            }
                        },
                        open: { openArtifact(item.id) },
                        importToVault: { Task { await importToVault(item.artifact) } },
                        remix: { remix(item.id) },
                        remove: { pendingConfirmation = .deleteArtifactRecord(item.artifact) }
                    )
                }
            }
        }
    }

    @MainActor
    private func scheduleSourceDerivation() {
        sourceGeneration &+= 1
        let generation = sourceGeneration
        let artifacts = providerState.providerArtifacts
        let researchRuns = providerState.providerResearchRuns
        let currentProviders = providers

        sourceDerivationTask?.cancel()
        queryProjectionTask?.cancel()
        sourceDerivationTask = Task { @MainActor in
            let interval = services.runtimeMetrics.begin(.artifactLibraryDerive)
            let nextIndex = await ArtifactLibraryDerivationEngine.shared.buildIndex(
                artifacts: artifacts,
                providers: currentProviders,
                researchRuns: researchRuns
            )
            services.runtimeMetrics.end(interval)
            guard !Task.isCancelled, generation == sourceGeneration else { return }

            libraryIndex = nextIndex
            hasBuiltLibraryIndex = true
            scheduleQueryProjection(debounced: false)
        }
    }

    @MainActor
    private func scheduleQueryProjection(debounced: Bool) {
        queryGeneration &+= 1
        let generation = queryGeneration
        let currentIndex = libraryIndex
        let currentQuery = query

        queryProjectionTask?.cancel()
        queryProjectionTask = Task { @MainActor in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(160))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            let nextProjection = await ArtifactLibraryDerivationEngine.shared.project(
                index: currentIndex,
                query: currentQuery
            )
            guard !Task.isCancelled, generation == queryGeneration else { return }
            if !hasMeasuredFirstGalleryThumbnail,
               galleryToFirstThumbnailInterval == nil,
               !nextProjection.completedItems.isEmpty {
                galleryToFirstThumbnailInterval = services.runtimeMetrics.begin(.galleryToFirstThumbnail)
            }
            libraryProjection = nextProjection
        }
    }

    @MainActor
    private func finishGalleryToFirstThumbnailMeasurement() {
        guard let interval = galleryToFirstThumbnailInterval else { return }
        galleryToFirstThumbnailInterval = nil
        hasMeasuredFirstGalleryThumbnail = true
        services.runtimeMetrics.end(interval)
    }

    @MainActor
    private func importToVault(_ artifact: ProviderArtifactRecord) async {
        do {
            _ = try await appModel.importProviderArtifactToVault(id: artifact.id, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func monitorActivity(_ operations: [ArtifactActivityPollOperation]) async {
        guard !PinesUITestLaunchConfiguration.isEnabled,
              !PinesUITestLaunchConfiguration.isSimulatorPerformanceTesting
        else { return }
        let scheduler = ArtifactActivityPollingScheduler()
        await scheduler.run(operations: operations) { operation in
            switch operation.kind {
            case .openAIVideo:
                let artifact = try await appModel.refreshOpenAIVideoArtifact(
                    id: operation.remoteID,
                    providerID: operation.providerID,
                    services: services
                )
                return artifact.artifactOperationState.isActive ? .active : .terminal
            case .geminiMedia:
                let artifact = try await appModel.refreshGeminiGeneratedMediaOperation(
                    id: operation.remoteID,
                    providerID: operation.providerID,
                    services: services
                )
                return artifact.artifactOperationState.isActive ? .active : .terminal
            case .openAIResearch:
                let run = try await appModel.refreshOpenAIDeepResearchRun(
                    id: operation.remoteID,
                    providerID: operation.providerID,
                    services: services
                )
                return run.status.providerIsTerminal ? .terminal : .active
            case .geminiResearch:
                let run = try await appModel.refreshGeminiDeepResearchRun(
                    id: operation.remoteID,
                    providerID: operation.providerID,
                    services: services
                )
                return run.status.providerIsTerminal ? .terminal : .active
            }
        }
    }
}

private struct ArtifactLibraryRow: View {
    @Environment(\.pinesTheme) private var theme
    let item: ArtifactLibraryItem
    let onThumbnailReady: () -> Void
    let open: () -> Void
    let importToVault: () -> Void
    let remix: () -> Void
    let remove: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: theme.spacing.medium) {
                Button(action: open) {
                    HStack(alignment: .top, spacing: theme.spacing.medium) {
                        ArtifactsArtifactThumbnail(
                            artifact: item.artifact,
                            onReady: onThumbnailReady
                        )
                            .frame(width: 104, height: 78)
                        labels
                        Spacer(minLength: theme.spacing.small)
                    }
                    .contentShape(Rectangle())
                }
                .pinesBareButtonStyle()
                .accessibilityLabel(rowAccessibilityLabel)
                overflowMenu
            }

            VStack(alignment: .leading, spacing: theme.spacing.small) {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        ArtifactsArtifactThumbnail(
                            artifact: item.artifact,
                            onReady: onThumbnailReady
                        )
                            .frame(maxWidth: .infinity)
                            .frame(height: 132)
                        labels
                    }
                }
                .pinesBareButtonStyle()
                .accessibilityLabel(rowAccessibilityLabel)
                HStack {
                    Spacer(minLength: 0)
                    overflowMenu
                }
            }
        }
        .padding(.vertical, theme.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            PinesDivider()
        }
    }

    private var rowAccessibilityLabel: String {
        "\(item.title), \(item.contentKind.title), \(item.providerName)"
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            Text(item.title)
                .font(theme.typography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let excerpt = item.excerpt, item.contentKind == .report {
                Text(excerpt)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(3)
            }

            Text("\(item.contentKind.title) · \(item.providerName) · \(RelativeDateTimeFormatter.shortLabel(for: item.createdAt))")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var overflowMenu: some View {
        ArtifactOverflowMenu(
            item: item,
            open: open,
            importToVault: importToVault,
            remix: remix,
            remove: remove
        )
    }
}

private struct ArtifactGalleryTile: View {
    @Environment(\.pinesTheme) private var theme
    let item: ArtifactLibraryItem
    let onThumbnailReady: () -> Void
    let open: () -> Void
    let importToVault: () -> Void
    let remix: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    thumbnail

                    Text(item.title)
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 38, alignment: .topLeading)
                }
                .contentShape(Rectangle())
            }
            .pinesBareButtonStyle()
            .accessibilityLabel("Open \(item.title), \(item.contentKind.title), \(item.providerName)")

            HStack(alignment: .center, spacing: theme.spacing.xsmall) {
                Image(systemName: item.contentKind.systemImage)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
                    .accessibilityHidden(true)
                Text("\(item.providerName) · \(RelativeDateTimeFormatter.shortLabel(for: item.createdAt))")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
                ArtifactOverflowMenu(
                    item: item,
                    open: open,
                    importToVault: importToVault,
                    remix: remix,
                    remove: remove
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var thumbnail: some View {
        ArtifactsArtifactThumbnail(
            artifact: item.artifact,
            onReady: onThumbnailReady
        )
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipped()
    }
}

private struct ArtifactOverflowMenu: View {
    let item: ArtifactLibraryItem
    let open: () -> Void
    let importToVault: () -> Void
    let remix: () -> Void
    let remove: () -> Void

    var body: some View {
        Menu {
            Button(action: open) {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button(action: importToVault) {
                Label("Import to Vault", systemImage: "square.and.arrow.down")
            }
            .disabled(!item.canImportToVault)
            if item.contentKind == .image {
                Button(action: remix) {
                    Label("Remix image", systemImage: "wand.and.stars")
                }
                .disabled(!item.canRemix)
            }
            Divider()
            Button(role: .destructive, action: remove) {
                Label("Remove from Pines", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .pinesBareButtonStyle()
        .accessibilityLabel("More actions for \(item.title)")
    }
}

private struct ArtifactsLoadingState: View {
    @Environment(\.pinesTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            ProgressView()
                .pinesProgressTint()
            Text("Refreshing artifacts")
                .font(theme.typography.callout.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private struct ArtifactsLibraryEmptyState: View {
    @Environment(\.pinesTheme) private var theme
    let hasProviders: Bool
    let hasQuery: Bool
    let clearFilters: () -> Void
    let create: () -> Void
    let research: () -> Void
    let connectProvider: () -> Void

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: hasQuery ? "magnifyingglass" : "rectangle.stack")
                .font(theme.typography.title.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 68, height: 68)
                .background(theme.colors.accentSoft, in: Circle())

            VStack(spacing: theme.spacing.xsmall) {
                Text(title)
                    .font(theme.typography.title.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasQuery {
                Button("Clear filters", action: clearFilters)
                    .pinesButtonStyle(.primary)
            } else if !hasProviders {
                Button(action: connectProvider) {
                    Label("Connect a provider", systemImage: "cloud")
                }
                .pinesButtonStyle(.primary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.spacing.small) {
                        createButton
                        researchButton
                    }
                    VStack(spacing: theme.spacing.small) {
                        createButton
                        researchButton
                    }
                }
            }
        }
        .padding(.vertical, theme.spacing.xlarge)
        .padding(.horizontal, theme.spacing.large)
        .frame(maxWidth: 620, minHeight: 320)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if hasQuery { return "No matching artifacts" }
        if !hasProviders { return "Connect a provider" }
        return "Your library is ready"
    }

    private var detail: String {
        if hasQuery { return "Try another search or clear the active filters." }
        if !hasProviders { return "Add an OpenAI or Gemini provider to create media and run Deep Research." }
        return "Created images, video, speech, and research reports will appear here."
    }

    private var createButton: some View {
        Button(action: create) {
            Label("Create", systemImage: "sparkles")
        }
        .pinesButtonStyle(.primary)
    }

    private var researchButton: some View {
        Button(action: research) {
            Label("Research", systemImage: "doc.text.magnifyingglass")
        }
        .pinesButtonStyle(.secondary)
    }
}

private struct ArtifactQuickLookView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let artifact: ProviderArtifactRecord
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    let open: (ArtifactsRoute) -> Void

    private var item: ArtifactLibraryItem {
        ArtifactLibraryItem(
            artifact: artifact,
            providers: settingsState.cloudProviders,
            researchRuns: providerState.providerResearchRuns
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                if usesWideLayout {
                    HStack(alignment: .top, spacing: theme.spacing.xlarge) {
                        preview
                            .frame(maxWidth: 560)
                        detailColumn
                            .frame(maxWidth: 380, alignment: .topLeading)
                    }
                } else {
                    preview
                    detailColumn
                }

                if item.contentKind == .report, let text = reportText {
                    reportBody(text)
                }
            }
            .padding(horizontalSizeClass == .compact ? theme.spacing.medium : theme.spacing.large)
            .padding(.bottom, theme.spacing.xlarge)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.contentKind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if item.isActive {
                        Button("Refresh status", systemImage: "arrow.clockwise") {
                            Task { await appModel.refreshProviderLifecycleState(services: services) }
                        }
                        if canCancelOperation {
                            Button("Cancel operation", systemImage: "xmark", role: .destructive) {
                                pendingConfirmation = .cancelMediaOperation(artifact)
                            }
                        }
                        Divider()
                    }
                    if artifact.galleryURL != nil {
                        Button("Open original", systemImage: "arrow.up.forward.app") {
                            if let url = artifact.galleryURL { openURL(url) }
                        }
                    }
                    Button("Import to Vault", systemImage: "square.and.arrow.down") {
                        Task { await importToVault() }
                    }
                    .disabled(!item.canImportToVault)
                    if item.contentKind == .image {
                        Button("Remix image", systemImage: "wand.and.stars") {
                            open(.create(kind: .image, referenceArtifactID: artifact.id))
                        }
                        .disabled(!item.canRemix)
                    }
                    Divider()
                    Button("Remove from Pines", systemImage: "trash", role: .destructive) {
                        pendingConfirmation = .deleteArtifactRecord(artifact)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Artifact actions")
            }
        }
        .pinesAppBackground()
        .pinesNavigationChrome()
        .accessibilityIdentifier("pines.artifacts.detail")
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass != .compact && !dynamicTypeSize.isAccessibilitySize
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: theme.spacing.large) {
            titleBlock
            primaryActions
            provenance
        }
    }

    @ViewBuilder
    private var preview: some View {
        if item.contentKind == .report {
            ArtifactsArtifactThumbnail(artifact: artifact)
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
        } else {
            ArtifactsArtifactPreviewSurface(
                artifact: artifact,
                maxHeight: usesWideLayout ? 420 : 300
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(item.contentKind == .image ? 4.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text(item.title)
                .font(theme.typography.title.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.spacing.small) {
                    metadataLabels
                }
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    metadataLabels
                }
            }
            .font(theme.typography.caption)
            .foregroundStyle(theme.colors.secondaryText)
        }
    }

    private var primaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.small) {
                primaryActionButtons
            }
            VStack(spacing: theme.spacing.small) {
                primaryActionButtons
            }
        }
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(item.providerName, systemImage: "cloud")
        Text(RelativeDateTimeFormatter.shortLabel(for: item.createdAt))
        Label(item.availability.title, systemImage: item.availability.systemImage)
    }

    @ViewBuilder
    private var primaryActionButtons: some View {
        if artifact.galleryURL != nil {
            Button {
                if let url = artifact.galleryURL { openURL(url) }
            } label: {
                Label("Open original", systemImage: "arrow.up.forward.app")
            }
            .pinesButtonStyle(.primary)
        }

        Button {
            Task { await importToVault() }
        } label: {
            Label("Import to Vault", systemImage: "square.and.arrow.down")
        }
        .disabled(!item.canImportToVault)
        .pinesButtonStyle(artifact.galleryURL == nil ? .primary : .secondary)

        if item.contentKind == .image {
            Button {
                open(.create(kind: .image, referenceArtifactID: artifact.id))
            } label: {
                Label("Remix", systemImage: "wand.and.stars")
            }
            .disabled(!item.canRemix)
            .pinesButtonStyle(.secondary)
        }
    }

    private var reportText: String? {
        if let text = artifact.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return ArtifactResearchReportText.text(from: artifact)
    }

    private var canCancelOperation: Bool {
        let kind = artifact.kind.lowercased()
        return item.isActive && (kind == "video_job" || kind == "media_operation")
    }

    private func reportBody(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesDivider()
            Text("Report")
                .font(theme.typography.title.weight(.semibold))
            MarkdownMessageView(messageID: UUID(), content: text, isStreaming: false)
        }
        .textSelection(.enabled)
    }

    private var provenance: some View {
        VStack(spacing: theme.spacing.small) {
            PinesDivider()
            DisclosureGroup {
                VStack(spacing: theme.spacing.small) {
                    ArtifactMetadataRow(title: "Provider", value: item.providerName, systemImage: "cloud")
                    ArtifactMetadataRow(title: "Kind", value: artifact.kind.readableArtifactKind, systemImage: "tag")
                    ArtifactMetadataRow(title: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    ArtifactMetadataRow(title: "Availability", value: item.availability.title, systemImage: item.availability.systemImage)
                    ArtifactMetadataRow(title: "Size", value: artifact.byteCount.map(providerByteCountLabel) ?? "Unknown", systemImage: "internaldrive")
                    if let id = artifact.providerFileID ?? artifact.responseID {
                        ArtifactMetadataRow(title: "Provider ID", value: id, systemImage: "number")
                    }
                }
                .padding(.top, theme.spacing.small)
            } label: {
                Label("Provenance", systemImage: "info.circle")
                    .font(theme.typography.headline)
            }
            .tint(theme.colors.accent)
            .foregroundStyle(theme.colors.primaryText)
        }
    }

    @MainActor
    private func importToVault() async {
        do {
            _ = try await appModel.importProviderArtifactToVault(id: artifact.id, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ArtifactMetadataRow: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 20)
            Text(title)
                .font(theme.typography.callout.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
            Spacer(minLength: theme.spacing.small)
            Text(value)
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct ArtifactsMissingRecordView: View {
    var body: some View {
        PinesEmptyState(
            title: "Artifact unavailable",
            detail: "The local record changed. Return to the library and refresh.",
            systemImage: "arrow.triangle.2.circlepath"
        )
        .padding()
        .navigationTitle("Artifact")
    }
}

private struct ArtifactCreateView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let initialKind: ArtifactsMediaKind
    let referenceArtifactID: String?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    let open: (ArtifactsRoute) -> Void
    @State private var mediaKind: ArtifactsMediaKind
    @State private var providerID: ProviderID?
    @State private var modelID = ""
    @State private var prompt = ""
    @State private var imageQuality = "auto"
    @State private var imageSize = "auto"
    @State private var imageFormat = "png"
    @State private var speechVoice = "alloy"
    @State private var refreshAfterVideoCreate = true
    @State private var isCreating = false
    @State private var showsSettings = false
    @State private var newArtifactIDs = [String]()
    @FocusState private var promptFocused: Bool

    init(
        initialKind: ArtifactsMediaKind,
        referenceArtifactID: String?,
        pendingConfirmation: Binding<ArtifactsConfirmation?>,
        open: @escaping (ArtifactsRoute) -> Void
    ) {
        self.initialKind = initialKind
        self.referenceArtifactID = referenceArtifactID
        _pendingConfirmation = pendingConfirmation
        self.open = open
        _mediaKind = State(initialValue: referenceArtifactID == nil ? initialKind : .image)
    }

    private var providers: [CloudProviderConfiguration] {
        settingsState.cloudProviders.artifactProviders
    }

    private var provider: CloudProviderConfiguration? {
        providerID.flatMap { id in providers.first(where: { $0.id == id }) }
    }

    private var modelOptions: [ArtifactsMediaModelOption] {
        ArtifactsWorkspaceDeriver.mediaModelOptions(
            provider: provider,
            kind: mediaKind,
            capabilities: providerState.providerModelCapabilities
        )
    }

    private var selectedReference: ProviderArtifactRecord? {
        referenceArtifactID.flatMap { id in providerState.providerArtifacts.first(where: { $0.id == id }) }
    }

    private var outputs: [ProviderArtifactRecord] {
        newArtifactIDs.compactMap { id in providerState.providerArtifacts.first(where: { $0.id == id }) }
    }

    private var canCreate: Bool {
        provider != nil
            && !modelID.isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCreating
    }

    private var selectedModelTitle: String {
        modelOptions.first(where: { $0.id == modelID })?.title ?? "Choose a model"
    }

    private var imageOutputSummary: String {
        "\(imageSizeTitle) · \(imageQualityTitle)"
    }

    private var imageSizeTitle: String {
        switch imageSize {
        case "1024x1024": "Square"
        case "1536x1024": "Landscape"
        case "1024x1536": "Portrait"
        default: "Auto size"
        }
    }

    private var imageSizeSystemImage: String {
        switch imageSize {
        case "1024x1024": "square"
        case "1536x1024": "rectangle"
        case "1024x1536": "rectangle.portrait"
        default: "aspectratio"
        }
    }

    private var imageQualityTitle: String {
        imageQuality == "auto" ? "Auto quality" : imageQuality.capitalized
    }

    private var imageCanvasAspectRatio: CGFloat {
        switch imageSize {
        case "1024x1024": 1
        case "1536x1024": 1.5
        case "1024x1536": 2.0 / 3.0
        default: 4.0 / 3.0
        }
    }

    private var studioOutputColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 240 : 260, maximum: 360), spacing: theme.spacing.medium)]
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.colors.appBackground
                .ignoresSafeArea()

            creationContent
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if mediaKind == .image, !providers.isEmpty {
                imagePromptDock
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                creationMenu
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = providerState.providerLifecycleError {
                PinesGlobalErrorBanner(message: error) {
                    providerState.providerLifecycleError = nil
                }
                .padding(.horizontal, theme.spacing.large)
                .background(theme.colors.appBackground)
            }
        }
        .sheet(isPresented: $showsSettings) {
            createSettings
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.colors.sheetBackground)
        }
        .onAppear {
            if providerID == nil { providerID = providers.first?.id }
            normalizeSelectedModel()
        }
        .onChange(of: providerID) { _, _ in normalizeSelectedModel() }
        .onChange(of: mediaKind) { _, _ in normalizeSelectedModel() }
        .pinesNavigationChrome()
    }

    @ViewBuilder
    private var creationContent: some View {
        if providers.isEmpty {
            noProviderState
                .padding(theme.spacing.large)
        } else if mediaKind == .image {
            imageStudio
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    configurationSummary
                    composer
                    if !outputs.isEmpty {
                        outputSection
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var imageStudio: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                studioConfigurationBar

                if let selectedReference {
                    referenceCanvas(selectedReference)
                }

                if outputs.isEmpty {
                    blankImageCanvas
                } else {
                    outputSection
                }
            }
            .padding(.horizontal, horizontalSizeClass == .compact ? theme.spacing.medium : theme.spacing.large)
            .padding(.top, theme.spacing.small)
            .padding(.bottom, theme.spacing.large)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("pines.artifacts.image-studio")
    }

    private var navigationTitle: String {
        if selectedReference != nil { return "Remix Image" }
        return mediaKind == .image ? "Image Studio" : "New \(mediaKind.title)"
    }

    private var noProviderState: some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: "cloud.badge.plus")
                .font(theme.typography.title.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
            Text("Connect a provider")
                .font(theme.typography.title)
            Text("OpenAI and Gemini can create artifacts. Add one in Settings, then return here.")
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                open(.providerSetup)
            } label: {
                Label("Provider setup", systemImage: "cloud")
            }
            .pinesButtonStyle(.primary)
            .accessibilityIdentifier("pines.artifacts.provider-setup")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var creationMenu: some View {
        Menu {
            if selectedReference == nil {
                Section("Output") {
                    ForEach(ArtifactsMediaKind.allCases) { kind in
                        Button {
                            mediaKind = kind
                        } label: {
                            Label(kind.title, systemImage: mediaKind == kind ? "checkmark" : kind.systemImage)
                        }
                    }
                }
            }

            Button("Provider & options", systemImage: "slider.horizontal.3") {
                showsSettings = true
            }
            .accessibilityIdentifier("pines.artifacts.create.configuration")
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("\(mediaKind.title) creation options")
        .accessibilityIdentifier("pines.artifacts.create.type")
    }

    private var studioConfigurationBar: some View {
        Button {
            showsSettings = true
        } label: {
            HStack(spacing: theme.spacing.small) {
                studioEngineLabel
                Spacer(minLength: theme.spacing.small)
                Image(systemName: "chevron.right")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
            }
            .padding(.vertical, theme.spacing.xsmall)
            .contentShape(Rectangle())
        }
        .pinesBareButtonStyle()
        .overlay(alignment: .bottom) { PinesDivider() }
        .accessibilityLabel("Image settings, \(provider?.displayName ?? "choose provider"), \(selectedModelTitle), \(imageOutputSummary)")
        .accessibilityIdentifier("pines.artifacts.image-studio.configuration")
    }

    private var studioEngineLabel: some View {
        HStack(spacing: theme.spacing.small) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(theme.colors.accent)
                .frame(width: 20, height: 20)
            Text(provider?.displayName ?? "Choose provider")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("·")
                .foregroundStyle(theme.colors.tertiaryText)
            Text(selectedModelTitle)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
    }

    private var blankImageCanvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.colors.accentSoft,
                            theme.colors.secondaryBackground,
                            theme.colors.infoSoft,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
                .fill(theme.colors.accent.opacity(0.08))
                .frame(width: 190, height: 140)
                .rotationEffect(.degrees(-12))
                .offset(x: -80, y: 35)
                .accessibilityHidden(true)

            Circle()
                .fill(theme.colors.info.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 120, y: -70)
                .accessibilityHidden(true)

            VStack(spacing: theme.spacing.medium) {
                Image(systemName: "photo.badge.plus")
                    .font(theme.typography.title.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 64, height: 64)
                    .background(theme.colors.chromeBackground, in: Circle())

                VStack(spacing: theme.spacing.xsmall) {
                    Text("Your next image starts with a sentence")
                        .font(theme.typography.title.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .multilineTextAlignment(.center)
                    Text("Describe the subject, composition, light, and feeling in the prompt below.")
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 440)
            }
            .padding(theme.spacing.large)
        }
        .aspectRatio(imageCanvasAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: horizontalSizeClass == .compact ? 440 : 500)
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
                .strokeBorder(theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pines.artifacts.image-studio.canvas")
    }

    private func referenceCanvas(_ artifact: ProviderArtifactRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack {
                Label("Reference", systemImage: "photo.on.rectangle")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                Spacer(minLength: theme.spacing.small)
                Text(artifact.artifactDisplayTitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }

            ArtifactsArtifactThumbnail(artifact: artifact)
                .frame(maxWidth: .infinity)
                .aspectRatio(imageCanvasAspectRatio, contentMode: .fit)
                .frame(maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous))
        }
        .accessibilityIdentifier("pines.artifacts.image-studio.reference")
    }

    private var imagePromptDock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .focused($promptFocused)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.vertical, theme.spacing.xsmall)
                .submitLabel(.go)
                .onSubmit {
                    guard canCreate else { return }
                    Task { await createMedia() }
                }
                .accessibilityIdentifier("pines.artifacts.create.prompt")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.spacing.xsmall) {
                    imageSizeMenu
                    imageQualityMenu
                    Spacer(minLength: theme.spacing.small)
                    imageGenerateButton(fillWidth: false, showsLabel: false)
                }

                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    HStack(spacing: theme.spacing.xsmall) {
                        imageSizeMenu
                        imageQualityMenu
                        Spacer(minLength: 0)
                    }
                    imageGenerateButton(fillWidth: true, showsLabel: true)
                }
            }
        }
        .pinesSurface(.chrome, padding: theme.spacing.medium)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalSizeClass == .compact ? theme.spacing.medium : theme.spacing.large)
        .padding(.bottom, theme.spacing.xsmall)
    }

    private var imageSizeMenu: some View {
        Menu {
            Button("Automatic", systemImage: imageSize == "auto" ? "checkmark" : "aspectratio") { imageSize = "auto" }
            Button("Square", systemImage: imageSize == "1024x1024" ? "checkmark" : "square") { imageSize = "1024x1024" }
            Button("Landscape", systemImage: imageSize == "1536x1024" ? "checkmark" : "rectangle") { imageSize = "1536x1024" }
            Button("Portrait", systemImage: imageSize == "1024x1536" ? "checkmark" : "rectangle.portrait") { imageSize = "1024x1536" }
        } label: {
            Label(imageSizeTitle, systemImage: imageSizeSystemImage)
        }
        .pinesButtonStyle(.ghost)
        .accessibilityLabel("Image size, \(imageSizeTitle)")
        .accessibilityIdentifier("pines.artifacts.image-studio.size")
    }

    private var imageQualityMenu: some View {
        Menu {
            ForEach(["auto", "low", "medium", "high"], id: \.self) { value in
                Button {
                    imageQuality = value
                } label: {
                    Label(value == "auto" ? "Automatic" : value.capitalized, systemImage: imageQuality == value ? "checkmark" : "circle")
                }
            }
        } label: {
            Label(imageQualityTitle, systemImage: "dial.medium")
        }
        .pinesButtonStyle(.ghost)
        .accessibilityLabel("Image quality, \(imageQualityTitle)")
        .accessibilityIdentifier("pines.artifacts.image-studio.quality")
    }

    private func imageGenerateButton(fillWidth: Bool, showsLabel: Bool) -> some View {
        Button {
            Task { await createMedia() }
        } label: {
            if showsLabel {
                Label(isCreating ? "Creating…" : "Generate", systemImage: isCreating ? "hourglass" : "sparkles")
            } else {
                Image(systemName: isCreating ? "hourglass" : "sparkles")
                    .frame(width: 20, height: 20)
            }
        }
        .disabled(!canCreate)
        .pinesButtonStyle(canCreate ? .primary : .secondary, fillWidth: fillWidth)
        .accessibilityLabel(isCreating ? "Creating image" : "Generate image")
        .accessibilityIdentifier("pines.artifacts.create.submit")
    }

    private var configurationSummary: some View {
        Button {
            showsSettings = true
        } label: {
            HStack(spacing: theme.spacing.small) {
                Image(systemName: "cloud")
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 20, height: 20)
                Text(provider?.displayName ?? "Choose provider")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Text("·")
                    .foregroundStyle(theme.colors.tertiaryText)
                Text(selectedModelTitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: theme.spacing.small)
                Image(systemName: "chevron.right")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
            }
            .padding(.vertical, theme.spacing.xsmall)
            .contentShape(Rectangle())
        }
        .pinesBareButtonStyle()
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { PinesDivider() }
        .accessibilityIdentifier("pines.artifacts.create.configuration")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                Text(promptTitle)
                    .font(theme.typography.title.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($promptFocused)
                    .pinesFieldChrome()
                    .accessibilityIdentifier("pines.artifacts.create.prompt")
            }

            createButton
        }
    }

    private var createButton: some View {
        Button {
            Task { await createMedia() }
        } label: {
            Label(isCreating ? "Creating…" : createButtonTitle, systemImage: isCreating ? "hourglass" : "sparkles")
        }
        .disabled(!canCreate)
        .pinesButtonStyle(.primary, fillWidth: true)
        .accessibilityIdentifier("pines.artifacts.create.submit")
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("This session")
                    .font(theme.typography.title)
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: theme.spacing.small)
                Text("\(outputs.count) \(outputs.count == 1 ? "image" : "images")")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .monospacedDigit()
            }

            if mediaKind == .image {
                LazyVGrid(columns: studioOutputColumns, alignment: .leading, spacing: theme.spacing.large) {
                    ForEach(outputs) { artifact in
                        imageSessionOutput(artifact)
                    }
                }
            } else {
                ForEach(outputs) { artifact in
                    mediaSessionOutput(artifact)
                }
            }
        }
    }

    private func imageSessionOutput(_ artifact: ProviderArtifactRecord) -> some View {
        let item = ArtifactLibraryItem(
            artifact: artifact,
            providers: providers,
            researchRuns: providerState.providerResearchRuns
        )
        return Button {
            open(.artifact(artifact.id))
        } label: {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                ZStack(alignment: .topTrailing) {
                    ArtifactsArtifactThumbnail(artifact: artifact)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))

                    if item.isActive {
                        ProgressView()
                            .pinesProgressTint()
                            .padding(theme.spacing.small)
                            .background(theme.colors.chromeBackground, in: Circle())
                            .padding(theme.spacing.small)
                    }
                }

                Text(item.title)
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.operationState.title)
                    .font(theme.typography.caption.weight(.medium))
                    .foregroundStyle(item.operationState.tone.color(in: theme))
            }
            .contentShape(Rectangle())
        }
        .pinesBareButtonStyle()
        .contextMenu { sessionOutputActions(artifact: artifact, item: item) }
        .accessibilityLabel("Open \(item.title), \(item.operationState.title)")
    }

    private func mediaSessionOutput(_ artifact: ProviderArtifactRecord) -> some View {
        let item = ArtifactLibraryItem(
            artifact: artifact,
            providers: providers,
            researchRuns: providerState.providerResearchRuns
        )
        return Button {
            open(.artifact(artifact.id))
        } label: {
            HStack(spacing: theme.spacing.medium) {
                ArtifactsArtifactThumbnail(artifact: artifact)
                    .frame(width: 88, height: 68)
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(item.title)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(2)
                    Text(item.operationState.title)
                        .font(theme.typography.caption)
                        .foregroundStyle(item.operationState.tone.color(in: theme))
                }
                Spacer()
                if item.isActive {
                    ProgressView()
                        .pinesProgressTint()
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(theme.colors.tertiaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .pinesBareButtonStyle()
        .contextMenu { sessionOutputActions(artifact: artifact, item: item) }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    @ViewBuilder
    private func sessionOutputActions(artifact: ProviderArtifactRecord, item: ArtifactLibraryItem) -> some View {
        if item.isActive {
            Button(role: .destructive) {
                pendingConfirmation = .cancelMediaOperation(artifact)
            } label: {
                Label("Cancel operation", systemImage: "xmark")
            }
        }
        Button(role: .destructive) {
            pendingConfirmation = .deleteArtifactRecord(artifact)
        } label: {
            Label("Remove from Pines", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var createSettings: some View {
        if mediaKind == .image {
            imageStudioSettings
        } else {
            mediaCreationSettings
        }
    }

    private var imageStudioSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                        Text("Shape the output")
                            .font(theme.typography.title.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .accessibilityIdentifier("pines.artifacts.image-studio.settings")
                        Text("Choose the engine, canvas, and finish. The prompt stays in the studio.")
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Engine", systemImage: "wand.and.stars")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.colors.primaryText)
                        VStack(spacing: 0) {
                            HStack(spacing: theme.spacing.small) {
                                Label("Provider", systemImage: "cloud")
                                    .foregroundStyle(theme.colors.secondaryText)
                                Spacer(minLength: theme.spacing.small)
                                Picker("Provider", selection: $providerID) {
                                    ForEach(providers) { provider in
                                        Text(provider.displayName).tag(Optional(provider.id))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(theme.spacing.medium)

                            PinesDivider()

                            HStack(spacing: theme.spacing.small) {
                                Label("Model", systemImage: "cpu")
                                    .foregroundStyle(theme.colors.secondaryText)
                                Spacer(minLength: theme.spacing.small)
                                Picker("Model", selection: $modelID) {
                                    ForEach(modelOptions) { option in
                                        Text(option.title).tag(option.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(theme.spacing.medium)
                        }
                        .pinesSurface(.panel, padding: 0)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Canvas", systemImage: "aspectratio")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.colors.primaryText)
                        LazyVGrid(columns: studioSettingsColumns, spacing: theme.spacing.small) {
                            studioOptionButton("Automatic", detail: "Provider default", systemImage: "aspectratio", isSelected: imageSize == "auto") {
                                imageSize = "auto"
                            }
                            studioOptionButton("Square", detail: "1:1", systemImage: "square", isSelected: imageSize == "1024x1024") {
                                imageSize = "1024x1024"
                            }
                            studioOptionButton("Landscape", detail: "3:2", systemImage: "rectangle", isSelected: imageSize == "1536x1024") {
                                imageSize = "1536x1024"
                            }
                            studioOptionButton("Portrait", detail: "2:3", systemImage: "rectangle.portrait", isSelected: imageSize == "1024x1536") {
                                imageSize = "1024x1536"
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Finish", systemImage: "dial.medium")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.colors.primaryText)
                        LazyVGrid(columns: studioSettingsColumns, spacing: theme.spacing.small) {
                            studioOptionButton("Automatic", detail: "Provider choice", systemImage: "wand.and.stars", isSelected: imageQuality == "auto") {
                                imageQuality = "auto"
                            }
                            studioOptionButton("Low", detail: "Faster", systemImage: "hare", isSelected: imageQuality == "low") {
                                imageQuality = "low"
                            }
                            studioOptionButton("Medium", detail: "Balanced", systemImage: "circle.lefthalf.filled", isSelected: imageQuality == "medium") {
                                imageQuality = "medium"
                            }
                            studioOptionButton("High", detail: "Maximum detail", systemImage: "sparkles", isSelected: imageQuality == "high") {
                                imageQuality = "high"
                            }
                        }

                        Picker("Format", selection: $imageFormat) {
                            Text("PNG").tag("png")
                            Text("JPEG").tag("jpeg")
                            Text("WebP").tag("webp")
                        }
                        .pickerStyle(.segmented)
                        .pinesSegmentedPickerChrome()
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Image Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
            .pinesAppBackground()
            .pinesNavigationChrome()
        }
    }

    private var studioSettingsColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func studioOptionButton(
        _ title: String,
        detail: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(title)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text(detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinesBareButtonStyle()
        .pinesSurface(isSelected ? .selected : .inset, padding: theme.spacing.small)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var mediaCreationSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                        Text(mediaKind == .speech ? "Shape the voice" : "Configure the render")
                            .font(theme.typography.title.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .accessibilityIdentifier("pines.artifacts.media.settings")
                        Text(mediaKind == .speech
                             ? "Choose the engine and voice. Your script stays in the creation workspace."
                             : "Choose the engine and decide whether Pines should keep watching for the finished render.")
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Engine", systemImage: "cpu")
                            .font(theme.typography.headline)
                            .foregroundStyle(theme.colors.primaryText)
                        VStack(spacing: 0) {
                            HStack(spacing: theme.spacing.small) {
                                Label("Provider", systemImage: "cloud")
                                    .foregroundStyle(theme.colors.secondaryText)
                                Spacer(minLength: theme.spacing.small)
                                Picker("Provider", selection: $providerID) {
                                    ForEach(providers) { provider in
                                        Text(provider.displayName).tag(Optional(provider.id))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(theme.spacing.medium)

                            PinesDivider()

                            HStack(spacing: theme.spacing.small) {
                                Label("Model", systemImage: "brain")
                                    .foregroundStyle(theme.colors.secondaryText)
                                Spacer(minLength: theme.spacing.small)
                                Picker("Model", selection: $modelID) {
                                    ForEach(modelOptions) { option in
                                        Text(option.title).tag(option.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(theme.spacing.medium)
                        }
                        .pinesSurface(.panel, padding: 0)
                    }

                    if mediaKind == .speech {
                        VStack(alignment: .leading, spacing: theme.spacing.small) {
                            Label("Voice", systemImage: "waveform")
                                .font(theme.typography.headline)
                                .foregroundStyle(theme.colors.primaryText)
                            LazyVGrid(columns: studioSettingsColumns, spacing: theme.spacing.small) {
                                ForEach(Self.speechVoices, id: \.self) { voice in
                                    studioOptionButton(
                                        voice.capitalized,
                                        detail: speechVoiceDetail(voice),
                                        systemImage: "waveform",
                                        isSelected: speechVoice == voice
                                    ) {
                                        speechVoice = voice
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: theme.spacing.small) {
                            Label("Delivery", systemImage: "film.stack")
                                .font(theme.typography.headline)
                                .foregroundStyle(theme.colors.primaryText)
                            Toggle(isOn: $refreshAfterVideoCreate) {
                                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                    Text("Watch for the finished render")
                                        .font(theme.typography.callout.weight(.semibold))
                                        .foregroundStyle(theme.colors.primaryText)
                                    Text("Pines refreshes the provider job and adds the completed video to this session.")
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(theme.colors.accent)
                            .pinesSurface(.panel, padding: theme.spacing.medium)
                        }
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("\(mediaKind.title) Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
            .pinesAppBackground()
            .pinesNavigationChrome()
        }
    }

    private static let speechVoices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    private func speechVoiceDetail(_ voice: String) -> String {
        switch voice {
        case "alloy": "Balanced"
        case "ash": "Clear"
        case "coral": "Warm"
        case "echo": "Resonant"
        case "fable": "Expressive"
        case "nova": "Bright"
        case "onyx": "Deep"
        case "sage": "Calm"
        case "shimmer": "Airy"
        default: "Provider voice"
        }
    }

    private var promptTitle: String {
        switch mediaKind {
        case .image: selectedReference == nil ? "Describe the image" : "Describe the changes"
        case .video: "Describe the video"
        case .speech: "Enter the text to speak"
        }
    }

    private var promptPlaceholder: String {
        switch mediaKind {
        case .image: "Subject, composition, lighting, and style"
        case .video: "Scene, motion, camera, and mood"
        case .speech: "What should the voice say?"
        }
    }

    private var createButtonTitle: String {
        selectedReference == nil ? "Generate \(mediaKind.title.lowercased())" : "Create remix"
    }

    @MainActor
    private func createMedia() async {
        guard let provider else { return }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let model = ModelID(rawValue: modelID)
            let created: [ProviderArtifactRecord]
            switch provider.kind {
            case .openAI:
                switch mediaKind {
                case .video:
                    let artifact = try await appModel.createOpenAIVideoArtifact(
                        OpenAIVideoArtifactRequest(prompt: trimmedPrompt, model: model.rawValue),
                        providerID: provider.id,
                        services: services
                    )
                    created = [artifact]
                    if refreshAfterVideoCreate {
                        _ = try? await appModel.refreshOpenAIVideoArtifact(
                            id: artifact.providerFileID ?? artifact.id,
                            providerID: provider.id,
                            services: services
                        )
                    }
                case .speech:
                    created = [try await appModel.createOpenAISpeechArtifact(
                        OpenAISpeechArtifactRequest(model: model.rawValue, input: trimmedPrompt, voice: speechVoice),
                        providerID: provider.id,
                        services: services
                    )]
                case .image:
                    if let selectedReference {
                        created = try await appModel.remixOpenAIImageArtifact(
                            providerID: provider.id,
                            modelID: model,
                            prompt: trimmedPrompt,
                            reference: selectedReference,
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
                if mediaKind == .image, let selectedReference {
                    created = try await appModel.remixGeminiImageArtifact(
                        providerID: provider.id,
                        modelID: model,
                        prompt: trimmedPrompt,
                        reference: selectedReference,
                        services: services
                    )
                } else {
                    created = try await appModel.createGeminiGeneratedMedia(
                        providerID: provider.id,
                        modelID: model,
                        prompt: trimmedPrompt,
                        kind: mediaKind.rawValue,
                        services: services
                    )
                }
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) media creation is not supported here.")
            }
            let annotated = try await appModel.annotateCreatedProviderArtifacts(
                created,
                prompt: trimmedPrompt,
                modelID: model,
                requestedKind: mediaKind.rawValue,
                referenceArtifactID: selectedReference?.id,
                services: services
            )
            for id in annotated.map(\.id).reversed() where !newArtifactIDs.contains(id) {
                newArtifactIDs.insert(id, at: 0)
            }
            prompt = ""
            promptFocused = true
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func openAIImageFields() -> [String: JSONValue] {
        var fields = [String: JSONValue]()
        if imageQuality != "auto" { fields["quality"] = .string(imageQuality) }
        if imageSize != "auto" { fields["size"] = .string(imageSize) }
        if imageFormat != "png" { fields["output_format"] = .string(imageFormat) }
        return fields
    }

    private func normalizeSelectedModel() {
        if providerID == nil { providerID = providers.first?.id }
        guard !modelOptions.isEmpty else {
            modelID = ""
            return
        }
        if !modelOptions.contains(where: { $0.id == modelID }) {
            modelID = modelOptions[0].id
        }
    }
}

private struct ArtifactResearchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let initialThreadID: String?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    let open: (ArtifactsRoute) -> Void
    @State private var selectedThreadID: String?
    @State private var providerID: ProviderID?
    @State private var modelID = ""
    @State private var prompt = ""
    @State private var followUpPrompt = ""
    @State private var depth: OpenAIDeepResearchDepth = .standard
    @State private var reportFormat: OpenAIDeepResearchReportFormat = .memo
    @State private var usesProviderFiles = false
    @State private var isStarting = false
    @State private var showsSettings = false
    @State private var clarificationDraft: ArtifactsResearchClarificationDraft?
    @State private var clarificationAnswers = [String: String]()
    @FocusState private var composerFocused: Bool

    init(
        initialThreadID: String?,
        pendingConfirmation: Binding<ArtifactsConfirmation?>,
        open: @escaping (ArtifactsRoute) -> Void
    ) {
        self.initialThreadID = initialThreadID
        _selectedThreadID = State(initialValue: initialThreadID)
        _pendingConfirmation = pendingConfirmation
        self.open = open
    }

    private var providers: [CloudProviderConfiguration] {
        settingsState.cloudProviders.artifactProviders
    }

    private var provider: CloudProviderConfiguration? {
        providerID.flatMap { id in providers.first(where: { $0.id == id }) }
    }

    private var modelOptions: [ArtifactsResearchModelOption] {
        ArtifactsWorkspaceDeriver.researchModelOptions(
            provider: provider,
            capabilities: providerState.providerModelCapabilities
        )
    }

    private var threads: [ArtifactsResearchThread] {
        ArtifactsResearchThread.threads(from: providerState.providerResearchRuns)
    }

    private var selectedThread: ArtifactsResearchThread? {
        selectedThreadID.flatMap { id in threads.first(where: { $0.id == id }) }
    }

    private var activeRuns: [ProviderResearchRunRecord] {
        selectedThread?.runs.filter { !$0.status.providerIsTerminal } ?? []
    }

    private var composerBinding: Binding<String> {
        Binding(
            get: { selectedThread == nil ? prompt : followUpPrompt },
            set: { value in
                if selectedThread == nil { prompt = value } else { followUpPrompt = value }
            }
        )
    }

    private var sendDisabled: Bool {
        let text = selectedThread == nil ? prompt : followUpPrompt
        return provider == nil
            || modelID.isEmpty
            || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isStarting
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = providerState.providerLifecycleError {
                PinesGlobalErrorBanner(message: error) {
                    providerState.providerLifecycleError = nil
                }
                .padding(.horizontal, theme.spacing.large)
                .padding(.top, theme.spacing.xsmall)
            }

            conversation
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !providers.isEmpty {
                researchComposer
            }
        }
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                researchThreadMenu

                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Research setup")
                .accessibilityIdentifier("pines.artifacts.research.settings")
            }
        }
        .sheet(isPresented: $showsSettings) {
            researchSettings
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.colors.sheetBackground)
        }
        .sheet(item: $clarificationDraft) { draft in
            ArtifactsResearchClarificationView(
                draft: draft,
                answers: $clarificationAnswers,
                start: { providerPrompt in
                    clarificationDraft = nil
                    Task { await startRun(originalPrompt: draft.originalPrompt, providerPrompt: providerPrompt) }
                },
                cancel: { clarificationDraft = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.colors.sheetBackground)
        }
        .onAppear(perform: configureInitialSelection)
        .onChange(of: providerID) { _, _ in normalizeSelectedModel() }
        .pinesAppBackground()
        .pinesNavigationChrome()
    }

    private var researchThreadMenu: some View {
        Menu {
            Button {
                startNewThread()
            } label: {
                Label("New research", systemImage: "square.and.pencil")
            }

            if !threads.isEmpty {
                Divider()
                Section("Recent research") {
                    ForEach(threads) { thread in
                        Button {
                            selectThread(thread)
                        } label: {
                            Label(
                                thread.title,
                                systemImage: selectedThreadID == thread.id ? "checkmark" : "doc.text"
                            )
                        }
                    }
                }
            }

            if !activeRuns.isEmpty {
                Divider()
                Button("Refresh progress", systemImage: "arrow.clockwise") {
                    Task { await refreshActiveRuns() }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel(selectedThread == nil ? "Research history" : "Current research, \(selectedThread?.title ?? "")")
        .accessibilityIdentifier("pines.artifacts.research.thread-menu")
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.large) {
                    if providers.isEmpty {
                        researchEmptyState(
                            title: "Connect a research provider",
                            detail: "Add OpenAI or Gemini in Settings before starting Deep Research.",
                            actionTitle: "Provider setup",
                            actionIdentifier: "pines.artifacts.provider-setup",
                            action: { open(.providerSetup) }
                        )
                    } else if let selectedThread {
                        ForEach(selectedThread.runs) { run in
                            ArtifactsResearchRunView(
                                run: run,
                                report: finalReport(for: run),
                                refresh: { Task { await refreshRun(run) } },
                                cancel: { pendingConfirmation = .cancelResearch(run) },
                                openReport: { artifact in open(.artifact(artifact.id)) }
                            )
                            .id(run.id)
                        }
                    } else {
                        researchEmptyState(
                            title: "Turn a question into a sourced brief",
                            detail: "Pines searches, tracks evidence, and keeps every follow-up with the final report.",
                            actionTitle: nil,
                            actionIdentifier: nil,
                            action: {}
                        )
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: selectedThread?.latestRun.id) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : theme.motion.fast) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private func researchEmptyState(
        title: String,
        detail: String,
        actionTitle: String?,
        actionIdentifier: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: theme.spacing.large) {
            ZStack {
                Circle()
                    .fill(theme.colors.accentSoft)
                    .frame(width: 82, height: 82)
                Circle()
                    .strokeBorder(theme.colors.accent.opacity(0.18), lineWidth: theme.stroke.hairline)
                    .frame(width: 66, height: 66)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(theme.typography.title.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
            }

            VStack(spacing: theme.spacing.small) {
                Text(title)
                    .font(theme.typography.title.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle {
                Button(actionTitle, action: action)
                    .pinesButtonStyle(.secondary)
                    .accessibilityIdentifier(actionIdentifier ?? "pines.artifacts.research.empty-action")
            } else {
                researchStarterPrompts
            }
        }
        .padding(.vertical, theme.spacing.large)
        .frame(maxWidth: 640, minHeight: 340)
        .frame(maxWidth: .infinity)
    }

    private var researchStarterPrompts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.small) {
                researchStarterButton("Compare options", systemImage: "arrow.left.arrow.right", prompt: "Compare the leading options for ")
                researchStarterButton("Map a market", systemImage: "map", prompt: "Map the current market for ")
                researchStarterButton("Verify a claim", systemImage: "checkmark.seal", prompt: "Verify the evidence behind the claim that ")
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func researchStarterButton(_ title: String, systemImage: String, prompt seed: String) -> some View {
        Button {
            prompt = seed
            composerFocused = true
        } label: {
            Label(title, systemImage: systemImage)
        }
        .pinesButtonStyle(.secondary)
    }

    private var researchComposer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            TextField(selectedThread == nil ? "Ask a research question" : "Ask a follow-up", text: composerBinding, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.vertical, theme.spacing.xsmall)
                .submitLabel(.send)
                .onSubmit {
                    guard !sendDisabled else { return }
                    Task { await commitComposer() }
                }
                .accessibilityIdentifier(selectedThread == nil ? "pines.artifacts.research.prompt" : "pines.artifacts.research.follow-up")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.spacing.xsmall) {
                    researchSourceMenu
                    researchDepthMenu
                    Spacer(minLength: theme.spacing.small)
                    researchSendButton(fillWidth: false, showsLabel: false)
                }

                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    HStack(spacing: theme.spacing.xsmall) {
                        researchSourceMenu
                        researchDepthMenu
                        Spacer(minLength: 0)
                    }
                    researchSendButton(fillWidth: true, showsLabel: true)
                }
            }
        }
        .pinesSurface(.chrome, padding: theme.spacing.medium)
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalSizeClass == .compact ? theme.spacing.medium : theme.spacing.large)
        .padding(.bottom, theme.spacing.xsmall)
    }

    private var researchSourceMenu: some View {
        Menu {
            Button {
                usesProviderFiles = false
            } label: {
                Label("Web only", systemImage: usesProviderFiles ? "globe" : "checkmark")
            }
            Button {
                usesProviderFiles = true
            } label: {
                Label("Web + provider files", systemImage: usesProviderFiles ? "checkmark" : "folder.badge.plus")
            }
        } label: {
            Label(usesProviderFiles ? "Web + files" : "Web", systemImage: usesProviderFiles ? "folder.badge.plus" : "globe")
        }
        .pinesButtonStyle(.ghost)
        .accessibilityLabel("Research sources, \(usesProviderFiles ? "web and provider files" : "web only")")
    }

    private var researchDepthMenu: some View {
        Menu {
            ForEach(OpenAIDeepResearchDepth.allCases, id: \.self) { value in
                Button {
                    depth = value
                } label: {
                    Label(
                        value.rawValue.readableArtifactKind,
                        systemImage: depth == value ? "checkmark" : "gauge.with.dots.needle.33percent"
                    )
                }
            }
        } label: {
            Label(depth.rawValue.readableArtifactKind, systemImage: "gauge.with.dots.needle.33percent")
        }
        .pinesButtonStyle(.ghost)
        .accessibilityLabel("Research depth, \(depth.rawValue.readableArtifactKind)")
    }

    private func researchSendButton(fillWidth: Bool, showsLabel: Bool) -> some View {
        Button {
            Task { await commitComposer() }
        } label: {
            if showsLabel {
                Label(
                    isStarting ? "Starting…" : (selectedThread == nil ? "Research" : "Send"),
                    systemImage: isStarting ? "hourglass" : "arrow.up"
                )
            } else {
                Image(systemName: isStarting ? "hourglass" : "arrow.up")
                    .frame(width: 20, height: 20)
            }
        }
        .disabled(sendDisabled)
        .pinesButtonStyle(sendDisabled ? .secondary : .primary, fillWidth: fillWidth)
        .accessibilityLabel(selectedThread == nil ? "Start research" : "Send follow-up")
        .accessibilityIdentifier("pines.artifacts.research.send")
    }

    private var researchSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                        Text("Define the research brief")
                            .font(theme.typography.title.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .accessibilityIdentifier("pines.artifacts.research.settings-sheet")
                        Text("Choose where Pines looks and how deeply it should investigate. You can refine the question in the composer.")
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Engine", systemImage: "cpu")
                            .font(theme.typography.headline)
                        VStack(spacing: 0) {
                            HStack(spacing: theme.spacing.small) {
                                Label("Provider", systemImage: "cloud")
                                    .foregroundStyle(theme.colors.secondaryText)
                                Spacer(minLength: theme.spacing.small)
                                Picker("Provider", selection: $providerID) {
                                    ForEach(providers) { provider in
                                        Text(provider.displayName).tag(Optional(provider.id))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(theme.spacing.medium)

                            PinesDivider()

                            HStack(spacing: theme.spacing.small) {
                                Label("Model", systemImage: "brain")
                                    .foregroundStyle(theme.colors.secondaryText)
                                Spacer(minLength: theme.spacing.small)
                                Picker("Model", selection: $modelID) {
                                    ForEach(modelOptions) { option in
                                        Text(option.title).tag(option.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(theme.spacing.medium)
                        }
                        .pinesSurface(.panel, padding: 0)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Sources", systemImage: "globe")
                            .font(theme.typography.headline)
                        LazyVGrid(columns: researchSettingsColumns, spacing: theme.spacing.small) {
                            researchSettingsChoice(
                                "Web only",
                                detail: "Public web sources",
                                systemImage: "globe",
                                isSelected: !usesProviderFiles
                            ) {
                                usesProviderFiles = false
                            }
                            researchSettingsChoice(
                                "Web + files",
                                detail: "Include provider-hosted context",
                                systemImage: "folder.badge.plus",
                                isSelected: usesProviderFiles
                            ) {
                                usesProviderFiles = true
                            }
                        }
                        Text(usesProviderFiles
                             ? "Research may use files and vector stores already hosted with this provider, in addition to the web."
                             : "Research uses the web only. Provider-hosted files are excluded.")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Depth", systemImage: "gauge.with.dots.needle.33percent")
                            .font(theme.typography.headline)
                        LazyVGrid(columns: researchSettingsColumns, spacing: theme.spacing.small) {
                            researchSettingsChoice("Quick", detail: "Fast scan", systemImage: "hare", isSelected: depth == .quick) {
                                depth = .quick
                            }
                            researchSettingsChoice("Standard", detail: "Balanced brief", systemImage: "text.page", isSelected: depth == .standard) {
                                depth = .standard
                            }
                            researchSettingsChoice("Deep", detail: "Thorough investigation", systemImage: "binoculars", isSelected: depth == .deep) {
                                depth = .deep
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Deliverable", systemImage: "doc.richtext")
                            .font(theme.typography.headline)
                        HStack(spacing: theme.spacing.small) {
                            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                Text("Report format")
                                    .font(theme.typography.callout.weight(.semibold))
                                Text("Controls the structure of the saved artifact")
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.secondaryText)
                            }
                            Spacer(minLength: theme.spacing.small)
                            Picker("Report format", selection: $reportFormat) {
                                ForEach(OpenAIDeepResearchReportFormat.allCases, id: \.self) { value in
                                    Text(value.rawValue.readableArtifactKind).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .pinesSurface(.panel, padding: theme.spacing.medium)
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Research Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
            .pinesAppBackground()
            .pinesNavigationChrome()
        }
    }

    private var researchSettingsColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func researchSettingsChoice(
        _ title: String,
        detail: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(title)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text(detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinesBareButtonStyle()
        .pinesSurface(isSelected ? .selected : .inset, padding: theme.spacing.small)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    @MainActor
    private func commitComposer() async {
        if let selectedThread {
            await sendFollowUp(in: selectedThread)
            return
        }
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let questions = ArtifactsResearchClarifier.questions(for: question)
        if questions.isEmpty {
            await startRun(originalPrompt: question, providerPrompt: question)
        } else {
            clarificationAnswers = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, "") })
            clarificationDraft = ArtifactsResearchClarificationDraft(originalPrompt: question, questions: questions)
        }
    }

    @MainActor
    private func startRun(originalPrompt: String, providerPrompt: String) async {
        guard let provider else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let threadID = UUID().uuidString
            let model = ModelID(rawValue: modelID)
            let vectorStoreIDs = usesProviderFiles
                ? providerState.providerVectorStores.filter { $0.providerID == provider.id }.map(\.id)
                : []
            let providerFileIDs = usesProviderFiles
                ? providerState.providerFiles.filter { $0.providerID == provider.id }.map(\.id)
                : []
            let metadata = researchMetadata(threadID: threadID, userPrompt: originalPrompt)
            let run: ProviderResearchRunRecord
            switch provider.kind {
            case .openAI:
                let sourcePolicy: OpenAIDeepResearchSourcePolicy = usesProviderFiles
                    ? .webAndFiles(
                        vectorStoreIDs: vectorStoreIDs.map { OpenAIVectorStoreID(rawValue: $0) },
                        providerFileIDs: providerFileIDs.map { OpenAIProviderFileID(rawValue: $0) }
                    )
                    : .webOnly()
                run = try await appModel.startOpenAIDeepResearch(
                    OpenAIDeepResearchRequest(
                        providerID: provider.id,
                        modelID: model,
                        title: Self.derivedResearchTitle(from: originalPrompt),
                        prompt: providerPrompt,
                        depth: depth,
                        sourcePolicy: sourcePolicy,
                        reportFormat: reportFormat,
                        metadata: metadata
                    ),
                    services: services
                )
            case .gemini:
                run = try await appModel.startGeminiDeepResearch(
                    PinesProviderDeepResearchRequest(
                        providerID: provider.id,
                        providerKind: provider.kind,
                        modelID: model,
                        title: Self.derivedResearchTitle(from: originalPrompt),
                        prompt: providerPrompt,
                        depth: depth.rawValue,
                        reportFormat: reportFormat.rawValue,
                        vectorStoreIDs: vectorStoreIDs,
                        providerFileIDs: providerFileIDs,
                        metadata: metadata
                    ),
                    services: services
                )
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
            selectedThreadID = threadID
            providerID = run.providerID
            prompt = ""
            clarificationAnswers = [:]
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func sendFollowUp(in thread: ArtifactsResearchThread) async {
        let question = followUpPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let latest = thread.latestRun
            let metadata = researchMetadata(threadID: thread.id, userPrompt: question, followUpOf: latest.id)
            switch latest.providerKind {
            case .gemini:
                _ = try await appModel.startGeminiDeepResearchFollowUp(
                    prompt: question,
                    previousRunID: latest.id,
                    providerID: latest.providerID,
                    services: services,
                    title: "Follow-up: \(thread.title)",
                    metadata: metadata
                )
            case .openAI:
                let sourcePolicy: OpenAIDeepResearchSourcePolicy = usesProviderFiles
                    ? .webAndFiles(
                        vectorStoreIDs: providerState.providerVectorStores.filter { $0.providerID == latest.providerID }.map { OpenAIVectorStoreID(rawValue: $0.id) },
                        providerFileIDs: providerState.providerFiles.filter { $0.providerID == latest.providerID }.map { OpenAIProviderFileID(rawValue: $0.id) }
                    )
                    : .webOnly()
                _ = try await appModel.startOpenAIDeepResearch(
                    OpenAIDeepResearchRequest(
                        providerID: latest.providerID,
                        modelID: latest.modelID,
                        title: "Follow-up: \(thread.title)",
                        prompt: Self.followUpProviderPrompt(question: question, thread: thread, artifacts: providerState.providerArtifacts),
                        depth: depth,
                        sourcePolicy: sourcePolicy,
                        reportFormat: reportFormat,
                        metadata: metadata
                    ),
                    services: services
                )
            default:
                throw InferenceError.invalidRequest("\(latest.providerKind.pinesLifecycleTitle) Deep Research follow-up is not supported here.")
            }
            followUpPrompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func configureInitialSelection() {
        if let selectedThread {
            providerID = selectedThread.latestRun.providerID
            modelID = selectedThread.modelID.rawValue
            usesProviderFiles = selectedThread.latestRun.usesProviderFilesForResearch
        } else if providerID == nil {
            providerID = providers.first?.id
        }
        normalizeSelectedModel()
    }

    private func selectThread(_ thread: ArtifactsResearchThread) {
        selectedThreadID = thread.id
        providerID = thread.latestRun.providerID
        modelID = thread.modelID.rawValue
        depth = OpenAIDeepResearchDepth(rawValue: thread.latestRun.depth) ?? .standard
        reportFormat = OpenAIDeepResearchReportFormat(rawValue: thread.latestRun.reportFormat) ?? .memo
        usesProviderFiles = thread.latestRun.usesProviderFilesForResearch
    }

    private func startNewThread() {
        selectedThreadID = nil
        prompt = ""
        followUpPrompt = ""
        composerFocused = true
    }

    private func normalizeSelectedModel() {
        if providerID == nil { providerID = providers.first?.id }
        guard !modelOptions.isEmpty else {
            modelID = ""
            return
        }
        if !modelOptions.contains(where: { $0.id == modelID }) {
            modelID = modelOptions[0].id
        }
    }

    private func finalReport(for run: ProviderResearchRunRecord) -> ProviderArtifactRecord? {
        run.finalReportArtifactID.flatMap { id in providerState.providerArtifacts.first(where: { $0.id == id }) }
    }

    private func researchMetadata(threadID: String, userPrompt: String, followUpOf: String? = nil) -> [String: String] {
        var metadata = [
            "pines.research_thread_id": threadID,
            "pines.user_prompt": String(userPrompt.prefix(512)),
            "pines.research_ui": "artifact_library_v3",
            "pines.source_scope": usesProviderFiles ? "web_and_provider_files" : "web_only",
        ]
        if let followUpOf { metadata["pines.follow_up_of"] = followUpOf }
        return metadata
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
                break
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshActiveRuns() async {
        for run in activeRuns { await refreshRun(run) }
    }

    private static func derivedResearchTitle(from prompt: String) -> String {
        let line = prompt.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let clipped = String(line.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.last == "?" ? String(clipped.dropLast()) : (clipped.isEmpty ? "Deep Research" : clipped)
    }

    private static func followUpProviderPrompt(
        question: String,
        thread: ArtifactsResearchThread,
        artifacts: [ProviderArtifactRecord]
    ) -> String {
        let context = thread.runs.map { run in
            let report = run.finalReportArtifactID
                .flatMap { id in artifacts.first(where: { $0.id == id }) }
                .flatMap(ArtifactResearchReportText.text(from:))
                .map { String($0.prefix(2400)) }
                ?? run.lastError
                ?? run.status
            return "Prior prompt:\n\(run.researchDisplayPrompt)\n\nPrior output excerpt:\n\(report)"
        }.joined(separator: "\n\n---\n\n")
        return "Follow-up question:\n\(question)\n\nContinue the same research thread. Verify new claims and retain visible citations.\n\n\(context)"
    }
}

struct ArtifactsResearchThread: Identifiable, Hashable, Sendable {
    var id: String
    var runs: [ProviderResearchRunRecord]

    var latestRun: ProviderResearchRunRecord {
        runs.max(by: { $0.updatedAt < $1.updatedAt }) ?? runs[0]
    }

    var title: String { runs.first?.title ?? latestRun.title }
    var providerKind: CloudProviderKind { latestRun.providerKind }
    var modelID: ModelID { latestRun.modelID }
    var updatedAt: Date { latestRun.updatedAt }
    var sourceCount: Int {
        Set(runs.flatMap { ArtifactsWorkspaceDeriver.researchSources(for: $0).map { $0.url ?? $0.title } }).count
    }
    var statusText: String {
        if runs.contains(where: { !$0.status.providerIsTerminal }) { return "Researching" }
        if runs.contains(where: { $0.lastError != nil }) { return "Needs attention" }
        return "Ready"
    }

    static func threads(from runs: [ProviderResearchRunRecord]) -> [ArtifactsResearchThread] {
        Dictionary(grouping: runs) { run in
            run.providerMetadata["pines.research_thread_id"]
                ?? run.providerMetadata["pines.follow_up_of"]
                ?? run.id
        }
        .map { id, groupedRuns in
            ArtifactsResearchThread(
                id: id,
                runs: groupedRuns.sorted { $0.createdAt == $1.createdAt ? $0.updatedAt < $1.updatedAt : $0.createdAt < $1.createdAt }
            )
        }
        .sorted { lhs, rhs in
            let lhsActive = lhs.runs.contains(where: { !$0.status.providerIsTerminal })
            let rhsActive = rhs.runs.contains(where: { !$0.status.providerIsTerminal })
            return lhsActive == rhsActive ? lhs.updatedAt > rhs.updatedAt : lhsActive
        }
    }
}

private extension ProviderResearchRunRecord {
    var researchDisplayPrompt: String {
        if let userPrompt = providerMetadata["pines.user_prompt"], !userPrompt.isEmpty {
            return userPrompt
        }
        return prompt
    }

    var usesProviderFilesForResearch: Bool {
        providerMetadata["pines.source_scope"] == "web_and_provider_files"
            || providerMetadata["pines_research_source_scope"] == OpenAIDeepResearchSourceScope.webAndProviderFiles.rawValue
    }
}

private struct ArtifactsResearchRunView: View {
    @Environment(\.pinesTheme) private var theme
    let run: ProviderResearchRunRecord
    let report: ProviderArtifactRecord?
    let refresh: () -> Void
    let cancel: () -> Void
    let openReport: (ProviderArtifactRecord) -> Void

    private var events: [ArtifactsResearchTimelineEvent] {
        ArtifactsWorkspaceDeriver.researchTimeline(for: run)
    }

    private var sources: [ArtifactsResearchSource] {
        ArtifactsWorkspaceDeriver.researchSources(for: run)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.large) {
            PinesMessageBubble(role: .user, maxWidth: 640) {
                Text(run.researchDisplayPrompt)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(alignment: .top, spacing: theme.spacing.medium) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.colors.accentSoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    HStack(spacing: theme.spacing.small) {
                        PinesStatusIndicator(
                            color: run.status.providerCloudStatus.tone.color(in: theme),
                            isActive: !run.status.providerIsTerminal,
                            size: 9
                        )
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            Text(run.status.providerCloudStatus.title)
                                .font(theme.typography.callout.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                            Text("\(run.providerKind.pinesLifecycleTitle) · \(run.modelID.rawValue)")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Menu {
                            Button(action: refresh) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            if !run.status.providerIsTerminal {
                                Button(role: .destructive, action: cancel) {
                                    Label("Cancel research", systemImage: "xmark")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Research run actions")
                    }

                    if !run.status.providerIsTerminal {
                        ProgressView()
                            .pinesProgressTint()
                            .progressViewStyle(.linear)
                            .tint(theme.colors.accent)
                            .accessibilityLabel("Research in progress")
                    }

                    ArtifactsResearchActivityDisclosure(events: events, sources: sources)

                    if let report {
                        Button {
                            openReport(report)
                        } label: {
                            VStack(alignment: .leading, spacing: theme.spacing.small) {
                                HStack {
                                    Label("Final report", systemImage: "doc.richtext")
                                        .font(theme.typography.callout.weight(.semibold))
                                        .foregroundStyle(theme.colors.success)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(theme.colors.secondaryText)
                                }
                                Text(ArtifactResearchReportText.text(from: report) ?? "Open the saved report")
                                    .font(theme.typography.callout)
                                    .foregroundStyle(theme.colors.primaryText)
                                    .lineLimit(6)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(theme.spacing.medium)
                            .contentShape(Rectangle())
                        }
                        .pinesBareButtonStyle()
                        .background(
                            LinearGradient(
                                colors: [theme.colors.successSoft, theme.colors.cardBackground],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                                .strokeBorder(theme.colors.success.opacity(0.22), lineWidth: theme.stroke.hairline)
                        }
                    } else if run.status.providerIsTerminal {
                        Text(run.lastError ?? "The provider completed without a saved report artifact.")
                            .font(theme.typography.callout)
                            .foregroundStyle(run.lastError == nil ? theme.colors.secondaryText : theme.colors.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("pines.artifacts.research.run")
    }
}

private struct ArtifactsResearchActivityDisclosure: View {
    @Environment(\.pinesTheme) private var theme
    let events: [ArtifactsResearchTimelineEvent]
    let sources: [ArtifactsResearchSource]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                ForEach(events.prefix(8)) { event in
                    HStack(alignment: .top, spacing: theme.spacing.small) {
                        Image(systemName: event.systemImage)
                            .foregroundStyle(event.tone.color(in: theme))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            Text(event.title)
                                .font(theme.typography.caption.weight(.semibold))
                            Text(event.detail)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(3)
                        }
                    }
                }
                ForEach(sources.prefix(12)) { source in
                    if let url = source.url.flatMap(URL.init(string:)) {
                        Link(destination: url) { researchSourceRow(source) }
                    } else {
                        researchSourceRow(source)
                    }
                }
            }
            .padding(.top, theme.spacing.small)
        } label: {
            HStack {
                Label("Activity & sources", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(theme.typography.caption.weight(.semibold))
                Spacer()
                Text("\(sources.count)")
                    .font(theme.typography.caption.monospacedDigit())
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .tint(theme.colors.accent)
        .foregroundStyle(theme.colors.primaryText)
        .padding(.vertical, theme.spacing.xsmall)
        .overlay(alignment: .bottom) { PinesDivider() }
    }

    private func researchSourceRow(_ source: ArtifactsResearchSource) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            Image(systemName: source.systemImage)
                .foregroundStyle(source.tone.color(in: theme))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
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
        }
    }
}

enum ArtifactResearchReportText {
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
            if let outputText = object["output_text"]?.stringValue, !outputText.isEmpty { return outputText }
            if let type = object["type"]?.stringValue,
               ["output_text", "text", "message"].contains(type),
               let text = object["text"]?.stringValue,
               !text.isEmpty {
                return text
            }
            if let content = object["content"] { return userFacingText(from: content) }
            if let output = object["output"] { return userFacingText(from: output) }
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

private struct ArtifactsResearchClarificationQuestion: Identifiable, Hashable {
    let id: String
    let title: String
    let placeholder: String
}

private struct ArtifactsResearchClarificationDraft: Identifiable, Hashable {
    var id: String { originalPrompt }
    let originalPrompt: String
    let questions: [ArtifactsResearchClarificationQuestion]

    func providerPrompt(answers: [String: String]) -> String {
        let resolved = questions.compactMap { question -> String? in
            let answer = answers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return answer.isEmpty ? nil : "- \(question.title): \(answer)"
        }
        guard !resolved.isEmpty else {
            return "\(originalPrompt)\n\nProceed with reasonable assumptions and state important assumptions in the report."
        }
        return "\(originalPrompt)\n\nClarifications from the user:\n\(resolved.joined(separator: "\n"))"
    }
}

private enum ArtifactsResearchClarifier {
    static func questions(for prompt: String) -> [ArtifactsResearchClarificationQuestion] {
        let value = prompt.lowercased()
        var questions = [ArtifactsResearchClarificationQuestion]()
        if !containsAny(value, ["today", "current", "latest", "last ", "next ", "202", "month", "year", "q1", "q2", "q3", "q4"]) {
            questions.append(.init(id: "timeframe", title: "Timeframe", placeholder: "For example: current as of today, or last 12 months"))
        }
        if !containsAny(value, ["global", "market", "united states", "u.s.", "europe", "eu", "uk", "germany", "asia"]) {
            questions.append(.init(id: "scope", title: "Market or audience", placeholder: "For example: global enterprise buyers"))
        }
        if !containsAny(value, ["compare", "decision", "recommend", "rank", "risk", "price", "adoption", "quality"]) {
            questions.append(.init(id: "goal", title: "Decision goal", placeholder: "What should the report help you decide?"))
        }
        return Array(questions.prefix(3))
    }

    private static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.contains($0) }
    }
}

private struct ArtifactsResearchClarificationView: View {
    @Environment(\.pinesTheme) private var theme
    let draft: ArtifactsResearchClarificationDraft
    @Binding var answers: [String: String]
    let start: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        Label("Sharpen the question", systemImage: "scope")
                            .font(theme.typography.title.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                        Text("A little context helps Pines produce a more decisive, better sourced report. Every answer is optional.")
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                        Text("Research question")
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.accent)
                        Text(draft.originalPrompt)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .pinesSurface(.inset, padding: theme.spacing.medium)

                    ForEach(draft.questions) { question in
                        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                            Text(question.title)
                                .font(theme.typography.callout.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                            TextField(question.placeholder, text: Binding(
                                get: { answers[question.id] ?? "" },
                                set: { answers[question.id] = $0 }
                            ), axis: .vertical)
                            .lineLimit(1...4)
                                .pinesFieldChrome()
                        }
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.spacing.small) {
                        Button("Use assumptions") {
                            start(draft.providerPrompt(answers: [:]))
                        }
                        .pinesButtonStyle(.ghost)
                        Spacer(minLength: theme.spacing.small)
                        Button {
                            start(draft.providerPrompt(answers: answers))
                        } label: {
                            Label("Start research", systemImage: "arrow.up")
                        }
                        .pinesButtonStyle(.primary)
                    }

                    VStack(spacing: theme.spacing.small) {
                        Button {
                            start(draft.providerPrompt(answers: answers))
                        } label: {
                            Label("Start research", systemImage: "arrow.up")
                        }
                        .pinesButtonStyle(.primary, fillWidth: true)
                        Button("Use reasonable assumptions") {
                            start(draft.providerPrompt(answers: [:]))
                        }
                        .pinesButtonStyle(.ghost, fillWidth: true)
                    }
                }
                .pinesSurface(.chrome, padding: theme.spacing.medium)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, theme.spacing.medium)
                .padding(.bottom, theme.spacing.xsmall)
            }
            .navigationTitle("Shape the Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                    }
                }
            }
            .pinesAppBackground()
            .pinesNavigationChrome()
        }
    }
}

enum ArtifactsConfirmation: Identifiable {
    case deleteArtifactRecord(ProviderArtifactRecord)
    case cancelResearch(ProviderResearchRunRecord)
    case cancelMediaOperation(ProviderArtifactRecord)

    var id: String {
        switch self {
        case .deleteArtifactRecord(let artifact): "delete-artifact-\(artifact.id)"
        case .cancelResearch(let run): "cancel-research-\(run.id)"
        case .cancelMediaOperation(let artifact): "cancel-media-\(artifact.id)"
        }
    }

    var title: String {
        switch self {
        case .deleteArtifactRecord: "Remove local record?"
        case .cancelResearch: "Cancel research run?"
        case .cancelMediaOperation: "Cancel media operation?"
        }
    }

    var message: String {
        switch self {
        case .deleteArtifactRecord(let artifact):
            "This removes only Pines' local record for \(artifact.fileName ?? artifact.artifactDisplayTitle). It does not delete provider-hosted copies."
        case .cancelResearch(let run):
            "This asks \(run.providerKind.pinesLifecycleTitle) to cancel \(run.title). Saved artifacts remain available."
        case .cancelMediaOperation(let artifact):
            "This asks \(artifact.providerKind.pinesLifecycleTitle) to stop \(artifact.fileName ?? artifact.artifactDisplayTitle). Completed output may remain with the provider."
        }
    }
}

private extension Array where Element == CloudProviderConfiguration {
    var artifactProviders: [CloudProviderConfiguration] {
        filter { $0.kind == .openAI || $0.kind == .gemini }
    }
}
