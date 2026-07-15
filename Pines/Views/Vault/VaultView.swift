import SwiftUI
import PinesCore
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct VaultView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var chatState: PinesChatState
    @EnvironmentObject private var vaultState: PinesVaultState
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedItemID: PinesVaultItemPreview.ID?
    @State private var showingImporter = false
    @State private var showingVaultSettings = false
    @State private var searchInput = VaultSearchInputState()

    private var selectedItem: PinesVaultItemPreview? {
        guard let selectedItemID = selectedItemID ?? defaultItemID else {
            return nil
        }

        return visibleVaultItems.first { $0.id == selectedItemID }
    }

    private var defaultItemID: PinesVaultItemPreview.ID? {
        shouldAutoSelectSidebarItem ? visibleVaultItems.first?.id : nil
    }

    private var vaultItemIDs: [PinesVaultItemPreview.ID] {
        visibleVaultItems.map(\.id)
    }

    private var visibleVaultItems: [PinesVaultItemPreview] {
        vaultState.vaultItems.filter { item in
            if let selectedProjectID = chatState.selectedProjectID {
                return item.projectID == selectedProjectID
            }
            return item.projectID == nil
        }
    }

    private var shouldAutoSelectSidebarItem: Bool {
        horizontalSizeClass != .compact
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemID) {
                if !searchInput.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Search results") {
                        ForEach(vaultState.vaultSearchResults) { result in
                            NavigationLink(value: result.document.id) {
                                VaultSearchResultRow(result: result)
                            }
                            .pinesSidebarListRow()
                        }
                    }
                }

                Section(chatState.selectedProjectID == nil ? "Vault" : "Project Vault") {
                    if visibleVaultItems.isEmpty {
                        Button {
                            haptics.play(.primaryAction)
                            showingImporter = true
                        } label: {
                            Label("Import your first file", systemImage: "doc.badge.plus")
                                .font(theme.typography.callout.weight(.semibold))
                                .foregroundStyle(theme.colors.accent)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .pinesSidebarListRow()
                    }

                    ForEach(visibleVaultItems) { item in
                        NavigationLink(value: item.id) {
                            VaultItemRow(item: item, isSelected: selectedItemID == item.id)
                        }
                        .pinesSidebarListRow()
                    }
                }
            }
            .navigationTitle("Vault")
            .pinesExpressiveScrollHaptics()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        haptics.play(.primaryAction)
                        showingImporter = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .accessibilityLabel("Import")

                    Button {
                        haptics.play(.primaryAction)
                        vaultState.isVaultSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search vault")

                    Button {
                        haptics.play(.navigationSelected)
                        showingVaultSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Vault settings")
                }
            }
            .searchable(text: vaultSearchBinding, isPresented: $vaultState.isVaultSearchPresented, prompt: "Search vault")
            .onSubmit(of: .search) {
                Task { await appModel.searchVault(searchInput.text, services: services) }
            }
            .onAppear(perform: selectDefaultItemIfNeeded)
            .onChange(of: horizontalSizeClass) { _, _ in
                selectDefaultItemIfNeeded()
            }
            .onChange(of: vaultItemIDs) { _, ids in
                if let selectedItemID, !ids.contains(selectedItemID) {
                    self.selectedItemID = nil
                }
                selectDefaultItemIfNeeded()
            }
            .onChange(of: chatState.selectedProjectID) { _, _ in
                selectedItemID = nil
                selectDefaultItemIfNeeded()
            }
            .onChange(of: selectedItemID) { _, _ in
                haptics.play(.navigationSelected)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: VaultIngestionService.allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    Task {
                        await appModel.importVaultFile(url, services: services)
                    }
                }
            }
            .sheet(isPresented: $showingVaultSettings) {
                NavigationStack {
                    List {
                        VaultEmbeddingSetupSection()
                        VaultProviderStorageSection()
                    }
                    .navigationTitle("Vault Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingVaultSettings = false }
                        }
                    }
                    .pinesSidebarListChrome()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .pinesSidebarListChrome()
        } detail: {
            if let selectedItem {
                VaultDetailView(item: selectedItem)
            } else {
                PinesEmptyState(
                    title: "Vault empty",
                    detail: "Private notes, documents, keys, and image references appear here.",
                    systemImage: "shippingbox",
                    primaryActionTitle: "Import file",
                    primaryActionSystemImage: "doc.badge.plus",
                    primaryAction: { showingImporter = true }
                )
            }
        }
        .accessibilityIdentifier("pines.screen.vault")
    }

    private func selectDefaultItemIfNeeded() {
        guard shouldAutoSelectSidebarItem else { return }
        selectedItemID = selectedItemID ?? visibleVaultItems.first?.id
    }

    private var vaultSearchBinding: Binding<String> {
        Binding(
            get: { searchInput.text },
            set: { newValue in
                searchInput.text = newValue
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    vaultState.vaultSearchResults = []
                }
            }
        )
    }
}

