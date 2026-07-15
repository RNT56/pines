import Foundation
import SwiftUI

enum PinesPerformancePressureLevel: Int, Comparable, Sendable {
    case normal
    case constrained
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PinesPerformancePolicy: Equatable, Sendable {
    let pressureLevel: PinesPerformancePressureLevel
    let allowsDecorativeMotion: Bool
    let allowsExpressiveHaptics: Bool
    let allowsSpeculativePrefetch: Bool
    let shouldPurgeCaches: Bool

    static func current(reduceMotion: Bool = false) -> PinesPerformancePolicy {
        resolve(
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState,
            reduceMotion: reduceMotion
        )
    }

    static func resolve(
        lowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState,
        reduceMotion: Bool
    ) -> PinesPerformancePolicy {
        let pressureLevel: PinesPerformancePressureLevel
        switch thermalState {
        case .serious, .critical:
            pressureLevel = .critical
        case .fair:
            pressureLevel = .constrained
        case .nominal:
            pressureLevel = lowPowerModeEnabled ? .constrained : .normal
        @unknown default:
            pressureLevel = .constrained
        }

        return PinesPerformancePolicy(
            pressureLevel: pressureLevel,
            allowsDecorativeMotion: !reduceMotion && pressureLevel == .normal,
            allowsExpressiveHaptics: pressureLevel == .normal,
            allowsSpeculativePrefetch: pressureLevel == .normal,
            shouldPurgeCaches: pressureLevel == .critical
        )
    }
}

private struct PinesPerformancePolicyEnvironmentKey: EnvironmentKey {
    static let defaultValue = PinesPerformancePolicy.current()
}

extension EnvironmentValues {
    var pinesPerformancePolicy: PinesPerformancePolicy {
        get { self[PinesPerformancePolicyEnvironmentKey.self] }
        set { self[PinesPerformancePolicyEnvironmentKey.self] = newValue }
    }
}
