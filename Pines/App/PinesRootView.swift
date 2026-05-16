import SwiftUI
import PinesCore

#if canImport(UIKit)
import UIKit
#endif

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct PinesRootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @StateObject private var appModel = PinesAppModel()
    @StateObject private var haptics = PinesHaptics()
    @State private var services = PinesAppServices()
    @State private var watchSessionService: PhoneWatchSessionService?
    @State private var selectedTab: PinesTab = .chats
    @State private var showsBootMark = true
    @State private var didStartBootstrap = false
    @State private var isBootstrapping = false

    private var theme: PinesTheme {
        PinesTheme.resolve(
            template: appModel.selectedThemeTemplate,
            mode: appModel.interfaceMode,
            systemScheme: systemScheme
        )
    }

    var body: some View {
        ZStack {
            tabShell
                .environmentObject(appModel)
                .environmentObject(haptics)
                .environment(\.pinesServices, services)
                .environment(\.openPinesModelsPage, PinesOpenModelsPageAction {
                    selectedTab = .models
                })
                .pinesTheme(theme)

            if showsBootMark {
                PinesBootMarkView()
                    .environmentObject(haptics)
                    .pinesTheme(theme)
                    .ignoresSafeArea()
                    .zIndex(1)
            }

            #if canImport(UIKit)
            PinesKeyboardWarmupView()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            #endif
        }
        .preferredColorScheme(appModel.interfaceMode.colorScheme)
        .task {
            guard !didStartBootstrap, !isBootstrapping else { return }
            isBootstrapping = true
            defer { isBootstrapping = false }

            await services.prepareForFirstFrame()
            #if canImport(WatchConnectivity)
            let watchSessionService = PhoneWatchSessionService(services: services)
            watchSessionService.start()
            self.watchSessionService = watchSessionService
            #endif
            await appModel.bootstrap(services: services)
            withAnimation(theme.motion.emphasized) {
                showsBootMark = false
            }
            haptics.play(.appReady)
            didStartBootstrap = true
        }
        .onChange(of: appModel.hapticSignal) { _, signal in
            guard let signal else { return }
            haptics.play(signal.event)
        }
        .onPinesMemoryWarning {
            appModel.stopCurrentRun()
            Task {
                await services.handleMemoryPressure()
            }
        }
        .alert("Approve Tool Call", isPresented: Binding(
            get: { appModel.pendingToolApproval != nil },
            set: { presented in
                if !presented {
                    appModel.resolvePendingToolApproval(.denied)
                }
            }
        )) {
            Button("Deny", role: .cancel) {
                appModel.resolvePendingToolApproval(.denied)
            }
            Button("Approve") {
                appModel.resolvePendingToolApproval(.approved)
            }
        } message: {
            if let request = appModel.pendingToolApproval {
                Text("\(request.invocation.toolName)\n\(request.invocation.privacyImpact)")
            }
        }
        .sheet(item: Binding(
            get: { appModel.pendingCloudContextApproval },
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
            get: { appModel.pendingMCPSamplingRequest },
            set: { request in
                if request == nil {
                    appModel.resolvePendingMCPSampling(false)
                }
            }
        )) { request in
            MCPSamplingApprovalSheet(
                request: request,
                promptDraft: $appModel.mcpSamplingPromptDraft,
                deny: { appModel.resolvePendingMCPSampling(false) },
                approve: { appModel.resolvePendingMCPSampling(true) }
            )
            .environmentObject(haptics)
            .pinesTheme(theme)
        }
        .sheet(item: Binding(
            get: { appModel.pendingMCPSamplingResultReview },
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

    private var tabShell: some View {
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

#if canImport(UIKit)
private struct PinesKeyboardWarmupView: UIViewRepresentable {
    final class Coordinator {
        var didWarm = false
        var retryCount = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.inputView = UIView(frame: .zero)
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.backgroundColor = .clear
        textField.isAccessibilityElement = false
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        guard !context.coordinator.didWarm else { return }
        context.coordinator.didWarm = true
        warmKeyboardInput(uiView, coordinator: context.coordinator)
    }

    private func warmKeyboardInput(_ textField: UITextField, coordinator: Coordinator) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard textField.window != nil else {
                guard coordinator.retryCount < 8 else { return }
                coordinator.retryCount += 1
                warmKeyboardInput(textField, coordinator: coordinator)
                return
            }

            guard !textField.isFirstResponder else { return }
            if textField.becomeFirstResponder() {
                DispatchQueue.main.async {
                    textField.resignFirstResponder()
                }
            }
        }
    }
}
#endif

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
    case settings

    var title: String {
        switch self {
        case .chats:
            "Chats"
        case .models:
            "Models"
        case .vault:
            "Vault"
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
        case .settings:
            "gearshape"
        }
    }
}
