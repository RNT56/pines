import SwiftUI
import LocalAuthentication
import PinesCore
import UniformTypeIdentifiers

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

                    AnthropicFileManager()

                    GeminiFileMediaManager()

                    GeminiCacheManager()

                    DeepResearchWorkspace()

                    RealtimeWorkspace()

                    GeminiGeneratedMediaWorkspace()

                    ProviderModelCapabilitySection()

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
                        subtitle: "Persisted schema results, validation state, refusal/truncation metadata, and local JSON validation.",
                        systemImage: "curlybraces.square",
                        isEmpty: providerState.providerStructuredOutputPreviews.isEmpty
                    ) {
                        ForEach(providerState.providerStructuredOutputPreviews) { output in
                            ProviderStructuredOutputRow(output: output)
                        }
                    }

                    ProviderLibrarySection(
                        title: "Batches",
                        subtitle: "Background jobs, operation state, output/error files, and imported result artifacts.",
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

                    Menu {
                        ForEach(lifecycleProviders) { provider in
                            Button(provider.displayName) {
                                Task { await refreshProviderStorage(provider) }
                            }
                        }
                    } label: {
                        Image(systemName: "cloud")
                    }
                    .accessibilityLabel("Refresh provider storage")
                    .disabled(lifecycleProviders.isEmpty)
                }
            }
            .task {
                await appModel.refreshProviderLifecycleState(services: services)
            }
        }
    }

    private var lifecycleProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.pinesLifecycleProviders
    }

    @MainActor
    private func refreshProviderStorage(_ provider: CloudProviderConfiguration) async {
        do {
            switch provider.kind {
            case .openAI:
                _ = try await appModel.refreshOpenAIProviderStorage(providerID: provider.id, services: services)
            case .anthropic:
                _ = try await appModel.refreshAnthropicProviderStorage(providerID: provider.id, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiProviderStorage(providerID: provider.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) provider storage is not supported here.")
            }
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

private struct AnthropicFileManager: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var selectedProviderID: ProviderID?
    @State private var isImporterPresented = false
    @State private var isUploading = false

    private var anthropicProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { $0.kind == .anthropic }
    }

    private var selectedProvider: CloudProviderConfiguration? {
        if let selectedProviderID, let provider = anthropicProviders.first(where: { $0.id == selectedProviderID }) {
            return provider
        }
        return anthropicProviders.first
    }

    private var files: [PinesProviderFilePreview] {
        providerState.providerFilePreviews.filter { preview in
            preview.providerKind == .anthropic && (selectedProvider == nil || preview.providerID == selectedProvider?.id)
        }
    }

    var body: some View {
        PinesCardSection("Anthropic Files", subtitle: "Provider-hosted PDFs, documents, images, and generated code-execution files stay labeled as Anthropic storage.", systemImage: "doc.badge.arrow.up") {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                HStack(spacing: theme.spacing.small) {
                    providerPicker

                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(isUploading ? "Uploading" : "Upload", systemImage: isUploading ? "hourglass" : "square.and.arrow.up")
                    }
                    .disabled(isUploading || selectedProvider == nil)
                    .pinesButtonStyle(.primary)

                    Button {
                        Task { await refreshStorage() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(selectedProvider == nil)
                }

                PinesMetricPillGroup(items: [
                    .init("Files", value: "\(files.count)", systemImage: "doc", tone: .warning),
                    .init("Provider", value: selectedProvider?.displayName ?? "None", systemImage: "cloud", tone: .info),
                    .init("Retention", value: "provider-hosted", systemImage: "timer", tone: .warning),
                ], minimumWidth: 126)

                if files.isEmpty {
                    PinesEmptyState(title: "No Anthropic files", detail: "Uploaded documents and generated hosted-tool files appear here after refresh.", systemImage: "doc.badge.plus")
                        .pinesSurface(.inset, padding: theme.spacing.small)
                } else {
                    ForEach(files) { file in
                        ProviderFileRow(file: file)
                    }
                }
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            Task { await handleImport(result) }
        }
    }

    @ViewBuilder
    private var providerPicker: some View {
        if !anthropicProviders.isEmpty {
            Picker("Provider", selection: Binding(
                get: { selectedProvider?.id },
                set: { selectedProviderID = $0 }
            )) {
                ForEach(anthropicProviders) { provider in
                    Text(provider.displayName).tag(Optional(provider.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        guard let provider = selectedProvider else { return }
        do {
            guard let url = try result.get().first else { return }
            isUploading = true
            defer { isUploading = false }
            let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            let consent = PinesAnthropicProviderStorageConsent(
                isGranted: true,
                sourceDescription: url.lastPathComponent,
                destinationDescription: "Anthropic Files API for \(provider.displayName)",
                byteCount: byteCount
            )
            _ = try await appModel.uploadAnthropicLocalFile(providerID: provider.id, fileURL: url, consent: consent, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
            isUploading = false
        }
    }

    @MainActor
    private func refreshStorage() async {
        guard let provider = selectedProvider else { return }
        do {
            _ = try await appModel.refreshAnthropicProviderStorage(providerID: provider.id, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct GeminiFileMediaManager: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var selectedProviderID: ProviderID?
    @State private var isImporterPresented = false
    @State private var isUploading = false

    private var geminiProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { $0.kind == .gemini }
    }

    private var selectedProvider: CloudProviderConfiguration? {
        if let selectedProviderID, let provider = geminiProviders.first(where: { $0.id == selectedProviderID }) {
            return provider
        }
        return geminiProviders.first
    }

    private var files: [PinesProviderFilePreview] {
        providerState.providerFilePreviews.filter { preview in
            preview.providerKind == .gemini && (selectedProvider == nil || preview.providerID == selectedProvider?.id)
        }
    }

    var body: some View {
        PinesCardSection("Gemini Files and Media", subtitle: "Provider-hosted media is explicit, retained by Gemini, and deletable independently from local Vault files.", systemImage: "doc.badge.arrow.up") {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                HStack(spacing: theme.spacing.small) {
                    providerPicker

                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(isUploading ? "Uploading" : "Upload", systemImage: isUploading ? "hourglass" : "square.and.arrow.up")
                    }
                    .disabled(isUploading || selectedProvider == nil)
                    .pinesButtonStyle(.primary)

                    Button {
                        Task { await refreshStorage() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(selectedProvider == nil)
                }

                PinesMetricPillGroup(items: [
                    .init("Files", value: "\(files.count)", systemImage: "doc", tone: .warning),
                    .init("Provider", value: selectedProvider?.displayName ?? "None", systemImage: "cloud", tone: .info),
                    .init("Retention", value: "provider-hosted", systemImage: "timer", tone: .warning),
                ], minimumWidth: 126)

                if files.isEmpty {
                    PinesEmptyState(title: "No Gemini files", detail: "Uploaded audio, video, PDFs, images, and reusable documents appear here with processing state.", systemImage: "doc.badge.plus")
                        .pinesSurface(.inset, padding: theme.spacing.small)
                } else {
                    ForEach(files) { file in
                        ProviderFileRow(file: file)
                    }
                }
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            Task { await handleImport(result) }
        }
    }

    @ViewBuilder
    private var providerPicker: some View {
        if !geminiProviders.isEmpty {
            Picker("Provider", selection: Binding(
                get: { selectedProvider?.id },
                set: { selectedProviderID = $0 }
            )) {
                ForEach(geminiProviders) { provider in
                    Text(provider.displayName).tag(Optional(provider.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        guard let provider = selectedProvider else { return }
        do {
            guard let url = try result.get().first else { return }
            isUploading = true
            defer { isUploading = false }
            let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            let consent = PinesGeminiProviderStorageConsent(
                isGranted: true,
                sourceDescription: url.lastPathComponent,
                destinationDescription: "Gemini Files API for \(provider.displayName)",
                byteCount: byteCount
            )
            _ = try await appModel.uploadGeminiLocalFile(providerID: provider.id, fileURL: url, consent: consent, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
            isUploading = false
        }
    }

    @MainActor
    private func refreshStorage() async {
        guard let provider = selectedProvider else { return }
        do {
            _ = try await appModel.refreshGeminiProviderStorage(providerID: provider.id, services: services)
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct GeminiCacheManager: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var selectedProviderID: ProviderID?
    @State private var modelID = "gemini-2.5-pro"
    @State private var displayName = ""
    @State private var cacheText = ""
    @State private var ttlSeconds = "3600"
    @State private var isCreating = false

    private var geminiProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { $0.kind == .gemini }
    }

    private var selectedProvider: CloudProviderConfiguration? {
        if let selectedProviderID, let provider = geminiProviders.first(where: { $0.id == selectedProviderID }) {
            return provider
        }
        return geminiProviders.first
    }

    private var caches: [PinesProviderCachePreview] {
        providerState.providerCachePreviews.filter { preview in
            preview.providerKind == .gemini && (selectedProvider == nil || preview.providerID == selectedProvider?.id)
        }
    }

    var body: some View {
        PinesCardSection("Gemini Context Caches", subtitle: "Create and clean up provider-hosted cached context with TTL, token usage, and linked model state.", systemImage: "externaldrive.badge.icloud") {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                HStack(spacing: theme.spacing.small) {
                    if !geminiProviders.isEmpty {
                        Picker("Provider", selection: Binding(
                            get: { selectedProvider?.id },
                            set: { selectedProviderID = $0 }
                        )) {
                            ForEach(geminiProviders) { provider in
                                Text(provider.displayName).tag(Optional(provider.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    TextField("Model", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pinesFieldChrome()
                        .frame(maxWidth: 180)

                    TextField("TTL seconds", text: $ttlSeconds)
                        .pinesFieldChrome()
                        .frame(maxWidth: 110)
                }

                TextField("Cache name", text: $displayName)
                    .pinesFieldChrome()

                TextField("Context to cache", text: $cacheText, axis: .vertical)
                    .lineLimit(2...6)
                    .pinesFieldChrome()

                HStack {
                    Button {
                        Task { await createCache() }
                    } label: {
                        Label(isCreating ? "Creating" : "Create cache", systemImage: isCreating ? "hourglass" : "plus.circle")
                    }
                    .disabled(isCreating || selectedProvider == nil || cacheText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pinesButtonStyle(.primary)

                    Spacer()
                }

                if caches.isEmpty {
                    PinesEmptyState(title: "No Gemini caches", detail: "Approved Vault context, reusable prompts, and media context caches appear here.", systemImage: "externaldrive")
                        .pinesSurface(.inset, padding: theme.spacing.small)
                } else {
                    ForEach(caches) { cache in
                        ProviderCacheRow(cache: cache)
                    }
                }
            }
        }
    }

    @MainActor
    private func createCache() async {
        guard let provider = selectedProvider else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            _ = try await appModel.createGeminiContextCache(
                providerID: provider.id,
                modelID: ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                text: cacheText,
                ttlSeconds: Int(ttlSeconds),
                services: services
            )
            cacheText = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
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

    private var lifecycleProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.pinesLifecycleProviders
    }

    private var selectedProvider: CloudProviderConfiguration? {
        if let selectedProviderID, let provider = lifecycleProviders.first(where: { $0.id == selectedProviderID }) {
            return provider
        }
        return lifecycleProviders.first
    }

    var body: some View {
        PinesCardSection("Deep Research", subtitle: "Start, refresh, cancel, and resume provider background research runs.", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                if !lifecycleProviders.isEmpty {
                    Picker("Provider", selection: Binding(
                        get: { selectedProvider?.id },
                        set: { providerID in
                            selectedProviderID = providerID
                            if let providerID, let provider = lifecycleProviders.first(where: { $0.id == providerID }) {
                                applyDefaultDeepResearchModel(for: provider.kind)
                            }
                        }
                    )) {
                        ForEach(lifecycleProviders) { provider in
                            Text("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)").tag(Optional(provider.id))
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
                    .disabled(isStarting || selectedProvider == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pinesButtonStyle(.primary)
                }

                HStack(spacing: theme.spacing.small) {
                    Button {
                        Task { await resumeRuns() }
                    } label: {
                        Label("Resume", systemImage: "arrow.clockwise")
                    }
                    .disabled(selectedProvider == nil)

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
        guard let provider = selectedProvider else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.isEmpty ? "Deep research" : trimmedTitle
            let modelID = ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            let vectorStoreIDs = providerState.providerVectorStores
                .filter { $0.providerID == provider.id }
                .map(\.id)
            let providerFileIDs = providerState.providerFiles
                .filter { $0.providerID == provider.id }
                .map(\.id)
            switch provider.kind {
            case .openAI:
                let request = OpenAIDeepResearchRequest(
                    providerID: provider.id,
                    modelID: modelID,
                    title: title,
                    prompt: prompt,
                    depth: depth,
                    sourcePolicy: .webAndFiles(
                        vectorStoreIDs: vectorStoreIDs.map { OpenAIVectorStoreID(rawValue: $0) },
                        providerFileIDs: providerFileIDs.map { OpenAIProviderFileID(rawValue: $0) }
                    ),
                    reportFormat: reportFormat
                )
                _ = try await appModel.startOpenAIDeepResearch(request, services: services)
            case .gemini:
                let request = PinesProviderDeepResearchRequest(
                    providerID: provider.id,
                    providerKind: provider.kind,
                    modelID: modelID,
                    title: title,
                    prompt: prompt,
                    depth: depth.rawValue,
                    reportFormat: reportFormat.rawValue,
                    vectorStoreIDs: vectorStoreIDs,
                    providerFileIDs: providerFileIDs
                )
                _ = try await appModel.startGeminiDeepResearch(request, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
            prompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func resumeRuns() async {
        guard let provider = selectedProvider else { return }
        do {
            switch provider.kind {
            case .openAI:
                _ = try await appModel.resumeOpenAIDeepResearchRuns(providerID: provider.id, services: services)
            case .gemini:
                _ = try await appModel.resumeGeminiDeepResearchRuns(providerID: provider.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func applyDefaultDeepResearchModel(for providerKind: CloudProviderKind) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || trimmed == "gpt-5.5-pro" || trimmed == "gemini-2.5-deep-research" else { return }
        switch providerKind {
        case .openAI:
            modelID = "gpt-5.5-pro"
        case .gemini:
            modelID = "gemini-2.5-deep-research"
        default:
            break
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

    private var lifecycleProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.pinesLifecycleProviders
    }

    private var selectedProvider: CloudProviderConfiguration? {
        if let selectedProviderID, let provider = lifecycleProviders.first(where: { $0.id == selectedProviderID }) {
            return provider
        }
        return lifecycleProviders.first
    }

    var body: some View {
        PinesCardSection("Realtime", subtitle: "Persisted session history, diagnostics, and transcript placeholders.", systemImage: "dot.radiowaves.left.and.right") {
            HStack(spacing: theme.spacing.small) {
                if !lifecycleProviders.isEmpty {
                    Picker("Provider", selection: Binding(
                        get: { selectedProvider?.id },
                        set: { providerID in
                            selectedProviderID = providerID
                            if let providerID, let provider = lifecycleProviders.first(where: { $0.id == providerID }) {
                                applyDefaultRealtimeModel(for: provider.kind)
                            }
                        }
                    )) {
                        ForEach(lifecycleProviders) { provider in
                            Text("\(provider.displayName) - \(provider.kind.pinesLifecycleTitle)").tag(Optional(provider.id))
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
                .disabled(isCreating || selectedProvider == nil)
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
        guard let provider = selectedProvider else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let modalities = includesAudio ? ["text", "audio"] : ["text"]
            let modelID = ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines))
            let session: JSONValue = .object([
                "type": .string("realtime"),
                "model": .string(modelID.rawValue),
                "modalities": .array(modalities.map { .string($0) }),
            ])
            switch provider.kind {
            case .openAI:
                let request = OpenAIRealtimeSessionWorkflowRequest(
                    kind: .clientSecret(OpenAIRealtimeClientSecretRequest(session: session), modalities: modalities),
                    fallbackModelID: modelID
                )
                _ = try await appModel.createOpenAIRealtimeSessionRecord(request, providerID: provider.id, services: services)
            case .gemini:
                let request = PinesProviderRealtimeSessionRequest(
                    providerID: provider.id,
                    providerKind: provider.kind,
                    modelID: modelID,
                    modalities: modalities,
                    session: session
                )
                _ = try await appModel.createGeminiRealtimeSessionRecord(request, providerID: provider.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Realtime is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    private func applyDefaultRealtimeModel(for providerKind: CloudProviderKind) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || trimmed == "gpt-4o-realtime-preview" || trimmed == "gemini-live-2.5-flash-preview" else { return }
        switch providerKind {
        case .openAI:
            modelID = "gpt-4o-realtime-preview"
        case .gemini:
            modelID = "gemini-live-2.5-flash-preview"
        default:
            break
        }
    }
}

private struct GeminiGeneratedMediaWorkspace: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    @State private var selectedProviderID: ProviderID?
    @State private var modelID = "imagen-4.0-generate-preview"
    @State private var prompt = ""
    @State private var kind = "image"
    @State private var isGenerating = false

    private var geminiProviders: [CloudProviderConfiguration] {
        settingsState.cloudProviders.filter { $0.kind == .gemini }
    }

    private var selectedProvider: CloudProviderConfiguration? {
        if let selectedProviderID, let provider = geminiProviders.first(where: { $0.id == selectedProviderID }) {
            return provider
        }
        return geminiProviders.first
    }

    private var mediaArtifacts: [PinesProviderArtifactPreview] {
        providerState.providerArtifactPreviews.filter { artifact in
            artifact.providerKind == .gemini
                && ["image", "video", "audio", "generated_media", "media_operation"].contains(artifact.kind)
        }
    }

    var body: some View {
        PinesCardSection("Gemini Generated Media", subtitle: "Images, Veo video jobs, and speech outputs are stored as provider artifacts with prompt/model provenance.", systemImage: "photo.stack") {
            VStack(alignment: .leading, spacing: theme.spacing.small) {
                HStack(spacing: theme.spacing.small) {
                    if !geminiProviders.isEmpty {
                        Picker("Provider", selection: Binding(
                            get: { selectedProvider?.id },
                            set: { selectedProviderID = $0 }
                        )) {
                            ForEach(geminiProviders) { provider in
                                Text(provider.displayName).tag(Optional(provider.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker("Kind", selection: $kind) {
                        Text("Image").tag("image")
                        Text("Video").tag("video")
                        Text("Speech").tag("speech")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: kind) { _, value in
                        switch value {
                        case "video":
                            modelID = "veo-3.1-generate-preview"
                        case "speech":
                            modelID = "gemini-2.5-flash-preview-tts"
                        default:
                            modelID = "imagen-4.0-generate-preview"
                        }
                    }

                    TextField("Model", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .pinesFieldChrome()
                }

                TextField("Prompt", text: $prompt, axis: .vertical)
                    .lineLimit(2...5)
                    .pinesFieldChrome()

                HStack {
                    Button {
                        Task { await createMedia() }
                    } label: {
                        Label(isGenerating ? "Creating" : "Create", systemImage: isGenerating ? "hourglass" : "sparkles")
                    }
                    .disabled(isGenerating || selectedProvider == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pinesButtonStyle(.primary)

                    Spacer()
                }

                if mediaArtifacts.isEmpty {
                    PinesEmptyState(title: "No Gemini media artifacts", detail: "Generated images, videos, speech, and operation records appear here.", systemImage: "photo")
                        .pinesSurface(.inset, padding: theme.spacing.small)
                } else {
                    ForEach(mediaArtifacts.prefix(6)) { artifact in
                        ProviderArtifactRow(artifact: artifact)
                    }
                }
            }
        }
    }

    @MainActor
    private func createMedia() async {
        guard let provider = selectedProvider else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            _ = try await appModel.createGeminiGeneratedMedia(
                providerID: provider.id,
                modelID: ModelID(rawValue: modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                prompt: prompt,
                kind: kind,
                services: services
            )
            prompt = ""
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ProviderModelCapabilitySection: View {
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var providerState: PinesProviderLifecycleState

    private var capabilities: [PinesProviderModelCapabilityPreview] {
        providerState.providerModelCapabilityPreviews
            .filter { $0.providerKind == .gemini || $0.providerKind == .anthropic }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        ProviderLibrarySection(
            title: "Provider Model Capabilities",
            subtitle: "Model picker gating uses provider metadata when available; absent metadata remains an estimated fallback.",
            systemImage: "cpu",
            isEmpty: capabilities.isEmpty
        ) {
            ForEach(capabilities.prefix(12)) { capability in
                ProviderModelCapabilityRow(capability: capability)
            }
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

private struct ProviderFileRow: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let file: PinesProviderFilePreview

    var body: some View {
        PinesCapabilityRow(
            title: file.title,
            detail: file.detail,
            systemImage: file.providerKind == .gemini ? "waveform.badge.magnifyingglass" : "doc",
            status: file.status.providerCloudStatus,
            secondaryStatus: file.expiresLabel.map { .custom("Expires \($0)", .warning) },
            metricItems: [
                .init("Purpose", value: file.purpose, systemImage: "tag", tone: .info),
                .init("Size", value: file.byteCountLabel, systemImage: "internaldrive", tone: .neutral),
                .init("Created", value: file.createdLabel, systemImage: "clock", tone: .neutral),
            ]
        )
        HStack {
            Spacer()
            Button("Refresh") {
                Task { await refreshFile() }
            }
            .buttonStyle(.borderless)
            Button("Delete") {
                Task { await deleteFile() }
            }
            .buttonStyle(.borderless)
        }
    }

    @MainActor
    private func refreshFile() async {
        do {
            switch file.providerKind {
            case .anthropic:
                _ = try await appModel.refreshAnthropicProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(file.providerKind.pinesLifecycleTitle) file refresh is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteFile() async {
        do {
            switch file.providerKind {
            case .openAI:
                try await appModel.deleteOpenAIProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .anthropic:
                try await appModel.deleteAnthropicProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            case .gemini:
                try await appModel.deleteGeminiProviderFile(providerID: file.providerID, fileID: file.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(file.providerKind.pinesLifecycleTitle) file deletion is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }
}

private struct ProviderCacheRow: View {
    @Environment(\.pinesServices) private var services
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var providerState: PinesProviderLifecycleState
    let cache: PinesProviderCachePreview

    var body: some View {
        PinesCapabilityRow(
            title: cache.title,
            detail: cache.detail,
            systemImage: cache.kind == "cached_content" ? "externaldrive.badge.icloud" : "square.stack.3d.up",
            status: cache.status.providerCloudStatus,
            secondaryStatus: cache.expiresLabel.map { .custom("Expires \($0)", .warning) },
            metricItems: [
                .init("Kind", value: cache.kind, systemImage: "tag", tone: .info),
                .init("Usage", value: cache.usageLabel, systemImage: "number", tone: .neutral),
                .init("Created", value: cache.createdLabel, systemImage: "clock", tone: .neutral),
            ]
        )
        HStack {
            Spacer()
            Button("Refresh") {
                Task { await refreshCache() }
            }
            .buttonStyle(.borderless)
            Button("Delete") {
                Task { await deleteCache() }
            }
            .buttonStyle(.borderless)
        }
    }

    @MainActor
    private func refreshCache() async {
        do {
            switch cache.providerKind {
            case .gemini:
                _ = try await appModel.refreshGeminiContextCache(providerID: cache.providerID, cacheID: cache.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(cache.providerKind.pinesLifecycleTitle) cache refresh is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteCache() async {
        do {
            switch cache.providerKind {
            case .openAI:
                try await appModel.deleteOpenAIVectorStore(providerID: cache.providerID, vectorStoreID: cache.id, services: services)
            case .gemini:
                try await appModel.deleteGeminiContextCache(providerID: cache.providerID, cacheID: cache.id, services: services)
            default:
                throw InferenceError.invalidRequest("\(cache.providerKind.pinesLifecycleTitle) cache deletion is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
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

private struct ProviderModelCapabilityRow: View {
    let capability: PinesProviderModelCapabilityPreview

    var body: some View {
        PinesCapabilityRow(
            title: capability.title,
            detail: capability.detail,
            systemImage: "cpu",
            status: .custom("metadata", .success),
            secondaryStatus: capability.expiresLabel.map { .custom("Expires \($0)", .warning) },
            metricItems: [
                .init("Capabilities", value: capability.capabilitySummary, systemImage: "checklist", tone: .info),
                .init("Fetched", value: capability.fetchedLabel, systemImage: "clock", tone: .neutral),
            ]
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
            if batch.providerKind == .anthropic {
                Button("Import") {
                    Task { await importResults() }
                }
                .buttonStyle(.borderless)
                .disabled(!batch.status.providerIsTerminal)
            }
        }
    }

    @MainActor
    private func refreshBatch() async {
        do {
            switch batch.providerKind {
            case .openAI:
                _ = try await appModel.refreshOpenAIBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .anthropic:
                _ = try await appModel.refreshAnthropicBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiBatch(id: batch.id, providerID: batch.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(batch.providerKind.pinesLifecycleTitle) batch lifecycle is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func cancelBatch() async {
        do {
            switch batch.providerKind {
            case .openAI:
                _ = try await appModel.cancelOpenAIBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .anthropic:
                _ = try await appModel.cancelAnthropicBatch(id: batch.id, providerID: batch.providerID, services: services)
            case .gemini:
                _ = try await appModel.cancelGeminiBatch(id: batch.id, providerID: batch.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(batch.providerKind.pinesLifecycleTitle) batch lifecycle is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func importResults() async {
        do {
            switch batch.providerKind {
            case .anthropic:
                _ = try await appModel.importAnthropicBatchResults(id: batch.id, providerID: batch.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(batch.providerKind.pinesLifecycleTitle) batch result import is not supported here.")
            }
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
            switch run.providerKind {
            case .openAI:
                _ = try await appModel.refreshOpenAIDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            case .gemini:
                _ = try await appModel.refreshGeminiDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(run.providerKind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
        } catch {
            providerState.providerLifecycleError = error.localizedDescription
        }
    }

    @MainActor
    private func cancelRun() async {
        do {
            switch run.providerKind {
            case .openAI:
                _ = try await appModel.cancelOpenAIDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            case .gemini:
                _ = try await appModel.cancelGeminiDeepResearchRun(id: run.id, providerID: run.providerID, services: services)
            default:
                throw InferenceError.invalidRequest("\(run.providerKind.pinesLifecycleTitle) Deep Research is not supported here.")
            }
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

private extension Array where Element == CloudProviderConfiguration {
    var pinesLifecycleProviders: [CloudProviderConfiguration] {
        filter { $0.kind == .openAI || $0.kind == .anthropic || $0.kind == .gemini }
    }
}

private extension CloudProviderKind {
    var pinesLifecycleTitle: String {
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
