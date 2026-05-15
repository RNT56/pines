import Foundation
import SwiftUI

#if canImport(CoreHaptics)
import CoreHaptics
#endif

#if canImport(UIKit)
import UIKit
#endif

enum PinesHapticMode: String, CaseIterable, Identifiable {
    case off
    case standard
    case expressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .standard:
            "Standard"
        case .expressive:
            "Expressive"
        }
    }

    var subtitle: String {
        switch self {
        case .off:
            "No in-app haptic feedback."
        case .standard:
            "Sparse feedback for actions, navigation, and chat state."
        case .expressive:
            "Adds gentle, throttled texture while assistant messages stream."
        }
    }
}

enum PinesHapticEvent: Hashable {
    case appReady
    case tabChanged
    case navigationSelected
    case primaryAction
    case destructiveAction
    case sendCommitted
    case runAccepted
    case firstToken
    case streamPulse
    case streamMilestone
    case toolApprovalNeeded
    case runCompleted
    case runCancelled
    case runFailed

    var allowsLowPowerPlayback: Bool {
        switch self {
        case .streamPulse, .streamMilestone, .firstToken:
            false
        case .appReady,
             .tabChanged,
             .navigationSelected,
             .primaryAction,
             .destructiveAction,
             .sendCommitted,
             .runAccepted,
             .toolApprovalNeeded,
             .runCompleted,
             .runCancelled,
             .runFailed:
            true
        }
    }
}

struct PinesHapticSignal: Identifiable, Equatable {
    let id = UUID()
    let event: PinesHapticEvent
}

struct PinesStreamHapticGate {
    private var didEmitFirstToken = false
    private var lastPulseAt = Date.distantPast
    private var lastPulseTokenCount = 0

    mutating func event(tokenCount: Int, content: String, now: Date = Date()) -> PinesHapticEvent? {
        guard tokenCount > 0, !content.isEmpty else { return nil }

        if !didEmitFirstToken {
            didEmitFirstToken = true
            lastPulseAt = now
            lastPulseTokenCount = tokenCount
            return .firstToken
        }

        let boundary = content.hasSuffix("\n")
            || content.hasSuffix(". ")
            || content.hasSuffix("? ")
            || content.hasSuffix("! ")
            || content.hasSuffix("```")
        let minimumInterval: TimeInterval = boundary ? 0.9 : 0.7
        let minimumTokens = boundary ? 8 : 10
        guard now.timeIntervalSince(lastPulseAt) >= minimumInterval else { return nil }
        guard tokenCount - lastPulseTokenCount >= minimumTokens else { return nil }

        lastPulseAt = now
        lastPulseTokenCount = tokenCount
        return boundary ? .streamMilestone : .streamPulse
    }

    mutating func reset() {
        didEmitFirstToken = false
        lastPulseAt = .distantPast
        lastPulseTokenCount = 0
    }
}

@MainActor
final class PinesHaptics: ObservableObject {
    @Published var mode: PinesHapticMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            if mode == .expressive {
                prepareCoreHaptics()
            }
        }
    }

    private static let modeKey = "pines.haptics.mode"

    #if canImport(UIKit)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    #endif

    #if canImport(CoreHaptics)
    private var hapticEngine: CHHapticEngine?
    #endif

    init() {
        let rawMode = UserDefaults.standard.string(forKey: Self.modeKey)
        mode = rawMode.flatMap(PinesHapticMode.init(rawValue:)) ?? .standard
        prepare()
    }

    func play(_ event: PinesHapticEvent) {
        guard mode != .off else { return }
        guard event.allowsLowPowerPlayback || !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        switch event {
        case .appReady:
            success()
        case .tabChanged, .navigationSelected:
            selectionChanged()
        case .primaryAction:
            impact(.light, intensity: 0.55)
        case .destructiveAction:
            impact(.heavy, intensity: 0.75)
        case .sendCommitted:
            impact(.medium, intensity: 0.65)
        case .runAccepted:
            impact(.soft, intensity: 0.45)
        case .firstToken:
            impact(.soft, intensity: 0.35)
        case .streamPulse:
            if mode == .expressive {
                playCorePulse(intensity: 0.16, sharpness: 0.18)
            } else {
                impact(.soft, intensity: 0.22)
            }
        case .streamMilestone:
            if mode == .expressive {
                playCorePulse(intensity: 0.26, sharpness: 0.28)
            } else {
                impact(.light, intensity: 0.34)
            }
        case .toolApprovalNeeded:
            warning()
        case .runCompleted:
            success()
        case .runCancelled:
            impact(.medium, intensity: 0.55)
        case .runFailed:
            error()
        }

        prepare()
    }

    func prepare() {
        #if canImport(UIKit)
        selection.prepare()
        notification.prepare()
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        softImpact.prepare()
        #endif

        if mode == .expressive {
            prepareCoreHaptics()
        }
    }

    private func selectionChanged() {
        #if canImport(UIKit)
        selection.selectionChanged()
        #endif
    }

    private func success() {
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        #endif
    }

    private func warning() {
        #if canImport(UIKit)
        notification.notificationOccurred(.warning)
        #endif
    }

    private func error() {
        #if canImport(UIKit)
        notification.notificationOccurred(.error)
        #endif
    }

    private func impact(_ style: ImpactStyle, intensity: CGFloat) {
        #if canImport(UIKit)
        switch style {
        case .light:
            lightImpact.impactOccurred(intensity: intensity)
        case .medium:
            mediumImpact.impactOccurred(intensity: intensity)
        case .heavy:
            heavyImpact.impactOccurred(intensity: intensity)
        case .soft:
            softImpact.impactOccurred(intensity: intensity)
        }
        #endif
    }

    private enum ImpactStyle {
        case light
        case medium
        case heavy
        case soft
    }

    private func prepareCoreHaptics() {
        #if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        guard hapticEngine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.hapticEngine = nil
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.hapticEngine = nil
                    self?.prepareCoreHaptics()
                }
            }
            try engine.start()
            hapticEngine = engine
        } catch {
            hapticEngine = nil
        }
        #endif
    }

    private func playCorePulse(intensity: Float, sharpness: Float) {
        #if canImport(CoreHaptics)
        prepareCoreHaptics()
        guard let hapticEngine else {
            impact(.soft, intensity: CGFloat(intensity))
            return
        }

        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            impact(.soft, intensity: CGFloat(intensity))
        }
        #else
        impact(.soft, intensity: CGFloat(intensity))
        #endif
    }
}
