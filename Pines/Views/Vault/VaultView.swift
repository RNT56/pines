import SwiftUI
import PinesCore
import UniformTypeIdentifiers

struct VaultView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedItemID: PinesVaultItemPreview.ID?
    @State private var showingImporter = false

    private var selectedItem: PinesVaultItemPreview? {
        guard let selectedItemID else {
            return appModel.vaultItems.first
        }

        return appModel.vaultItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemID) {
                Section("Vault") {
                    ForEach(appModel.vaultItems) { item in
                        VaultItemRow(item: item)
                            .tag(item.id)
                    }
                }
            }
            .navigationTitle("Vault")
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
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search vault")
                }
            }
            .onAppear {
                selectedItemID = selectedItemID ?? appModel.vaultItems.first?.id
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
            .scrollContentBackground(.hidden)
            .background(theme.colors.secondaryBackground)
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
}

private struct VaultItemRow: View {
    @Environment(\.pinesTheme) private var theme
    let item: PinesVaultItemPreview

    var body: some View {
        HStack(spacing: theme.spacing.medium) {
            Image(systemName: item.kind.systemImage)
                .font(theme.typography.section)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 34, height: 34)
                .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                HStack {
                    Text(item.title)
                        .font(theme.typography.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: theme.spacing.small)

                    Text(item.updatedLabel)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.tertiaryText)
                }

                Text(item.detail)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct VaultDetailView: View {
    @Environment(\.pinesTheme) private var theme
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

                    Text("The selected item is ready for retrieval once the vault index is attached to the chat runtime.")
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let chunk = item.chunks.first {
                        Text("Indexed chunk: \(chunk.characterCount) characters")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.tertiaryText)
                    }
                }
                .pinesSurface(.elevated)

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    Text("Linked activity")
                        .font(theme.typography.section)

                    ForEach(0..<max(item.linkedThreads, 1), id: \.self) { index in
                        HStack {
                            Image(systemName: index == 0 ? "bubble.left" : "sparkles")
                                .foregroundStyle(theme.colors.info)
                                .frame(width: 26)

                            Text(index == 0 ? "Chat context prepared" : "Retrieval citation queued")
                                .font(theme.typography.callout)
                                .pinesFittingText()

                            Spacer()
                        }
                        .padding(.vertical, theme.spacing.xsmall)

                        if index < max(item.linkedThreads, 1) - 1 {
                            Divider()
                        }
                    }
                }
                .pinesSurface(.panel)
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.title)
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
    }
}
