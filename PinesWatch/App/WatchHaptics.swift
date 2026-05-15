import Foundation
import PinesWatchSupport
#if canImport(WatchKit)
import WatchKit
#endif

enum WatchHapticEvent: Hashable {
    case appReady
    case navigationSelected
    case primaryAction
    case destructiveAction
    case sendCommitted
    case runAccepted
    case firstToken
    case streamPulse
    case streamMilestone
    case runCompleted
    case runCancelled
    case runFailed
}

@MainActor
final class WatchHaptics {
    static let shared = WatchHaptics()

    private var lastPlaybackAt = Date.distantPast

    private init() {}

    func play(_ event: WatchHapticEvent) {
        let now = Date()
        let minimumInterval = event.isStreamTexture ? 1.1 : 0.12
        guard now.timeIntervalSince(lastPlaybackAt) >= minimumInterval else { return }
        lastPlaybackAt = now

        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(event.hapticType)
        #endif
    }
}

struct WatchStreamHapticGate {
    private var runID: UUID?
    private var didEmitFirstToken = false
    private var lastPulseAt = Date.distantPast
    private var lastPulseProgress = 0

    mutating func event(for update: WatchChatRunUpdate, now: Date = Date()) -> WatchHapticEvent? {
        if runID != update.runID {
            runID = update.runID
            didEmitFirstToken = false
            lastPulseAt = .distantPast
            lastPulseProgress = 0
        }

        switch update.status {
        case .accepted:
            return .runAccepted
        case .streaming:
            let progress = max(update.tokenCount, update.text.count / 4)
            guard progress > 0, !update.text.isEmpty else { return nil }
            if !didEmitFirstToken {
                didEmitFirstToken = true
                lastPulseAt = now
                lastPulseProgress = progress
                return .firstToken
            }

            let boundary = update.text.hasSuffix("\n")
                || update.text.hasSuffix(". ")
                || update.text.hasSuffix("? ")
                || update.text.hasSuffix("! ")
            guard now.timeIntervalSince(lastPulseAt) >= (boundary ? 1.5 : 1.2) else { return nil }
            guard progress - lastPulseProgress >= (boundary ? 16 : 20) else { return nil }
            lastPulseAt = now
            lastPulseProgress = progress
            return boundary ? .streamMilestone : .streamPulse
        case .completed:
            return .runCompleted
        case .failed:
            return .runFailed
        case .cancelled:
            return .runCancelled
        }
    }
}

private extension WatchHapticEvent {
    #if canImport(WatchKit)
    var hapticType: WKHapticType {
        switch self {
        case .appReady, .runCompleted:
            .success
        case .navigationSelected, .primaryAction, .firstToken, .streamPulse:
            .click
        case .destructiveAction, .runFailed:
            .failure
        case .sendCommitted, .runAccepted:
            .start
        case .streamMilestone:
            .directionUp
        case .runCancelled:
            .stop
        }
    }
    #endif

    var isStreamTexture: Bool {
        switch self {
        case .streamPulse, .streamMilestone:
            true
        case .appReady,
             .navigationSelected,
             .primaryAction,
             .destructiveAction,
             .sendCommitted,
             .runAccepted,
             .firstToken,
             .runCompleted,
             .runCancelled,
             .runFailed:
            false
        }
    }
}
