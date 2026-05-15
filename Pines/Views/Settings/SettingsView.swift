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
    @State private var mcpName = "Local MCP"
    @State private var mcpEndpointURL = "https://"
    @State private var mcpAuthMode: MCPAuthMode = .none
    @State private var mcpBearerToken = ""
    @State private var mcpOAuthAuthorizationURL = ""
    @State private var mcpOAuthTokenURL = ""
    @State private var mcpOAuthClientID = ""
    @State private var mcpOAuthScopes = ""
    @State private var mcpOAuthResource = ""
    @State private var mcpEnabled = true
    @State private var mcpAllowInsecureLocalHTTP = false
    @State private var mcpEditingServerID: MCPServerID?
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
                let diagnostics = services.mlxRuntime.runtimeDiagnostics
                let memory = diagnostics.memoryCounters
                Toggle("Local inference", isOn: .constant(true))
                LabeledContent("KV cache", value: diagnostics.activeAlgorithm.title)
                if let preset = diagnostics.preset {
                    LabeledContent("Preset", value: preset.displayName)
                }
                if let requestedBackend = diagnostics.requestedBackend {
                    LabeledContent("Requested backend", value: requestedBackend.displayName)
                }
                if let activeBackend = diagnostics.activeBackend {
                    LabeledContent("Active backend", value: activeBackend.displayName)
                }
                LabeledContent(
                    "Metal codec",
                    value: diagnostics.metalCodecAvailable ? "Available" : "Unavailable"
                )
                LabeledContent(
                    "Metal attention",
                    value: diagnostics.metalAttentionAvailable ? "Available" : "Unavailable"
                )
                if let attentionPath = diagnostics.activeAttentionPath {
                    LabeledContent("Attention path", value: attentionPath.displayName)
                }
                if let performanceClass = diagnostics.devicePerformanceClass {
                    LabeledContent("Performance class", value: performanceClass.displayName)
                }
                if let kernelProfile = diagnostics.metalKernelProfile {
                    LabeledContent("Kernel variant", value: kernelProfile.displayName)
                }
                if let selfTest = diagnostics.metalSelfTestStatus {
                    LabeledContent("MLX self-test", value: selfTest.displayName)
                }
                if let policy = diagnostics.turboQuantOptimizationPolicy {
                    LabeledContent("Optimization policy", value: policy.displayName)
                }
                if let rawFallbackAllocated = diagnostics.rawFallbackAllocated {
                    LabeledContent("Raw KV fallback", value: rawFallbackAllocated ? "Allocated" : "Not allocated")
                }
                if diagnostics.thermalDownshiftActive == true {
                    LabeledContent("Thermal downshift", value: "Active")
                }
                if let unsupportedShape = diagnostics.lastUnsupportedAttentionShape {
                    LabeledContent("Unsupported shape", value: unsupportedShape)
                }
                if let hardware = memory.hardwareModelIdentifier {
                    LabeledContent("Device identifier", value: hardware)
                }
                if let metalArchitecture = memory.metalArchitectureName {
                    LabeledContent("Metal architecture", value: metalArchitecture)
                }
                if let workingSet = memory.metalRecommendedWorkingSetBytes {
                    LabeledContent("MLX working set", value: ByteCountFormatter.string(fromByteCount: workingSet, countStyle: .memory))
                }
                if let lowPower = memory.lowPowerModeEnabled {
                    LabeledContent("Low Power Mode", value: lowPower ? "On" : "Off")
                }
                if let contextTokens = memory.recommendedContextTokens {
                    LabeledContent("Context window", value: "\(contextTokens.formatted()) tokens")
                }
                if let physicalMemory = memory.physicalMemoryBytes {
                    LabeledContent("Device memory", value: ByteCountFormatter.string(fromByteCount: physicalMemory, countStyle: .memory))
                }
                if let availableMemory = memory.availableMemoryBytes {
                    LabeledContent("Available memory", value: ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory))
                }
                if let thermalState = memory.thermalState {
                    LabeledContent("Thermal state", value: thermalState.capitalized)
                }
                if let fallback = diagnostics.activeFallbackReason {
                    LabeledContent("Fallback", value: fallback)
                }
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

            Section("MCP Servers") {
                HStack {
                    Text(mcpEditingServerID == nil ? "New server" : "Editing server")
                        .font(theme.typography.headline)
                    Spacer()
                    Button {
                        resetMCPForm()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                TextField("Display name", text: $mcpName)
                TextField("Streamable HTTP endpoint", text: $mcpEndpointURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Authentication", selection: $mcpAuthMode) {
                    ForEach(MCPAuthMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if mcpAuthMode == .bearerToken {
                    SecureField("Bearer token", text: $mcpBearerToken)
                        .textContentType(.password)
                }
                if mcpAuthMode == .oauthPKCE {
                    TextField("Authorization URL", text: $mcpOAuthAuthorizationURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Token URL", text: $mcpOAuthTokenURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Client ID", text: $mcpOAuthClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Scopes", text: $mcpOAuthScopes)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Resource", text: $mcpOAuthResource)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Toggle("Enable server", isOn: $mcpEnabled)
                Toggle("Allow insecure local HTTP", isOn: $mcpAllowInsecureLocalHTTP)

                HStack {
                    Button {
                        Task {
                            await appModel.saveMCPServer(
                                existingID: mcpEditingServerID,
                                displayName: mcpName,
                                endpointURLString: mcpEndpointURL,
                                authMode: mcpAuthMode,
                                bearerToken: mcpBearerToken,
                                oauthAuthorizationURLString: mcpOAuthAuthorizationURL,
                                oauthTokenURLString: mcpOAuthTokenURL,
                                oauthClientID: mcpOAuthClientID,
                                oauthScopes: mcpOAuthScopes,
                                oauthResource: mcpOAuthResource,
                                enabled: mcpEnabled,
                                allowInsecureLocalHTTP: mcpAllowInsecureLocalHTTP,
                                services: services
                            )
                            mcpBearerToken = ""
                        }
                    } label: {
                        Label("Save and discover tools", systemImage: "point.3.connected.trianglepath.dotted")
                    }

                    Button {
                        Task {
                            if let discovery = await appModel.discoverMCPOAuth(
                                endpointURLString: mcpEndpointURL,
                                allowInsecureLocalHTTP: mcpAllowInsecureLocalHTTP,
                                services: services
                            ) {
                                mcpAuthMode = .oauthPKCE
                                mcpOAuthAuthorizationURL = discovery.authorizationURL.absoluteString
                                mcpOAuthTokenURL = discovery.tokenURL.absoluteString
                                mcpOAuthClientID = discovery.clientID
                                mcpOAuthScopes = discovery.scopes ?? ""
                                mcpOAuthResource = discovery.resource
                            }
                        }
                    } label: {
                        Label("Discover OAuth", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(mcpEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if appModel.mcpServers.isEmpty {
                    Text("No MCP servers configured.")
                        .foregroundStyle(theme.colors.secondaryText)
                } else {
                    ForEach(appModel.mcpServers) { server in
                        VStack(alignment: .leading, spacing: theme.spacing.small) {
                            HStack {
                                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                    Text(server.displayName)
                                        .font(theme.typography.headline)
                                    Text(server.endpointURL.absoluteString)
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(server.status.rawValue)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(server.status == .ready ? theme.colors.success : theme.colors.warning)
                                Button {
                                    Task {
                                        await appModel.refreshMCPServer(server, services: services)
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Refresh \(server.displayName)")
                                Button {
                                    loadMCPServer(server)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Edit \(server.displayName)")
                                if server.authMode == .oauthPKCE {
                                    Button {
                                        Task {
                                            await appModel.connectMCPOAuth(server, services: services)
                                        }
                                    } label: {
                                        Image(systemName: "person.badge.key")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Connect OAuth for \(server.displayName)")
                                    Button {
                                        Task {
                                            await appModel.disconnectMCPOAuth(server, services: services)
                                        }
                                    } label: {
                                        Image(systemName: "person.badge.minus")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Disconnect OAuth for \(server.displayName)")
                                }
                                Button(role: .destructive) {
                                    Task {
                                        await appModel.deleteMCPServer(server, services: services)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete \(server.displayName)")
                            }
                            if let error = server.lastError {
                                Text(error)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.danger)
                            }
                            LabeledContent("Auth", value: server.authMode.title)
                            if let connectedAt = server.lastConnectedAt {
                                LabeledContent("Last connected", value: connectedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            ForEach(appModel.mcpTools.filter { $0.serverID == server.id }) { tool in
                                Toggle(isOn: Binding(
                                    get: { tool.enabled },
                                    set: { value in
                                        Task {
                                            await appModel.setMCPToolEnabled(tool, enabled: value, services: services)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                        Text(tool.displayName)
                                        Text(tool.namespacedName)
                                            .font(theme.typography.caption)
                                            .foregroundStyle(theme.colors.secondaryText)
                                        Text(tool.description)
                                            .font(theme.typography.caption)
                                            .foregroundStyle(theme.colors.tertiaryText)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, theme.spacing.xsmall)
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

    private func loadMCPServer(_ server: MCPServerConfiguration) {
        mcpEditingServerID = server.id
        mcpName = server.displayName
        mcpEndpointURL = server.endpointURL.absoluteString
        mcpAuthMode = server.authMode
        mcpBearerToken = ""
        mcpOAuthAuthorizationURL = server.oauthAuthorizationURL?.absoluteString ?? ""
        mcpOAuthTokenURL = server.oauthTokenURL?.absoluteString ?? ""
        mcpOAuthClientID = server.oauthClientID ?? ""
        mcpOAuthScopes = server.oauthScopes ?? ""
        mcpOAuthResource = server.oauthResource ?? ""
        mcpEnabled = server.enabled
        mcpAllowInsecureLocalHTTP = server.allowInsecureLocalHTTP
    }

    private func resetMCPForm() {
        mcpEditingServerID = nil
        mcpName = "Local MCP"
        mcpEndpointURL = "https://"
        mcpAuthMode = .none
        mcpBearerToken = ""
        mcpOAuthAuthorizationURL = ""
        mcpOAuthTokenURL = ""
        mcpOAuthClientID = ""
        mcpOAuthScopes = ""
        mcpOAuthResource = ""
        mcpEnabled = true
        mcpAllowInsecureLocalHTTP = false
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

private extension QuantizationAlgorithm {
    var title: String {
        switch self {
        case .none:
            "None"
        case .mlxAffine:
            "MLX affine"
        case .turboQuant:
            "TurboQuant"
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

private extension MCPAuthMode {
    var title: String {
        switch self {
        case .none:
            "None"
        case .bearerToken:
            "Bearer token"
        case .oauthPKCE:
            "OAuth PKCE"
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
