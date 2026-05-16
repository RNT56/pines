import ActivityKit
import Foundation
import PinesCore

enum ModelDownloadLiveActivityController {
    private static let throttle = ModelDownloadLiveActivityThrottle()

    static func update(progress: ModelDownloadProgress) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        switch progress.status {
        case .queued, .downloading, .verifying, .installing:
            guard await throttle.shouldUpdate(progress) else { return }
            let activity = activity(for: progress.repository)
                ?? startActivity(for: progress)
            await activity?.update(content(progress: progress))
        case .installed, .failed, .cancelled:
            await throttle.remove(repository: progress.repository)
            guard let activity = activity(for: progress.repository) else { return }
            await activity.end(content(progress: progress), dismissalPolicy: .after(Date(timeIntervalSinceNow: 30)))
        }
    }

    static func end(repository: String) async {
        await throttle.remove(repository: repository)
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

private actor ModelDownloadLiveActivityThrottle {
    private struct Snapshot {
        var status: ModelDownloadStatus
        var currentFile: String?
        var fraction: Double?
        var updatedAt: Date
    }

    private let minimumInterval: TimeInterval = 15
    private let minimumFractionDelta = 0.05
    private var snapshots: [String: Snapshot] = [:]

    func shouldUpdate(_ progress: ModelDownloadProgress, now: Date = Date()) -> Bool {
        let key = progress.repository.lowercased()
        let fraction = fraction(for: progress)

        guard let previous = snapshots[key] else {
            snapshots[key] = Snapshot(status: progress.status, currentFile: progress.currentFile, fraction: fraction, updatedAt: now)
            return true
        }

        let statusChanged = previous.status != progress.status
        let fileChanged = previous.currentFile != progress.currentFile
        let fractionChanged = abs((fraction ?? 0) - (previous.fraction ?? 0)) >= minimumFractionDelta
        let intervalElapsed = now.timeIntervalSince(previous.updatedAt) >= minimumInterval

        guard statusChanged || fileChanged || fractionChanged || intervalElapsed else {
            return false
        }

        snapshots[key] = Snapshot(status: progress.status, currentFile: progress.currentFile, fraction: fraction, updatedAt: now)
        return true
    }

    func remove(repository: String) {
        snapshots[repository.lowercased()] = nil
    }

    private func fraction(for progress: ModelDownloadProgress) -> Double? {
        guard let totalBytes = progress.totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(progress.bytesReceived) / Double(totalBytes)))
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
