import SwiftUI
import PinesCore

private enum PinesSettingsDetailLayout {
    static let contentSpacing: CGFloat = 20
    static let contentPadding: CGFloat = 20
    static let contentMaxWidth: CGFloat = 760
    static let dashboardGridMinWidth: CGFloat = 144
    static let dashboardGridSpacing: CGFloat = 10
}

struct SettingsDetailView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var haptics: PinesHaptics
    let section: PinesSettingsSection
    let executionMode: AgentExecutionMode
    let storeConfiguration: LocalStoreConfiguration
    @Binding var selectedThemeTemplate: PinesThemeTemplate
    @Binding var interfaceMode: PinesInterfaceMode
    @State private var providerKind: CloudProviderKind = .openAI
    @State private var providerName = "OpenAI"
    @State private var providerBaseURL = "https://api.openai.com/v1"
    @State private var providerAPIKey = ""
    @State private var providerEnabled = true
    @State private var providerSaveConfirmation: String?
    @State private var providerSaveError: String?
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
    @State private var showsEraseAllDataConfirmation = false

    private var iCloudSyncAvailable: Bool {
        services.cloudKitSyncService != nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PinesSettingsDetailLayout.contentSpacing) {
                    settingsHeader(scrollProxy: proxy)

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
                .padding(PinesSettingsDetailLayout.contentPadding)
                .frame(maxWidth: PinesSettingsDetailLayout.contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .pinesExpressiveScrollHaptics()
        }
        .navigationTitle(section.title)
        .accessibilityIdentifier("pines.settings.detail.\(section.title.uiTestIdentifierComponent)")
        .confirmationDialog(
            "Delete all Pines data?",
            isPresented: $showsEraseAllDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete local and iCloud data", role: .destructive) {
                Task { await appModel.eraseAllUserData(services: services) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes local models, chats, vault files, provider records, credentials, MCP servers, artifacts, and the private iCloud sync zone when available.")
        }
        .task(id: section.destination) {
            guard section.destination == .tools else { return }
            await appModel.startMCPServersIfNeeded(services: services)
        }
        .pinesInlineNavigationTitle()
        .pinesAppBackground()
    }

    private var dashboardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: PinesSettingsDetailLayout.dashboardGridMinWidth), spacing: PinesSettingsDetailLayout.dashboardGridSpacing)]
    }

    private func settingsHeader(scrollProxy: ScrollViewProxy) -> some View {
        PinesCardSection(section.title, subtitle: section.subtitle, systemImage: section.systemImage, kind: .glass) {
            LazyVGrid(columns: dashboardColumns, spacing: PinesSettingsDetailLayout.dashboardGridSpacing) {
                ForEach(section.rows) { row in
                    Button {
                        guard let anchor = section.detailAnchor(for: row) else { return }
                        haptics.play(.navigationSelected)
                        withAnimation(theme.motion.standard) {
                            scrollProxy.scrollTo(anchor, anchor: .top)
                        }
                    } label: {
                        PinesInfoTile(title: row.title, value: row.detail, systemImage: row.systemImage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Jumps to this settings section")
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
        StableSettingsCardSection("Appearance", subtitle: "Theme, contrast, and interface behavior.", systemImage: "paintpalette") {
            Picker("Interface mode", selection: $interfaceMode) {
                ForEach(PinesInterfaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .pinesSegmentedPickerChrome()
            .onChange(of: interfaceMode) { _, _ in
                Task { await appModel.saveSettings(services: services) }
            }

            LazyVGrid(
                columns: PinesThemePickerLayout.gridColumns,
                spacing: PinesThemePickerLayout.gridSpacing
            ) {
                ForEach(PinesThemeTemplate.allCases) { template in
                    Button {
                        selectedThemeTemplate = template
                        haptics.play(.navigationSelected)
                        Task { await appModel.saveSettings(services: services) }
                    } label: {
                        PinesThemePreviewCard(template: template, isSelected: selectedThemeTemplate == template)
                    }
                    .buttonStyle(.plain)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .id(SettingsDetailAnchor.appearance)

        PinesCardSection("Haptics and Motion", subtitle: "A compact preview of feedback intensity and motion handling.", systemImage: "hand.tap") {
            Picker("Feedback", selection: $haptics.mode) {
                ForEach(PinesHapticMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .pinesSegmentedPickerChrome()
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
        .id(SettingsDetailAnchor.hapticsAndMotion)
    }

    @ViewBuilder
    private var inferenceDashboard: some View {
        PinesCardSection("Execution", subtitle: "Routing policy for local inference and configured providers.", systemImage: "point.3.connected.trianglepath.dotted") {
            Picker("Execution mode", selection: $settingsState.executionMode) {
                ForEach(AgentExecutionMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: settingsState.executionMode) { _, _ in
                Task { await appModel.saveSettings(services: services) }
            }
        }
        .id(SettingsDetailAnchor.execution)

        generationLimitsCard
        runtimeDiagnosticsCard
        huggingFaceCard
    }

    private var generationLimitsCard: some View {
        PinesCardSection("Generation Limits", subtitle: "Completion and local context budgets used for chat and sampling.", systemImage: "slider.horizontal.3") {
            Stepper(
                "Cloud completion tokens: \(settingsState.cloudMaxCompletionTokens.formatted())",
                value: $settingsState.cloudMaxCompletionTokens,
                in: AppSettingsSnapshot.minCompletionTokens...AppSettingsSnapshot.maxCompletionTokens,
                step: 1024
            )
            .onChange(of: settingsState.cloudMaxCompletionTokens) { _, _ in
                Task { await appModel.saveSettings(services: services) }
            }

            Stepper(
                "Local completion tokens: \(settingsState.localMaxCompletionTokens.formatted())",
                value: $settingsState.localMaxCompletionTokens,
                in: AppSettingsSnapshot.minCompletionTokens...AppSettingsSnapshot.maxCompletionTokens,
                step: 256
            )
            .onChange(of: settingsState.localMaxCompletionTokens) { _, _ in
                Task { await appModel.saveSettings(services: services) }
            }

            Stepper(
                "Requested local context tokens: \(settingsState.localMaxContextTokens.formatted())",
                value: $settingsState.localMaxContextTokens,
                in: AppSettingsSnapshot.minLocalContextTokens...AppSettingsSnapshot.maxLocalContextTokens,
                step: 1024
            )
            .onChange(of: settingsState.localMaxContextTokens) { _, _ in
                Task { await appModel.saveSettings(services: services) }
            }

            PinesKeyValueGrid(items: [
                .init("Cloud completion", "\(settingsState.cloudMaxCompletionTokens.formatted()) tokens", systemImage: "cloud"),
                .init("Local completion", "\(settingsState.localMaxCompletionTokens.formatted()) tokens", systemImage: "cpu"),
                .init("Requested local context", "\(settingsState.localMaxContextTokens.formatted()) tokens", systemImage: "text.word.spacing")
            ])
        }
        .id(SettingsDetailAnchor.generationLimits)
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
        if let valueBits = diagnostics.turboQuantValueBits { items.append(.init("Value bits", "\(valueBits)")) }
        if let requestedBackend = diagnostics.requestedBackend { items.append(.init("Requested backend", requestedBackend.displayName)) }
        if let activeBackend = diagnostics.activeBackend { items.append(.init("Active backend", activeBackend.displayName)) }
        if let attentionPath = diagnostics.activeAttentionPath { items.append(.init("Attention path", attentionPath.displayName)) }
        if let performanceClass = diagnostics.devicePerformanceClass { items.append(.init("Performance", performanceClass.displayName)) }
        if let kernelProfile = diagnostics.metalKernelProfile { items.append(.init("Kernel", kernelProfile.displayName)) }
        if let selfTest = diagnostics.metalSelfTestStatus { items.append(.init("MLX self-test", selfTest.displayName)) }
        if let policy = diagnostics.turboQuantOptimizationPolicy { items.append(.init("Optimization", policy.displayName)) }
        if let rawFallbackAllocated = diagnostics.rawFallbackAllocated { items.append(.init("Raw KV fallback", rawFallbackAllocated ? "Allocated" : "Not allocated")) }
        if let pressureReason = diagnostics.runtimePressureReason, pressureReason != .none {
            items.append(.init("Pressure reason", pressureReason.displayName))
        }
        if diagnostics.thermalDownshiftActive == true { items.append(.init("Pressure downshift", "Active")) }
        if let unsupportedShape = diagnostics.lastUnsupportedAttentionShape { items.append(.init("Unsupported shape", unsupportedShape, copyable: true)) }
        if let hardware = memory.hardwareModelIdentifier { items.append(.init("Device identifier", hardware, copyable: true)) }
        if let metalArchitecture = memory.metalArchitectureName { items.append(.init("Metal architecture", metalArchitecture)) }
        if let workingSet = memory.metalRecommendedWorkingSetBytes { items.append(.init("MLX working set", ByteCountFormatter.string(fromByteCount: workingSet, countStyle: .memory))) }
        if let lowPower = memory.lowPowerModeEnabled { items.append(.init("Low Power Mode", lowPower ? "On" : "Off")) }
        if let contextTokens = memory.recommendedContextTokens { items.append(.init("Context window", "\(contextTokens.formatted()) tokens")) }
        if let physicalMemory = memory.physicalMemoryBytes { items.append(.init("Device memory", ByteCountFormatter.string(fromByteCount: physicalMemory, countStyle: .memory))) }
        if let availableMemory = memory.availableMemoryBytes { items.append(.init("Available memory", ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory))) }
        if let memoryPressureReason = memory.runtimePressureReason, memoryPressureReason != .none {
            items.append(.init("Live pressure reason", memoryPressureReason.displayName))
        }
        if let thermalState = memory.thermalState { items.append(.init("System thermal state", thermalState.capitalized)) }
        if let fallback = diagnostics.activeFallbackReason { items.append(.init("Fallback", fallback, copyable: true)) }

        return PinesCardSection("Runtime Diagnostics", subtitle: "Live MLX and device routing state.", systemImage: "gauge.with.dots.needle.67percent") {
            PinesKeyValueGrid(items: items)
        }
        .id(SettingsDetailAnchor.runtimeDiagnostics)
    }

    private var huggingFaceCard: some View {
        PinesCardSection("Hugging Face", subtitle: "Hub token used for gated model downloads.", systemImage: "key") {
            PinesKeyValueGrid(items: [.init("Hub token", settingsState.huggingFaceCredentialStatus, systemImage: "checkmark.seal")])
            SecureField("Access token", text: $huggingFaceToken)
                .textContentType(.password)
                .accessibilityIdentifier("pines.settings.huggingface.token")
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
        .id(SettingsDetailAnchor.huggingFace)
    }

    @ViewBuilder
    private var privacyDashboard: some View {
        PinesCardSection("Storage and Sync", subtitle: "Local database protection and private iCloud sync controls.", systemImage: "externaldrive.badge.icloud") {
            PinesKeyValueGrid(items: [
                .init("Store", settingsState.storeConfiguration.databaseFileName, systemImage: "internaldrive", copyable: true),
                .init("Protection", settingsState.storeConfiguration.dataProtection.title, systemImage: "lock.shield"),
                .init("iCloud", iCloudSyncAvailable ? "Available" : "Unavailable", systemImage: "icloud")
            ])

            Toggle("Private iCloud sync", isOn: Binding(
                get: { iCloudSyncAvailable && settingsState.storeConfiguration.iCloudSyncEnabled },
                set: { value in
                    settingsState.storeConfiguration.iCloudSyncEnabled = iCloudSyncAvailable && value
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!iCloudSyncAvailable)

            Toggle("App lock", isOn: Binding(
                get: { settingsState.securityConfiguration.appLockEnabled },
                set: { value in
                    settingsState.securityConfiguration.appLockEnabled = value
                    Task { await appModel.saveSettings(services: services) }
                }
            ))

            Toggle("Sync source documents", isOn: Binding(
                get: { settingsState.storeConfiguration.syncsSourceDocuments },
                set: { value in
                    settingsState.storeConfiguration.syncsSourceDocuments = value
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!iCloudSyncAvailable || !settingsState.storeConfiguration.iCloudSyncEnabled)

            Toggle("Sync embeddings", isOn: Binding(
                get: { settingsState.storeConfiguration.syncsEmbeddings },
                set: { value in
                    settingsState.storeConfiguration.syncsEmbeddings = value
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!iCloudSyncAvailable || !settingsState.storeConfiguration.iCloudSyncEnabled)

            Button(role: .destructive) {
                showsEraseAllDataConfirmation = true
            } label: {
                if appModel.isErasingAllData {
                    ProgressView()
                } else {
                    Label("Delete all Pines data", systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.isErasingAllData)
        }
        .id(SettingsDetailAnchor.storageAndSync)

        cloudProviderCard
    }

    private var cloudProviderCard: some View {
        let proToggleEnabled = settingsState.proEntitlementStatus.enablesManagedCloud && services.managedCloudService.isConfigured
        return PinesCardSection("Cloud Intelligence", subtitle: "Use managed cloud or your own provider keys explicitly.", systemImage: "sparkles") {
            PinesKeyValueGrid(items: [
                .init("Pro", settingsState.proEntitlementStatus.title, systemImage: "crown"),
                .init("Cloud", settingsState.managedCloudConsent.title, systemImage: "sparkles"),
                .init("Pro service", services.managedCloudService.isConfigured ? "Ready" : "Unavailable", systemImage: "network"),
                .init("Access", settingsState.cloudAccessMode.title, systemImage: "point.3.connected.trianglepath.dotted"),
            ])

            Toggle("Use Pro Cloud Intelligence", isOn: Binding(
                get: {
                    settingsState.proEntitlementStatus.enablesManagedCloud
                        && settingsState.managedCloudConsent == .optedIn
                        && settingsState.cloudAccessMode.usesManagedCloud
                },
                set: { enabled in
                    if enabled {
                        settingsState.managedCloudConsent = .optedIn
                        settingsState.cloudAccessMode = .managedPro
                    } else {
                        settingsState.managedCloudConsent = .optedOut
                        if settingsState.cloudAccessMode.usesManagedCloud {
                            settingsState.cloudAccessMode = .byok
                        }
                    }
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!proToggleEnabled)

            Toggle("Use Advanced Keys as explicit fallback", isOn: Binding(
                get: { settingsState.cloudAccessMode == .managedProWithBYOKOverride },
                set: { enabled in
                    settingsState.cloudAccessMode = enabled ? .managedProWithBYOKOverride : .managedPro
                    Task { await appModel.saveSettings(services: services) }
                }
            ))
            .disabled(!settingsState.cloudAccessMode.usesManagedCloud || settingsState.cloudProviders.isEmpty)

            Text(cloudIntelligenceSummary)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: theme.spacing.medium) {
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
                    SecureField("API key", text: $providerAPIKey)
                        .textContentType(.password)
                        .pinesFieldChrome()
                    Toggle("Enable for agents", isOn: $providerEnabled)
                        .disabled(providerKind == .voyageAI)

                    Button {
                        Task {
                            providerSaveConfirmation = nil
                            providerSaveError = nil
                            let savedName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let didSave = await appModel.saveCloudProvider(
                                kind: providerKind,
                                displayName: providerName,
                                baseURLString: providerBaseURL,
                                apiKey: providerAPIKey,
                                enabledForAgents: providerEnabled,
                                services: services
                            )
                            if didSave {
                                providerAPIKey = ""
                                providerSaveConfirmation = "Saved \(savedName). Validating the key and refreshing models."
                            } else {
                                providerSaveError = appModel.serviceError ?? "Provider key could not be saved."
                            }
                        }
                    } label: {
                        if settingsState.isSavingCloudProvider {
                            Label("Saving", systemImage: "hourglass")
                        } else {
                            Label("Save key", systemImage: "key")
                        }
                    }
                    .disabled(
                        settingsState.isSavingCloudProvider
                            || providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || providerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .pinesButtonStyle(.primary, fillWidth: true)

                    if let providerSaveConfirmation {
                        Label(providerSaveConfirmation, systemImage: "checkmark.circle.fill")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.success)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let providerSaveError {
                        Label(providerSaveError, systemImage: "exclamationmark.triangle.fill")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if settingsState.isRefreshingCloudModels {
                        PinesStatusChip(status: .running)
                    }

                    if settingsState.cloudProviders.isEmpty {
                        Text("No cloud providers saved.")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    } else {
                        ForEach(settingsState.cloudProviders) { provider in
                            providerRow(provider)
                        }
                    }
                }
            } label: {
                Label("Cloud Providers", systemImage: "cloud")
                    .font(theme.typography.headline)
            }
        }
        .id(SettingsDetailAnchor.cloudBYOK)
    }

    private var cloudIntelligenceSummary: String {
        if !services.managedCloudService.isConfigured {
            return "Managed cloud is unavailable in this build. Local models and saved provider keys still work."
        }
        if !settingsState.proEntitlementStatus.enablesManagedCloud {
            return "Pro Cloud is inactive. No managed cloud call will be made."
        }
        switch settingsState.managedCloudConsent {
        case .optedIn:
            return settingsState.cloudAccessMode.usesManagedCloud
                ? "Managed cloud is available for selected routes. Saved provider keys remain available when you choose them."
                : "You are opted in, but managed routing is not selected."
        case .optedOut:
            return "Cloud Intelligence is off. Managed routes are disabled until you turn this back on."
        case .notAsked:
            return "Cloud Intelligence has not been enabled. Vault and chat content stay local unless you choose a saved provider key."
        case .revoked:
            return "Cloud Intelligence consent was revoked. Managed routes are disabled."
        }
    }

    private func providerRow(_ provider: CloudProviderConfiguration) -> some View {
        let isValidating = settingsState.validatingCloudProviderIDs.contains(provider.id)
        return VStack(alignment: .leading, spacing: theme.spacing.medium) {
            HStack(alignment: .center, spacing: theme.spacing.small) {
                Image(systemName: provider.kind.providerSystemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 34, height: 34)
                    .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(provider.displayName)
                        .font(theme.typography.headline)
                        .pinesFittingText()
                    Text(provider.kind.title)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: theme.spacing.small)

                PinesStatusChip(status: isValidating ? .running : provider.validationStatus.cloudStatus, compact: true)
            }

            VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                providerDetailLine(
                    title: "Endpoint",
                    value: providerEndpointSummary(provider.baseURL),
                    systemImage: "network"
                )

                if let defaultModelID = provider.defaultModelID {
                    providerDetailLine(
                        title: "Default model",
                        value: Self.compactModelName(defaultModelID.rawValue),
                        systemImage: "checkmark.circle"
                    )
                }
            }

            Divider()
                .overlay(theme.colors.separator)

            HStack(alignment: .center, spacing: theme.spacing.small) {
                Toggle("Use for agents", isOn: Binding(
                    get: { provider.enabledForAgents },
                    set: { enabled in
                        Task { await appModel.setCloudProviderEnabled(provider, enabled: enabled, services: services) }
                    }
                ))
                .disabled(provider.kind == .voyageAI)

                Spacer(minLength: theme.spacing.small)

                Button {
                    Task { await appModel.validateCloudProvider(provider, services: services) }
                } label: {
                    if isValidating {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.seal")
                    }
                }
                .accessibilityLabel("Validate \(provider.displayName)")
                .disabled(isValidating)
                .pinesButtonStyle(.icon)

                Button(role: .destructive) {
                    Task { await appModel.deleteCloudProvider(provider, services: services) }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete \(provider.displayName)")
                .pinesButtonStyle(.icon)
            }

            if let error = provider.lastValidationError?.nilIfEmpty {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.warning)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: theme.row.minHeight)
        .pinesSurface(.inset, padding: theme.spacing.small)
    }

    private func providerDetailLine(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xsmall) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.tertiaryText)
                .frame(width: 14)

            Text(title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.tertiaryText)

            Text(value)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }

    private func providerEndpointSummary(_ url: URL) -> String {
        if let host = url.host {
            return host
        }
        return url.absoluteString
    }

    @ViewBuilder
    private var toolsDashboard: some View {
        toolKeysCard
        mcpEditorCard
        mcpServersCard
    }

    private var toolKeysCard: some View {
        PinesCardSection("Agent Tool Keys", subtitle: "Credentials for built-in external tools.", systemImage: "wrench.and.screwdriver") {
            PinesKeyValueGrid(items: [.init("Brave Search", settingsState.braveSearchCredentialStatus, systemImage: "magnifyingglass")])
            SecureField("Brave Search API key", text: $braveSearchKey)
                .textContentType(.password)
                .accessibilityIdentifier("pines.settings.brave.key")
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
        .id(SettingsDetailAnchor.toolKeys)
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
                .accessibilityIdentifier("pines.settings.mcp.name")
                .pinesFieldChrome()
            TextField("Streamable HTTP endpoint", text: $mcpEndpointURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pines.settings.mcp.endpoint")
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
        .id(SettingsDetailAnchor.mcpEditor)
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
            if settingsState.mcpServers.isEmpty {
                PinesEmptyState(title: "No MCP servers", detail: "Add a streamable HTTP endpoint to expose tools to agents.", systemImage: "server.rack")
            } else {
                ForEach(settingsState.mcpServers) { server in
                    mcpServerCard(server)
                }
            }
        }
        .id(SettingsDetailAnchor.mcpServers)
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

                PinesStatusChip(status: server.status.cloudStatus, compact: true)

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
            .pinesSegmentedPickerChrome()

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
            PinesToolTimelineRow(
                title: "Discovery and tool availability",
                provider: server.displayName,
                toolType: "MCP streamable HTTP",
                status: server.status.cloudStatus,
                inputSummary: server.enabledCapabilityTitles.joined(separator: ", ").nilIfEmpty ?? "Tools only",
                outputSummary: server.lastConnectedAt.map { "Last connected \($0.formatted(date: .abbreviated, time: .shortened))" },
                environmentLabel: "Local device",
                metricItems: [
                    .init("Auth", value: server.authMode.title, systemImage: "lock", tone: server.authMode == .none ? .neutral : .info),
                    .init("Sampling", value: server.samplingEnabled ? "on" : "off", systemImage: "waveform.path.ecg", tone: server.samplingEnabled ? .warning : .neutral)
                ],
                systemImage: "server.rack"
            )
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
        return settingsState.mcpTools.filter { tool in
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
        return settingsState.mcpResources.filter { resource in
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
        return settingsState.mcpResourceTemplates.filter { template in
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
        return settingsState.mcpPrompts.filter { prompt in
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
        .id(SettingsDetailAnchor.architectureHealth)

        PinesCardSection("Audit Timeline", subtitle: "Recent privacy-preserving system events.", systemImage: "clock.arrow.circlepath") {
            if settingsState.auditEvents.isEmpty {
                PinesEmptyState(title: "No audit events", detail: "Audit entries appear here when the system records notable actions.", systemImage: "checkmark.shield")
            } else {
                PinesTimeline(items: Array(settingsState.auditEvents.prefix(8)).enumerated().map { index, event in
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
        .id(SettingsDetailAnchor.auditTimeline)
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
        providerEnabled = kind != .voyageAI
        providerSaveConfirmation = nil
        providerSaveError = nil
    }

    private static func compactModelName(_ rawValue: String) -> String {
        let name = rawValue
            .split(separator: "/")
            .last
            .map(String.init) ?? rawValue
        return name.replacingOccurrences(of: "_", with: " ")
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

private struct StableSettingsCardSection<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let subtitle: String?
    let systemImage: String
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 38, height: 38)
                    .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .pinesFittingText()

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }
                }
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 104, alignment: .topLeading)
        .background(theme.colors.surface, in: shape)
        .overlay {
            shape
                .strokeBorder(theme.colors.cardBorder, lineWidth: 1)
        }
        .shadow(color: theme.shadow.panelColor.opacity(0.24), radius: 8, x: 0, y: 4)
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

private enum SettingsDestination: Hashable {
    case design
    case inference
    case privacy
    case tools
    case system
}

private enum SettingsDetailAnchor: Hashable {
    case appearance
    case hapticsAndMotion
    case execution
    case generationLimits
    case runtimeDiagnostics
    case huggingFace
    case storageAndSync
    case cloudBYOK
    case toolKeys
    case mcpEditor
    case mcpServers
    case architectureHealth
    case auditTimeline
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

    func detailAnchor(for row: PinesSettingsRow) -> SettingsDetailAnchor? {
        switch (destination, row.title) {
        case (.design, "Theme template"):
            .appearance
        case (.design, "Interaction feel"):
            .hapticsAndMotion
        case (.inference, "Execution policy"):
            .execution
        case (.inference, "Generation limits"):
            .generationLimits
        case (.inference, "Runtime diagnostics"):
            .runtimeDiagnostics
        case (.privacy, "Vault storage"):
            .storageAndSync
        case (.privacy, "Provider keys"):
            .cloudBYOK
        case (.tools, "Tool approval"):
            .toolKeys
        case (.tools, "MCP servers"):
            .mcpServers
        case (.system, "Architecture health"):
            .architectureHealth
        case (.system, "Audit trail"):
            .auditTimeline
        default:
            nil
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

private extension CloudAccessMode {
    var title: String {
        switch self {
        case .localOnly:
            "Local only"
        case .byok:
            "Advanced Keys"
        case .managedPro:
            "Pro Cloud"
        case .managedProWithBYOKOverride:
            "Pro Cloud + Keys"
        }
    }
}

private extension ProEntitlementStatus {
    var title: String {
        switch self {
        case .inactive:
            "Inactive"
        case .active:
            "Active"
        case .expired:
            "Expired"
        case .billingRetry:
            "Billing retry"
        case .revoked:
            "Revoked"
        }
    }
}

private extension ManagedCloudConsent {
    var title: String {
        switch self {
        case .notAsked:
            "Not enabled"
        case .optedIn:
            "On"
        case .optedOut:
            "Off"
        case .revoked:
            "Revoked"
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
        case .openAI:
            "OpenAI"
        case .openAICompatible:
            "OpenAI-compatible"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        case .openRouter:
            "OpenRouter"
        case .voyageAI:
            "Voyage AI"
        case .custom:
            "Custom"
        }
    }

    var defaultDisplayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .openAICompatible:
            "OpenAI-compatible"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        case .openRouter:
            "OpenRouter"
        case .voyageAI:
            "Voyage AI"
        case .custom:
            "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI:
            "https://api.openai.com/v1"
        case .openAICompatible:
            "https://"
        case .anthropic:
            "https://api.anthropic.com"
        case .gemini:
            "https://generativelanguage.googleapis.com"
        case .openRouter:
            "https://openrouter.ai/api/v1"
        case .voyageAI:
            "https://api.voyageai.com/v1"
        case .custom:
            "https://"
        }
    }

    var providerSystemImage: String {
        switch self {
        case .openAI, .openAICompatible, .openRouter, .custom:
            "cloud"
        case .anthropic:
            "text.bubble"
        case .gemini:
            "sparkles"
        case .voyageAI:
            "square.stack.3d.up"
        }
    }

}

private extension ProviderValidationStatus {
    var cloudStatus: PinesCloudStatus {
        switch self {
        case .valid:
            .enabled
        case .unvalidated:
            .needsValidation
        case .invalid:
            .failed
        case .rateLimited:
            .warning("Rate limited")
        }
    }
}

private extension MCPConnectionStatus {
    var cloudStatus: PinesCloudStatus {
        switch self {
        case .ready:
            .enabled
        case .connecting:
            .running
        case .requiresAuthentication:
            .accountGated
        case .degraded:
            .warning("Degraded")
        case .failed:
            .failed
        case .disconnected:
            .pending
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
