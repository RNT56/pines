import SwiftUI
import PinesCore

struct SettingsView: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @State private var selectedSectionID: PinesSettingsSection.ID?

    private var selectedSection: PinesSettingsSection? {
        guard let selectedSectionID else {
            return appModel.settingsSections.first
        }

        return appModel.settingsSections.first { $0.id == selectedSectionID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSectionID) {
                Section("Preferences") {
                    ForEach(appModel.settingsSections) { section in
                        SettingsSectionRow(section: section)
                            .tag(section.id)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedSectionID = selectedSectionID ?? appModel.settingsSections.first?.id
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.secondaryBackground)
        } detail: {
            if let selectedSection {
                SettingsDetailView(
                    section: selectedSection,
                    executionMode: appModel.executionMode,
                    storeConfiguration: appModel.storeConfiguration,
                    selectedThemeTemplate: $appModel.selectedThemeTemplate,
                    interfaceMode: $appModel.interfaceMode
                )
            } else {
                PinesEmptyState(
                    title: "No settings",
                    detail: "Runtime preferences appear when the app model is loaded.",
                    systemImage: "gearshape"
                )
            }
        }
    }
}

private struct SettingsSectionRow: View {
    @Environment(\.pinesTheme) private var theme
    let section: PinesSettingsSection

    var body: some View {
        HStack(spacing: theme.spacing.medium) {
            Image(systemName: section.systemImage)
                .font(theme.typography.section)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 34, height: 34)
                .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                Text(section.title)
                    .font(theme.typography.headline)

                Text(section.subtitle)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct SettingsDetailView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    let section: PinesSettingsSection
    let executionMode: AgentExecutionMode
    let storeConfiguration: LocalStoreConfiguration
    @Binding var selectedThemeTemplate: PinesThemeTemplate
    @Binding var interfaceMode: PinesInterfaceMode
    @State private var localInference = true
    @State private var privateSync = false
    @State private var approvalRequired = true

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    Label(section.title, systemImage: section.systemImage)
                        .font(theme.typography.title)

                    Text(section.subtitle)
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .padding(.vertical, theme.spacing.xsmall)
            }

            Section("Defaults") {
                ForEach(section.rows) { row in
                    HStack(spacing: theme.spacing.medium) {
                        Image(systemName: row.systemImage)
                            .foregroundStyle(theme.colors.accent)
                            .frame(width: 24)

                        Text(row.title)

                        Spacer()

                        Text(row.detail)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }

            Section("Design template") {
                Picker("Interface mode", selection: $interfaceMode) {
                    ForEach(PinesInterfaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: theme.spacing.small)], spacing: theme.spacing.small) {
                    ForEach(PinesThemeTemplate.allCases) { template in
                        Button {
                            withAnimation(theme.motion.standard) {
                                selectedThemeTemplate = template
                            }
                        } label: {
                            PinesThemePreviewCard(
                                template: template,
                                isSelected: selectedThemeTemplate == template
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, theme.spacing.xsmall)
            }

            Section("Core") {
                LabeledContent("Execution mode", value: executionMode.title)
                LabeledContent("Store", value: storeConfiguration.databaseFileName)
                LabeledContent("Protection", value: storeConfiguration.dataProtection.title)
            }

            Section("Architecture health") {
                ForEach(services.serviceHealth) { service in
                    HStack(spacing: theme.spacing.medium) {
                        Circle()
                            .fill(service.readiness.tint(in: theme))
                            .frame(width: 9, height: 9)

                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            Text(service.name)
                                .font(theme.typography.headline)

                            Text(service.summary)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                        }

                        Spacer()

                        Text(service.readiness.title)
                            .font(theme.typography.caption)
                            .foregroundStyle(service.readiness.tint(in: theme))
                    }
                }
            }

            Section("Runtime") {
                Toggle("Local inference", isOn: $localInference)
                Toggle("Private iCloud sync", isOn: $privateSync)
                Toggle("Require tool approval", isOn: $approvalRequired)
            }
        }
        .navigationTitle(section.title)
        .pinesInlineNavigationTitle()
        .scrollContentBackground(.hidden)
        .pinesAppBackground()
    }
}

private extension ServiceReadiness {
    var title: String {
        switch self {
        case .unavailable:
            "Unavailable"
        case .booting:
            "Booting"
        case .ready:
            "Ready"
        case .degraded:
            "Degraded"
        case .requiresUserAction:
            "Action"
        }
    }

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .ready:
            theme.colors.success
        case .booting:
            theme.colors.info
        case .degraded, .requiresUserAction:
            theme.colors.warning
        case .unavailable:
            theme.colors.danger
        }
    }
}

private extension AgentExecutionMode {
    var title: String {
        switch self {
        case .localOnly:
            "Local only"
        case .preferLocal:
            "Prefer local"
        case .cloudAllowed:
            "Cloud allowed"
        case .cloudRequired:
            "Cloud required"
        }
    }
}

private extension DataProtectionClass {
    var title: String {
        switch self {
        case .complete:
            "Complete"
        case .completeUntilFirstUserAuthentication:
            "After first unlock"
        }
    }
}
