import SwiftUI

@main
struct PinesWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WatchChatViewModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .task {
                    model.setSceneActive(scenePhase == .active)
                    model.activate()
                    model.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    model.setSceneActive(phase == .active)
                }
        }
    }
}
