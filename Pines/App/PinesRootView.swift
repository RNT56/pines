import SwiftUI
import LocalAuthentication
import PinesCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct PinesRootView: View {
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
                    .pinesTheme(theme)
                    .transition(.opacity)
            }

            if showsBootMark {
                PinesBootMarkView()
                    .environmentObject(haptics)
                    .pinesTheme(theme)
                    .ignoresSafeArea()
                    .zIndex(1)
            }

            if isPrivacyCoverVisible || isPrivacyLocked {
                privacyCover
                    .zIndex(2)
            }
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
            let services = PinesAppServices()
            self.services = services
            services.runtimeMetrics.recordStartupPhase("services_init", elapsedSeconds: Date().timeIntervalSince(servicesStartedAt))

            await services.prepareForFirstFrame()
            #if canImport(WatchConnectivity)
            let watchSessionService = PhoneWatchSessionService(services: services)
            watchSessionService.start()
            self.watchSessionService = watchSessionService
            #endif

            isMainUIReady = true
            withAnimation(theme.motion.emphasized) {
                showsBootMark = false
            }
            haptics.play(.appReady)
            services.runtimeMetrics.recordStartupPhase("root_boot_to_main", elapsedSeconds: Date().timeIntervalSince(totalStartedAt))

            bootstrapTask = Task { @MainActor in
                defer { isBootstrapping = false }
                await Task.yield()
                await appModel.bootstrap(services: services)
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
            guard enabled else {
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
            appModel.stopCurrentRun()
            if let services {
                Task {
                    await services.handleMemoryPressure()
                }
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
        switch phase {
        case .active:
            if settingsState.securityConfiguration.appLockEnabled, isPrivacyLocked {
                Task { await authenticateAppUnlock() }
            } else if !settingsState.securityConfiguration.appLockEnabled {
                isPrivacyCoverVisible = false
            }
        case .inactive, .background:
            isPrivacyCoverVisible = true
            if settingsState.securityConfiguration.appLockEnabled {
                isPrivacyLocked = true
            }
        @unknown default:
            isPrivacyCoverVisible = true
        }
    }

    @MainActor
    private func authenticateAppUnlock() async {
        guard settingsState.securityConfiguration.appLockEnabled else {
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

            ModelsView()
                .tabItem { Label(PinesTab.models.title, systemImage: PinesTab.models.systemImage) }
                .tag(PinesTab.models)

            VaultView()
                .tabItem { Label(PinesTab.vault.title, systemImage: PinesTab.vault.systemImage) }
                .tag(PinesTab.vault)

            ProviderWorkspaceView()
                .tabItem { Label(PinesTab.artifacts.title, systemImage: PinesTab.artifacts.systemImage) }
                .tag(PinesTab.artifacts)

            SettingsView()
                .tabItem { Label(PinesTab.settings.title, systemImage: PinesTab.settings.systemImage) }
                .tag(PinesTab.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
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

private struct PinesOpenModelsPageKey: EnvironmentKey {
    static let defaultValue = PinesOpenModelsPageAction {}
}

extension EnvironmentValues {
    var openPinesModelsPage: PinesOpenModelsPageAction {
        get { self[PinesOpenModelsPageKey.self] }
        set { self[PinesOpenModelsPageKey.self] = newValue }
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

private struct ProviderWorkspaceView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.large) {
                    PinesSectionHeader(
                        "Provider Artifacts",
                        subtitle: "Hosted files, media, structured outputs, batches, realtime sessions, and research runs."
                    )

                    ProviderLifecycleDashboard()

                    DeepResearchWorkspace()

                    RealtimeWorkspace()

                    ProviderLibrarySection(
                        title: "Artifacts",
                        subtitle: "Generated media, hosted tool outputs, transcripts, and imported batch results.",
                        systemImage: "sparkles",
                        isEmpty: providerState.providerArtifactPreviews.isEmpty
                    ) {
                        ForEach(providerState.providerArtifactPreviews) { artifact in
                            ProviderArtifactRow(artifact: artifact)
                        }
                    }

                    ProviderLibrarySection(
                        title: "Structured Outputs",
                        subtitle: "Persisted schema results and validation state from cloud responses.",
                        systemImage: "curlybraces.square",
                        isEmpty: providerState.providerStructuredOutputPreviews.isEmpty
                    ) {
                        ForEach(providerState.providerStructuredOutputPreviews) { output in
                            ProviderStructuredOutputRow(output: output)
                        }
                    }

                    ProviderLibrarySection(
                        title: "Batches",
                        subtitle: "Background batch jobs and vector-store file batches.",
                        systemImage: "tray.full",
                        isEmpty: providerState.providerBatchPreviews.isEmpty
                    ) {
                        ForEach(providerState.providerBatchPreviews) { batch in
                            ProviderBatchRow(batch: batch)
                        }
                    }
                }
                .padding(theme.spacing.large)
                .frame(maxWidth: theme.spacing.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .pinesExpressiveScrollHaptics()
            .pinesAppBackground()
            .navigationTitle("Artifacts")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await appModel.refreshProviderLifecycleState(services: services) }
                    } label: {
                        if providerState.isRefreshingProviderLifecycle {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .accessibilityLabel("Refresh provider artifacts")

                    Button {
                        Task { await refreshOpenAIStorage() }
                    } label: {
                        Image(systemName: "cloud")
                    }
                    .accessibilityLabel("Refresh OpenAI provider storage")
                    .disabled(openAIProviders.isEmpty)
                }
            }
            .task {
                await appModel.refreshProviderLifecycleState(services: services)
            }
        }
    }

    private var openAIProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { $0.kind == .openAI }
    }

    @MainActor
    private func refreshOpenAIStorage() async {
        do {
            _ = try await appModel.refreshOpenAIProviderStorage(services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ProviderLifecycleDashboard: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var providerState: PinesProviderLifecycleState

    var body: some View {
        PinesCardSection("Lifecycle Dashboard", subtitle: providerState.providerLifecycleError ?? "Provider-hosted state is explicit and separately refreshable.", systemImage: "chart.bar.doc.horizontal") {
            PinesMetricPillGroup(items: [
                .init("Files", value: "\(providerState.providerFilePreviews.count)", systemImage: "doc", tone: .warning),
                .init("Vector stores", value: "\(providerState.providerVectorStorePreviews.count)", systemImage: "square.stack.3d.up", tone: .warning),
                .init("Artifacts", value: "\(providerState.providerArtifactPreviews.count)", systemImage: "sparkles", tone: .accent),
                .init("Structured", value: "\(providerState.providerStructuredOutputPreviews.count)", systemImage: "curlybraces", tone: .success),
                .init("Batches", value: "\(providerState.providerBatchPreviews.count)", systemImage: "tray.full", tone: .info),
                .init("Live", value: "\(providerState.providerLiveSessionPreviews.count)", systemImage: "dot.radiowaves.left.and.right", tone: .info),
                .init("Research", value: "\(providerState.providerResearchRunPreviews.count)", systemImage: "doc.text.magnifyingglass", tone: .accent),
            ], minimumWidth: 126)
        }
    }
}

private struct DeepResearchWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var selectedProviderID: ProviderID?
    @State private var title = ""
    @State private var prompt = ""
    @State private var modelID = "gpt-5.5-pro"
    @State private var depth: OpenAIDeepResearchDepth = .standard
    @State private var reportFormat: OpenAIDeepResearchReportFormat = .memo
    @State private var isStarting = false

    private var openAIProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { $0.kind == .openAI }
    }

    private var providerID: ProviderID? {
        selectedProviderID ?? openAIProviders.first?.id
    }

    var body: some View {
        PinesCardSection("Deep Research", subtitle: "Start, refresh, cancel, and resume OpenAI background research runs.", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                if !openAIProviders.isEmpty {
                    Picker("Provider", selection: Binding(
                        get: { providerID },
                        set: { selectedProviderID = $0 }
                    )) {
                        ForEach(openAIProviders) { provider in
                            Text(provider.displayName).tag(Optional(provider.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: theme.spacing.small) {
                    TextField("Title", text: $title)
                        .pinesFieldChrome()
                    TextField("Model", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pinesFieldChrome()
                        .frame(maxWidth: 180)
                }

                TextField("Research prompt", text: $prompt, axis: .vertical)
                    .lineLimit(2...5)
                    .pinesFieldChrome()

                HStack(spacing: theme.spacing.small) {
                    Picker("Depth", selection: $depth) {
                        ForEach(OpenAIDeepResearchDepth.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Format", selection: $reportFormat) {
                        ForEach(OpenAIDeepResearchReportFormat.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer(minLength: theme.spacing.small)

                    Button {
                        Task { await startRun() }
                    } label: {
                        Label(isStarting ? "Starting" : "Start", systemImage: isStarting ? "hourglass" : "play.fill")
                    }
                    .disabled(isStarting || providerID == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pinesButtonStyle(.primary)
                }

                HStack(spacing: theme.spacing.small) {
                    Button {
                        Task { await resumeRuns() }
                    } label: {
                        Label("Resume", systemImage: "arrow.clockwise")
                    }
                    .disabled(providerID == nil)

                    Button {
                        Task { await appModel.refreshProviderLifecycleState(services: services) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
            }

            ForEach(providerState.providerResearchRunPreviews) { run in
                ProviderResearchRunRow(run: run)
            }
        }
    }

    @MainActor
    private func startRun() async {
        guard let providerID else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let request = OpenAIDeepResearchRequest(
                providerID: providerID,
                modelID: ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                title: trimmedTitle.isEmpty ? "Deep research" : trimmedTitle,
                prompt: prompt,
                depth: depth,
                sourcePolicy: .webAndFiles(
                    vectorStoreIDs: providerState.providerVectorStores
                        .filter { $0.providerID == providerID }
                        .map { OpenAIVectorStoreID(rawValue: $0.id) },
                    providerFileIDs: providerState.providerFiles
                        .filter { $0.providerID == providerID }
                        .map { OpenAIProviderFileID(rawValue: $0.id) }
                ),
                reportFormat: reportFormat
            )
            _ = try await appModel.startOpenAIDeepResearch(request, services: services)
            prompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func resumeRuns() async {
        guard let providerID else { return }
        do {
            _ = try await appModel.resumeOpenAIDeepResearchRuns(providerID: providerID, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct RealtimeWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var selectedProviderID: ProviderID?
    @State private var modelID = "gpt-4o-realtime-preview"
    @State private var includesAudio = true
    @State private var isCreating = false

    private var openAIProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { $0.kind == .openAI }
    }

    private var providerID: ProviderID? {
        selectedProviderID ?? openAIProviders.first?.id
    }

    var body: some View {
        PinesCardSection("Realtime", subtitle: "Persisted session history, diagnostics, and transcript placeholders.", systemImage: "dot.radiowaves.left.and.right") {
            HStack(spacing: theme.spacing.small) {
                if !openAIProviders.isEmpty {
                    Picker("Provider", selection: Binding(
                        get: { providerID },
                        set: { selectedProviderID = $0 }
                    )) {
                        ForEach(openAIProviders) { provider in
                            Text(provider.displayName).tag(Optional(provider.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                TextField("Model", text: $modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .pinesFieldChrome()

                Toggle("Audio", isOn: $includesAudio)
                    .toggleStyle(.switch)

                Button {
                    Task { await createSession() }
                } label: {
                    Label(isCreating ? "Creating" : "Session", systemImage: isCreating ? "hourglass" : "plus.circle")
                }
                .disabled(isCreating || providerID == nil)
                .pinesButtonStyle(.primary)
            }

            if providerState.providerLiveSessionPreviews.isEmpty {
                PinesEmptyState(title: "No realtime sessions", detail: "Created sessions and transcription placeholders appear here.", systemImage: "waveform")
                    .pinesSurface(.inset, padding: theme.spacing.small)
            } else {
                ForEach(providerState.providerLiveSessionPreviews) { session in
                    ProviderLiveSessionRow(session: session)
                }
            }
        }
    }

    @MainActor
    private func createSession() async {
        guard let providerID else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let modalities = includesAudio ? ["text", "audio"] : ["text"]
            let session: JSONValue = .object([
                "type": .string("realtime"),
                "model": .string(modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                "modalities": .array(modalities.map { .string($0) }),
            ])
            let request = OpenAIRealtimeSessionWorkflowRequest(
                kind: .clientSecret(OpenAIRealtimeClientSecretRequest(session: session), modalities: modalities),
                fallbackModelID: ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            _ = try await appModel.createOpenAIRealtimeSessionRecord(request, providerID: providerID, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ProviderLibrarySection<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let subtitle: String
    let systemImage: String
    let isEmpty: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        PinesCardSection(title, subtitle: subtitle, systemImage: systemImage) {
            if isEmpty {
                PinesEmptyState(title: "Nothing stored", detail: "Provider records appear after compatible workflows run.", systemImage: systemImage)
                    .pinesSurface(.inset, padding: theme.spacing.small)
            } else {
                content()
            }
        }
    }
}

private struct ProviderArtifactRow: View {
    let artifact: PinesProviderArtifactPreview

    var body: some View {
        PinesCapabilityRow(
            title: artifact.title,
            detail: artifact.detail,
            systemImage: artifact.kind.providerArtifactSystemImage,
            status: .custom(artifact.status, .accent),
            secondaryStatus: artifact.byteCountLabel.map { .custom($0, .neutral) },
            metricItems: [
                .init("Kind", value: artifact.kind, systemImage: "tag", tone: .info),
                .init("Created", value: artifact.createdLabel, systemImage: "clock", tone: .neutral),
            ]
        )
    }
}

private struct ProviderStructuredOutputRow: View {
    let output: PinesProviderStructuredOutputPreview

    var body: some View {
        PinesCapabilityRow(
            title: output.title,
            detail: output.detail,
            systemImage: "curlybraces.square",
            status: output.status.providerCloudStatus,
            secondaryStatus: .custom(output.validationSummary, output.validationSummary == "Valid" ? .success : .warning),
            metricItems: [.init("Created", value: output.createdLabel, systemImage: "clock", tone: .neutral)]
        )
    }
}

private struct ProviderBatchRow: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let batch: PinesProviderBatchPreview

    var body: some View {
        PinesCapabilityRow(
            title: batch.title,
            detail: batch.fileSummary,
            systemImage: "tray.full",
            status: batch.status.providerCloudStatus,
            secondaryStatus: batch.completedLabel.map { .custom($0, .success) },
            metricItems: [
                .init("Endpoint", value: batch.endpoint, systemImage: "arrow.left.arrow.right", tone: .info),
                .init("Created", value: batch.createdLabel, systemImage: "clock", tone: .neutral),
            ]
        )
        HStack {
            Spacer()
            Button("Refresh") {
                Task { await refreshBatch() }
            }
            .buttonStyle(.borderless)
            Button("Cancel") {
                Task { await cancelBatch() }
            }
            .buttonStyle(.borderless)
            .disabled(batch.status.providerIsTerminal)
        }
    }

    @MainActor
    private func refreshBatch() async {
        do {
            _ = try await appModel.refreshOpenAIBatch(id: batch.id, providerID: batch.providerID, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func cancelBatch() async {
        do {
            _ = try await appModel.cancelOpenAIBatch(id: batch.id, providerID: batch.providerID, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ProviderResearchRunRow: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let run: PinesProviderResearchRunPreview

    var body: some View {
        PinesCapabilityRow(
            title: run.title,
            detail: "\(run.detail) - \(run.activitySummary)",
            systemImage: "doc.text.magnifyingglass",
            status: run.status.providerCloudStatus,
            secondaryStatus: .custom(run.updatedLabel, .neutral),
            metricItems: [.init("Model", value: run.modelID.rawValue, systemImage: "cpu", tone: .info)]
        )
        HStack {
            Spacer()
            Button("Refresh") {
                Task { await refreshRun() }
            }
            .buttonStyle(.borderless)
            Button("Cancel") {
                Task { await cancelRun() }
            }
            .buttonStyle(.borderless)
            .disabled(run.status.providerIsTerminal)
        }
    }

    @MainActor
    private func refreshRun() async {
        do {
            _ = try await appModel.refreshOpenAIDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func cancelRun() async {
        do {
            _ = try await appModel.cancelOpenAIDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ProviderLiveSessionRow: View {
    let session: PinesProviderLiveSessionPreview

    var body: some View {
        PinesCapabilityRow(
            title: session.title,
            detail: "Transcript placeholder - \(session.modalitySummary)",
            systemImage: "dot.radiowaves.left.and.right",
            status: session.status.providerCloudStatus,
            secondaryStatus: session.expiresLabel.map { .custom("Expires \($0)", .warning) },
            metricItems: [
                .init("Model", value: session.modelID.rawValue, systemImage: "cpu", tone: .info),
                .init("Created", value: session.createdLabel, systemImage: "clock", tone: .neutral),
            ]
        )
    }
}

private extension String {
    var providerCloudStatus: PinesCloudStatus {
        switch lowercased().replacingOccurrences(of: "_", with: "") {
        case "completed", "complete", "processed", "closed":
            .complete
        case "failed", "error":
            .failed
        case "cancelled", "canceled", "expired", "deleted":
            .warning(capitalized)
        case "queued", "pending", "created", "validating":
            .pending
        case "inprogress", "running", "active", "finalizing", "uploaded":
            .running
        case "requiresaction", "cancelling", "deleting", "closing":
            .needsValidation
        default:
            .custom(isEmpty ? "Unknown" : self, .neutral)
        }
    }

    var providerIsTerminal: Bool {
        switch lowercased().replacingOccurrences(of: "_", with: "") {
        case "completed", "complete", "processed", "closed", "failed", "error", "cancelled", "canceled", "expired", "deleted":
            true
        default:
            false
        }
    }

    var providerArtifactSystemImage: String {
        switch lowercased() {
        case "image":
            "photo"
        case "audio", "transcript":
            "waveform"
        case "video":
            "film"
        case "structuredoutput", "structured_output":
            "curlybraces.square"
        case "code":
            "chevron.left.forwardslash.chevron.right"
        case "tooloutput", "tool_output":
            "wrench.and.screwdriver"
        default:
            "doc"
        }
    }
}
