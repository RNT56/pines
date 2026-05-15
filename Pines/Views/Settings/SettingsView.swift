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
                        NavigationLink(value: section.id) {
                            SettingsSectionRow(section: section, isSelected: selectedSectionID == section.id)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .pinesExpressiveScrollHaptics()
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
    let isSelected: Bool

    var body: some View {
        PinesSidebarRow(
            title: section.title,
            subtitle: section.subtitle,
            systemImage: section.systemImage,
            tint: theme.colors.accent,
            isSelected: isSelected
        )
        .listRowInsets(EdgeInsets(top: theme.spacing.xxsmall, leading: theme.spacing.xsmall, bottom: theme.spacing.xxsmall, trailing: theme.spacing.xsmall))
        .listRowBackground(Color.clear)
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
    @State private var mcpSelectedTabs: [MCPServerID: MCPServerDetailTab] = [:]
    @State private var mcpToolSearch = ""
    @State private var mcpResourceSearch = ""
    @State private var mcpPromptSearch = ""
    @State private var huggingFaceToken = ""
    @State private var braveSearchKey = ""

    private var iCloudSyncAvailable: Bool {
        services.cloudKitSyncService != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                settingsHeader

                switch section.destination {
                case .design:
                    designDashboard
                case .inference:
                    inferenceDashboard
                case .privacy:
                    privacyDashboard
                case .tools:
                    toolsDashboard
                case .system:
                    systemDashboard
                }
            }
            .padding(theme.spacing.large)
            .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(section.title)
        .pinesExpressiveScrollHaptics()
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
    }

    private var dashboardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: theme.dashboard.compactGridMinWidth), spacing: theme.spacing.small)]
    }

    private var settingsHeader: some View {
        PinesCardSection(section.title, subtitle: section.subtitle, systemImage: section.systemImage, kind: .glass) {
            LazyVGrid(columns: dashboardColumns, spacing: theme.spacing.small) {
                ForEach(section.rows) { row in
                    PinesInfoTile(title: row.title, value: row.detail, systemImage: row.systemImage)
                }
            }
        }
        .background {
            PinesAmbientBackground()
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous))
                .opacity(0.42)
        }
    }

    @ViewBuilder
    private var designDashboard: some View {
        PinesCardSection("Appearance", subtitle: "Theme, contrast, and interface behavior.", systemImage: "paintpalette") {
            Picker("Interface mode", selection: $interfaceMode) {
                ForEach(PinesInterfaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: interfaceMode) { _, _ in
                Task { await appModel.saveSettings(services: services) }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.card.gridMinWidth), spacing: theme.spacing.small)], spacing: theme.spacing.small) {
                ForEach(PinesThemeTemplate.allCases) { template in
                    Button {
                        withAnimation(theme.motion.selection) {
                            selectedThemeTemplate = template
                        }
                        haptics.play(.navigationSelected)
                        Task { await appModel.saveSettings(services: services) }
                    } label: {
                        PinesThemePreviewCard(template: template, isSelected: selectedThemeTemplate == template)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        PinesCardSection("Haptics and Motion", subtitle: "A compact preview of feedback intensity and motion handling.", systemImage: "hand.tap") {
            Picker("Feedback", selection: $haptics.mode) {
                ForEach(PinesHapticMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: haptics.mode) { _, newMode in
                if newMode != .off { haptics.play(.primaryAction) }
            }

            PinesInfoTile(
                title: "Feedback",
                value: haptics.mode.title,
                systemImage: "waveform.path",
                detail: haptics.mode.subtitle
            )
        }
    }

    @ViewBuilder
    private var inferenceDashboard: some View {
        PinesCardSection("Execution", subtitle: "Routing policy for local inference and configured providers.", systemImage: "point.3.connected.trianglepath.dotted") {
            Picker("Execution mode", selection: $appModel.executionMode) {
                ForEach(AgentExecutionMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: appModel.executionMode) { _, _ in
                Task { await appModel.saveSettings(services: services) }
            }
        }

        runtimeDiagnosticsCard
        huggingFaceCard
    }

    private var runtimeDiagnosticsCard: some View {
        let diagnostics = services.mlxRuntime.runtimeDiagnostics
        let memory = diagnostics.memoryCounters
        var items: [PinesKeyValueGrid.Item] = [
            .init("Local inference", "On", systemImage: "cpu"),
            .init("KV cache", diagnostics.activeAlgorithm.title, systemImage: "memorychip"),
            .init("Metal codec", diagnostics.metalCodecAvailable ? "Available" : "Unavailable", systemImage: "bolt.horizontal"),
            .init("Metal attention", diagnostics.metalAttentionAvailable ? "Available" : "Unavailable", systemImage: "scope")
        ]
        if let preset = diagnostics.preset { items.append(.init("Preset", preset.displayName)) }
        if let requestedBackend = diagnostics.requestedBackend { items.append(.init("Requested backend", requestedBackend.displayName)) }
        if let activeBackend = diagnostics.activeBackend { items.append(.init("Active backend", activeBackend.displayName)) }
        if let attentionPath = diagnostics.activeAttentionPath { items.append(.init("Attention path", attentionPath.displayName)) }
        if let performanceClass = diagnostics.devicePerformanceClass { items.append(.init("Performance", performanceClass.displayName)) }
        if let kernelProfile = diagnostics.metalKernelProfile { items.append(.init("Kernel", kernelProfile.displayName)) }
        if let selfTest = diagnostics.metalSelfTestStatus { items.append(.init("MLX self-test", selfTest.displayName)) }
        if let policy = diagnostics.turboQuantOptimizationPolicy { items.append(.init("Optimization", policy.displayName)) }
        if let rawFallbackAllocated = diagnostics.rawFallbackAllocated { items.append(.init("Raw KV fallback", rawFallbackAllocated ? "Allocated" : "Not allocated")) }
        if diagnostics.thermalDownshiftActive == true { items.append(.init("Thermal downshift", "Active")) }
        if let unsupportedShape = diagnostics.lastUnsupportedAttentionShape { items.append(.init("Unsupported shape", unsupportedShape, copyable: true)) }
        if let hardware = memory.hardwareModelIdentifier { items.append(.init("Device identifier", hardware, copyable: true)) }
        if let metalArchitecture = memory.metalArchitectureName { items.append(.init("Metal architecture", metalArchitecture)) }
        if let workingSet = memory.metalRecommendedWorkingSetBytes { items.append(.init("MLX working set", ByteCountFormatter.string(fromByteCount: workingSet, countStyle: .memory))) }
        if let lowPower = memory.lowPowerModeEnabled { items.append(.init("Low Power Mode", lowPower ? "On" : "Off")) }
        if let contextTokens = memory.recommendedContextTokens { items.append(.init("Context window", "\(contextTokens.formatted()) tokens")) }
        if let physicalMemory = memory.physicalMemoryBytes { items.append(.init("Device memory", ByteCountFormatter.string(fromByteCount: physicalMemory, countStyle: .memory))) }
        if let availableMemory = memory.availableMemoryBytes { items.append(.init("Available memory", ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory))) }
        if let thermalState = memory.thermalState { items.append(.init("Thermal state", thermalState.capitalized)) }
        if let fallback = diagnostics.activeFallbackReason { items.append(.init("Fallback", fallback, copyable: true)) }

        return PinesCardSection("Runtime Diagnostics", subtitle: "Live MLX and device routing state.", systemImage: "gauge.with.dots.needle.67percent") {
            PinesKeyValueGrid(items: items)
        }
    }

    private var huggingFaceCard: some View {
        PinesCardSection("Hugging Face", subtitle: "Hub token used for gated model downloads.", systemImage: "key") {
            PinesKeyValueGrid(items: [.init("Hub token", appModel.huggingFaceCredentialStatus, systemImage: "checkmark.seal")])
            SecureField("Access token", text: $huggingFaceToken)
                .textContentType(.password)
                .pinesFieldChrome()

            VStack(spacing: theme.spacing.small) {
                HStack(spacing: theme.spacing.small) {
                    Button {
                        Task {
                            await appModel.saveHuggingFaceToken(huggingFaceToken, services: services)
                            huggingFaceToken = ""
                        }
                    } label: {
                        Label("Save", systemImage: "key.fill")
                    }
                    .disabled(huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pinesButtonStyle(.primary, fillWidth: true)

                    Button {
                        Task { await appModel.validateHuggingFaceToken(services: services) }
                    } label: {
                        Label("Validate", systemImage: "checkmark.seal")
                    }
                    .pinesButtonStyle(.secondary, fillWidth: true)
                }

                Button(role: .destructive) {
                    Task {
                        await appModel.deleteHuggingFaceToken(services: services)
                        huggingFaceToken = ""
                    }
                } label: {
                    Label("Delete token", systemImage: "trash")
                }
                .pinesButtonStyle(.destructive, fillWidth: true)
            }
        }
    }

    @ViewBuilder
    private var privacyDashboard: some View {
        PinesCardSection("Storage and Sync", subtitle: "Local database protection and private iCloud sync controls.", systemImage: "externaldrive.badge.icloud") {
            PinesKeyValueGrid(items: [
                .init("Store", appModel.storeConfiguration.databaseFileName, systemImage: "internaldrive", copyable: true),
                .init("Protection", appModel.storeConfiguration.dataProtection.title, systemImage: "lock.shield"),
                .init("iCloud", iCloudSyncAvailable ? "Available" : "Unavailable", systemImage: "icloud")
            ])

            Toggle("Private iCloud sync", isOn: Binding(
                get: { iCloudSyncAvailable && appModel.storeConfiguration.iCloudSyncEnabled },
                set: { value in
                    appModel.storeConfiguration.iCloudSyncEnabled = iCloudSyncAvailable && value
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!iCloudSyncAvailable)

            Toggle("Sync source documents", isOn: Binding(
                get: { appModel.storeConfiguration.syncsSourceDocuments },
                set: { value in
                    appModel.storeConfiguration.syncsSourceDocuments = value
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!iCloudSyncAvailable || !appModel.storeConfiguration.iCloudSyncEnabled)

            Toggle("Sync embeddings", isOn: Binding(
                get: { appModel.storeConfiguration.syncsEmbeddings },
                set: { value in
                    appModel.storeConfiguration.syncsEmbeddings = value
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!iCloudSyncAvailable || !appModel.storeConfiguration.iCloudSyncEnabled)
        }

        cloudProviderCard
    }

    private var cloudProviderCard: some View {
        PinesCardSection("Cloud BYOK", subtitle: "Bring your own provider credentials without changing routing semantics.", systemImage: "cloud.badge.key") {
            Picker("Provider", selection: $providerKind) {
                ForEach(CloudProviderKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .onChange(of: providerKind) { _, kind in applyProviderDefaults(kind) }

            TextField("Display name", text: $providerName)
                .pinesFieldChrome()
            TextField("Base URL", text: $providerBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            TextField("Default model", text: $providerModelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            SecureField("API key", text: $providerAPIKey)
                .textContentType(.password)
                .pinesFieldChrome()
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
            .pinesButtonStyle(.primary, fillWidth: true)

            ForEach(appModel.cloudProviders) { provider in
                providerRow(provider)
            }
        }
    }

    private func providerRow(_ provider: CloudProviderConfiguration) -> some View {
        HStack(spacing: theme.spacing.medium) {
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(provider.displayName)
                    .font(theme.typography.headline)
                    .pinesFittingText()
                Text(provider.kind.title)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer(minLength: theme.spacing.small)

            Text(provider.validationStatus.rawValue)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(provider.validationStatus == .valid ? theme.colors.success : theme.colors.warning)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Button {
                Task { await appModel.validateCloudProvider(provider, services: services) }
            } label: {
                Image(systemName: "checkmark.seal")
            }
            .accessibilityLabel("Validate \(provider.displayName)")
            .pinesButtonStyle(.icon)

            Button(role: .destructive) {
                Task { await appModel.deleteCloudProvider(provider, services: services) }
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete \(provider.displayName)")
            .pinesButtonStyle(.icon)
        }
        .frame(minHeight: theme.row.minHeight)
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    @ViewBuilder
    private var toolsDashboard: some View {
        toolKeysCard
        mcpEditorCard
        mcpServersCard
    }

    private var toolKeysCard: some View {
        PinesCardSection("Agent Tool Keys", subtitle: "Credentials for built-in external tools.", systemImage: "wrench.and.screwdriver") {
            PinesKeyValueGrid(items: [.init("Brave Search", appModel.braveSearchCredentialStatus, systemImage: "magnifyingglass")])
            SecureField("Brave Search API key", text: $braveSearchKey)
                .textContentType(.password)
                .pinesFieldChrome()

            HStack(spacing: theme.spacing.small) {
                Button {
                    Task {
                        await appModel.saveBraveSearchKey(braveSearchKey, services: services)
                        braveSearchKey = ""
                    }
                } label: {
                    Label("Save", systemImage: "magnifyingglass.circle")
                }
                .disabled(braveSearchKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .pinesButtonStyle(.primary, fillWidth: true)

                Button(role: .destructive) {
                    Task {
                        await appModel.saveBraveSearchKey("", services: services)
                        braveSearchKey = ""
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .pinesButtonStyle(.destructive, fillWidth: true)
            }
        }
    }

    private var mcpEditorCard: some View {
        PinesCardSection(mcpEditingServerID == nil ? "New MCP Server" : "Editing MCP Server", subtitle: "Configure streamable HTTP transport, auth, and optional capabilities.", systemImage: "server.rack") {
            HStack {
                Spacer()
                Button {
                    resetMCPForm()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .pinesButtonStyle(.secondary)
            }

            TextField("Display name", text: $mcpName)
                .pinesFieldChrome()
            TextField("Streamable HTTP endpoint", text: $mcpEndpointURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            Picker("Authentication", selection: $mcpAuthMode) {
                ForEach(MCPAuthMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            if mcpAuthMode == .bearerToken {
                SecureField("Bearer token", text: $mcpBearerToken)
                    .textContentType(.password)
                    .pinesFieldChrome()
            }

            if mcpAuthMode == .oauthPKCE {
                oauthFields
            }

            LazyVGrid(columns: dashboardColumns, spacing: theme.spacing.small) {
                Toggle("Enable server", isOn: $mcpEnabled)
                Toggle("Allow insecure local HTTP", isOn: $mcpAllowInsecureLocalHTTP)
                Toggle("Resources", isOn: $mcpResourcesEnabled)
                Toggle("Prompts", isOn: $mcpPromptsEnabled)
                Toggle("Sampling", isOn: $mcpSamplingEnabled)
                Toggle("BYOK sampling", isOn: $mcpBYOKSamplingEnabled)
                    .disabled(!mcpSamplingEnabled)
                Toggle("Resource subscriptions", isOn: $mcpSubscriptionsEnabled)
                    .disabled(!mcpResourcesEnabled)
            }

            Stepper("Sampling requests per session: \(mcpMaxSamplingRequests)", value: $mcpMaxSamplingRequests, in: 0...20)
                .disabled(!mcpSamplingEnabled)

            HStack(spacing: theme.spacing.small) {
                Button {
                    Task {
                        await saveMCPServer()
                    }
                } label: {
                    Label("Save and discover tools", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .pinesButtonStyle(.primary, fillWidth: true)

                Button {
                    Task { await discoverOAuth() }
                } label: {
                    Label("Discover OAuth", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(mcpEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .pinesButtonStyle(.secondary, fillWidth: true)
            }
        }
    }

    private var oauthFields: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            TextField("Authorization URL", text: $mcpOAuthAuthorizationURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            TextField("Token URL", text: $mcpOAuthTokenURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            TextField("Client ID", text: $mcpOAuthClientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            TextField("Scopes", text: $mcpOAuthScopes)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            TextField("Resource", text: $mcpOAuthResource)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
        }
    }

    private var mcpServersCard: some View {
        PinesCardSection("MCP Servers", subtitle: "Configured servers, grouped capabilities, and runtime state.", systemImage: "rectangle.connected.to.line.below") {
            if appModel.mcpServers.isEmpty {
                PinesEmptyState(title: "No MCP servers", detail: "Add a streamable HTTP endpoint to expose tools to agents.", systemImage: "server.rack")
            } else {
                ForEach(appModel.mcpServers) { server in
                    mcpServerCard(server)
                }
            }
        }
    }

    private func mcpServerCard(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.medium) {
            HStack(alignment: .top, spacing: theme.spacing.small) {
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(server.displayName)
                        .font(theme.typography.headline)
                        .pinesFittingText()
                    Text(server.endpointURL.absoluteString)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: theme.spacing.small)

                Text(server.status.rawValue)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(server.status == .ready ? theme.colors.success : theme.colors.warning)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Button {
                    Task { await appModel.refreshMCPServer(server, services: services) }
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

                Button(role: .destructive) {
                    Task { await appModel.deleteMCPServer(server, services: services) }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete \(server.displayName)")
                .pinesButtonStyle(.icon)
            }

            if server.authMode == .oauthPKCE {
                HStack(spacing: theme.spacing.small) {
                    Button {
                        Task { await appModel.connectMCPOAuth(server, services: services) }
                    } label: {
                        Label("Connect OAuth", systemImage: "person.badge.key")
                    }
                    .pinesButtonStyle(.secondary, fillWidth: true)

                    Button {
                        Task { await appModel.disconnectMCPOAuth(server, services: services) }
                    } label: {
                        Label("Disconnect OAuth", systemImage: "person.badge.minus")
                    }
                    .pinesButtonStyle(.secondary, fillWidth: true)
                }
            }

            PinesKeyValueGrid(items: mcpServerItems(server))

            if let error = server.lastError {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger)
                    .lineLimit(3)
                    .pinesSurface(.inset, padding: theme.spacing.small)
            }

            mcpCapabilities(server)
        }
        .pinesSurface(.inset, padding: theme.spacing.medium)
    }

    private func mcpServerItems(_ server: MCPServerConfiguration) -> [PinesKeyValueGrid.Item] {
        var items: [PinesKeyValueGrid.Item] = [
            .init("Auth", server.authMode.title, systemImage: "lock"),
            .init("Capabilities", server.enabledCapabilityTitles.joined(separator: ", ").nilIfEmpty ?? "Tools only", systemImage: "square.grid.2x2")
        ]
        if let connectedAt = server.lastConnectedAt {
            items.append(.init("Last connected", connectedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock"))
        }
        if let resource = server.oauthResource {
            items.append(.init("OAuth resource", resource, systemImage: "link", copyable: true))
        }
        return items
    }

    @ViewBuilder
    private func mcpCapabilities(_ server: MCPServerConfiguration) -> some View {
        let selectedTab = mcpSelectedTabBinding(for: server)
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Picker("MCP detail", selection: selectedTab) {
                ForEach(MCPServerDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab.wrappedValue {
            case .tools:
                mcpTools(server)
            case .resources:
                if server.resourcesEnabled {
                    mcpResources(server)
                } else {
                    MCPDisabledCapabilityView(title: "Resources Disabled", detail: "Enable resources on this server to list, preview, subscribe, and attach context.")
                }
            case .prompts:
                if server.promptsEnabled {
                    mcpPrompts(server)
                } else {
                    MCPDisabledCapabilityView(title: "Prompts Disabled", detail: "Enable prompts on this server to invoke reusable templates.")
                }
            case .sampling:
                mcpSampling(server)
            case .auth:
                mcpAuth(server)
            case .activity:
                mcpActivity(server)
            }
        }
    }

    private func mcpSelectedTabBinding(for server: MCPServerConfiguration) -> Binding<MCPServerDetailTab> {
        Binding(
            get: { mcpSelectedTabs[server.id] ?? .tools },
            set: { mcpSelectedTabs[server.id] = $0 }
        )
    }

    private func mcpTools(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text("Tools")
                .font(theme.typography.headline)
            TextField("Search tools", text: $mcpToolSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            let tools = filteredMCPTools(for: server)
            if tools.isEmpty {
                PinesEmptyState(title: "No matching tools", detail: "Refresh discovery or clear the search filter.", systemImage: "wrench.adjustable")
            }
            ForEach(tools) { tool in
                Toggle(isOn: Binding(
                    get: { tool.enabled },
                    set: { value in
                        Task { await appModel.setMCPToolEnabled(tool, enabled: value, services: services) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(tool.displayName)
                            .pinesFittingText()
                        Text(tool.namespacedName)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(tool.description)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.tertiaryText)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func mcpResources(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack {
                Text("Resources")
                    .font(theme.typography.headline)
                Spacer()
                Button {
                    Task { await appModel.refreshMCPResources(server, services: services) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .pinesButtonStyle(.secondary)
            }

            TextField("Search resources and URI templates", text: $mcpResourceSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()

            let resources = filteredMCPResources(for: server)
            if resources.isEmpty {
                PinesEmptyState(title: "No matching resources", detail: "Refresh resources or clear the search filter.", systemImage: "doc.text.magnifyingglass")
            }
            ForEach(resources) { resource in
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    Text(resource.title ?? resource.name)
                        .font(theme.typography.callout.weight(.semibold))
                    Text(resource.uri)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        Task {
                            if let preview = await appModel.previewMCPResource(resource, services: services) {
                                mcpResourcePreviews[resource.uri] = preview
                            }
                        }
                    } label: {
                        Label("Preview", systemImage: "doc.text.magnifyingglass")
                    }
                    .pinesButtonStyle(.secondary, fillWidth: true)

                    if let preview = mcpResourcePreviews[resource.uri] {
                        Text(preview)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(8)
                            .textSelection(.enabled)
                    }

                    Toggle("Attach to chat context", isOn: Binding(
                        get: { resource.selectedForContext },
                        set: { value in
                            Task { await appModel.setMCPResourceSelected(resource, selected: value, services: services) }
                        }
                    ))
                    if server.subscriptionsEnabled {
                        Toggle("Subscribe", isOn: Binding(
                            get: { resource.subscribed },
                            set: { value in
                                Task { await appModel.setMCPResourceSubscribed(resource, subscribed: value, services: services) }
                            }
                        ))
                    }
                }
                .pinesSurface(.panel, padding: theme.spacing.small)
            }

            ForEach(filteredMCPResourceTemplates(for: server)) { template in
                PinesKeyValueGrid(items: [
                    .init("Template", template.title ?? template.name, systemImage: "doc.badge.gearshape"),
                    .init("URI", template.uriTemplate, copyable: true)
                ])
            }
        }
    }

    private func mcpPrompts(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack {
                Text("Prompts")
                    .font(theme.typography.headline)
                Spacer()
                Button {
                    Task { await appModel.refreshMCPPrompts(server, services: services) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .pinesButtonStyle(.secondary)
            }

            TextField("Search prompts", text: $mcpPromptSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            let prompts = filteredMCPPrompts(for: server)
            if prompts.isEmpty {
                PinesEmptyState(title: "No matching prompts", detail: "Refresh prompts or clear the search filter.", systemImage: "text.bubble")
            }
            ForEach(prompts) { prompt in
                HStack(alignment: .top, spacing: theme.spacing.small) {
                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(prompt.title ?? prompt.name)
                            .font(theme.typography.callout.weight(.semibold))
                            .pinesFittingText()
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
                            .pinesFieldChrome()
                        }
                    }
                    Spacer()
                    Button {
                        Task {
                            await appModel.useMCPPrompt(prompt, arguments: promptArguments(for: prompt), services: services)
                        }
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                    .accessibilityLabel("Use \(prompt.name)")
                    .pinesButtonStyle(.icon)
                }
                .pinesSurface(.panel, padding: theme.spacing.small)
            }
        }
    }

    private func mcpSampling(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text("Sampling")
                .font(theme.typography.headline)
            PinesKeyValueGrid(items: [
                .init("Enabled", server.samplingEnabled ? "Yes" : "No", systemImage: "waveform.path.ecg"),
                .init("BYOK", server.byokSamplingEnabled ? "Allowed" : "Disabled", systemImage: "cloud"),
                .init("Limit", "\(server.maxSamplingRequestsPerSession) per session", systemImage: "number")
            ])
            Text("Sampling requests require consent before generation and a second review before Pines returns the result to the server.")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

    private func mcpAuth(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text("Auth")
                .font(theme.typography.headline)
            PinesKeyValueGrid(items: mcpAuthItems(server))
        }
    }

    private func mcpActivity(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text("Activity")
                .font(theme.typography.headline)
            PinesKeyValueGrid(items: mcpActivityItems(server))
            if let error = server.lastError {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger)
                    .textSelection(.enabled)
                    .pinesSurface(.panel, padding: theme.spacing.small)
            }
        }
    }

    private func mcpAuthItems(_ server: MCPServerConfiguration) -> [PinesKeyValueGrid.Item] {
        var items = [
            PinesKeyValueGrid.Item("Mode", server.authMode.title, systemImage: "lock"),
            PinesKeyValueGrid.Item("Endpoint", server.endpointURL.absoluteString, systemImage: "link", copyable: true),
            PinesKeyValueGrid.Item("Insecure local HTTP", server.allowInsecureLocalHTTP ? "Allowed" : "Blocked", systemImage: "network")
        ]
        if let scopes = server.oauthScopes {
            items.append(.init("OAuth scopes", scopes, systemImage: "key"))
        }
        if let resource = server.oauthResource {
            items.append(.init("OAuth resource", resource, systemImage: "person.badge.key", copyable: true))
        }
        return items
    }

    private func mcpActivityItems(_ server: MCPServerConfiguration) -> [PinesKeyValueGrid.Item] {
        var items = [
            PinesKeyValueGrid.Item("Status", server.status.rawValue, systemImage: "circle.dashed"),
            PinesKeyValueGrid.Item("Enabled", server.enabled ? "Yes" : "No", systemImage: "power")
        ]
        if let connectedAt = server.lastConnectedAt {
            items.append(.init("Last connected", connectedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock"))
        }
        return items
    }

    private func filteredMCPTools(for server: MCPServerConfiguration) -> [MCPToolRecord] {
        let query = mcpToolSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appModel.mcpTools.filter { tool in
            guard tool.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [tool.displayName, tool.namespacedName, tool.description, tool.originalName]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    private func filteredMCPResources(for server: MCPServerConfiguration) -> [MCPResourceRecord] {
        let query = mcpResourceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appModel.mcpResources.filter { resource in
            guard resource.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [
                resource.name,
                resource.title ?? "",
                resource.description ?? "",
                resource.uri,
                resource.mimeType ?? "",
            ].joined(separator: " ").lowercased().contains(query)
        }
    }

    private func filteredMCPResourceTemplates(for server: MCPServerConfiguration) -> [MCPResourceTemplateRecord] {
        let query = mcpResourceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appModel.mcpResourceTemplates.filter { template in
            guard template.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [
                template.name,
                template.title ?? "",
                template.description ?? "",
                template.uriTemplate,
                template.mimeType ?? "",
            ].joined(separator: " ").lowercased().contains(query)
        }
    }

    private func filteredMCPPrompts(for server: MCPServerConfiguration) -> [MCPPromptRecord] {
        let query = mcpPromptSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appModel.mcpPrompts.filter { prompt in
            guard prompt.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [
                prompt.name,
                prompt.title ?? "",
                prompt.description ?? "",
                prompt.arguments.map(\.name).joined(separator: " "),
            ].joined(separator: " ").lowercased().contains(query)
        }
    }

    @ViewBuilder
    private var systemDashboard: some View {
        PinesCardSection("Architecture Health", subtitle: "Service readiness across the local app stack.", systemImage: "stethoscope") {
            ForEach(services.serviceHealth) { service in
                HStack(spacing: theme.spacing.medium) {
                    PinesStatusIndicator(color: service.readiness.tint(in: theme), isActive: service.readiness == .booting, size: 9)
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
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(service.readiness.tint(in: theme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .frame(minHeight: theme.row.minHeight)
                .pinesSurface(.inset, padding: theme.spacing.small)
            }
        }

        PinesCardSection("Audit Timeline", subtitle: "Recent privacy-preserving system events.", systemImage: "clock.arrow.circlepath") {
            if appModel.auditEvents.isEmpty {
                PinesEmptyState(title: "No audit events", detail: "Audit entries appear here when the system records notable actions.", systemImage: "checkmark.shield")
            } else {
                PinesTimeline(items: Array(appModel.auditEvents.prefix(8)).enumerated().map { index, event in
                    PinesTimelineItem(
                        title: event.category.rawValue,
                        detail: [event.summary, event.redactedPayload].compactMap(\.self).joined(separator: "\n"),
                        systemImage: index == 0 ? "record.circle" : "circle",
                        tint: theme.colors.accent,
                        isCurrent: index == 0
                    )
                })
            }
        }
    }

    private func saveMCPServer() async {
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

    private func discoverOAuth() async {
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

private enum MCPServerDetailTab: String, CaseIterable, Identifiable {
    case tools
    case resources
    case prompts
    case sampling
    case auth
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tools:
            "Tools"
        case .resources:
            "Resources"
        case .prompts:
            "Prompts"
        case .sampling:
            "Sampling"
        case .auth:
            "Auth"
        case .activity:
            "Activity"
        }
    }
}

private struct MCPDisabledCapabilityView: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String

    var body: some View {
        PinesEmptyState(title: title, detail: detail, systemImage: "slash.circle")
            .pinesSurface(.panel, padding: theme.spacing.medium)
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
