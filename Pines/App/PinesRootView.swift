import SwiftUI
import LocalAuthentication
import PinesCore
import UniformTypeIdentifiers

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct PinesRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appModel: PinesAppModel
    @StateObject private var chatState: PinesChatState
    @StateObject private var modelState: PinesModelState
    @StateObject private var vaultState: PinesVaultState
    @StateObject private var settingsState: PinesSettingsState
    @StateObject private var providerLifecycleState: PinesProviderLifecycleState
    @StateObject private var workflowState: PinesWorkflowState
    @StateObject private var haptics = PinesHaptics()
    @State private var services: PinesAppServices?
    @State private var watchSessionService: PhoneWatchSessionService?
    @State private var selectedTab: PinesTab = .chats
    @State private var requestedSettingsSectionID: UUID?
    @State private var isMainUIReady = false
    @State private var showsBootMark = true
    @State private var didStartBootstrap = false
    @State private var didReportMainUIAppeared = false
    @State private var isBootstrapping = false
    @State private var bootstrapTask: Task<Void, Never>?
    @State private var rootCreatedAt = Date()
    @State private var isPrivacyCoverVisible = false
    @State private var isPrivacyLocked = false
    @State private var appUnlockError: String?
    @State private var isUITestBootstrapReady = false

    init() {
        let chatState = PinesChatState()
        let modelState = PinesModelState()
        let vaultState = PinesVaultState()
        let settingsState = PinesSettingsState()
        let providerLifecycleState = PinesProviderLifecycleState()
        let workflowState = PinesWorkflowState()
        _chatState = StateObject(wrappedValue: chatState)
        _modelState = StateObject(wrappedValue: modelState)
        _vaultState = StateObject(wrappedValue: vaultState)
        _settingsState = StateObject(wrappedValue: settingsState)
        _providerLifecycleState = StateObject(wrappedValue: providerLifecycleState)
        _workflowState = StateObject(wrappedValue: workflowState)
        _appModel = StateObject(
            wrappedValue: PinesAppModel(
                chatState: chatState,
                modelState: modelState,
                vaultState: vaultState,
                settingsState: settingsState,
                providerLifecycleState: providerLifecycleState,
                workflowState: workflowState
            )
        )
    }

    private var theme: PinesTheme {
        PinesTheme.resolve(
            template: settingsState.selectedThemeTemplate,
            mode: settingsState.interfaceMode,
            systemScheme: systemScheme
        )
    }

    private var canShowPrivacyLock: Bool {
        !PinesUITestLaunchConfiguration.isEnabled
    }

    var body: some View {
        ZStack {
            if isMainUIReady, let services {
                tabShell(services: services)
                    .environmentObject(appModel)
                    .environmentObject(chatState)
                    .environmentObject(modelState)
                    .environmentObject(vaultState)
                    .environmentObject(settingsState)
                    .environmentObject(providerLifecycleState)
                    .environmentObject(workflowState)
                    .environmentObject(haptics)
                    .environment(\.pinesServices, services)
                    .environment(\.openPinesModelsPage, PinesOpenModelsPageAction {
                        selectedTab = .models
                    })
                    .environment(\.openPinesProviderSettings, PinesOpenProviderSettingsAction {
                        requestedSettingsSectionID = UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20001")
                        selectedTab = .settings
                    })
                    .pinesTheme(theme)
                    .transition(.opacity)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let serviceError = appModel.serviceError {
                            PinesGlobalErrorBanner(
                                message: serviceError,
                                dismiss: { appModel.serviceError = nil }
                            )
                            .padding(.horizontal, theme.spacing.medium)
                            .padding(.top, theme.spacing.xsmall)
                            .pinesTheme(theme)
                        }
                    }
            }

            if showsBootMark {
                PinesBootMarkView()
                    .environmentObject(haptics)
                    .pinesTheme(theme)
                    .ignoresSafeArea()
                    .zIndex(1)
            }

            if canShowPrivacyLock, isPrivacyCoverVisible || isPrivacyLocked {
                privacyCover
                    .zIndex(2)
            }

            #if DEBUG
            if isUITestBootstrapReady {
                Text(".")
                    .font(.system(size: 8))
                    .foregroundStyle(.clear)
                    .frame(width: 10, height: 10)
                    .accessibilityElement()
                    .accessibilityLabel("Pines UI test ready")
                    .accessibilityIdentifier("pines.ui-test.ready")
            }
            #endif
        }
        .pinesHighRefreshRate()
        .preferredColorScheme(settingsState.interfaceMode.colorScheme)
        .task {
            guard !didStartBootstrap, !isBootstrapping else { return }
            didStartBootstrap = true
            isBootstrapping = true

            let totalStartedAt = Date()
            PinesRuntimeMetrics.shared.start()
            PinesRuntimeMetrics.shared.recordStartupPhase("root_task_visible", elapsedSeconds: Date().timeIntervalSince(rootCreatedAt))
            await Task.yield()
            PinesRuntimeMetrics.shared.recordStartupPhase("boot_first_frame_yield", elapsedSeconds: Date().timeIntervalSince(totalStartedAt))

            let servicesStartedAt = Date()
            let services = PinesAppServices(loadsDefaultStore: PinesUITestLaunchConfiguration.isEnabled)
            self.services = services
            #if DEBUG
            if PinesUITestLaunchConfiguration.isEnabled {
                if services.liveStore == nil {
                    appModel.serviceError = services.defaultStoreStartupError ?? "UI test local store is unavailable."
                }
            }
            #endif
            services.runtimeMetrics.recordStartupPhase("services_init", elapsedSeconds: Date().timeIntervalSince(servicesStartedAt))

            await services.prepareForFirstFrame()
            #if canImport(WatchConnectivity)
            let watchSessionService = PhoneWatchSessionService(services: services)
            watchSessionService.start()
            self.watchSessionService = watchSessionService
            #endif

            isMainUIReady = true
            withAnimation(reduceMotion ? nil : theme.motion.emphasized) {
                showsBootMark = false
            }
            haptics.play(.appReady)
            services.runtimeMetrics.recordStartupPhase("root_boot_to_main", elapsedSeconds: Date().timeIntervalSince(totalStartedAt))

            bootstrapTask = Task { @MainActor in
                defer { isBootstrapping = false }
                await Task.yield()
                let installStateStartedAt = Date()
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try AppInstallStateCoordinator.prepareForLaunch()
                    }.value
                } catch {
                    appModel.serviceError = error.localizedDescription
                }
                services.runtimeMetrics.recordStartupPhase("install_state", elapsedSeconds: Date().timeIntervalSince(installStateStartedAt))

                let storeReady = await services.loadDefaultStoreIfNeeded()
                if !storeReady, let error = services.defaultStoreStartupError {
                    appModel.serviceError = error
                }
                await appModel.bootstrap(services: services)
                #if DEBUG
                if PinesUITestLaunchConfiguration.isEnabled {
                    isUITestBootstrapReady = storeReady
                }
                #endif
                #if DEBUG
                await appModel.runLaunchTurboQuantBenchIfNeeded()
                await appModel.runLaunchRealModelTurboQuantBenchIfNeeded(services: services)
                await appModel.runLaunchStressModeIfNeeded(services: services)
                #endif
                haptics.prepare()
                services.runtimeMetrics.recordStartupPhase("root_bootstrap_complete", elapsedSeconds: Date().timeIntervalSince(totalStartedAt))
            }
        }
        .onChange(of: workflowState.hapticSignal) { _, signal in
            guard let signal else { return }
            haptics.play(signal.event)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: settingsState.securityConfiguration.appLockEnabled) { _, enabled in
            guard canShowPrivacyLock, enabled else {
                isPrivacyLocked = false
                isPrivacyCoverVisible = false
                appUnlockError = nil
                return
            }
            isPrivacyLocked = true
            isPrivacyCoverVisible = true
            Task { await authenticateAppUnlock() }
        }
        .onPinesMemoryWarning {
            if let services {
                Task {
                    await services.handleMemoryPressure()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            guard ProcessInfo.processInfo.thermalState == .critical else { return }
            if let services {
                Task {
                    await services.handleThermalPressure()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinesRecoveredModelDownloadDidFinish)) { _ in
            guard let services else { return }
            Task {
                await appModel.reconcileModelDownloads(services: services)
            }
        }
        .sheet(item: Binding(
            get: { workflowState.pendingToolApproval },
            set: { request in
                if request == nil {
                    appModel.resolvePendingToolApproval(.denied)
                }
            }
        )) { request in
            ToolApprovalSheet(
                request: request,
                deny: { appModel.resolvePendingToolApproval(.denied) },
                approve: { appModel.resolvePendingToolApproval(.approved) }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { workflowState.pendingHostedToolApproval },
            set: { request in
                if request == nil {
                    appModel.resolvePendingHostedToolApproval(false, services: services)
                }
            }
        )) { request in
            HostedToolApprovalSheet(
                request: request,
                deny: { appModel.resolvePendingHostedToolApproval(false, services: services) },
                approve: { appModel.resolvePendingHostedToolApproval(true, services: services) }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { workflowState.pendingCloudContextApproval },
            set: { request in
                if request == nil {
                    appModel.resolvePendingCloudContextApproval(.cancel)
                }
            }
        )) { request in
            CloudContextApprovalSheet(
                request: request,
                cancel: { appModel.resolvePendingCloudContextApproval(.cancel) },
                sendWithoutContext: { appModel.resolvePendingCloudContextApproval(.sendWithoutContext) },
                sendWithContext: { appModel.resolvePendingCloudContextApproval(.sendWithContext) }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { workflowState.pendingCloudVaultEmbeddingApproval },
            set: { request in
                if request == nil {
                    appModel.resolvePendingCloudVaultEmbeddingApproval(false)
                }
            }
        )) { request in
            CloudVaultEmbeddingApprovalSheet(
                request: request,
                cancel: { appModel.resolvePendingCloudVaultEmbeddingApproval(false) },
                approve: { appModel.resolvePendingCloudVaultEmbeddingApproval(true) }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { workflowState.pendingMCPSamplingRequest },
            set: { request in
                if request == nil {
                    appModel.resolvePendingMCPSampling(false)
                }
            }
        )) { request in
            MCPSamplingApprovalSheet(
                request: request,
                promptDraft: $workflowState.mcpSamplingPromptDraft,
                deny: { appModel.resolvePendingMCPSampling(false) },
                approve: { appModel.resolvePendingMCPSampling(true) }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { workflowState.pendingMCPSamplingResultReview },
            set: { review in
                if review == nil {
                    appModel.resolvePendingMCPSamplingResultReview(false)
                }
            }
        )) { review in
            MCPSamplingResultReviewSheet(
                review: review,
                deny: { appModel.resolvePendingMCPSamplingResultReview(false) },
                approve: { appModel.resolvePendingMCPSamplingResultReview(true) }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var privacyCover: some View {
        ZStack {
            theme.colors.appBackground.ignoresSafeArea()
            VStack(spacing: theme.spacing.medium) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                Text("Pines Locked")
                    .font(theme.typography.title.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                if let appUnlockError {
                    Text(appUnlockError)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, theme.spacing.large)
                }
                if isPrivacyLocked {
                    Button {
                        Task { await authenticateAppUnlock() }
                    } label: {
                        Label("Unlock", systemImage: "faceid")
                    }
                    .pinesButtonStyle(.primary)
                }
            }
        }
        .pinesTheme(theme)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        let appLockEnabled = canShowPrivacyLock && settingsState.securityConfiguration.appLockEnabled
        switch phase {
        case .active:
            if let services {
                Task {
                    await services.mlxRuntime.setForegroundActive(true)
                    appModel.scheduleCloudKitSync(
                        services: services,
                        reason: "foreground_active",
                        delaySeconds: 3
                    )
                }
            }
            if appLockEnabled, isPrivacyLocked {
                Task { await authenticateAppUnlock() }
            } else if !appLockEnabled {
                isPrivacyCoverVisible = false
                isPrivacyLocked = false
                appUnlockError = nil
            }
        case .inactive, .background:
            isPrivacyCoverVisible = canShowPrivacyLock
            if let services {
                Task {
                    await appModel.stopLocalRuntimeForBackground(services: services)
                }
            }
            if appLockEnabled {
                isPrivacyLocked = true
            } else {
                isPrivacyLocked = false
                appUnlockError = nil
            }
        @unknown default:
            isPrivacyCoverVisible = canShowPrivacyLock
        }
    }

    @MainActor
    private func authenticateAppUnlock() async {
        guard canShowPrivacyLock, settingsState.securityConfiguration.appLockEnabled else {
            isPrivacyLocked = false
            isPrivacyCoverVisible = false
            appUnlockError = nil
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            appUnlockError = error?.localizedDescription ?? "Device authentication is unavailable."
            return
        }
        do {
            let approved = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Pines"
            )
            if approved {
                isPrivacyLocked = false
                isPrivacyCoverVisible = false
                appUnlockError = nil
            }
        } catch {
            appUnlockError = "Authentication was not completed."
        }
    }

    private func tabShell(services: PinesAppServices) -> some View {
        TabView(selection: $selectedTab) {
            ChatsView()
                .tabItem { Label(PinesTab.chats.title, systemImage: PinesTab.chats.systemImage) }
                .tag(PinesTab.chats)
                .accessibilityIdentifier("pines.tab.chats")

            ModelsView()
                .tabItem { Label(PinesTab.models.title, systemImage: PinesTab.models.systemImage) }
                .tag(PinesTab.models)
                .accessibilityIdentifier("pines.tab.models")

            VaultView()
                .tabItem { Label(PinesTab.vault.title, systemImage: PinesTab.vault.systemImage) }
                .tag(PinesTab.vault)
                .accessibilityIdentifier("pines.tab.vault")

            ArtifactsWorkspaceView()
                .tabItem { Label(PinesTab.artifacts.title, systemImage: PinesTab.artifacts.systemImage) }
                .tag(PinesTab.artifacts)
                .accessibilityIdentifier("pines.tab.artifacts")

            SettingsView(requestedSectionID: $requestedSettingsSectionID)
                .tabItem { Label(PinesTab.settings.title, systemImage: PinesTab.settings.systemImage) }
                .tag(PinesTab.settings)
                .accessibilityIdentifier("pines.tab.settings")
        }
        .accessibilityIdentifier("pines.root.tabs")
        .pinesAdaptiveTabViewStyle()
        .tint(theme.colors.accent)
        .background {
            Rectangle()
                .fill(theme.colors.backgroundWash)
                .ignoresSafeArea()
        }
        .onAppear {
            guard !didReportMainUIAppeared else { return }
            didReportMainUIAppeared = true
            services.runtimeMetrics.recordStartupPhase("main_ui_appeared", elapsedSeconds: 0)
        }
        .onChange(of: selectedTab) { _, _ in
            haptics.play(.tabChanged)
        }
    }
}
struct PinesOpenModelsPageAction: Sendable {
    var action: @MainActor @Sendable () -> Void

    @MainActor
    func callAsFunction() {
        action()
    }
}

struct PinesOpenProviderSettingsAction: Sendable {
    var action: @MainActor @Sendable () -> Void

    @MainActor
    func callAsFunction() {
        action()
    }
}

private extension View {
    @ViewBuilder
    func pinesAdaptiveTabViewStyle() -> some View {
        if PinesUITestLaunchConfiguration.isEnabled {
            if #available(iOS 18.0, *) {
                tabViewStyle(.tabBarOnly)
            } else {
                self
            }
        } else if #available(iOS 18.0, *) {
            tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}

private struct PinesOpenModelsPageKey: EnvironmentKey {
    static let defaultValue = PinesOpenModelsPageAction {}
}

private struct PinesOpenProviderSettingsKey: EnvironmentKey {
    static let defaultValue = PinesOpenProviderSettingsAction {}
}

extension EnvironmentValues {
    var openPinesModelsPage: PinesOpenModelsPageAction {
        get { self[PinesOpenModelsPageKey.self] }
        set { self[PinesOpenModelsPageKey.self] = newValue }
    }

    var openPinesProviderSettings: PinesOpenProviderSettingsAction {
        get { self[PinesOpenProviderSettingsKey.self] }
        set { self[PinesOpenProviderSettingsKey.self] = newValue }
    }
}

private struct ToolApprovalSheet: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var haptics: PinesHaptics
    let request: ToolApprovalRequest
    let deny: () -> Void
    let approve: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool") {
                    LabeledContent("Name", value: request.invocation.toolName)
                    LabeledContent("Access", value: request.invocation.privacyImpact.isEmpty ? "Local" : request.invocation.privacyImpact)
                }

                Section("Reason") {
                    Text(request.invocation.reason)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.primaryText)

                    Text(request.invocation.expectedOutput)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }

                if !request.invocation.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Arguments") {
                        Text(prettyArguments)
                            .font(theme.typography.code)
                            .foregroundStyle(theme.colors.secondaryText)
                            .textSelection(.enabled)
                    }
                }
            }
            .pinesThemedForm()
            .pinesExpressiveScrollHaptics()
            .navigationTitle("Approve Tool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deny", role: .cancel) {
                        haptics.play(.primaryAction)
                        deny()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") {
                        haptics.play(.primaryAction)
                        approve()
                    }
                }
            }
        }
    }

    private var prettyArguments: String {
        let raw = request.invocation.argumentsJSON
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return raw
        }
        return String(decoding: pretty, as: UTF8.self)
    }
}

