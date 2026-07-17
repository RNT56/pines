import SwiftUI
import PinesCore

struct ToolsIntegrationsSettingsPage: View {
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var showsBraveEditor = false
    @State private var editorContext: MCPServerEditorContext?
    @State private var selectedServerID: MCPServerID?
    @State private var serverPendingDeletion: MCPServerConfiguration?

    var body: some View {
        PinesSettingsPage(introduction: "Connect external tools and context sources. Pines still asks before potentially sensitive tool actions; integrations do not bypass approval.") {
            PinesSettingsGroup("Built-in tools") {
                PinesSettingsValueRow(
                    "Web search",
                    value: settingsState.braveSearchCredentialStatus.hasPrefix("Configured") ? "Ready" : "Not configured",
                    detail: "Brave Search is available to agents only after an API key is added.",
                    systemImage: "magnifyingglass",
                    valueTone: settingsState.braveSearchCredentialStatus.hasPrefix("Configured") ? .success : .neutral
                )

                PinesSettingsDivider()

                PinesSettingsActionRow(
                    title: "Manage web search key",
                    detail: "Add, replace, or remove the key stored in this device's keychain.",
                    systemImage: "key",
                    action: { showsBraveEditor = true }
                )
            }

            PinesSettingsNotice(
                title: "Tool approval stays on",
                detail: "Pines requires confirmation before tools perform sensitive or external actions. This safety boundary is not configurable here.",
                systemImage: "hand.raised",
                tone: .success
            )

            PinesSettingsGroup("MCP servers", detail: "Servers can provide tools, resources, prompts, and optional sampling.") {
                if settingsState.mcpServers.isEmpty {
                    PinesSettingsValueRow(
                        "No servers connected",
                        value: "Off",
                        detail: "Add a Streamable HTTP endpoint when you want to extend Pines.",
                        systemImage: "server.rack"
                    )
                } else {
                    ForEach(Array(settingsState.mcpServers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 { PinesSettingsDivider() }
                        mcpServerRow(server)
                    }
                }

                PinesSettingsDivider()

                PinesSettingsActionRow(
                    title: "Add MCP server",
                    detail: "Configure an endpoint, authentication, and the capabilities you want to allow.",
                    systemImage: "plus.circle",
                    action: { editorContext = MCPServerEditorContext(server: nil) }
                )
            }
        }
        .task {
            await appModel.startMCPServersIfNeeded(services: services)
        }
        .sheet(isPresented: $showsBraveEditor) {
            BraveSearchCredentialSheet()
                .environmentObject(appModel)
                .environmentObject(settingsState)
        }
        .sheet(item: $editorContext) { context in
            MCPServerEditorSheet(server: context.server)
                .environmentObject(appModel)
                .environmentObject(settingsState)
        }
        .sheet(isPresented: Binding(
            get: { selectedServerID != nil },
            set: { if !$0 { selectedServerID = nil } }
        )) {
            if let selectedServerID {
                MCPServerDetailSheet(serverID: selectedServerID)
                    .environmentObject(appModel)
                    .environmentObject(settingsState)
            }
        }
        .confirmationDialog(
            "Delete MCP server?",
            isPresented: Binding(
                get: { serverPendingDeletion != nil },
                set: { if !$0 { serverPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete server", role: .destructive) {
                guard let server = serverPendingDeletion else { return }
                serverPendingDeletion = nil
                Task { await appModel.deleteMCPServer(server, services: services) }
            }
            Button("Cancel", role: .cancel) { serverPendingDeletion = nil }
        } message: {
            Text("This removes the server configuration and credentials. Its tools will no longer be available to agents.")
        }
    }

    private func mcpServerRow(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(alignment: .top, spacing: theme.spacing.small) {
                Image(systemName: "server.rack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 34, height: 34)
                    .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(server.displayName)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text(server.settingsSummary)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: theme.spacing.small)
                PinesStatusChip(status: server.status.settingsCloudStatus, compact: true)
            }

            if let error = server.lastError, !error.isEmpty {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.warning)
                    .lineLimit(3)
            }

            HStack(spacing: theme.spacing.small) {
                Button("Open") { selectedServerID = server.id }
                    .pinesButtonStyle(.secondary)

                Spacer(minLength: theme.spacing.small)

                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await appModel.refreshMCPServer(server, services: services) }
                    }
                    Button("Edit configuration", systemImage: "pencil") {
                        editorContext = MCPServerEditorContext(server: server)
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        serverPendingDeletion = server
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Manage \(server.displayName)")
                .pinesButtonStyle(.icon)
            }
        }
        .padding(theme.spacing.medium)
    }
}

