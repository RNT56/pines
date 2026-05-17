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
            "Minimal, subtle feedback for direct actions and navigation."
        case .expressive:
            "Richer feedback for actions, streaming, scroll texture, and boundaries."
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
    case scrollUp
    case scrollDown
    case scrollBoundaryTop
    case scrollBoundaryBottom
    case toolApprovalNeeded
    case runCompleted
    case runCancelled
    case runFailed

    var allowsLowPowerPlayback: Bool {
        switch self {
        case .streamPulse, .streamMilestone, .firstToken, .scrollUp, .scrollDown:
            false
        case .appReady,
             .tabChanged,
             .navigationSelected,
             .primaryAction,
             .destructiveAction,
             .sendCommitted,
             .runAccepted,
             .scrollBoundaryTop,
             .scrollBoundaryBottom,
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

private enum PinesScrollDirection {
    case up
    case down
}

struct PinesScrollHapticGate {
    private var lastOffset: CGFloat?
    private var lastEmittedOffset: CGFloat?
    private var lastEmittedDirection: PinesScrollDirection?
    private var lastEmittedAt = Date.distantPast
    private var lastBoundaryAt = Date.distantPast
    private var wasAtTop = false
    private var wasAtBottom = false

    mutating func event(
        offset: CGFloat,
        minOffset: CGFloat = 0,
        maxOffset: CGFloat? = nil,
        isAtTop: Bool? = nil,
        isAtBottom: Bool? = nil,
        now: Date = Date()
    ) -> PinesHapticEvent? {
        defer { lastOffset = offset }
        let boundaryTolerance: CGFloat = 6
        let atTop = isAtTop ?? (offset <= minOffset + boundaryTolerance)
        let atBottom = isAtBottom ?? maxOffset.map { offset >= $0 - boundaryTolerance && $0 > minOffset + boundaryTolerance } ?? false

        guard let previousOffset = lastOffset else {
            lastEmittedOffset = offset
            wasAtTop = atTop
            wasAtBottom = atBottom
            return nil
        }

        defer {
            if !atTop { wasAtTop = false }
            if !atBottom { wasAtBottom = false }
        }

        if atTop, !wasAtTop, now.timeIntervalSince(lastBoundaryAt) >= 0.35 {
            wasAtTop = true
            lastBoundaryAt = now
            return .scrollBoundaryTop
        }

        if atBottom, !wasAtBottom, now.timeIntervalSince(lastBoundaryAt) >= 0.35 {
            wasAtBottom = true
            lastBoundaryAt = now
            return .scrollBoundaryBottom
        }

        let delta = offset - previousOffset
        guard abs(delta) > 1.5 else { return nil }

        let direction: PinesScrollDirection = delta > 0 ? .down : .up
        let emittedOffset = lastEmittedOffset ?? previousOffset
        let distance = abs(offset - emittedOffset)
        let directionChanged = lastEmittedDirection != nil && lastEmittedDirection != direction
        let minimumDistance: CGFloat = directionChanged ? 28 : 84
        let minimumInterval: TimeInterval = directionChanged ? 0.10 : 0.16

        guard distance >= minimumDistance else { return nil }
        guard now.timeIntervalSince(lastEmittedAt) >= minimumInterval else { return nil }

        lastEmittedOffset = offset
        lastEmittedDirection = direction
        lastEmittedAt = now
        return direction == .down ? .scrollDown : .scrollUp
    }

    mutating func reset() {
        lastOffset = nil
        lastEmittedOffset = nil
        lastEmittedDirection = nil
        lastEmittedAt = .distantPast
        lastBoundaryAt = .distantPast
        wasAtTop = false
        wasAtBottom = false
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
    private var hapticEngineRunning = false
    private var hapticEngineStartInFlight = false
    private var lastHapticEngineStartAttempt = Date.distantPast
    private var coreHapticsDisabledUntil = Date.distantPast
    #endif

    init() {
        let rawMode = UserDefaults.standard.string(forKey: Self.modeKey)
        mode = rawMode.flatMap(PinesHapticMode.init(rawValue:)) ?? .standard
    }

    func play(_ event: PinesHapticEvent) {
        #if targetEnvironment(simulator)
        return
        #endif

        guard mode != .off else { return }
        guard event.allowsLowPowerPlayback || !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        switch mode {
        case .off:
            break
        case .standard:
            playStandard(event)
        case .expressive:
            playExpressive(event)
        }

        prepare()
    }

    private func playStandard(_ event: PinesHapticEvent) {
        switch event {
        case .appReady, .firstToken, .streamPulse, .streamMilestone, .scrollUp, .scrollDown, .scrollBoundaryTop, .scrollBoundaryBottom:
            break
        case .tabChanged, .navigationSelected:
            selectionChanged()
        case .primaryAction:
            impact(.light, intensity: 0.30)
        case .destructiveAction:
            impact(.medium, intensity: 0.46)
        case .sendCommitted:
            impact(.light, intensity: 0.36)
        case .runAccepted:
            impact(.soft, intensity: 0.28)
        case .toolApprovalNeeded:
            impact(.medium, intensity: 0.48)
        case .runCompleted:
            impact(.soft, intensity: 0.34)
        case .runCancelled:
            impact(.light, intensity: 0.34)
        case .runFailed:
            impact(.medium, intensity: 0.52)
        }
    }

    private func playExpressive(_ event: PinesHapticEvent) {
        switch event {
        case .appReady:
            success()
        case .tabChanged, .navigationSelected:
            selectionChanged()
        case .primaryAction:
            impact(.light, intensity: 0.58)
        case .destructiveAction:
            impact(.heavy, intensity: 0.82)
        case .sendCommitted:
            impact(.medium, intensity: 0.70)
        case .runAccepted:
            playCorePulse(intensity: 0.34, sharpness: 0.24, fallback: .soft, fallbackIntensity: 0.48)
        case .firstToken:
            playCorePulse(intensity: 0.28, sharpness: 0.20, fallback: .soft, fallbackIntensity: 0.38)
        case .streamPulse:
            playCorePulse(intensity: 0.20, sharpness: 0.18, fallback: .soft, fallbackIntensity: 0.28)
        case .streamMilestone:
            playCoreSequence(
                [
                    (intensity: 0.30, sharpness: 0.28, relativeTime: 0),
                    (intensity: 0.18, sharpness: 0.18, relativeTime: 0.055),
                ],
                fallback: .light,
                fallbackIntensity: 0.46
            )
        case .scrollUp:
            playCorePulse(intensity: 0.12, sharpness: 0.18, fallback: .soft, fallbackIntensity: 0.18)
        case .scrollDown:
            playCorePulse(intensity: 0.14, sharpness: 0.24, fallback: .soft, fallbackIntensity: 0.20)
        case .scrollBoundaryTop:
            playCoreSequence(
                [
                    (intensity: 0.40, sharpness: 0.42, relativeTime: 0),
                    (intensity: 0.18, sharpness: 0.22, relativeTime: 0.045),
                ],
                fallback: .light,
                fallbackIntensity: 0.58
            )
        case .scrollBoundaryBottom:
            playCoreSequence(
                [
                    (intensity: 0.50, sharpness: 0.54, relativeTime: 0),
                    (intensity: 0.24, sharpness: 0.26, relativeTime: 0.05),
                ],
                fallback: .medium,
                fallbackIntensity: 0.66
            )
        case .toolApprovalNeeded:
            warning()
        case .runCompleted:
            success()
        case .runCancelled:
            impact(.medium, intensity: 0.58)
        case .runFailed:
            error()
        }
    }

    func prepare() {
        #if targetEnvironment(simulator)
        return
        #endif

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
        #if targetEnvironment(simulator)
        return
        #else
        #if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if hapticEngineRunning { return }
        if hapticEngineStartInFlight { return }
        let now = Date()
        guard now >= coreHapticsDisabledUntil else { return }
        guard now.timeIntervalSince(lastHapticEngineStartAttempt) > 0.4 else { return }
        lastHapticEngineStartAttempt = now
        hapticEngineStartInFlight = true
        defer { hapticEngineStartInFlight = false }

        do {
            let engine: CHHapticEngine
            if let hapticEngine {
                engine = hapticEngine
            } else {
                engine = try CHHapticEngine()
            }
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.hapticEngineRunning = false
                    self?.hapticEngine = nil
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.hapticEngineRunning = false
                    self?.hapticEngine = nil
                }
            }
            hapticEngine = engine
            try engine.start()
            hapticEngineRunning = true
        } catch {
            hapticEngineRunning = false
            hapticEngine = nil
            disableCoreHapticsTemporarily()
        }
        #endif
        #endif
    }

    #if canImport(CoreHaptics)
    private func disableCoreHapticsTemporarily() {
        coreHapticsDisabledUntil = Date().addingTimeInterval(20)
    }
    #endif

    private func playCorePulse(intensity: Float, sharpness: Float, fallback: ImpactStyle = .soft, fallbackIntensity: CGFloat? = nil) {
        playCoreSequence(
            [(intensity: intensity, sharpness: sharpness, relativeTime: 0)],
            fallback: fallback,
            fallbackIntensity: fallbackIntensity ?? CGFloat(intensity)
        )
    }

    private func playCoreSequence(
        _ events: [(intensity: Float, sharpness: Float, relativeTime: TimeInterval)],
        fallback: ImpactStyle,
        fallbackIntensity: CGFloat
    ) {
        #if canImport(CoreHaptics)
        prepareCoreHaptics()
        guard let hapticEngine, hapticEngineRunning else {
            impact(fallback, intensity: fallbackIntensity)
            return
        }

        do {
            let hapticEvents = events.map { event in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
                    ],
                    relativeTime: event.relativeTime
                )
            }
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            hapticEngineRunning = false
            self.hapticEngine = nil
            disableCoreHapticsTemporarily()
            impact(fallback, intensity: fallbackIntensity)
        }
        #else
        impact(fallback, intensity: fallbackIntensity)
        #endif
    }
}