private struct HostedToolApprovalSheet: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var haptics: PinesHaptics
    let request: HostedToolApprovalRequest
    let deny: () -> Void
    let approve: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider Environment") {
                    LabeledContent("Provider", value: request.providerName)
                    LabeledContent("Model", value: request.modelID.rawValue)
                    Text("These tools run outside this iPhone. Review what leaves the device and what each hosted environment can change.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }

                ForEach(request.descriptors) { descriptor in
                    Section(descriptor.displayName) {
                        LabeledContent("Runs in", value: descriptor.environment)
                        hostedApprovalList("Data leaving this device", values: descriptor.dataLeavingDevice)
                        hostedApprovalList("Possible side effects", values: descriptor.sideEffects)
                        hostedApprovalList("Network destinations", values: descriptor.networkDestinations)
                        Text(descriptor.retentionNotice)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }
            .pinesThemedForm()
            .navigationTitle("Approve Hosted Tools")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deny", role: .cancel) {
                        haptics.play(.primaryAction)
                        deny()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve Once") {
                        haptics.play(.primaryAction)
                        approve()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hostedApprovalList(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
            Text(title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: "circle.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

private struct CloudContextApprovalSheet: View {
    @Environment(\.pinesTheme) private var theme
    let request: CloudContextApprovalRequest
    let cancel: () -> Void
    let sendWithoutContext: () -> Void
    let sendWithContext: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloud Context") {
                    LabeledContent("Provider", value: request.providerID.rawValue)
                    LabeledContent("Model", value: request.modelID.rawValue)
                    LabeledContent("Vault documents", value: "\(request.documentIDs.count)")
                    LabeledContent("MCP resources", value: "\(request.mcpResourceIDs.count)")
                    LabeledContent(
                        "Context size",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(request.estimatedContextBytes),
                            countStyle: .file
                        )
                    )
                }

                Section("Privacy") {
                    Text("Selected local vault and MCP resource context can be sent to this cloud provider for this turn.")
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .pinesThemedForm()
            .pinesExpressiveScrollHaptics()
            .navigationTitle("Send Local Context?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: cancel)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Without Context", action: sendWithoutContext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Context", action: sendWithContext)
                }
            }
        }
    }
}