private struct BraveSearchCredentialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var apiKey = ""
    @State private var showsDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            PinesSettingsPage(introduction: "Pines stores the Brave Search key in the device keychain and uses it only for web searches you allow.") {
                PinesSettingsGroup("Brave Search") {
                    PinesSettingsValueRow(
                        "Status",
                        value: settingsState.braveSearchCredentialStatus,
                        systemImage: "checkmark.seal",
                        valueTone: settingsState.braveSearchCredentialStatus.hasPrefix("Configured") ? .success : .neutral
                    )

                    PinesSettingsDivider()

                    SecureField("Paste a new API key", text: $apiKey)
                        .textContentType(.password)
                        .accessibilityIdentifier("pines.settings.brave.key")
                        .pinesFieldChrome()
                        .padding(theme.spacing.medium)

                    PinesSettingsDivider()

                    Button {
                        Task {
                            await appModel.saveBraveSearchKey(apiKey, services: services)
                            apiKey = ""
                        }
                    } label: {
                        Label("Save key", systemImage: "key.fill")
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pinesButtonStyle(.primary, fillWidth: true)
                    .padding(theme.spacing.medium)
                }

                PinesSettingsGroup("Remove access") {
                    PinesSettingsActionRow(
                        title: "Delete key",
                        detail: "Agent web search will be unavailable until another key is saved.",
                        systemImage: "trash",
                        role: .destructive,
                        showsDisclosure: false,
                        action: { showsDeleteConfirmation = true }
                    )
                }
            }
            .navigationTitle("Web Search")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete Brave Search key?", isPresented: $showsDeleteConfirmation) {
                Button("Delete key", role: .destructive) {
                    Task {
                        await appModel.saveBraveSearchKey("", services: services)
                        apiKey = ""
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct MCPServerEditorContext: Identifiable {
    let id = UUID()
    let server: MCPServerConfiguration?
}

private struct MCPServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    let server: MCPServerConfiguration?
    @State private var name: String
    @State private var endpointURL: String
    @State private var authMode: MCPAuthMode
    @State private var bearerToken = ""
    @State private var oauthAuthorizationURL: String
    @State private var oauthTokenURL: String
    @State private var oauthClientID: String
    @State private var oauthScopes: String
    @State private var oauthResource: String
    @State private var enabled: Bool
    @State private var allowInsecureLocalHTTP: Bool
    @State private var resourcesEnabled: Bool
    @State private var promptsEnabled: Bool
    @State private var samplingEnabled: Bool
    @State private var byokSamplingEnabled: Bool
    @State private var subscriptionsEnabled: Bool
    @State private var maxSamplingRequests: Int
    @State private var showsCapabilities = false
    @State private var showsOAuthDetails = false
    @State private var saveError: String?

    init(server: MCPServerConfiguration?) {
        self.server = server
        _name = State(initialValue: server?.displayName ?? "")
        _endpointURL = State(initialValue: server?.endpointURL.absoluteString ?? "https://")
        _authMode = State(initialValue: server?.authMode ?? .none)
        _oauthAuthorizationURL = State(initialValue: server?.oauthAuthorizationURL?.absoluteString ?? "")
        _oauthTokenURL = State(initialValue: server?.oauthTokenURL?.absoluteString ?? "")
        _oauthClientID = State(initialValue: server?.oauthClientID ?? "")
        _oauthScopes = State(initialValue: server?.oauthScopes ?? "")
        _oauthResource = State(initialValue: server?.oauthResource ?? "")
        _enabled = State(initialValue: server?.enabled ?? true)
        _allowInsecureLocalHTTP = State(initialValue: server?.allowInsecureLocalHTTP ?? false)
        _resourcesEnabled = State(initialValue: server?.resourcesEnabled ?? false)
        _promptsEnabled = State(initialValue: server?.promptsEnabled ?? false)
        _samplingEnabled = State(initialValue: server?.samplingEnabled ?? false)
        _byokSamplingEnabled = State(initialValue: server?.byokSamplingEnabled ?? false)
        _subscriptionsEnabled = State(initialValue: server?.subscriptionsEnabled ?? false)
        _maxSamplingRequests = State(initialValue: server?.maxSamplingRequestsPerSession ?? 3)
    }

    var body: some View {
        NavigationStack {
            PinesSettingsPage(introduction: "Add only servers you trust. Pines blocks insecure remote endpoints and keeps authentication secrets in the keychain.") {
                PinesSettingsGroup("Connection") {
                    TextField("Display name", text: $name)
                        .accessibilityIdentifier("pines.settings.mcp.name")
                        .pinesFieldChrome()
                        .padding(theme.spacing.medium)

                    PinesSettingsDivider()

                    TextField("Streamable HTTP endpoint", text: $endpointURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pines.settings.mcp.endpoint")
                        .pinesFieldChrome()
                        .padding(theme.spacing.medium)

                    PinesSettingsDivider()

                    PinesSettingsControlRow("Authentication", systemImage: "lock") {
                        Picker("Authentication", selection: $authMode) {
                            ForEach(MCPAuthMode.allCases, id: \.self) { mode in
                                Text(mode.settingsTitle).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if authMode == .bearerToken {
                        PinesSettingsDivider()
                        SecureField(server == nil ? "Bearer token" : "New bearer token (optional)", text: $bearerToken)
                            .textContentType(.password)
                            .pinesFieldChrome()
                            .padding(theme.spacing.medium)
                    }

                    if authMode == .oauthPKCE {
                        PinesSettingsDivider()
                        oauthConfiguration
                    }

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Enable server",
                        detail: "Connect and make its enabled tools available to agents.",
                        systemImage: "power"
                    ) {
                        Toggle("Enable server", isOn: $enabled).labelsHidden()
                    }
                }

                PinesSettingsGroup("Capabilities", detail: "Tools are always discovered. Enable additional MCP capabilities only when needed.") {
                    DisclosureGroup(isExpanded: $showsCapabilities) {
                        VStack(alignment: .leading, spacing: theme.spacing.medium) {
                            Toggle("Resources", isOn: $resourcesEnabled)
                            Toggle("Prompts", isOn: $promptsEnabled)
                            Toggle("Sampling", isOn: $samplingEnabled)
                            Toggle("Allow BYOK for sampling", isOn: $byokSamplingEnabled)
                                .disabled(!samplingEnabled)
                            Toggle("Resource subscriptions", isOn: $subscriptionsEnabled)
                                .disabled(!resourcesEnabled)
                            Stepper(
                                "Sampling requests per session: \(maxSamplingRequests)",
                                value: $maxSamplingRequests,
                                in: 0...20
                            )
                            .disabled(!samplingEnabled)
                        }
                        .padding(.top, theme.spacing.medium)
                    } label: {
                        Label("Optional capabilities", systemImage: "switch.2")
                            .font(theme.typography.callout.weight(.semibold))
                    }
                    .padding(theme.spacing.medium)

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Allow local HTTP",
                        detail: "Only permits explicit HTTP endpoints on this device or local network. Remote insecure endpoints remain blocked.",
                        systemImage: "network"
                    ) {
                        Toggle("Allow local HTTP", isOn: $allowInsecureLocalHTTP).labelsHidden()
                    }
                }

                if let saveError {
                    PinesSettingsNotice(
                        title: "Server was not saved",
                        detail: saveError,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
            }
            .navigationTitle(server == nil ? "Add MCP Server" : "Edit MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveServer() }
                        .disabled(endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var oauthConfiguration: some View {
        DisclosureGroup(isExpanded: $showsOAuthDetails) {
            VStack(alignment: .leading, spacing: theme.spacing.medium) {
                Button {
                    discoverOAuth()
                } label: {
                    Label("Discover from endpoint", systemImage: "sparkle.magnifyingglass")
                }
                .pinesButtonStyle(.secondary, fillWidth: true)

                TextField("Authorization URL", text: $oauthAuthorizationURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .pinesFieldChrome()
                TextField("Token URL", text: $oauthTokenURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .pinesFieldChrome()
                TextField("Client ID", text: $oauthClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .pinesFieldChrome()
                TextField("Scopes", text: $oauthScopes)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .pinesFieldChrome()
                TextField("Resource", text: $oauthResource)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .pinesFieldChrome()
            }
            .padding(.top, theme.spacing.medium)
        } label: {
            Label("OAuth configuration", systemImage: "person.badge.key")
                .font(theme.typography.callout.weight(.semibold))
        }
        .padding(theme.spacing.medium)
    }

    private func discoverOAuth() {
        Task {
            saveError = nil
            if let discovery = await appModel.discoverMCPOAuth(
                endpointURLString: endpointURL,
                allowInsecureLocalHTTP: allowInsecureLocalHTTP,
                services: services
            ) {
                oauthAuthorizationURL = discovery.authorizationURL.absoluteString
                oauthTokenURL = discovery.tokenURL.absoluteString
                oauthClientID = discovery.clientID
                oauthScopes = discovery.scopes ?? ""
                oauthResource = discovery.resource
                showsOAuthDetails = true
            } else {
                saveError = appModel.serviceError ?? "OAuth metadata could not be discovered."
            }
        }
    }

    private func saveServer() {
        Task {
            appModel.serviceError = nil
            await appModel.saveMCPServer(
                existingID: server?.id,
                displayName: name,
                endpointURLString: endpointURL,
                authMode: authMode,
                bearerToken: bearerToken,
                oauthAuthorizationURLString: oauthAuthorizationURL,
                oauthTokenURLString: oauthTokenURL,
                oauthClientID: oauthClientID,
                oauthScopes: oauthScopes,
                oauthResource: oauthResource,
                resourcesEnabled: resourcesEnabled,
                promptsEnabled: promptsEnabled,
                samplingEnabled: samplingEnabled,
                byokSamplingEnabled: byokSamplingEnabled,
                subscriptionsEnabled: subscriptionsEnabled,
                maxSamplingRequestsPerSession: maxSamplingRequests,
                enabled: enabled,
                allowInsecureLocalHTTP: allowInsecureLocalHTTP,
                services: services
            )
            if let serviceError = appModel.serviceError {
                saveError = serviceError
            } else {
                dismiss()
            }
        }
    }
}

private struct MCPServerDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    let serverID: MCPServerID
    @State private var showsEditor = false
    @State private var showsTools = true
    @State private var showsResources = false
    @State private var showsPrompts = false
    @State private var showsSecurity = false
    @State private var toolSearch = ""
    @State private var resourceSearch = ""
    @State private var promptSearch = ""
    @State private var resourcePreviews: [String: String] = [:]
    @State private var promptArguments: [String: String] = [:]

    private var server: MCPServerConfiguration? {
        settingsState.mcpServers.first(where: { $0.id == serverID })
    }

    var body: some View {
        NavigationStack {
            if let server {
                PinesSettingsPage(introduction: server.endpointURL.absoluteString) {
                    summaryGroup(server)
                    toolsGroup(server)
                    resourcesGroup(server)
                    promptsGroup(server)
                    securityAndActivityGroup(server)
                }
                .navigationTitle(server.displayName)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                Task { await appModel.refreshMCPServer(server, services: services) }
                            }
                            Button("Edit configuration", systemImage: "pencil") {
                                showsEditor = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showsEditor) {
                    MCPServerEditorSheet(server: server)
                        .environmentObject(appModel)
                        .environmentObject(settingsState)
                }
            } else {
                PinesEmptyState(
                    title: "Server unavailable",
                    detail: "This server may have been removed on another device.",
                    systemImage: "server.rack"
                )
            }
        }
    }

    private func summaryGroup(_ server: MCPServerConfiguration) -> some View {
        PinesSettingsGroup("Overview") {
            PinesSettingsValueRow(
                "Connection",
                value: server.status.settingsTitle,
                detail: server.lastConnectedAt.map { "Last connected \($0.formatted(date: .abbreviated, time: .shortened))." },
                systemImage: "server.rack",
                valueTone: server.status.settingsTone
            )
            PinesSettingsDivider()
            PinesSettingsValueRow(
                "Capabilities",
                value: server.settingsCapabilityTitles.joined(separator: ", ").nilIfEmpty ?? "Tools only",
                detail: server.enabled ? "Server enabled" : "Server disabled",
                systemImage: "square.grid.2x2"
            )
            if let error = server.lastError, !error.isEmpty {
                PinesSettingsDivider()
                PinesSettingsNotice(
                    title: "Server reported an error",
                    detail: error,
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
                .padding(theme.spacing.medium)
            }
        }
    }

    private func toolsGroup(_ server: MCPServerConfiguration) -> some View {
        PinesSettingsGroup("Tools", detail: "Choose which discovered tools agents may request.") {
            DisclosureGroup(isExpanded: $showsTools) {
                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    TextField("Search tools", text: $toolSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pinesFieldChrome()

                    let tools = filteredTools(server)
                    if tools.isEmpty {
                        Text("No matching tools. Refresh the server or clear the search.")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    } else {
                        ForEach(tools) { tool in
                            Toggle(isOn: Binding(
                                get: { tool.enabled },
                                set: { enabled in
                                    Task { await appModel.setMCPToolEnabled(tool, enabled: enabled, services: services) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                    Text(tool.displayName)
                                        .font(theme.typography.callout.weight(.semibold))
                                    Text(tool.description)
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.top, theme.spacing.medium)
            } label: {
                Label("\(filteredTools(server).count) available", systemImage: "wrench.and.screwdriver")
                    .font(theme.typography.callout.weight(.semibold))
            }
            .padding(theme.spacing.medium)
        }
    }

    private func resourcesGroup(_ server: MCPServerConfiguration) -> some View {
        PinesSettingsGroup("Resources", detail: "Preview or attach server-provided context to chats.") {
            if !server.resourcesEnabled {
                PinesSettingsValueRow(
                    "Resources disabled",
                    value: "Off",
                    detail: "Enable Resources in the server configuration to use this capability.",
                    systemImage: "doc.text"
                )
            } else {
                DisclosureGroup(isExpanded: $showsResources) {
                    VStack(alignment: .leading, spacing: theme.spacing.medium) {
                        HStack {
                            TextField("Search resources", text: $resourceSearch)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .pinesFieldChrome()
                            Button {
                                Task { await appModel.refreshMCPResources(server, services: services) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Refresh resources")
                            .pinesButtonStyle(.icon)
                        }

                        let resources = filteredResources(server)
                        if resources.isEmpty {
                            Text("No matching resources.")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                        ForEach(resources) { resource in
                            resourceRow(resource, server: server)
                        }

                        ForEach(filteredResourceTemplates(server)) { template in
                            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                Text(template.title ?? template.name)
                                    .font(theme.typography.callout.weight(.semibold))
                                Text(template.uriTemplate)
                                    .font(theme.typography.caption.monospaced())
                                    .foregroundStyle(theme.colors.secondaryText)
                                    .textSelection(.enabled)
                            }
                            .pinesSurface(.inset, padding: theme.spacing.small)
                        }
                    }
                    .padding(.top, theme.spacing.medium)
                } label: {
                    Label("Browse resources", systemImage: "doc.text.magnifyingglass")
                        .font(theme.typography.callout.weight(.semibold))
                }
                .padding(theme.spacing.medium)
            }
        }
    }

    private func resourceRow(_ resource: MCPResourceRecord, server: MCPServerConfiguration) -> some View {
        let previewKey = "\(server.id.rawValue)|\(resource.uri)"
        return VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text(resource.title ?? resource.name)
                .font(theme.typography.callout.weight(.semibold))
            Text(resource.uri)
                .font(theme.typography.caption.monospaced())
                .foregroundStyle(theme.colors.secondaryText)
                .textSelection(.enabled)

            if let preview = resourcePreviews[previewKey] {
                Text(preview)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }

            PinesAdaptiveButtonRow {
                Button("Preview") {
                    Task {
                        if let preview = await appModel.previewMCPResource(resource, services: services) {
                            resourcePreviews[previewKey] = preview
                        }
                    }
                }
                .pinesButtonStyle(.secondary, fillWidth: true)

                Toggle("Attach to chats", isOn: Binding(
                    get: { resource.selectedForContext },
                    set: { selected in
                        Task { await appModel.setMCPResourceSelected(resource, selected: selected, services: services) }
                    }
                ))
            }

            if server.subscriptionsEnabled {
                Toggle("Subscribe to updates", isOn: Binding(
                    get: { resource.subscribed },
                    set: { subscribed in
                        Task { await appModel.setMCPResourceSubscribed(resource, subscribed: subscribed, services: services) }
                    }
                ))
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    private func promptsGroup(_ server: MCPServerConfiguration) -> some View {
        PinesSettingsGroup("Prompts", detail: "Run reusable prompt templates exposed by this server.") {
            if !server.promptsEnabled {
                PinesSettingsValueRow(
                    "Prompts disabled",
                    value: "Off",
                    detail: "Enable Prompts in the server configuration to use this capability.",
                    systemImage: "text.bubble"
                )
            } else {
                DisclosureGroup(isExpanded: $showsPrompts) {
                    VStack(alignment: .leading, spacing: theme.spacing.medium) {
                        HStack {
                            TextField("Search prompts", text: $promptSearch)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .pinesFieldChrome()
                            Button {
                                Task { await appModel.refreshMCPPrompts(server, services: services) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Refresh prompts")
                            .pinesButtonStyle(.icon)
                        }

                        let prompts = filteredPrompts(server)
                        if prompts.isEmpty {
                            Text("No matching prompts.")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                        ForEach(prompts) { prompt in
                            promptRow(prompt)
                        }
                    }
                    .padding(.top, theme.spacing.medium)
                } label: {
                    Label("Browse prompts", systemImage: "text.bubble")
                        .font(theme.typography.callout.weight(.semibold))
                }
                .padding(theme.spacing.medium)
            }
        }
    }

    private func promptRow(_ prompt: MCPPromptRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text(prompt.title ?? prompt.name)
                .font(theme.typography.callout.weight(.semibold))
            if let description = prompt.description {
                Text(description)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(prompt.arguments, id: \.name) { argument in
                TextField(
                    argument.required == true ? "\(argument.name) (required)" : argument.name,
                    text: promptArgumentBinding(prompt: prompt, argument: argument)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pinesFieldChrome()
            }

            Button {
                Task {
                    await appModel.useMCPPrompt(
                        prompt,
                        arguments: promptArguments(for: prompt),
                        services: services
                    )
                }
            } label: {
                Label("Use prompt", systemImage: "text.bubble")
            }
            .pinesButtonStyle(.secondary, fillWidth: true)
        }
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    private func securityAndActivityGroup(_ server: MCPServerConfiguration) -> some View {
        PinesSettingsGroup("Security & activity") {
            DisclosureGroup(isExpanded: $showsSecurity) {
                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    LabeledContent("Authentication", value: server.authMode.settingsTitle)
                    LabeledContent("Local HTTP", value: server.allowInsecureLocalHTTP ? "Allowed" : "Blocked")
                    LabeledContent("Sampling", value: server.samplingEnabled ? "Enabled" : "Disabled")
                    if server.samplingEnabled {
                        LabeledContent("Sampling limit", value: "\(server.maxSamplingRequestsPerSession) per session")
                        LabeledContent("BYOK sampling", value: server.byokSamplingEnabled ? "Allowed" : "Blocked")
                    }
                    if let scopes = server.oauthScopes {
                        LabeledContent("OAuth scopes", value: scopes)
                    }
                    if let resource = server.oauthResource {
                        LabeledContent("OAuth resource", value: resource)
                    }

                    if server.authMode == .oauthPKCE {
                        PinesAdaptiveButtonRow {
                            Button("Connect OAuth") {
                                Task { await appModel.connectMCPOAuth(server, services: services) }
                            }
                            .pinesButtonStyle(.secondary, fillWidth: true)
                            Button("Disconnect") {
                                Task { await appModel.disconnectMCPOAuth(server, services: services) }
                            }
                            .pinesButtonStyle(.secondary, fillWidth: true)
                        }
                    }
                }
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, theme.spacing.medium)
            } label: {
                Label("Connection policy", systemImage: "lock.shield")
                    .font(theme.typography.callout.weight(.semibold))
            }
            .padding(theme.spacing.medium)
        }
    }

    private func filteredTools(_ server: MCPServerConfiguration) -> [MCPToolRecord] {
        let query = toolSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return settingsState.mcpTools.filter { tool in
            guard tool.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [tool.displayName, tool.namespacedName, tool.description, tool.originalName]
                .joined(separator: " ").lowercased().contains(query)
        }
    }

    private func filteredResources(_ server: MCPServerConfiguration) -> [MCPResourceRecord] {
        let query = resourceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return settingsState.mcpResources.filter { resource in
            guard resource.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [resource.name, resource.title ?? "", resource.description ?? "", resource.uri]
                .joined(separator: " ").lowercased().contains(query)
        }
    }

    private func filteredResourceTemplates(_ server: MCPServerConfiguration) -> [MCPResourceTemplateRecord] {
        let query = resourceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return settingsState.mcpResourceTemplates.filter { template in
            guard template.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [template.name, template.title ?? "", template.description ?? "", template.uriTemplate]
                .joined(separator: " ").lowercased().contains(query)
        }
    }

    private func filteredPrompts(_ server: MCPServerConfiguration) -> [MCPPromptRecord] {
        let query = promptSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return settingsState.mcpPrompts.filter { prompt in
            guard prompt.serverID == server.id else { return false }
            guard !query.isEmpty else { return true }
            return [prompt.name, prompt.title ?? "", prompt.description ?? "", prompt.arguments.map(\.name).joined(separator: " ")]
                .joined(separator: " ").lowercased().contains(query)
        }
    }

    private func promptArgumentBinding(prompt: MCPPromptRecord, argument: MCPPromptArgument) -> Binding<String> {
        let key = "\(prompt.id)|\(argument.name)"
        return Binding(
            get: { promptArguments[key] ?? "" },
            set: { promptArguments[key] = $0 }
        )
    }

    private func promptArguments(for prompt: MCPPromptRecord) -> [String: String] {
        Dictionary(uniqueKeysWithValues: prompt.arguments.compactMap { argument in
            let value = promptArguments["\(prompt.id)|\(argument.name)"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : (argument.name, value)
        })
    }
}

private extension MCPServerConfiguration {
    var settingsCapabilityTitles: [String] {
        var values = [String]()
        if resourcesEnabled { values.append("Resources") }
        if promptsEnabled { values.append("Prompts") }
        if samplingEnabled { values.append("Sampling") }
        return values
    }

    var settingsSummary: String {
        let host = endpointURL.host ?? endpointURL.absoluteString
        let capabilities = settingsCapabilityTitles.joined(separator: ", ").nilIfEmpty ?? "Tools"
        return "\(host) · \(capabilities)"
    }
}

private extension MCPAuthMode {
    var settingsTitle: String {
        switch self {
        case .none: "None"
        case .bearerToken: "Bearer token"
        case .oauthPKCE: "OAuth"
        }
    }
}

private extension MCPConnectionStatus {
    var settingsTitle: String {
        switch self {
        case .ready: "Ready"
        case .connecting: "Connecting"
        case .requiresAuthentication: "Sign-in required"
        case .degraded: "Degraded"
        case .failed: "Failed"
        case .disconnected: "Disconnected"
        }
    }

    var settingsTone: PinesCloudStatusTone {
        switch self {
        case .ready: .success
        case .connecting: .info
        case .requiresAuthentication, .degraded: .warning
        case .failed: .danger
        case .disconnected: .neutral
        }
    }

    var settingsCloudStatus: PinesCloudStatus {
        switch self {
        case .ready: .enabled
        case .connecting: .running
        case .requiresAuthentication: .accountGated
        case .degraded: .warning("Degraded")
        case .failed: .failed
        case .disconnected: .pending
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
