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
                .pinesTheme(theme)

            if showsBootMark {
                PinesBootMarkView()
                    .environmentObject(haptics)
                    .pinesTheme(theme)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(appModel.interfaceMode.colorScheme)
        .task {
            await services.bootstrap()
            #if canImport(WatchConnectivity)
            let watchSessionService = PhoneWatchSessionService(services: services)
            watchSessionService.start()
            self.watchSessionService = watchSessionService
            #endif
            await appModel.bootstrap(services: services)
            try? await Task.sleep(nanoseconds: 720_000_000)
            withAnimation(theme.motion.emphasized) {
                showsBootMark = false
            }
            haptics.play(.appReady)
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
                }

                if let preferences = request.modelPreferences {
                    Section("Model Preferences") {
                        Text(String(describing: preferences))
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }
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