private struct CloudVaultEmbeddingApprovalSheet: View {
    @Environment(\.pinesTheme) private var theme
    let request: CloudVaultEmbeddingApprovalRequest
    let cancel: () -> Void
    let approve: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault Embeddings") {
                    LabeledContent("Provider", value: request.profile.displayName)
                    LabeledContent("Model", value: request.profile.modelID.rawValue)
                    LabeledContent("Dimensions", value: "\(request.profile.dimensions)")
                }

                Section("Privacy") {
                    Text(request.reason)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.secondaryText)
                    Text("This is separate from chat context approval. You can change the vault embedding provider later from the Vault tab.")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.tertiaryText)
                }
            }
            .pinesThemedForm()
            .pinesExpressiveScrollHaptics()
            .navigationTitle("Enable Cloud Embeddings?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enable", action: approve)
                }
            }
        }
    }
}

private struct MCPSamplingApprovalSheet: View {
    @Environment(\.pinesTheme) private var theme
    let request: MCPSamplingRequest
    @Binding var promptDraft: String
    let deny: () -> Void
    let approve: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Server", value: request.serverID.rawValue)
                    LabeledContent("Max tokens", value: "\(request.maxTokens ?? 512)")
                    LabeledContent("Temperature", value: String(format: "%.2f", request.temperature ?? 0.6))
                    LabeledContent("Include context", value: request.includeContext ?? "Unspecified")
                    LabeledContent("Tools", value: request.tools.isEmpty ? "None" : "\(request.tools.count)")
                }

                Section("Prompt") {
                    TextEditor(text: $promptDraft)
                        .frame(minHeight: 220)
                        .font(theme.typography.body)
                        .pinesExpressiveScrollHaptics()
                }

                if let preferences = request.modelPreferences {
                    Section("Model Preferences") {
                        Text(String(describing: preferences))
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }
            .pinesThemedForm()
            .pinesExpressiveScrollHaptics()
            .navigationTitle("MCP Sampling")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deny", role: .cancel, action: deny)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate", action: approve)
                }
            }
        }
        .pinesDismissKeyboardOnSwipeDown()
    }
}

