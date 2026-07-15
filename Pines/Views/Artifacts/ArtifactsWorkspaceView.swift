import SwiftUI
import PinesCore

struct ArtifactsWorkspaceView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesServices) private var services
    @Environment(\.openPinesProviderSettings) private var openProviderSettings
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var query = ArtifactsLibraryQuery()
    @State private var selectedArtifactID: String?
    @State private var presentedSheet: ArtifactsDeskSheet?
    @State private var pendingConfirmation: ArtifactsConfirmation?

    private var usesInspector: Bool {
        horizontalSizeClass != .compact
    }

    private var selectedArtifact: ProviderArtifactRecord? {
        selectedArtifactID.flatMap { id in
            providerState.providerArtifacts.first(where: { $0.id == id })
        }
    }

    var body: some View {
        NavigationStack {
            ArtifactsLibraryView(
                query: $query,
                selectedArtifactID: usesInspector ? selectedArtifactID : nil,
                pendingConfirmation: $pendingConfirmation,
                openArtifact: openArtifact,
                startNew: { presentedSheet = .commandDeck },
                openResearch: { threadID in present(.research(threadID: threadID)) },
                remix: { artifactID in present(.create(kind: .image, referenceArtifactID: artifactID)) },
                openProviderSettings: showProviderSettings
            )
            .navigationTitle("Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await appModel.refreshProviderLifecycleState(services: services)
            }
        }
        .inspector(isPresented: inspectorPresentation) {
            NavigationStack {
                inspectorContent
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") {
                                selectedArtifactID = nil
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Close artifact details")
                        }
                    }
            }
            .inspectorColumnWidth(min: 340, ideal: 420, max: 520)
            .accessibilityIdentifier("pines.artifacts.inspector")
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
            }
            .presentationDragIndicator(.visible)
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
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            adaptSelection(to: sizeClass)
        }
        .accessibilityIdentifier("pines.screen.artifacts")
    }

    private var inspectorPresentation: Binding<Bool> {
        Binding(
            get: { usesInspector && selectedArtifactID != nil },
            set: { isPresented in
                if !isPresented { selectedArtifactID = nil }
            }
        )
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let selectedArtifact {
            ArtifactDetailView(
                artifact: selectedArtifact,
                presentation: .inspector,
                pendingConfirmation: $pendingConfirmation,
                open: handle
            )
        } else {
            ArtifactsMissingRecordView()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ArtifactsDeskSheet) -> some View {
        switch sheet {
        case .commandDeck:
            ArtifactCommandDeck { command in
                switch command {
                case .image:
                    present(.create(kind: .image, referenceArtifactID: nil))
                case .video:
                    present(.create(kind: .video, referenceArtifactID: nil))
                case .speech:
                    present(.create(kind: .speech, referenceArtifactID: nil))
                case .research:
                    present(.research(threadID: nil))
                }
            }
        case .artifact(let id):
            if let artifact = providerState.providerArtifacts.first(where: { $0.id == id }) {
                ArtifactDetailView(
                    artifact: artifact,
                    presentation: .sheet,
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
            openArtifact(id)
        case .create(let kind, let referenceArtifactID):
            present(.create(kind: kind, referenceArtifactID: referenceArtifactID))
        case .research(let threadID):
            present(.research(threadID: threadID))
        case .providerSetup:
            showProviderSettings()
        }
    }

    private func openArtifact(_ id: String) {
        if usesInspector {
            presentedSheet = nil
            Task { @MainActor in
                await Task.yield()
                selectedArtifactID = id
            }
        } else {
            present(.artifact(id))
        }
    }

    private func present(_ sheet: ArtifactsDeskSheet) {
        selectedArtifactID = nil
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
        selectedArtifactID = nil
        presentedSheet = nil
        Task { @MainActor in
            await Task.yield()
            openProviderSettings()
        }
    }

    private func adaptSelection(to sizeClass: UserInterfaceSizeClass?) {
        guard let selectedArtifactID else { return }
        if sizeClass == .compact {
            self.selectedArtifactID = nil
            presentedSheet = .artifact(selectedArtifactID)
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
            if selectedArtifactID == artifact.id { selectedArtifactID = nil }
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

private enum ArtifactsDeskSheet: Hashable, Identifiable {
    case commandDeck
    case artifact(String)
    case create(kind: ArtifactsMediaKind, referenceArtifactID: String?)
    case research(threadID: String?)

    var id: String {
        switch self {
        case .commandDeck:
            "command-deck"
        case .artifact(let id):
            "artifact-\(id)"
        case .create(let kind, let referenceArtifactID):
            "create-\(kind.rawValue)-\(referenceArtifactID ?? "new")"
        case .research(let threadID):
            "research-\(threadID ?? "new")"
        }
    }
}

private enum ArtifactDetailPresentation {
    case sheet
    case inspector
}

private enum ArtifactDeskCommand: String, CaseIterable, Identifiable {
    case image
    case video
    case speech
    case research

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .speech: "Speech"
        case .research: "Research"
        }
    }

    var detail: String {
        switch self {
        case .image: "Generate a new image or begin a visual remix."
        case .video: "Create a motion artifact from a written direction."
        case .speech: "Turn text into a reusable narrated audio file."
        case .research: "Investigate the web and produce a cited report."
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .speech: "waveform"
        case .research: "doc.text.magnifyingglass"
        }
    }
}

private struct ArtifactCommandDeck: View {
    @Environment(\.pinesTheme) private var theme
    let choose: (ArtifactDeskCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    Text("Choose an outcome")
                        .font(theme.typography.title.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .accessibilityIdentifier("pines.artifacts.command-deck")
                    Text("Start with what you want to make. Provider and model choices come next, inside the focused composer.")
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: theme.spacing.small)],
                    spacing: theme.spacing.small
                ) {
                    ForEach(ArtifactDeskCommand.allCases) { command in
                        Button {
                            choose(command)
                        } label: {
                            HStack(alignment: .top, spacing: theme.spacing.medium) {
                                Image(systemName: command.systemImage)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(theme.colors.accent)
                                    .frame(width: 44, height: 44)
                                    .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                    Text(command.title)
                                        .font(theme.typography.headline)
                                        .foregroundStyle(theme.colors.primaryText)
                                    Text(command.detail)
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: theme.spacing.small)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(theme.colors.tertiaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pinesSurface(.panel, padding: theme.spacing.medium)
                        .accessibilityIdentifier("pines.artifacts.command.\(command.rawValue)")
                    }
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("New Artifact")
        .navigationBarTitleDisplayMode(.inline)
        .pinesAppBackground()
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
    let selectedArtifactID: String?
    @Binding var pendingConfirmation: ArtifactsConfirmation?
    let openArtifact: (String) -> Void
    let startNew: () -> Void
    let openResearch: (String?) -> Void
    let remix: (String) -> Void
    let openProviderSettings: () -> Void
    @State private var showsFilters = false

    private var providers: [CloudProviderConfiguration] {
        settingsState.cloudProviders.artifactProviders
    }

    private var items: [ArtifactLibraryItem] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = providerState.providerArtifacts
            .filter(\.isVisibleInArtifactsGallery)
            .filter { query.category.matches($0) }
            .filter { query.providerScope.includes($0.providerID) }
            .map {
                ArtifactLibraryItem(
                    artifact: $0,
                    providers: providers,
                    researchRuns: providerState.providerResearchRuns
                )
            }
            .filter { item in
                needle.isEmpty
                    || item.title.lowercased().contains(needle)
                    || item.providerName.lowercased().contains(needle)
                    || item.excerpt?.lowercased().contains(needle) == true
                    || item.artifact.searchText.lowercased().contains(needle)
            }

        switch query.sort {
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .provider:
            return filtered.sorted { $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending }
        case .kind:
            return filtered.sorted { $0.contentKind.title.localizedCaseInsensitiveCompare($1.contentKind.title) == .orderedAscending }
        }
    }

    private var activeResearchThreads: [ArtifactsResearchThread] {
        guard query.category == .all || query.category == .reports else { return [] }
        return ArtifactsResearchThread.threads(from: providerState.providerResearchRuns)
            .filter { $0.runs.contains(where: { !$0.status.providerIsTerminal }) }
            .filter { query.providerScope.includes($0.latestRun.providerID) }
    }

    private var activeItems: [ArtifactLibraryItem] {
        providerState.providerArtifacts
            .filter(\.isVisibleInArtifactsGallery)
            .filter { query.category.matches($0) }
            .filter { query.providerScope.includes($0.providerID) }
            .map {
                ArtifactLibraryItem(
                    artifact: $0,
                    providers: providers,
                    researchRuns: providerState.providerResearchRuns
                )
            }
            .filter(\.isActive)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var completedItems: [ArtifactLibraryItem] {
        items.filter { !$0.isActive }
    }

    private var activitySignature: String {
        let artifacts = activeItems.map { "artifact:\($0.id):\($0.operationState.title)" }
        let research = providerState.providerResearchRuns
            .filter { !$0.status.providerIsTerminal }
            .map { "research:\($0.id):\($0.status):\($0.updatedAt.timeIntervalSince1970)" }
        return (artifacts + research).joined(separator: "|")
    }

    private var usesGrid: Bool {
        horizontalSizeClass != .compact && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                commandStrip
                workQueue
                resultsHeader
                libraryContent
            }
            .padding(.horizontal, theme.spacing.large)
            .padding(.vertical, theme.spacing.medium)
            .frame(maxWidth: 1180, alignment: .leading)
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
        .sheet(isPresented: $showsFilters) {
            ArtifactsLibraryFilterSheet(
                query: $query,
                providers: providers
            )
            .presentationDetents([.medium, .large])
        }
        .task(id: activitySignature) {
            await monitorActivity()
        }
        .accessibilityIdentifier("pines.artifacts.library")
    }

    private var commandStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.small) {
                searchField
                    .frame(minWidth: 240, maxWidth: 440)
                scopeMenu
                refineButton
                Spacer(minLength: theme.spacing.small)
                newArtifactButton
            }

            VStack(spacing: theme.spacing.small) {
                searchField
                HStack(spacing: theme.spacing.small) {
                    scopeMenu
                    refineButton
                    Spacer(minLength: theme.spacing.xsmall)
                    newArtifactButton
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: theme.spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.colors.secondaryText)
            TextField("Search artifacts", text: $query.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pines.artifacts.search")
            if !query.text.isEmpty {
                Button {
                    query.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.tertiaryText)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, theme.spacing.medium)
        .frame(minHeight: 46)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .stroke(theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
        }
    }

    private var scopeMenu: some View {
        Menu {
            ForEach(ArtifactsAssetKindFilter.allCases) { category in
                Button {
                    query.category = category
                } label: {
                    Label(category.deskTitle, systemImage: query.category == category ? "checkmark" : category.systemImage)
                }
            }
        } label: {
            Label(query.category.deskTitle, systemImage: query.category.systemImage)
                .lineLimit(1)
        }
        .pinesButtonStyle(.secondary)
        .accessibilityLabel("Artifact scope, \(query.category.deskTitle)")
        .accessibilityIdentifier("pines.artifacts.scope")
    }

    private var refineButton: some View {
        Button {
            showsFilters = true
        } label: {
            Label(query.hasSheetFilters ? "Refined" : "Refine", systemImage: "line.3.horizontal.decrease")
        }
        .pinesButtonStyle(query.hasSheetFilters ? .primary : .secondary)
        .accessibilityIdentifier("pines.artifacts.library.filter")
    }

    private var newArtifactButton: some View {
        Button(action: startNew) {
            Label("New", systemImage: "plus")
        }
        .pinesButtonStyle(.primary)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("New artifact")
        .accessibilityIdentifier("pines.artifacts.new")
    }

    @ViewBuilder
    private var workQueue: some View {
        if !activeItems.isEmpty || !activeResearchThreads.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                HStack(spacing: theme.spacing.xsmall) {
                    Text("In progress")
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.colors.primaryText)
                    Text("\(activeItems.count + activeResearchThreads.count)")
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .padding(.horizontal, theme.spacing.xsmall)
                        .padding(.vertical, theme.spacing.xxsmall)
                        .background(theme.colors.controlFill, in: Capsule())
                }

                if dynamicTypeSize.isAccessibilitySize {
                    LazyVStack(spacing: theme.spacing.small) {
                        workQueueRows(fixedWidth: false)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: theme.spacing.small) {
                            workQueueRows(fixedWidth: true)
                        }
                    }
                    .pinesExpressiveHorizontalScrollHaptics()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func workQueueRows(fixedWidth: Bool) -> some View {
        ForEach(activeResearchThreads) { thread in
            ArtifactsActivityRow(
                title: thread.title,
                detail: "Research · \(thread.providerKind.pinesLifecycleTitle)",
                status: thread.statusText,
                systemImage: "doc.text.magnifyingglass"
            ) {
                openResearch(thread.id)
            }
            .frame(width: fixedWidth ? 300 : nil)
            .frame(maxWidth: fixedWidth ? nil : .infinity, alignment: .leading)
        }

        ForEach(activeItems) { item in
            ArtifactsActivityRow(
                title: item.title,
                detail: "\(item.contentKind.title) · \(item.providerName)",
                status: item.operationState.title,
                systemImage: item.contentKind.systemImage
            ) {
                openArtifact(item.id)
            }
            .frame(width: fixedWidth ? 300 : nil)
            .frame(maxWidth: fixedWidth ? nil : .infinity, alignment: .leading)
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.small) {
            Text(query.category == .all ? "Recent work" : query.category.title)
                .font(theme.typography.title.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("\(completedItems.count)")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.tertiaryText)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if providerState.isRefreshingProviderLifecycle && items.isEmpty {
            ArtifactsLoadingState()
        } else if completedItems.isEmpty {
            ArtifactsLibraryEmptyState(
                hasProviders: !providers.isEmpty,
                hasQuery: !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || query.hasActiveFilters,
                clearFilters: {
                    query.text = ""
                    query.resetFilters()
                },
                create: startNew,
                research: { openResearch(nil) },
                connectProvider: openProviderSettings
            )
        } else if usesGrid {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: theme.spacing.medium)],
                alignment: .leading,
                spacing: theme.spacing.medium
            ) {
                ForEach(completedItems) { item in
                    ArtifactDeskTile(
                        item: item,
                        isSelected: selectedArtifactID == item.id,
                        open: { openArtifact(item.id) },
                        importToVault: { Task { await importToVault(item.artifact) } },
                        remix: { remix(item.id) },
                        remove: { pendingConfirmation = .deleteArtifactRecord(item.artifact) }
                    )
                }
            }
        } else {
            LazyVStack(spacing: theme.spacing.small) {
                ForEach(completedItems) { item in
                    ArtifactLibraryRow(
                        item: item,
                        isSelected: selectedArtifactID == item.id,
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
    private func importToVault(_ artifact: ProviderArtifactRecord) async {
        do {
            _ = try await appModel.importProviderArtifactToVault(id: artifact.id, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func monitorActivity() async {
        guard !PinesUITestLaunchConfiguration.isEnabled else { return }
        while !Task.isCancelled, !activitySignature.isEmpty {
            let artifacts = activeItems.prefix(6)
            let researchRuns = providerState.providerResearchRuns
                .filter { !$0.status.providerIsTerminal }
                .prefix(6)

            for item in artifacts where !Task.isCancelled {
                guard let providerID = item.artifact.providerID else { continue }
                switch item.artifact.providerKind {
                case .openAI where item.artifact.kind.lowercased() == "video_job":
                    _ = try? await appModel.refreshOpenAIVideoArtifact(
                        id: item.artifact.providerFileID ?? item.artifact.id,
                        providerID: providerID,
                        services: services
                    )
                case .gemini where item.artifact.kind.lowercased() == "media_operation":
                    _ = try? await appModel.refreshGeminiGeneratedMediaOperation(
                        id: item.artifact.responseID ?? item.artifact.id,
                        providerID: providerID,
                        services: services
                    )
                default:
                    continue
                }
            }

            for run in researchRuns where !Task.isCancelled {
                switch run.providerKind {
                case .openAI:
                    _ = try? await appModel.refreshOpenAIDeepResearchRun(
                        id: run.id,
                        providerID: run.providerID,
                        services: services
                    )
                case .gemini:
                    _ = try? await appModel.refreshGeminiDeepResearchRun(
                        id: run.id,
                        providerID: run.providerID,
                        services: services
                    )
                default:
                    continue
                }
            }

            do {
                try await Task.sleep(for: .seconds(6))
            } catch {
                return
            }
        }
    }
}

private struct ArtifactsLibraryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var query: ArtifactsLibraryQuery
    let providers: [CloudProviderConfiguration]

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $query.providerScope) {
                        Text("All providers").tag(ArtifactsProviderScope.all)
                        ForEach(providers) { provider in
                            Text(provider.displayName).tag(ArtifactsProviderScope.provider(provider.id))
                        }
                    }
                }

                Section("Sort") {
                    Picker("Sort", selection: $query.sort) {
                        ForEach(ArtifactsSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if query.hasActiveFilters {
                    Section {
                        Button("Reset filters", role: .destructive) {
                            query.resetFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filter Artifacts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ArtifactsActivityRow: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let detail: String
    let status: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: theme.spacing.small) {
                activityIndicator
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    activityLabels
                    HStack(spacing: theme.spacing.xsmall) {
                        statusLabel
                        Spacer(minLength: theme.spacing.small)
                        disclosureIndicator
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    private var activityIndicator: some View {
        PinesStatusIndicator(color: theme.colors.accent, isActive: true, size: 9)
            .frame(width: 24, height: 24)
    }

    private var activityLabels: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
            Text(title)
                .font(theme.typography.callout.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusLabel: some View {
        Text(status)
            .font(theme.typography.caption.weight(.semibold))
            .foregroundStyle(theme.colors.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.colors.tertiaryText)
    }
}

private struct ArtifactLibraryRow: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: ArtifactLibraryItem
    let isSelected: Bool
    let open: () -> Void
    let importToVault: () -> Void
    let remix: () -> Void
    let remove: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    Button(action: open) {
                        VStack(alignment: .leading, spacing: theme.spacing.small) {
                            ArtifactsArtifactThumbnail(artifact: item.artifact)
                                .frame(maxWidth: .infinity)
                                .frame(height: 156)
                            labels
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rowAccessibilityLabel)

                    HStack {
                        Spacer(minLength: 0)
                        overflowMenu
                    }
                }
            } else {
                HStack(alignment: .center, spacing: theme.spacing.medium) {
                    Button(action: open) {
                        HStack(alignment: .center, spacing: theme.spacing.medium) {
                            ArtifactsArtifactThumbnail(artifact: item.artifact)
                                .frame(width: 92, height: 72)
                            labels
                            Spacer(minLength: theme.spacing.small)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rowAccessibilityLabel)

                    overflowMenu
                }
            }
        }
        .padding(theme.spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinesSurface(isSelected ? .selected : .panel, padding: 0)
    }

    private var rowAccessibilityLabel: String {
        "\(item.title), \(item.contentKind.title), \(item.providerName)"
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            Text(item.title)
                .font(theme.typography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if let excerpt = item.excerpt, item.contentKind == .report {
                Text(excerpt)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
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

private struct ArtifactDeskTile: View {
    @Environment(\.pinesTheme) private var theme
    let item: ArtifactLibraryItem
    let isSelected: Bool
    let open: () -> Void
    let importToVault: () -> Void
    let remix: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Button(action: open) {
                thumbnail
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.title)")

            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Button(action: open) {
                    Text(item.title)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(item.title)")

                HStack(alignment: .center, spacing: theme.spacing.xxsmall) {
                    Button(action: open) {
                        Text("\(item.contentKind.title) · \(item.providerName) · \(RelativeDateTimeFormatter.shortLabel(for: item.createdAt))")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(item.title)")

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
        }
        .padding(theme.spacing.small)
        .pinesSurface(isSelected ? .selected : .panel, padding: 0)
    }

    private var thumbnail: some View {
        ArtifactsArtifactThumbnail(artifact: item.artifact)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
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
        .buttonStyle(.plain)
        .accessibilityLabel("More actions for \(item.title)")
    }
}

private struct ArtifactsLoadingState: View {
    @Environment(\.pinesTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            ProgressView()
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
                .font(.system(size: 32, weight: .semibold))
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

private struct ArtifactDetailView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let artifact: ProviderArtifactRecord
    let presentation: ArtifactDetailPresentation
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
            VStack(alignment: .leading, spacing: presentation == .inspector ? theme.spacing.medium : theme.spacing.large) {
                preview
                titleBlock
                primaryActions
                if item.contentKind == .report, let text = reportText {
                    reportBody(text)
                }
                provenance
            }
            .padding(presentation == .inspector ? theme.spacing.medium : theme.spacing.large)
            .frame(maxWidth: presentation == .inspector ? 520 : 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(presentation == .inspector ? "Details" : item.contentKind.title)
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
        .accessibilityIdentifier("pines.artifacts.detail")
    }

    @ViewBuilder
    private var preview: some View {
        if item.contentKind == .report {
            ArtifactsArtifactThumbnail(artifact: artifact)
                .frame(
                    maxWidth: .infinity,
                    minHeight: presentation == .inspector ? 140 : 180,
                    maxHeight: presentation == .inspector ? 190 : 240
                )
        } else {
            ArtifactsArtifactPreviewSurface(
                artifact: artifact,
                maxHeight: presentation == .inspector ? 260 : 560
            )
                .frame(maxWidth: .infinity)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text(item.title)
                .font(presentation == .inspector ? theme.typography.title.weight(.semibold) : theme.typography.hero)
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
            Text("Report")
                .font(theme.typography.title.weight(.semibold))
            MarkdownMessageView(messageID: UUID(), content: text, isStreaming: false)
        }
        .textSelection(.enabled)
        .pinesSurface(.panel, padding: theme.spacing.large)
    }

    private var provenance: some View {
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
        .pinesSurface(.inset, padding: theme.spacing.medium)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                if providers.isEmpty {
                    noProviderState
                } else {
                    creationContext
                    if let selectedReference {
                        referenceCard(selectedReference)
                    }
                    composer
                    if !outputs.isEmpty {
                        outputSection
                    }
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(selectedReference == nil ? "New \(mediaKind.title)" : "Remix Image")
        .navigationBarTitleDisplayMode(.inline)
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
        }
        .onAppear {
            if providerID == nil { providerID = providers.first?.id }
            normalizeSelectedModel()
        }
        .onChange(of: providerID) { _, _ in normalizeSelectedModel() }
        .onChange(of: mediaKind) { _, _ in normalizeSelectedModel() }
        .pinesAppBackground()
        .accessibilityIdentifier("pines.artifacts.create")
    }

    private var noProviderState: some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: "cloud.badge.plus")
                .font(.system(size: 32, weight: .semibold))
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
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var creationContext: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.medium) {
                kindMenu
                Divider()
                configurationButton
            }
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                kindMenu
                Divider()
                configurationButton
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.medium)
    }

    private var kindMenu: some View {
        Menu {
            ForEach(ArtifactsMediaKind.allCases) { kind in
                Button {
                    mediaKind = kind
                } label: {
                    Label(kind.title, systemImage: mediaKind == kind ? "checkmark" : kind.systemImage)
                }
            }
        } label: {
            HStack(spacing: theme.spacing.small) {
                Image(systemName: mediaKind.systemImage)
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text("Output")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                    Text(mediaKind.title)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedReference != nil)
        .accessibilityLabel("Output type, \(mediaKind.title)")
        .accessibilityIdentifier("pines.artifacts.create.type")
    }

    private var configurationButton: some View {
        Button {
            showsSettings = true
        } label: {
            HStack(spacing: theme.spacing.small) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(provider?.displayName ?? "Choose provider")
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text(modelOptions.first(where: { $0.id == modelID })?.title ?? "Choose a model")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: theme.spacing.small)
                Text("Adjust")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pines.artifacts.create.configuration")
    }

    private func referenceCard(_ artifact: ProviderArtifactRecord) -> some View {
        HStack(spacing: theme.spacing.medium) {
            ArtifactsArtifactThumbnail(artifact: artifact)
                .frame(width: 84, height: 72)
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text("Reference image")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.accent)
                Text(artifact.artifactDisplayTitle)
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .pinesSurface(.panel, padding: theme.spacing.small)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                Text(promptTitle)
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.primaryText)
                TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($promptFocused)
                    .pinesFieldChrome()
                    .accessibilityIdentifier("pines.artifacts.create.prompt")
            }

            createButton
        }
        .pinesSurface(.panel, padding: theme.spacing.large)
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
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text("This session")
                .font(theme.typography.title)
            ForEach(outputs) { artifact in
                let item = ArtifactLibraryItem(
                    artifact: artifact,
                    providers: providers,
                    researchRuns: providerState.providerResearchRuns
                )
                Button {
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
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.colors.tertiaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
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
                .pinesSurface(.inset, padding: theme.spacing.small)
            }
        }
    }

    private var createSettings: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $providerID) {
                        ForEach(providers) { provider in
                            Text(provider.displayName).tag(Optional(provider.id))
                        }
                    }
                    Picker("Model", selection: $modelID) {
                        ForEach(modelOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }

                if mediaKind == .image {
                    Section("Image") {
                        Picker("Quality", selection: $imageQuality) {
                            Text("Automatic").tag("auto")
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                        }
                        Picker("Size", selection: $imageSize) {
                            Text("Automatic").tag("auto")
                            Text("Square").tag("1024x1024")
                            Text("Landscape").tag("1536x1024")
                            Text("Portrait").tag("1024x1536")
                        }
                        Picker("Format", selection: $imageFormat) {
                            Text("PNG").tag("png")
                            Text("JPEG").tag("jpeg")
                            Text("WebP").tag("webp")
                        }
                    }
                } else if mediaKind == .speech {
                    Section("Speech") {
                        Picker("Voice", selection: $speechVoice) {
                            ForEach(["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"], id: \.self) { voice in
                                Text(voice.capitalized).tag(voice)
                            }
                        }
                    }
                } else {
                    Section("Video") {
                        Toggle("Check for output after creation", isOn: $refreshAfterVideoCreate)
                    }
                }
            }
            .navigationTitle("Creation Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
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

    private var activeRunSignature: String {
        activeRuns.map { "\($0.id):\($0.status):\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: "|")
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

            researchContextBar
            conversation
            composer
        }
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSettings) {
            researchSettings
                .presentationDetents([.medium, .large])
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
        }
        .onAppear(perform: configureInitialSelection)
        .onChange(of: providerID) { _, _ in normalizeSelectedModel() }
        .task(id: activeRunSignature) {
            await monitorActiveRuns()
        }
        .pinesAppBackground()
        .accessibilityIdentifier("pines.artifacts.research")
    }

    private var researchContextBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.small) {
                researchThreadMenu
                Spacer(minLength: theme.spacing.small)
                researchUtilityButtons
            }
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                researchThreadMenu
                HStack(spacing: theme.spacing.small) {
                    researchUtilityButtons
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, theme.spacing.large)
        .padding(.vertical, theme.spacing.small)
        .background(theme.colors.chromeBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
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
        } label: {
            Label(selectedThread?.title ?? "Research history", systemImage: "clock.arrow.circlepath")
                .lineLimit(1)
        }
        .pinesButtonStyle(.secondary)
        .accessibilityLabel(selectedThread == nil ? "Research history" : "Current research, \(selectedThread?.title ?? "")")
        .accessibilityIdentifier("pines.artifacts.research.thread-menu")
    }

    @ViewBuilder
    private var researchUtilityButtons: some View {
        if selectedThread != nil {
            Button {
                startNewThread()
            } label: {
                Label("New", systemImage: "square.and.pencil")
            }
            .pinesButtonStyle(.secondary)
            .accessibilityIdentifier("pines.artifacts.research.new")
        }

        Button {
            showsSettings = true
        } label: {
            Label("Setup", systemImage: "slider.horizontal.3")
        }
        .pinesButtonStyle(.secondary)
        .accessibilityIdentifier("pines.artifacts.research.settings")

        if !activeRuns.isEmpty {
            Button {
                Task { await refreshActiveRuns() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .pinesButtonStyle(.secondary)
            .accessibilityLabel("Refresh research progress")
        }
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
                            title: "What should we research?",
                            detail: "Ask a question below. Pines can clarify scope before starting, then keeps sources, progress, and the final report together.",
                            actionTitle: nil,
                            action: {}
                        )
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: 880, alignment: .leading)
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

    private func researchEmptyState(
        title: String,
        detail: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 68, height: 68)
                .background(theme.colors.accentSoft, in: Circle())
            Text(title)
                .font(theme.typography.title)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .pinesButtonStyle(.secondary)
            }
        }
        .padding(.vertical, theme.spacing.xlarge)
        .frame(maxWidth: 620, minHeight: 360)
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            if selectedThread == nil {
                Button {
                    showsSettings = true
                } label: {
                    Label(researchConfigurationLabel, systemImage: usesProviderFiles ? "globe.badge.chevron.backward" : "globe")
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: theme.spacing.small) {
                TextField(selectedThread == nil ? "Ask a research question" : "Ask a follow-up", text: composerBinding, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .pinesFieldChrome()
                    .accessibilityIdentifier(selectedThread == nil ? "pines.artifacts.research.prompt" : "pines.artifacts.research.follow-up")

                Button {
                    Task { await commitComposer() }
                } label: {
                    Image(systemName: isStarting ? "hourglass" : "arrow.up")
                        .frame(width: 20, height: 20)
                }
                .disabled(sendDisabled)
                .pinesButtonStyle(.primary)
                .accessibilityLabel(selectedThread == nil ? "Start research" : "Send follow-up")
                .accessibilityIdentifier("pines.artifacts.research.send")
            }
        }
        .padding(.horizontal, theme.spacing.large)
        .padding(.vertical, theme.spacing.small)
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var researchConfigurationLabel: String {
        let providerName = provider?.displayName ?? "Choose provider"
        let source = usesProviderFiles ? "web + provider files" : "web only"
        return "\(providerName) · \(source)"
    }

    private var researchSettings: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $providerID) {
                        ForEach(providers) { provider in
                            Text(provider.displayName).tag(Optional(provider.id))
                        }
                    }
                    Picker("Model", selection: $modelID) {
                        ForEach(modelOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }

                Section("Sources") {
                    Toggle("Include provider files", isOn: $usesProviderFiles)
                    Text(usesProviderFiles
                         ? "Research may use files and vector stores already hosted with this provider, in addition to the web."
                         : "Research uses the web only. Provider-hosted files are excluded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Report") {
                    Picker("Depth", selection: $depth) {
                        ForEach(OpenAIDeepResearchDepth.allCases, id: \.self) { value in
                            Text(value.rawValue.readableArtifactKind).tag(value)
                        }
                    }
                    Picker("Format", selection: $reportFormat) {
                        ForEach(OpenAIDeepResearchReportFormat.allCases, id: \.self) { value in
                            Text(value.rawValue.readableArtifactKind).tag(value)
                        }
                    }
                }
            }
            .navigationTitle("Research Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
        }
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

    @MainActor
    private func monitorActiveRuns() async {
        guard !activeRuns.isEmpty else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard !activeRuns.isEmpty else { return }
            await refreshActiveRuns()
        }
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

struct ArtifactsResearchThread: Identifiable, Hashable {
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
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            PinesMessageBubble(role: .user, maxWidth: 640) {
                Text(run.researchDisplayPrompt)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

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
                                .lineLimit(5)
                                .multilineTextAlignment(.leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pinesSurface(.inset, padding: theme.spacing.medium)
                } else if run.status.providerIsTerminal {
                    Text(run.lastError ?? "The provider completed without a saved report artifact.")
                        .font(theme.typography.callout)
                        .foregroundStyle(run.lastError == nil ? theme.colors.secondaryText : theme.colors.danger)
                }
            }
            .pinesSurface(.panel, padding: theme.spacing.medium)
        }
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
        .pinesSurface(.inset, padding: theme.spacing.small)
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
    @Environment(\.dismiss) private var dismiss
    let draft: ArtifactsResearchClarificationDraft
    @Binding var answers: [String: String]
    let start: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A little more context can make the report substantially more useful. Every answer is optional.")
                        .foregroundStyle(.secondary)
                }
                ForEach(draft.questions) { question in
                    Section(question.title) {
                        TextField(question.placeholder, text: Binding(
                            get: { answers[question.id] ?? "" },
                            set: { answers[question.id] = $0 }
                        ), axis: .vertical)
                        .lineLimit(1...4)
                    }
                }
                Section {
                    Button("Start with these answers") {
                        start(draft.providerPrompt(answers: answers))
                    }
                    Button("Use reasonable assumptions") {
                        start(draft.providerPrompt(answers: [:]))
                    }
                }
            }
            .navigationTitle("Clarify Research")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                        dismiss()
                    }
                }
            }
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
