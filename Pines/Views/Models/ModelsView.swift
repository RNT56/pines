import SwiftUI
import PinesCore

struct ModelsView: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @State private var selectedModelID: PinesModelPreview.ID?

    private var selectedModel: PinesModelPreview? {
        guard let selectedModelID else {
            return appModel.models.first
        }

        return appModel.models.first { $0.id == selectedModelID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedModelID) {
                Section("Library") {
                    ForEach(appModel.models) { model in
                        ModelRow(model: model)
                            .tag(model.id)
                    }
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .accessibilityLabel("Download model")

                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add model")
                }
            }
            .onAppear {
                selectedModelID = selectedModelID ?? appModel.models.first?.id
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.secondaryBackground)
        } detail: {
            if let selectedModel {
                ModelDetailView(model: selectedModel)
            } else {
                PinesEmptyState(
                    title: "No models",
                    detail: "Add a local MLX model to enable inference.",
                    systemImage: "cpu"
                )
            }
        }
    }
}

private struct ModelRow: View {
    @Environment(\.pinesTheme) private var theme
    let model: PinesModelPreview

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            HStack {
                Text(model.name)
                    .font(theme.typography.headline)
                    .lineLimit(1)

                Spacer(minLength: theme.spacing.small)

                Image(systemName: model.status.systemImage)
                    .foregroundStyle(model.status == .ready ? theme.colors.success : theme.colors.warning)
            }

            Text("\(model.family) - \(model.footprint) - \(model.contextWindow)")
                .font(theme.typography.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct ModelDetailView: View {
    @Environment(\.pinesTheme) private var theme
    let model: PinesModelPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                PinesSectionHeader(model.name, subtitle: "\(model.family) model for \(model.runtime)")

                HStack(spacing: theme.spacing.small) {
                    PinesMetricPill(title: model.status.title, systemImage: model.status.systemImage)
                    PinesMetricPill(title: model.footprint, systemImage: "externaldrive")
                    PinesMetricPill(title: model.contextWindow, systemImage: "text.word.spacing")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.82)

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    HStack {
                        Text("Readiness")
                            .font(theme.typography.section)
                        Spacer()
                        Text("\(Int(model.readiness * 100))%")
                            .font(theme.typography.code)
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    ProgressView(value: model.readiness)
                        .tint(theme.colors.accent)

                    Text("Runtime: \(model.runtime)")
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Profile: \(model.runtimeProfile.name)")
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Repository: \(model.install.repository)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.tertiaryText)
                        .lineLimit(1)
                }
                .pinesPanel()

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    Text("Capabilities")
                        .font(theme.typography.section)

                    FlowPills(items: model.capabilities)
                }
                .pinesPanel()
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.name)
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
    }
}

private struct FlowPills: View {
    @Environment(\.pinesTheme) private var theme
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: theme.spacing.small)], alignment: .leading, spacing: theme.spacing.small) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(theme.typography.callout.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing.small)
                    .padding(.vertical, theme.spacing.xsmall)
                    .background(theme.colors.elevatedSurface, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            }
        }
    }
}
