import Foundation

public enum LocalModelAdmissionMemoryKind: String, Codable, Sendable, CaseIterable {
    case coldLoad
    case warmReuse
    case modelReplacement
}

/// Converts Apple's incremental per-process headroom into the memory basis used to
/// decide whether a local model can be loaded or reused.
///
/// `os_proc_available_memory()` already subtracts the app's current footprint. A
/// warm model must therefore not be charged a second time. During replacement, only
/// the resident bytes belonging to the outgoing model are considered reclaimable.
public struct LocalModelAdmissionMemoryBasis: Hashable, Codable, Sendable {
    public var kind: LocalModelAdmissionMemoryKind
    public var currentAvailableMemoryBytes: Int64
    public var plannerAvailableMemoryBytes: Int64
    public var incrementalTargetModelBytes: Int64
    public var reclaimableLoadedModelBytes: Int64

    public init(
        kind: LocalModelAdmissionMemoryKind,
        currentAvailableMemoryBytes: Int64,
        plannerAvailableMemoryBytes: Int64,
        incrementalTargetModelBytes: Int64,
        reclaimableLoadedModelBytes: Int64
    ) {
        self.kind = kind
        self.currentAvailableMemoryBytes = max(0, currentAvailableMemoryBytes)
        self.plannerAvailableMemoryBytes = max(0, plannerAvailableMemoryBytes)
        self.incrementalTargetModelBytes = max(0, incrementalTargetModelBytes)
        self.reclaimableLoadedModelBytes = max(0, reclaimableLoadedModelBytes)
    }
}

public enum LocalModelRuntimePolicy {
    private static let compactWeightBytes: Int64 = 900_000_000
    private static let balancedWeightBytes: Int64 = 1_650_000_000

    public static func admissionMemoryBasis(
        availableMemoryBytes: Int64?,
        mlxActiveMemoryBytes: Int64?,
        loadedModelEstimatedBytes: Int64?,
        targetModelEstimatedBytes: Int64?,
        hasLoadedModel: Bool,
        reusesLoadedModel: Bool
    ) -> LocalModelAdmissionMemoryBasis {
        let available = max(0, availableMemoryBytes ?? 0)
        let targetBytes = max(0, targetModelEstimatedBytes ?? 0)

        guard hasLoadedModel else {
            return LocalModelAdmissionMemoryBasis(
                kind: .coldLoad,
                currentAvailableMemoryBytes: available,
                plannerAvailableMemoryBytes: available,
                incrementalTargetModelBytes: targetBytes,
                reclaimableLoadedModelBytes: 0
            )
        }

        if reusesLoadedModel {
            return LocalModelAdmissionMemoryBasis(
                kind: .warmReuse,
                currentAvailableMemoryBytes: available,
                plannerAvailableMemoryBytes: available,
                incrementalTargetModelBytes: 0,
                reclaimableLoadedModelBytes: 0
            )
        }

        let activeBytes = max(0, mlxActiveMemoryBytes ?? 0)
        let loadedEstimate = max(0, loadedModelEstimatedBytes ?? 0)
        let reclaimableBytes = loadedEstimate > 0 ? min(activeBytes, loadedEstimate) : 0
        let (prospectiveAvailable, overflow) = available.addingReportingOverflow(reclaimableBytes)

        return LocalModelAdmissionMemoryBasis(
            kind: .modelReplacement,
            currentAvailableMemoryBytes: available,
            plannerAvailableMemoryBytes: overflow ? Int64.max : prospectiveAvailable,
            incrementalTargetModelBytes: targetBytes,
            reclaimableLoadedModelBytes: reclaimableBytes
        )
    }

    /// Conservative product defaults for A17 Pro. Larger windows remain available
    /// through the explicit Max Context mode, where live admission still has final say.
    public static func contextTokenCap(
        for install: ModelInstall,
        deviceProfile: DeviceProfile,
        userMode: TurboQuantUserMode,
        deviceRecommendedTokens: Int
    ) -> Int {
        let recommended = max(AppSettingsSnapshot.minLocalContextTokens, deviceRecommendedTokens)

        if userMode == .maxContext {
            return recommended
        }

        let isPressureConstrained = deviceProfile.runtimePressureReason == .lowMemory
            || deviceProfile.runtimePressureReason == .thermalCritical
            || deviceProfile.runtimePressureReason == .thermalSerious
        var cap = recommended
        if deviceProfile.performanceClass == .a17Pro {
            if install.effectiveTurboQuantModalities.contains(.vision)
                || install.effectiveTurboQuantModalities.contains(.audio)
            {
                cap = min(cap, 2_048)
            } else {
                let estimatedBytes = install.estimatedBytes.flatMap { $0 > 0 ? $0 : nil }
                let parameterCount = install.resolvedParameterCount
                let tierCap: Int
                if let estimatedBytes {
                    if estimatedBytes <= compactWeightBytes {
                        tierCap = 8_192
                    } else if estimatedBytes <= balancedWeightBytes {
                        tierCap = 4_096
                    } else {
                        tierCap = 2_048
                    }
                } else if let parameterCount {
                    if parameterCount <= 1_500_000_000 {
                        tierCap = 8_192
                    } else if parameterCount <= 2_500_000_000 {
                        tierCap = 4_096
                    } else {
                        tierCap = 2_048
                    }
                } else {
                    tierCap = 4_096
                }
                cap = min(cap, tierCap)
            }
        }

        if userMode == .fastest {
            cap = min(cap, 8_192)
        }
        if userMode == .batterySaver || isPressureConstrained {
            cap = min(cap, 4_096)
        }
        return cap
    }
}