private struct MCPSamplingResultReviewSheet: View {
    @Environment(\.pinesTheme) private var theme
    let review: MCPSamplingResultReview
    let deny: () -> Void
    let approve: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Result") {
                    LabeledContent("Server", value: review.serverID.rawValue)
                    LabeledContent("Model", value: review.result.model)
                    if let stopReason = review.result.stopReason {
                        LabeledContent("Stop reason", value: stopReason)
                    }
                    Text(review.summary)
                        .font(theme.typography.body)
                        .textSelection(.enabled)
                }
            }
            .pinesThemedForm()
            .pinesExpressiveScrollHaptics()
            .navigationTitle("Return Sampling Result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deny", role: .cancel, action: deny)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Return", action: approve)
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func onPinesMemoryWarning(_ action: @escaping () -> Void) -> some View {
        #if canImport(UIKit)
        self.onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            action()
        }
        #else
        self
        #endif
    }
}

private enum PinesTab: Hashable {
    case chats
    case models
    case vault
    case artifacts
    case settings

    var title: String {
        switch self {
        case .chats:
            "Chats"
        case .models:
            "Models"
        case .vault:
            "Vault"
        case .artifacts:
            "Artifacts"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .chats:
            "bubble.left.and.text.bubble.right"
        case .models:
            "cpu"
        case .vault:
            "shippingbox"
        case .artifacts:
            "rectangle.stack.badge.play"
        case .settings:
            "gearshape"
        }
    }
}
