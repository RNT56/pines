import SwiftUI
import PinesCore

final class PinesAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundModelFileDownloadCenter.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundModelFileDownloadCenter.shared.setBackgroundCompletionHandler(
            completionHandler,
            for: identifier
        )
    }
}

@main
struct PinesApp: App {
    @UIApplicationDelegateAdaptor(PinesAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            PinesRootView()
        }
    }
}
