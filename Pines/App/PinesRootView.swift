import SwiftUI

struct PinesRootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @StateObject private var appModel = PinesAppModel()
    @State private var services = PinesAppServices()
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
                .environment(\.pinesServices, services)
                .pinesTheme(theme)

            if showsBootMark {
                PinesBootMarkView()
                    .pinesTheme(theme)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(appModel.interfaceMode.colorScheme)
        .task {
            await services.bootstrap()
            await appModel.bootstrap(services: services)
            try? await Task.sleep(nanoseconds: 720_000_000)
            withAnimation(theme.motion.emphasized) {
                showsBootMark = false
            }
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
        .background(theme.colors.appBackground.ignoresSafeArea())
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
