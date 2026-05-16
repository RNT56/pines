import ActivityKit
import Foundation
import PinesCore

enum ModelDownloadLiveActivityController {
    static func update(progress: ModelDownloadProgress) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        switch progress.status {
        case .queued, .downloading, .verifying, .installing:
            let activity = activity(for: progress.repository)
                ?? startActivity(for: progress)
            await activity?.update(content(progress: progress))
        case .installed, .failed, .cancelled:
            guard let activity = activity(for: progress.repository) else { return }
            await activity.end(content(progress: progress), dismissalPolicy: .after(Date(timeIntervalSinceNow: 30)))
        }
    }

    static func end(repository: String) async {
        guard let activity = activity(for: repository) else { return }
        let state = ModelDownloadActivityAttributes.ContentState(
            status: "Removed",
            bytesReceived: 0,
            totalBytes: nil,
            currentFile: nil,
            errorMessage: nil,
            updatedAt: Date()
        )
        await activity.end(
            ActivityContent(state: state, staleDate: Date()),
            dismissalPolicy: .immediate
        )
    }

    private static func activity(for repository: String) -> Activity<ModelDownloadActivityAttributes>? {
        Activity<ModelDownloadActivityAttributes>.activities.first {
            $0.attributes.repository.caseInsensitiveCompare(repository) == .orderedSame
        }
    }

    private static func startActivity(for progress: ModelDownloadProgress) -> Activity<ModelDownloadActivityAttributes>? {
        let attributes = ModelDownloadActivityAttributes(
            repository: progress.repository,
            displayName: progress.repository.components(separatedBy: "/").last ?? progress.repository
        )
        do {
            return try Activity.request(
                attributes: attributes,
                content: content(progress: progress),
                pushType: nil
            )
        } catch {
            return nil
        }
    }

    private static func content(progress: ModelDownloadProgress) -> ActivityContent<ModelDownloadActivityAttributes.ContentState> {
        ActivityContent(
            state: ModelDownloadActivityAttributes.ContentState(
                status: progress.status.title,
                bytesReceived: progress.bytesReceived,
                totalBytes: progress.totalBytes,
                currentFile: progress.currentFile,
                errorMessage: progress.errorMessage,
                updatedAt: progress.updatedAt
            ),
            staleDate: Date(timeIntervalSinceNow: 60)
        )
    }
}

private extension ModelDownloadStatus {
    var title: String {
        switch self {
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .verifying: "Verifying"
        case .installing: "Installing"
        case .installed: "Installed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}
