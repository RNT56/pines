import SwiftUI
import PinesCore

struct SettingsView: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
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
                Section("Settings") {
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
            .onChange(of: selectedSectionID) { _, _ in
                haptics.play(.navigationSelected)
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
                    .pinesFittingText()

                Text(section.subtitle)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
        }
        .padding(.vertical, theme.spacing.xsmall)
    }
}

private struct SettingsDetailView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
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
    @State private var mcpResourcesEnabled = false
    @State private var mcpPromptsEnabled = false
    @State private var mcpSamplingEnabled = false
    @State private var mcpBYOKSamplingEnabled = false
    @State private var mcpSubscriptionsEnabled = false
    @State private var mcpMaxSamplingRequests = 3
    @State private var mcpEditingServerID: MCPServerID?
    @State private var mcpResourcePreviews: [String: String] = [:]
    @State private var mcpPromptArguments: [String: String] = [:]
    @State private var huggingFaceToken = ""
    @State private var braveSearchKey = ""

    private var iCloudSyncAvailable: Bool {
        services.cloudKitSyncService != nil
    }

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

            Section("At a glance") {
                ForEach(section.rows) { row in
                    HStack(spacing: theme.spacing.medium) {
                        Image(systemName: row.systemImage)
                            .foregroundStyle(theme.colors.accent)
                            .frame(width: 24)

                        Text(row.title)

                        Spacer()

                        Text(row.detail)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
            }

            if section.destination == .design {
                Section("Appearance") {
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

                Section("Haptics") {
                    Picker("Feedback", selection: $haptics.mode) {
                        ForEach(PinesHapticMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: haptics.mode) { _, newMode in
                        if newMode != .off {
                            haptics.play(.primaryAction)
                        }
                    }

                    Text(haptics.mode.subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }

            if section.destination == .inference {
                Section("Execution") {
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

                    Text("Controls how Pines routes chat work between local MLX inference and configured cloud providers.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }

            if section.destination == .system {
                Section("Architecture health") {
                    ForEach(services.serviceHealth) { service in
                        HStack(spacing: theme.spacing.medium) {
                            PinesStatusIndicator(
                                color: service.readiness.tint(in: theme),
                                isActive: service.readiness == .booting,
                                size: 9
                            )

                            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                Text(service.name)
                                    .font(theme.typography.headline)
                                    .pinesFittingText()

                                Text(service.summary)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.secondaryText)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.86)
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
            }

            if section.destination == .inference {
                Section("Runtime diagnostics") {
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
                    .pinesButtonStyle(.primary)

                    Button {
                        Task {
                            await appModel.validateHuggingFaceToken(services: services)
                        }
                    } label: {
                        Label("Validate", systemImage: "checkmark.seal")
                    }
                    .pinesButtonStyle(.secondary)

                    Button(role: .destructive) {
                        Task {
                            await appModel.deleteHuggingFaceToken(services: services)
                            huggingFaceToken = ""
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .pinesButtonStyle(.destructive)
                }
            }
            }

            if section.destination == .tools {
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
                    .pinesButtonStyle(.primary)

                    Button(role: .destructive) {
                        Task {
                            await appModel.saveBraveSearchKey("", services: services)
                            braveSearchKey = ""
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .pinesButtonStyle(.destructive)
                }
            }

            }

            if section.destination == .privacy {
                Section("Storage and Sync") {
                    LabeledContent("Store", value: appModel.storeConfiguration.databaseFileName)
                    LabeledContent("Protection", value: appModel.storeConfiguration.dataProtection.title)
                    Toggle("Private iCloud sync", isOn: Binding(
                        get: { iCloudSyncAvailable && appModel.storeConfiguration.iCloudSyncEnabled },
                        set: { value in
                            appModel.storeConfiguration.iCloudSyncEnabled = iCloudSyncAvailable && value
                            Task {
                                await appModel.saveSettings(services: services)
                            }
                        }
                    ))
                    .disabled(!iCloudSyncAvailable)
                    Toggle("Sync source documents", isOn: Binding(
                        get: { appModel.storeConfiguration.syncsSourceDocuments },
                        set: { value in
                            appModel.storeConfiguration.syncsSourceDocuments = value
                            Task {
                                await appModel.saveSettings(services: services)
                            }
                        }
                    ))
                    .disabled(!iCloudSyncAvailable || !appModel.storeConfiguration.iCloudSyncEnabled)
                    Toggle("Sync embeddings", isOn: Binding(
                        get: { appModel.storeConfiguration.syncsEmbeddings },
                        set: { value in
                            appModel.storeConfiguration.syncsEmbeddings = value
                            Task {
                                await appModel.saveSettings(services: services)
                            }
                        }
                    ))
                    .disabled(!iCloudSyncAvailable || !appModel.storeConfiguration.iCloudSyncEnabled)
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
                .pinesButtonStyle(.primary)

                ForEach(appModel.cloudProviders) { provider in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(provider.displayName)
                                .pinesFittingText()
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
                        .accessibilityLabel("Validate \(provider.displayName)")
                        .pinesButtonStyle(.icon)

                        Button(role: .destructive) {
                            Task {
                                await appModel.deleteCloudProvider(provider, services: services)
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete \(provider.displayName)")
                        .pinesButtonStyle(.icon)
                    }
                }
            }
            }

            if section.destination == .tools {
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
                    .pinesButtonStyle(.secondary)
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
                Toggle("Resources", isOn: $mcpResourcesEnabled)
                Toggle("Prompts", isOn: $mcpPromptsEnabled)
                Toggle("Sampling", isOn: $mcpSamplingEnabled)
                Toggle("BYOK sampling", isOn: $mcpBYOKSamplingEnabled)
                    .disabled(!mcpSamplingEnabled)
                Toggle("Resource subscriptions", isOn: $mcpSubscriptionsEnabled)
                    .disabled(!mcpResourcesEnabled)
                Stepper("Sampling requests per session: \(mcpMaxSamplingRequests)", value: $mcpMaxSamplingRequests, in: 0...20)
                    .disabled(!mcpSamplingEnabled)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: theme.spacing.small)], spacing: theme.spacing.small) {
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
                                resourcesEnabled: mcpResourcesEnabled,
                                promptsEnabled: mcpPromptsEnabled,
                                samplingEnabled: mcpSamplingEnabled,
                                byokSamplingEnabled: mcpBYOKSamplingEnabled,
                                subscriptionsEnabled: mcpSubscriptionsEnabled,
                                maxSamplingRequestsPerSession: mcpMaxSamplingRequests,
                                enabled: mcpEnabled,
                                allowInsecureLocalHTTP: mcpAllowInsecureLocalHTTP,
                                services: services
                            )
                            mcpBearerToken = ""
                        }
                    } label: {
                        Label("Save and discover tools", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .pinesButtonStyle(.primary, fillWidth: true)

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
                    .pinesButtonStyle(.secondary, fillWidth: true)
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
                                        .pinesFittingText()
                                    Text(server.endpointURL.absoluteString)
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)
                                }
                                Spacer()
                                Text(server.status.rawValue)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(server.status == .ready ? theme.colors.success : theme.colors.warning)
                                    .pinesFittingText()
                                Button {
                                    Task {
                                        await appModel.refreshMCPServer(server, services: services)
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .accessibilityLabel("Refresh \(server.displayName)")
                                .pinesButtonStyle(.icon)
                                Button {
                                    loadMCPServer(server)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .accessibilityLabel("Edit \(server.displayName)")
                                .pinesButtonStyle(.icon)
                                if server.authMode == .oauthPKCE {
                                    Button {
                                        Task {
                                            await appModel.connectMCPOAuth(server, services: services)
                                        }
                                    } label: {
                                        Image(systemName: "person.badge.key")
                                    }
                                    .accessibilityLabel("Connect OAuth for \(server.displayName)")
                                    .pinesButtonStyle(.icon)
                                    Button {
                                        Task {
                                            await appModel.disconnectMCPOAuth(server, services: services)
                                        }
                                    } label: {
                                        Image(systemName: "person.badge.minus")
                                    }
                                    .accessibilityLabel("Disconnect OAuth for \(server.displayName)")
                                    .pinesButtonStyle(.icon)
                                }
                                Button(role: .destructive) {
                                    Task {
                                        await appModel.deleteMCPServer(server, services: services)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete \(server.displayName)")
                                .pinesButtonStyle(.icon)
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
                            LabeledContent(
                                "Capabilities",
                                value: server.enabledCapabilityTitles.joined(separator: ", ").nilIfEmpty ?? "Tools only"
                            )
                            DisclosureGroup("Tools") {
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
                            DisclosureGroup("Resources") {
                                Button {
                                    Task {
                                        await appModel.refreshMCPResources(server, services: services)
                                    }
                                } label: {
                                    Label("Refresh resources", systemImage: "arrow.clockwise")
                                }
                                .pinesButtonStyle(.secondary)
                                ForEach(appModel.mcpResources.filter { $0.serverID == server.id }) { resource in
                                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                        Text(resource.title ?? resource.name)
                                        Text(resource.uri)
                                            .font(theme.typography.caption)
                                            .foregroundStyle(theme.colors.secondaryText)
                                            .lineLimit(1)
                                        Button {
                                            Task {
                                                if let preview = await appModel.previewMCPResource(resource, services: services) {
                                                    mcpResourcePreviews[resource.uri] = preview
                                                }
                                            }
                                        } label: {
                                            Label("Preview", systemImage: "doc.text.magnifyingglass")
                                        }
                                        .pinesButtonStyle(.secondary)
                                        if let preview = mcpResourcePreviews[resource.uri] {
                                            Text(preview)
                                                .font(theme.typography.caption)
                                                .foregroundStyle(theme.colors.secondaryText)
                                                .lineLimit(8)
                                                .textSelection(.enabled)
                                        }
                                        HStack {
                                            Toggle("Attach to chat context", isOn: Binding(
                                                get: { resource.selectedForContext },
                                                set: { value in
                                                    Task {
                                                        await appModel.setMCPResourceSelected(resource, selected: value, services: services)
                                                    }
                                                }
                                            ))
                                            if server.subscriptionsEnabled {
                                                Toggle("Subscribe", isOn: Binding(
                                                    get: { resource.subscribed },
                                                    set: { value in
                                                        Task {
                                                            await appModel.setMCPResourceSubscribed(resource, subscribed: value, services: services)
                                                        }
                                                    }
                                                ))
                                            }
                                        }
                                    }
                                }
                                if !appModel.mcpResourceTemplates.filter({ $0.serverID == server.id }).isEmpty {
                                    Text("Templates")
                                        .font(theme.typography.headline)
                                    ForEach(appModel.mcpResourceTemplates.filter { $0.serverID == server.id }) { template in
                                        VStack(alignment: .leading) {
                                            Text(template.title ?? template.name)
                                            Text(template.uriTemplate)
                                                .font(theme.typography.caption)
                                                .foregroundStyle(theme.colors.secondaryText)
                                        }
                                    }
                                }
                            }
                            .disabled(!server.resourcesEnabled)
                            DisclosureGroup("Prompts") {
                                Button {
                                    Task {
                                        await appModel.refreshMCPPrompts(server, services: services)
                                    }
                                } label: {
                                    Label("Refresh prompts", systemImage: "arrow.clockwise")
                                }
                                .pinesButtonStyle(.secondary)
                                ForEach(appModel.mcpPrompts.filter { $0.serverID == server.id }) { prompt in
                                    HStack {
                                        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                            Text(prompt.title ?? prompt.name)
                                            Text(prompt.description ?? "No description")
                                                .font(theme.typography.caption)
                                                .foregroundStyle(theme.colors.secondaryText)
                                                .lineLimit(2)
                                            ForEach(prompt.arguments, id: \.name) { argument in
                                                TextField(
                                                    argument.required == true ? "\(argument.name) required" : argument.name,
                                                    text: promptArgumentBinding(prompt: prompt, argument: argument)
                                                )
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                            }
                                        }
                                        Spacer()
                                        Button {
                                            Task {
                                                await appModel.useMCPPrompt(
                                                    prompt,
                                                    arguments: promptArguments(for: prompt),
                                                    services: services
                                                )
                                            }
                                        } label: {
                                            Image(systemName: "text.bubble")
                                        }
                                        .accessibilityLabel("Use \(prompt.name)")
                                        .pinesButtonStyle(.icon)
                                    }
                                }
                            }
                            .disabled(!server.promptsEnabled)
                            DisclosureGroup("Sampling") {
                                LabeledContent("Enabled", value: server.samplingEnabled ? "Yes" : "No")
                                LabeledContent("BYOK", value: server.byokSamplingEnabled ? "Allowed" : "Disabled")
                                LabeledContent("Limit", value: "\(server.maxSamplingRequestsPerSession) per session")
                            }
                            .disabled(!server.samplingEnabled)
                            DisclosureGroup("Auth") {
                                LabeledContent("Mode", value: server.authMode.title)
                                if let resource = server.oauthResource {
                                    LabeledContent("Resource", value: resource)
                                }
                            }
                            DisclosureGroup("Activity") {
                                LabeledContent("Status", value: server.status.rawValue)
                                if let error = server.lastError {
                                    Text(error)
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.danger)
                                }
                            }
                        }
                        .padding(.vertical, theme.spacing.xsmall)
                    }
                }
            }
            }
        }
        .navigationTitle(section.title)
        .pinesInlineNavigationTitle()
        .scrollContentBackground(.hidden)
        .pinesAppBackground()
    }

    private func promptArgumentBinding(prompt: MCPPromptRecord, argument: MCPPromptArgument) -> Binding<String> {
        let key = "\(prompt.id):\(argument.name)"
        return Binding(
            get: { mcpPromptArguments[key] ?? "" },
            set: { mcpPromptArguments[key] = $0 }
        )
    }

    private func promptArguments(for prompt: MCPPromptRecord) -> [String: String] {
        Dictionary(uniqueKeysWithValues: prompt.arguments.map { argument in
            ("\(argument.name)", mcpPromptArguments["\(prompt.id):\(argument.name)"] ?? "")
        })
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
        mcpResourcesEnabled = server.resourcesEnabled
        mcpPromptsEnabled = server.promptsEnabled
        mcpSamplingEnabled = server.samplingEnabled
        mcpBYOKSamplingEnabled = server.byokSamplingEnabled
        mcpSubscriptionsEnabled = server.subscriptionsEnabled
        mcpMaxSamplingRequests = server.maxSamplingRequestsPerSession
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
        mcpResourcesEnabled = false
        mcpPromptsEnabled = false
        mcpSamplingEnabled = false
        mcpBYOKSamplingEnabled = false
        mcpSubscriptionsEnabled = false
        mcpMaxSamplingRequests = 3
    }
}

private enum SettingsDestination {
    case design
    case inference
    case privacy
    case tools
    case system
}

private extension PinesSettingsSection {
    var destination: SettingsDestination {
        switch title {
        case "Design":
            .design
        case "Inference":
            .inference
        case "Privacy":
            .privacy
        case "Tools":
            .tools
        case "System":
            .system
        default:
            .design
        }
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

private extension MCPServerConfiguration {
    var enabledCapabilityTitles: [String] {
        var values = [String]()
        if resourcesEnabled { values.append("Resources") }
        if promptsEnabled { values.append("Prompts") }
        if samplingEnabled { values.append("Sampling") }
        return values
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