private final class VaultSearchInputState {
    var text = ""
}

private struct VaultProviderStorageSection: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @EnvironmentObject private var settingsState: PinesSettingsState

    private var providerStorageProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { provider in
            provider.kind == .openAI || provider.kind == .anthropic || provider.kind == .gemini
        }
    }

    private var fileSearchConfigSummary: String {
        let ids = providerState.providerVectorStores.map(\.id)
        guard !ids.isEmpty else { return "No vector store selected" }
        let quotedIDs = ids.map { #""\#($0)""# }.joined(separator: ",")
        return #"{"type":"file_search","vector_store_ids":["# + quotedIDs + #"]}"#
    }

    var body: some View {
        Section("Cloud Copies") {
            VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                HStack(spacing: theme.spacing.xsmall) {
                    PinesProviderStorageBadge(kind: .providerHosted, compact: true)
                    PinesProviderStorageBadge(kind: .vectorStore, compact: true)
                }

                Text("Cloud copies are opt-in and can be deleted separately. Vault files stay local unless explicitly exported.")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, theme.spacing.xsmall)

            HStack {
                Label("\(providerState.providerFilePreviews.count) files", systemImage: "doc")
                    .font(theme.typography.caption.weight(.semibold))
                Spacer()
                Label("\(providerState.providerVectorStorePreviews.count) stores", systemImage: "square.stack.3d.up")
                    .font(theme.typography.caption.weight(.semibold))
            }
            .foregroundStyle(theme.colors.secondaryText)

            Button {
                Task { await refreshProviderStorage() }
            } label: {
                Label(providerState.isRefreshingProviderLifecycle ? "Refreshing" : "Refresh cloud copies", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(providerStorageProviders.isEmpty || providerState.isRefreshingProviderLifecycle)

            if !providerState.providerVectorStorePreviews.isEmpty {
                Text("File search config")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.tertiaryText)
                Text(fileSearchConfigSummary)
                    .font(theme.typography.code)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            ForEach(providerState.providerVectorStorePreviews.prefix(4)) { store in
                VaultProviderVectorStoreRow(store: store)
            }

            ForEach(providerState.providerFilePreviews.prefix(4)) { file in
                VaultProviderFileRow(file: file)
            }

            if let error = providerState.providerLifecycleError {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger)
            }
        }
    }

    @MainActor
    private func refreshProviderStorage() async {
        do {
            for provider in providerStorageProviders {
                switch provider.kind {
                case .openAI:
                    _ = try await appModel.refreshOpenAIProviderStorage(providerID: provider.id, services: services)
                case .anthropic:
                    _ = try await appModel.refreshAnthropicProviderStorage(providerID: provider.id, services: services)
                case .gemini:
                    _ = try await appModel.refreshGeminiProviderStorage(providerID: provider.id, services: services)
                default:
                    break
                }
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct VaultProviderVectorStoreRow: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let store: PinesProviderCachePreview
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
            HStack {
                Label(store.title, systemImage: "square.stack.3d.up")
                    .font(theme.typography.caption.weight(.semibold))
                    .pinesFittingText()
                Spacer(minLength: theme.spacing.xsmall)
                PinesStatusChip(status: store.status.providerStorageCloudStatus, compact: true)
            }

            Text("\(store.usageLabel) - \(store.createdLabel)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)

            HStack(spacing: theme.spacing.xsmall) {
                PinesCompactIconButton(title: "Refresh cloud files", systemImage: "arrow.clockwise") {
                    Task { await refreshFiles() }
                }

                PinesCompactIconButton(title: "Delete cloud context", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
        .confirmationDialog(
            "Delete this cloud context?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete cloud context", role: .destructive) {
                Task { await deleteStore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the provider-hosted vector store. Local Vault documents are not deleted.")
        }
    }

    @MainActor
    private func refreshFiles() async {
        do {
            _ = try await appModel.refreshOpenAIVectorStoreFiles(
                providerID: store.providerID,
                vectorStoreID: store.id,
                services: services
            )
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteStore() async {
        do {
            try await appModel.deleteOpenAIVectorStore(
                providerID: store.providerID,
                vectorStoreID: store.id,
                services: services
            )
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct VaultProviderFileRow: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let file: PinesProviderFilePreview
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
            HStack {
                Label(file.title, systemImage: "doc")
                    .font(theme.typography.caption.weight(.semibold))
                    .pinesFittingText()
                Spacer(minLength: theme.spacing.xsmall)
                PinesStatusChip(status: file.status.providerStorageCloudStatus, compact: true)
            }

            Text("\(file.purpose) - \(file.byteCountLabel) - \(file.createdLabel)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)

            HStack {
                Spacer()
                PinesCompactIconButton(title: "Delete hosted file", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
        .confirmationDialog(
            "Delete this hosted file?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete cloud copy", role: .destructive) {
                Task { await deleteFile() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the provider-hosted copy. The local Vault document is not deleted.")
        }
    }

    @MainActor
    private func deleteFile() async {
        do {
            switch file.providerKind {
            case .openAI:
                try await appModel.deleteOpenAIProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .anthropic:
                try await appModel.deleteAnthropicProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .gemini:
                try await appModel.deleteGeminiProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(file.providerKind.rawValue) file deletion is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct VaultEmbeddingSetupSection: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var vaultState: PinesVaultState
    @EnvironmentObject private var settingsState: PinesSettingsState

    private var activeProfile: VaultEmbeddingProfile? {
        vaultState.vaultEmbeddingProfiles.first(where: \.isActive)
    }

    private var selectableProfiles: [VaultEmbeddingProfile] {
        vaultState.vaultEmbeddingProfiles.filter { $0.status != .failed }
    }

    private var managedCloudSearchHint: String {
        guard settingsState.proEntitlementStatus.enablesManagedCloud else {
            return "No cloud-enhanced Vault search runs without Pro Cloud or an advanced key."
        }
        guard settingsState.managedCloudConsent == .optedIn, settingsState.cloudAccessMode.usesManagedCloud else {
            return "Pro Cloud search improvements stay off until Cloud Intelligence is enabled."
        }
        return "Pro Cloud can improve retrieval only after you approve the document or project scope."
    }

    var body: some View {
        Section("Search Quality") {
            if let activeProfile {
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    Label(activeProfile.kind.isCloud ? "Cloud-enhanced search" : "Local semantic search", systemImage: activeProfile.kind.isCloud ? "cloud.fill" : "cpu")
                        .font(theme.typography.callout.weight(.semibold))
                        .pinesFittingText()
                    Text("\(activeProfile.displayName) · \(activeProfile.modelID.rawValue) · \(activeProfile.dimensions > 0 ? "\(activeProfile.dimensions)d" : "native dimensions")")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(2)
                    Text(activeProfile.kind.isCloud
                        ? "Vault content is sent only for the selected embedding profile and approved scope."
                        : managedCloudSearchHint)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, theme.spacing.xsmall)

                if selectableProfiles.count > 1 {
                    Picker("Provider", selection: Binding(
                        get: { activeProfile.id },
                        set: { id in
                            guard let profile = selectableProfiles.first(where: { $0.id == id }) else { return }
                            Task { await appModel.selectVaultEmbeddingProfile(profile, services: services) }
                        }
                    )) {
                        ForEach(selectableProfiles) { profile in
                            Text(profile.displayName).tag(profile.id)
                        }
                    }
                }

                Button {
                    if vaultState.isVaultReindexing {
                        appModel.cancelVaultReindex()
                    } else {
                        Task { await appModel.reindexVault(services: services) }
                    }
                } label: {
                    Label(
                        vaultState.isVaultReindexing ? "Cancel reindex" : "Reindex vault",
                        systemImage: vaultState.isVaultReindexing ? "xmark.circle" : "arrow.triangle.2.circlepath"
                    )
                }

                if let activeJob = vaultState.vaultEmbeddingJobs.first(where: { $0.profileID == activeProfile.id && $0.status == .running }) {
                    Text("\(activeJob.processedChunks)/\(activeJob.totalChunks) chunks embedded")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    Label("Semantic search disabled", systemImage: "exclamationmark.triangle")
                        .font(theme.typography.callout.weight(.semibold))
                    Text("Install a local embedding model or add an advanced key to enable semantic search. Text search still works.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if !selectableProfiles.isEmpty {
                        ForEach(selectableProfiles) { profile in
                            Button {
                                Task { await appModel.selectVaultEmbeddingProfile(profile, services: services) }
                            } label: {
                                Label(profile.displayName, systemImage: profile.kind.isCloud ? "cloud" : "cpu")
                            }
                        }
                    }

                    Button {
                        Task {
                            await appModel.installModel(
                                repository: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
                                services: services
                            )
                        }
                    } label: {
                        Label("Install local model", systemImage: "arrow.down.circle")
                    }

                    Link(destination: URL(string: "https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")!) {
                        Label("Qwen3 Embedding", systemImage: "link")
                    }
                    Link(destination: URL(string: "https://platform.openai.com/settings/organization/api-keys")!) {
                        Label("Advanced OpenAI key", systemImage: "key")
                    }
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        Label("Advanced Gemini key", systemImage: "key")
                    }
                    Link(destination: URL(string: "https://openrouter.ai/settings/keys")!) {
                        Label("OpenRouter keys", systemImage: "key")
                    }
                    Link(destination: URL(string: "https://docs.voyageai.com/docs/embeddings")!) {
                        Label("Voyage setup", systemImage: "link")
                    }
                }
                .padding(.vertical, theme.spacing.xsmall)
            }
        }
    }
}

private struct VaultSearchResultRow: View {
    @Environment(\.pinesTheme) private var theme
    let result: VaultSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
            Text(result.document.title)
                .font(theme.typography.callout.weight(.semibold))
                .pinesFittingText()
            Text(result.snippet)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(3)
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct VaultItemRow: View {
    @Environment(\.pinesTheme) private var theme
    let item: PinesVaultItemPreview
    let isSelected: Bool

    var body: some View {
        PinesSidebarRow(
            title: item.title,
            subtitle: item.detail,
            systemImage: item.kind.systemImage,
            detail: item.updatedLabel,
            tint: item.sensitivity == .locked ? theme.colors.warning : theme.colors.accent,
            isSelected: isSelected,
            isActive: item.sensitivity == .locked
        )
    }
}

private struct VaultDetailView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var chatState: PinesChatState
    @EnvironmentObject private var vaultState: PinesVaultState
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var providerStorageExportInFlightID: ProviderID?
    @State private var showsDocumentDeleteConfirmation = false
    @State private var chunkPendingDeletion: VaultChunk?
    let item: PinesVaultItemPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                PinesSectionHeader(item.title, subtitle: item.detail)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: theme.spacing.small)], alignment: .leading, spacing: theme.spacing.small) {
                    PinesMetricPill(title: item.kind.title, systemImage: item.kind.systemImage)
                    PinesMetricPill(title: item.sensitivity.title, systemImage: item.sensitivity.systemImage, tint: item.sensitivity == .locked ? theme.colors.warning : theme.colors.accent)
                    PinesMetricPill(title: "\(loadedDetail?.linkedThreads ?? item.linkedThreads) links", systemImage: "link")
                }

                HStack {
                    Menu {
                        Button("Personal Vault") {
                            Task { await appModel.moveVaultDocument(id: item.id, toProject: nil, services: services) }
                        }
                        ForEach(chatState.projects) { project in
                            Button(project.name) {
                                Task { await appModel.moveVaultDocument(id: item.id, toProject: project.id, services: services) }
                            }
                        }
                    } label: {
                        Label(projectLabel, systemImage: "folder")
                    }
                    .pinesButtonStyle(.secondary)

                    Spacer()
                    Button(role: .destructive) {
                        showsDocumentDeleteConfirmation = true
                    } label: {
                        Label("Delete Vault file", systemImage: "trash")
                    }
                    .pinesButtonStyle(.destructive)
                }

                VaultSourcePreview(
                    item: item,
                    sourceData: loadedDetail?.sourceData
                )

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    Label("Private context", systemImage: "lock.shield")
                        .font(theme.typography.section)

                    Text(indexSummary)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(detailChunks.prefix(4)) { chunk in
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Chunk \(chunk.ordinal + 1) · \(chunk.characterCount) characters")
                                    .font(theme.typography.caption.weight(.semibold))
                                    .foregroundStyle(theme.colors.tertiaryText)
                                Spacer(minLength: theme.spacing.xsmall)
                                Button(role: .destructive) {
                                    chunkPendingDeletion = chunk
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .pinesButtonStyle(.icon)
                                .accessibilityLabel("Delete chunk \(chunk.ordinal + 1)")
                            }
                            Text(chunk.text)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(5)
                        }
                        .padding(.vertical, theme.spacing.xsmall)
                    }

                    if loadedDetail?.hasMoreChunks == true {
                        Text("Showing the first \(detailChunks.count) of \(item.activeProfileTotalChunks) chunks.")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.tertiaryText)
                    }
                }
                .pinesSurface(.elevated)

                if !providerStorageExportProviders.isEmpty {
                    VStack(alignment: .leading, spacing: theme.spacing.medium) {
                        HStack {
                            Label("Provider storage", systemImage: "cloud")
                                .font(theme.typography.section)

                            Spacer(minLength: theme.spacing.small)

                            Menu {
                                ForEach(providerStorageExportProviders) { provider in
                                    Button(provider.displayName) {
                                        Task { await exportToProviderStorage(provider) }
                                    }
                                }
                            } label: {
                                Label(
                                    providerStorageExportInFlightID == nil ? "Export" : "Exporting",
                                    systemImage: providerStorageExportInFlightID == nil ? "square.and.arrow.up" : "hourglass"
                                )
                            }
                            .disabled(providerStorageExportInFlightID != nil || loadedDetail == nil)
                        }

                        Text("Exported Vault documents become cloud copies and can be deleted separately from local Vault files.")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let error = providerState.providerLifecycleError {
                            Text(error)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .pinesSurface(.panel)
                }

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    Text("Index activity")
                        .font(theme.typography.section)

                    ForEach(Array(activityRows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Image(systemName: row.image)
                                .foregroundStyle(theme.colors.info)
                                .frame(width: 26)

                            Text(row.title)
                                .font(theme.typography.callout)
                                .pinesFittingText()

                            Spacer()
                        }
                        .padding(.vertical, theme.spacing.xsmall)
                    }
                }
                .pinesSurface(.panel)
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.title)
        .task(id: item.id) {
            await appModel.loadVaultItemDetails(id: item.id, services: services)
        }
        .onDisappear {
            appModel.clearVaultItemDetail(id: item.id)
        }
        .pinesExpressiveScrollHaptics()
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
        .confirmationDialog(
            "Delete this Vault file?",
            isPresented: $showsDocumentDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete local Vault file", role: .destructive) {
                Task { await appModel.deleteVaultDocument(id: item.id, services: services) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the local Vault document and its local search index. Provider-hosted copies, if any, are separate.")
        }
        .confirmationDialog(
            "Delete this indexed chunk?",
            isPresented: Binding(
                get: { chunkPendingDeletion != nil },
                set: { if !$0 { chunkPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: chunkPendingDeletion
        ) { chunk in
            Button("Delete local chunk", role: .destructive) {
                chunkPendingDeletion = nil
                Task { await appModel.deleteVaultChunk(chunk, documentID: item.id, services: services) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the chunk from local Vault search. It does not delete provider-hosted copies.")
        }
    }

    private var indexSummary: String {
        if let active = vaultState.vaultEmbeddingProfiles.first(where: \.isActive) {
            return "\(loadedDetail?.activeProfileEmbeddedChunks ?? item.activeProfileEmbeddedChunks)/\(item.activeProfileTotalChunks) chunks are embedded with \(active.displayName). Text search covers all chunks."
        }
        return "\(item.activeProfileTotalChunks) chunks are available for text search. Add an embedding provider for semantic retrieval."
    }

    private var loadedDetail: PinesVaultItemDetail? {
        guard vaultState.selectedItemDetail?.id == item.id else { return nil }
        return vaultState.selectedItemDetail
    }

    private var detailChunks: [VaultChunk] {
        loadedDetail?.chunks ?? []
    }

    private var projectLabel: String {
        guard let projectID = item.projectID,
              let project = chatState.projects.first(where: { $0.id == projectID })
        else {
            return "Personal Vault"
        }
        return project.name
    }

    private var providerStorageExportProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { provider in
            provider.kind == .openAI || provider.kind == .anthropic
        }
    }

    private var providerStorageByteCount: Int64 {
        guard let detail = loadedDetail else { return 0 }
        return detail.chunkUTF8ByteCount + Int64(max(0, detail.totalChunkCount - 1) * 2)
    }

    @MainActor
    private func exportToProviderStorage(_ provider: CloudProviderConfiguration) async {
        providerStorageExportInFlightID = provider.id
        defer { providerStorageExportInFlightID = nil }
        do {
            switch provider.kind {
            case .openAI:
                let consent = PinesOpenAIProviderStorageConsent(
                    isGranted: true,
                    sourceDescription: "Vault document \(item.title)",
                    destinationDescription: "OpenAI Files API for \(provider.displayName)",
                    byteCount: providerStorageByteCount
                )
                _ = try await appModel.uploadOpenAIVaultDocument(
                    providerID: provider.id,
                    documentID: item.id,
                    consent: consent,
                    services: services
                )
            case .anthropic:
                let consent = PinesAnthropicProviderStorageConsent(
                    isGranted: true,
                    sourceDescription: "Vault document \(item.title)",
                    destinationDescription: "Anthropic Files API for \(provider.displayName)",
                    byteCount: providerStorageByteCount
                )
                _ = try await appModel.uploadAnthropicVaultDocument(
                    providerID: provider.id,
                    documentID: item.id,
                    consent: consent,
                    services: services
                )
            default:
                throw InferenceError.invalidRequest("\(provider.kind.rawValue) Vault export is not supported.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private var activityRows: [(title: String, image: String)] {
        let activeJob = vaultState.vaultEmbeddingJobs.first { $0.documentID == item.id }
        var rows = [(String, String)]()
        if let activeJob {
            rows.append(("\(activeJob.status.rawValue.capitalized): \(activeJob.processedChunks)/\(activeJob.totalChunks) chunks", "waveform.path.ecg"))
        }
        rows.append(("\(vaultState.vaultRetrievalEvents.count) recent retrieval events", "magnifyingglass"))
        return rows.map { (title: $0.0, image: $0.1) }
    }
}

private struct VaultSourcePreview: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @State private var decodedImage: UIImage?
    @State private var imageDecodeFailed = false
    let item: PinesVaultItemPreview
    let sourceData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            Label("File preview", systemImage: item.kind.systemImage)
                .font(theme.typography.section)

            if let data = sourceData {
                preview(for: data)
            } else {
                PinesEmptyState(title: "Preview unavailable", detail: "Extracted content appears below.", systemImage: "eye.slash")
            }
        }
        .pinesSurface(.panel)
    }

    @ViewBuilder
    private func preview(for data: Data) -> some View {
        switch item.kind {
        case .image:
            #if canImport(UIKit)
            if let decodedImage {
                Image(uiImage: decodedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .frame(maxWidth: .infinity)
                    .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
            } else if imageDecodeFailed {
                PinesEmptyState(
                    title: "Preview unavailable",
                    detail: "The stored image could not be decoded.",
                    systemImage: "photo.badge.exclamationmark"
                )
            } else {
                ProgressView("Preparing preview")
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .task(id: item.sourceRevision) {
                        await decodeImage(data)
                    }
            }
            #else
            fallbackTextPreview(data)
            #endif
        case .note, .document, .key:
            fallbackTextPreview(data)
        }
    }

    private func fallbackTextPreview(_ data: Data) -> some View {
        let text = String(data: data.prefix(48_000), encoding: .utf8)
        return ScrollView {
            Text(text ?? "\(data.count) bytes")
                .font(.system(.caption, design: text == nil ? .default : .monospaced))
                .foregroundStyle(theme.colors.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.small)
        }
        .frame(maxHeight: 320)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
    }

    @MainActor
    private func decodeImage(_ data: Data) async {
        imageDecodeFailed = false
        do {
            let decoded = try await PinesImagePipeline.shared.image(
                for: .data(
                    data,
                    identity: "vault:\(item.id.uuidString)",
                    revision: item.sourceRevision
                ),
                targetSize: CGSize(width: 720, height: 320),
                scale: displayScale
            )
            try Task.checkCancellation()
            decodedImage = UIImage(cgImage: decoded.cgImage, scale: decoded.scale, orientation: .up)
        } catch is CancellationError {
            return
        } catch {
            decodedImage = nil
            imageDecodeFailed = true
        }
    }
}

private extension String {
    var providerStorageCloudStatus: PinesCloudStatus {
        switch lowercased().replacingOccurrences(of: "_", with: "") {
        case "completed", "complete", "processed", "closed":
            .complete
        case "failed", "error":
            .failed
        case "cancelled", "canceled", "expired", "deleted":
            .warning(capitalized)
        case "queued", "pending", "created", "validating":
            .pending
        case "inprogress", "running", "active", "finalizing", "uploaded":
            .running
        case "requiresaction", "cancelling", "deleting", "closing":
            .needsValidation
        default:
            .custom(isEmpty ? "Unknown" : self, .neutral)
        }
    }
}