private struct PinesScrollHapticSnapshot: Equatable {
    var offset: CGFloat
    var minOffset: CGFloat
    var maxOffset: CGFloat?
    var isAtTop: Bool
    var isAtBottom: Bool
}

private enum PinesScrollHapticAxis {
    case horizontal
    case vertical
}

private final class PinesScrollHapticCoordinator {
    private var gate = PinesScrollHapticGate()

    func reset() {
        gate.reset()
    }

    func event(for snapshot: PinesScrollHapticSnapshot) -> PinesHapticEvent? {
        gate.event(
            offset: snapshot.offset,
            minOffset: snapshot.minOffset,
            maxOffset: snapshot.maxOffset,
            isAtTop: snapshot.isAtTop,
            isAtBottom: snapshot.isAtBottom
        )
    }
}

private struct PinesExpressiveScrollHapticsModifier: ViewModifier {
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var coordinator = PinesScrollHapticCoordinator()
    let axis: PinesScrollHapticAxis

    func body(content: Content) -> some View {
        #if targetEnvironment(simulator)
        content
        #else
        if haptics.mode == .expressive {
            content
                .onScrollGeometryChange(for: PinesScrollHapticSnapshot.self) { geometry in
                    let quantizedMinOffset = quantizedScrollOffset(minOffset(for: geometry))
                    let rawMaxOffset = maxOffset(for: geometry)
                    let maxOffset = max(quantizedMinOffset, quantizedScrollOffset(rawMaxOffset))
                    let quantizedOffset = quantizedScrollOffset(offset(for: geometry))
                    let rawMinOffset = minOffset(for: geometry)
                    let rawOffset = offset(for: geometry)
                    let hasScrollableContent = rawMaxOffset > rawMinOffset + 6
                    return PinesScrollHapticSnapshot(
                        offset: quantizedOffset,
                        minOffset: quantizedMinOffset,
                        maxOffset: maxOffset > quantizedMinOffset ? maxOffset : nil,
                        isAtTop: rawOffset <= rawMinOffset + 6,
                        isAtBottom: hasScrollableContent && rawOffset >= rawMaxOffset - 6
                    )
                } action: { _, snapshot in
                    if let event = coordinator.event(for: snapshot) {
                        haptics.play(event)
                    }
                }
        } else {
            content
                .onAppear {
                    coordinator.reset()
                }
        }
        #endif
    }

    private func quantizedScrollOffset(_ value: CGFloat) -> CGFloat {
        let step: CGFloat = 24
        return (value / step).rounded() * step
    }

    private func offset(for geometry: ScrollGeometry) -> CGFloat {
        switch axis {
        case .horizontal:
            geometry.contentOffset.x
        case .vertical:
            geometry.contentOffset.y
        }
    }

    private func minOffset(for geometry: ScrollGeometry) -> CGFloat {
        switch axis {
        case .horizontal:
            -geometry.contentInsets.leading
        case .vertical:
            -geometry.contentInsets.top
        }
    }

    private func maxOffset(for geometry: ScrollGeometry) -> CGFloat {
        switch axis {
        case .horizontal:
            geometry.contentSize.width - geometry.containerSize.width + geometry.contentInsets.trailing
        case .vertical:
            geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom
        }
    }
}

extension View {
    func pinesExpressiveScrollHaptics() -> some View {
        modifier(PinesExpressiveScrollHapticsModifier(axis: .vertical))
    }

    func pinesExpressiveHorizontalScrollHaptics() -> some View {
        modifier(PinesExpressiveScrollHapticsModifier(axis: .horizontal))
    }
}
