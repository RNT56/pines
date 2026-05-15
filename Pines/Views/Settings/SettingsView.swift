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
    @EnvironmentObject private var appModel: PinesAppModel
    let section: PinesSettingsSection
    let executionMode: AgentExecutionMode
    let storeConfiguration: LocalStoreConfiguration
    @Binding var selectedThemeTemplate: PinesThemeTemplate
    @Binding var interfaceMode: PinesInterfaceMode
    @State private var providerKind: CloudProviderKind = .openAICompatible
    @State private var providerName = "OpenAI"
    @State private var providerBaseURL = "https://api.openai.com/v1"
    @State private var providerModelID = "gpt-4.1-mini"
    @State private var providerAPIKey = ""
    @State private var providerEnabled = false
    @State private var huggingFaceToken = ""
    @State private var braveSearchKey = ""

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
                .onChange(of: interfaceMode) { _, _ in
                    Task {
                        await appModel.saveSettings(services: services)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: theme.spacing.small)], spacing: theme.spacing.small) {
                    ForEach(PinesThemeTemplate.allCases) { template in
                        Button {
                            withAnimation(theme.motion.standard) {
                                selectedThemeTemplate = template
                            }
                            Task {
                                await appModel.saveSettings(services: services)
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
                Picker("Execution mode", selection: $appModel.executionMode) {
                    ForEach(AgentExecutionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .onChange(of: appModel.executionMode) { _, _ in
                    Task {
                        await appModel.saveSettings(services: services)
                    }
                }

                LabeledContent("Store", value: appModel.storeConfiguration.databaseFileName)
                LabeledContent("Protection", value: appModel.storeConfiguration.dataProtection.title)
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

            Section("Audit") {
                if appModel.auditEvents.isEmpty {
                    Text("No audit events recorded.")
                        .foregroundStyle(theme.colors.secondaryText)
                } else {
                    ForEach(appModel.auditEvents.prefix(8)) { event in
                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                            HStack {
                                Text(event.category.rawValue)
                                    .font(theme.typography.caption.weight(.semibold))
                                    .foregroundStyle(theme.colors.accent)
                                Spacer()
                                Text(event.createdAt, style: .time)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.tertiaryText)
                            }
                            Text(event.summary)
                                .font(theme.typography.callout)
                            if let payload = event.redactedPayload {
                                Text(payload)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.secondaryText)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }

            Section("Runtime") {
                Toggle("Local inference", isOn: .constant(true))
                Toggle("Private iCloud sync", isOn: Binding(
                    get: { appModel.storeConfiguration.iCloudSyncEnabled },
                    set: { value in
                        appModel.storeConfiguration.iCloudSyncEnabled = value
                        Task {
                            await appModel.saveSettings(services: services)
                        }
                    }
                ))
                Toggle("Sync source documents", isOn: Binding(
                    get: { appModel.storeConfiguration.syncsSourceDocuments },
                    set: { value in
                        appModel.storeConfiguration.syncsSourceDocuments = value
                        Task {
                            await appModel.saveSettings(services: services)
                        }
                    }
                ))
                Toggle("Sync embeddings", isOn: Binding(
                    get: { appModel.storeConfiguration.syncsEmbeddings },
                    set: { value in
                        appModel.storeConfiguration.syncsEmbeddings = value
                        Task {
                            await appModel.saveSettings(services: services)
                        }
                    }
                ))
            }

            Section("Hugging Face") {
                LabeledContent("Hub token", value: appModel.huggingFaceCredentialStatus)
                SecureField("Access token", text: $huggingFaceToken)
                    .textContentType(.password)

                HStack {
                    Button {
                        Task {
                            await appModel.saveHuggingFaceToken(huggingFaceToken, services: services)
                            huggingFaceToken = ""
                        }
                    } label: {
                        Label("Save", systemImage: "key.fill")
                    }
                    .disabled(huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task {
                            await appModel.validateHuggingFaceToken(services: services)
                        }
                    } label: {
                        Label("Validate", systemImage: "checkmark.seal")
                    }

                    Button(role: .destructive) {
                        Task {
                            await appModel.deleteHuggingFaceToken(services: services)
                            huggingFaceToken = ""
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Section("Agent Tool Keys") {
                LabeledContent("Brave Search", value: appModel.braveSearchCredentialStatus)
                SecureField("Brave Search API key", text: $braveSearchKey)
                    .textContentType(.password)

                HStack {
                    Button {
                        Task {
                            await appModel.saveBraveSearchKey(braveSearchKey, services: services)
                            braveSearchKey = ""
                        }
                    } label: {
                        Label("Save", systemImage: "magnifyingglass.circle")
                    }
                    .disabled(braveSearchKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(role: .destructive) {
                        Task {
                            await appModel.saveBraveSearchKey("", services: services)
                            braveSearchKey = ""
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Section("Cloud BYOK") {
                Picker("Provider", selection: $providerKind) {
                    ForEach(CloudProviderKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .onChange(of: providerKind) { _, kind in
                    applyProviderDefaults(kind)
                }
                TextField("Display name", text: $providerName)
                TextField("Base URL", text: $providerBaseURL)
                TextField("Default model", text: $providerModelID)
                SecureField("API key", text: $providerAPIKey)
                Toggle("Enable for agents", isOn: $providerEnabled)

                Button {
                    Task {
                        await appModel.saveCloudProvider(
                            kind: providerKind,
                            displayName: providerName,
                            baseURLString: providerBaseURL,
                            defaultModelID: providerModelID,
                            apiKey: providerAPIKey,
                            enabledForAgents: providerEnabled,
                            services: services
                        )
                        providerAPIKey = ""
                    }
                } label: {
                    Label("Save and validate", systemImage: "key")
                }

                ForEach(appModel.cloudProviders) { provider in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(provider.displayName)
                            Text(provider.kind.title)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                        Spacer()
                        Text(provider.validationStatus.rawValue)
                            .font(theme.typography.caption)
                            .foregroundStyle(provider.validationStatus == .valid ? theme.colors.success : theme.colors.warning)
                        Button {
                            Task {
                                await appModel.validateCloudProvider(provider, services: services)
                            }
                        } label: {
                            Image(systemName: "checkmark.seal")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Validate \(provider.displayName)")

                        Button(role: .destructive) {
                            Task {
                                await appModel.deleteCloudProvider(provider, services: services)
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(provider.displayName)")
                    }
                }
            }
        }
        .navigationTitle(section.title)
        .pinesInlineNavigationTitle()
        .scrollContentBackground(.hidden)
        .pinesAppBackground()
    }

    private func applyProviderDefaults(_ kind: CloudProviderKind) {
        providerName = kind.defaultDisplayName
        providerBaseURL = kind.defaultBaseURL
        providerModelID = kind.defaultModelID
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

private extension CloudProviderKind {
    var title: String {
        switch self {
        case .openAICompatible:
            "OpenAI-compatible"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        case .openRouter:
            "OpenRouter"
        case .custom:
            "Custom"
        }
    }

    var defaultDisplayName: String {
        switch self {
        case .openAICompatible:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        case .openRouter:
            "OpenRouter"
        case .custom:
            "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAICompatible:
            "https://api.openai.com/v1"
        case .anthropic:
            "https://api.anthropic.com"
        case .gemini:
            "https://generativelanguage.googleapis.com"
        case .openRouter:
            "https://openrouter.ai/api/v1"
        case .custom:
            "https://"
        }
    }

    var defaultModelID: String {
        switch self {
        case .openAICompatible:
            "gpt-4.1-mini"
        case .anthropic:
            "claude-3-5-haiku-latest"
        case .gemini:
            "gemini-2.0-flash"
        case .openRouter:
            "openai/gpt-4.1-mini"
        case .custom:
            ""
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
