import SwiftUI
import PinesCore
import UniformTypeIdentifiers

struct VaultView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedItemID: PinesVaultItemPreview.ID?
    @State private var showingImporter = false

    private var selectedItem: PinesVaultItemPreview? {
        guard let selectedItemID = selectedItemID ?? defaultItemID else {
            return nil
        }

        return appModel.vaultItems.first { $0.id == selectedItemID }
    }

    private var defaultItemID: PinesVaultItemPreview.ID? {
        shouldAutoSelectSidebarItem ? appModel.vaultItems.first?.id : nil
    }

    private var shouldAutoSelectSidebarItem: Bool {
        horizontalSizeClass != .compact
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemID) {
                VaultEmbeddingSetupSection()

                if !appModel.vaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Search results") {
                        ForEach(appModel.vaultSearchResults) { result in
                            NavigationLink(value: result.document.id) {
                                VaultSearchResultRow(result: result)
                            }
                            .pinesSidebarListRow()
                        }
                    }
                }

                Section("Vault") {
                    ForEach(appModel.vaultItems) { item in
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
                        appModel.isVaultSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search vault")
                }
            }
            .searchable(text: $appModel.vaultSearchQuery, isPresented: $appModel.isVaultSearchPresented, prompt: "Search vault")
            .onSubmit(of: .search) {
                Task { await appModel.searchVault(appModel.vaultSearchQuery, services: services) }
            }
            .onChange(of: appModel.vaultSearchQuery) { _, query in
                guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                appModel.vaultSearchResults = []
            }
            .onAppear(perform: selectDefaultItemIfNeeded)
            .onChange(of: horizontalSizeClass) { _, _ in
                selectDefaultItemIfNeeded()
            }
            .onChange(of: appModel.vaultItems) { _, items in
                if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                    self.selectedItemID = nil
                }
                selectDefaultItemIfNeeded()
            }
            .onChange(of: selectedItemID) { _, _ in
                haptics.play(.navigationSelected)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    Task {
                        await appModel.importVaultFile(url, services: services)
                    }
                }
            }
            .pinesSidebarListChrome()
        } detail: {
            if let selectedItem {
                VaultDetailView(item: selectedItem)
            } else {
                PinesEmptyState(
                    title: "Vault empty",
                    detail: "Private notes, documents, keys, and image references appear here.",
                    systemImage: "shippingbox"
                )
            }
        }
    }

    private func selectDefaultItemIfNeeded() {
        guard shouldAutoSelectSidebarItem else { return }
        selectedItemID = selectedItemID ?? appModel.vaultItems.first?.id
    }
}

private struct VaultEmbeddingSetupSection: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: PinesAppModel

    private var activeProfile: VaultEmbeddingProfile? {
        appModel.vaultEmbeddingProfiles.first(where: \.isActive)
    }

    private var selectableProfiles: [VaultEmbeddingProfile] {
        appModel.vaultEmbeddingProfiles.filter { $0.status != .failed }
    }

    var body: some View {
        Section("Embeddings") {
            if let activeProfile {
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    Label(activeProfile.displayName, systemImage: activeProfile.kind.isCloud ? "cloud.fill" : "cpu")
                        .font(theme.typography.callout.weight(.semibold))
                        .pinesFittingText()
                    Text("\(activeProfile.modelID.rawValue) · \(activeProfile.dimensions > 0 ? "\(activeProfile.dimensions)d" : "native dimensions")")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(2)
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
                    if appModel.isVaultReindexing {
                        appModel.cancelVaultReindex()
                    } else {
                        Task { await appModel.reindexVault(services: services) }
                    }
                } label: {
                    Label(
                        appModel.isVaultReindexing ? "Cancel reindex" : "Reindex vault",
                        systemImage: appModel.isVaultReindexing ? "xmark.circle" : "arrow.triangle.2.circlepath"
                    )
                }

                if let activeJob = appModel.vaultEmbeddingJobs.first(where: { $0.profileID == activeProfile.id && $0.status == .running }) {
                    Text("\(activeJob.processedChunks)/\(activeJob.totalChunks) chunks embedded")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    Label("Semantic search disabled", systemImage: "exclamationmark.triangle")
                        .font(theme.typography.callout.weight(.semibold))
                    Text("Install a local embedding model or add cloud credentials to enable vector search. Text search still works.")
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
                        Label("OpenAI keys", systemImage: "key")
                    }
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        Label("Gemini keys", systemImage: "key")
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
    let item: PinesVaultItemPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                PinesSectionHeader(item.title, subtitle: item.detail)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: theme.spacing.small)], alignment: .leading, spacing: theme.spacing.small) {
                    PinesMetricPill(title: item.kind.title, systemImage: item.kind.systemImage)
                    PinesMetricPill(title: item.sensitivity.title, systemImage: item.sensitivity.systemImage, tint: item.sensitivity == .locked ? theme.colors.warning : theme.colors.accent)
                    PinesMetricPill(title: "\(item.linkedThreads) links", systemImage: "link")
                }

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    Label("Private context", systemImage: "lock.shield")
                        .font(theme.typography.section)

                    Text(indexSummary)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(item.chunks.prefix(4)) { chunk in
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            Text("Chunk \(chunk.ordinal + 1) · \(chunk.characterCount) characters")
                                .font(theme.typography.caption.weight(.semibold))
                                .foregroundStyle(theme.colors.tertiaryText)
                            Text(chunk.text)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(5)
                        }
                        .padding(.vertical, theme.spacing.xsmall)
                    }
                }
                .pinesSurface(.elevated)

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
        .pinesExpressiveScrollHaptics()
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
    }

    private var indexSummary: String {
        if let active = appModel.vaultEmbeddingProfiles.first(where: \.isActive) {
            return "\(item.activeProfileEmbeddedChunks)/\(item.activeProfileTotalChunks) chunks are embedded with \(active.displayName). Text search covers all chunks."
        }
        return "\(item.chunks.count) chunks are available for text search. Add an embedding provider for semantic retrieval."
    }

    private var activityRows: [(title: String, image: String)] {
        let activeJob = appModel.vaultEmbeddingJobs.first { $0.documentID == item.id }
        var rows = [(String, String)]()
        if let activeJob {
            rows.append(("\(activeJob.status.rawValue.capitalized): \(activeJob.processedChunks)/\(activeJob.totalChunks) chunks", "waveform.path.ecg"))
        }
        rows.append(("\(appModel.vaultRetrievalEvents.count) recent retrieval events", "magnifyingglass"))
        return rows.map { (title: $0.0, image: $0.1) }
    }
}
