import Foundation
import PinesCore

#if canImport(Metal)
import Metal
#endif
#if canImport(Darwin)
import Darwin
#endif

struct DeviceRuntimeMonitor: Sendable {
    func snapshot() -> RuntimeMemorySnapshot {
        let mlxCapabilities = metalCapabilities()
        return RuntimeMemorySnapshot(
            physicalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            availableMemoryBytes: availableMemoryBytes(),
            thermalState: ProcessInfo.processInfo.thermalState.pinesRuntimeValue,
            hardwareModelIdentifier: hardwareModelIdentifier(),
            lowPowerModeEnabled: isLowPowerModeEnabled(),
            metalArchitectureName: mlxCapabilities.architectureName,
            metalRecommendedWorkingSetBytes: mlxCapabilities.recommendedWorkingSetBytes,
            metalKernelProfile: mlxCapabilities.kernelProfile,
            metalSelfTestStatus: mlxCapabilities.selfTestStatus
        )
    }

    func currentProfile() -> DeviceProfile {
        DeviceProfile.recommended(for: snapshot())
    }

    func memoryCounters(
        kvCacheBytes: Int64? = nil,
        quantizedKVCacheBytes: Int64? = nil,
        vaultIndexBytes: Int64? = nil
    ) -> RuntimeMemoryCounters {
        let currentSnapshot = snapshot()
        let profile = DeviceProfile.recommended(for: currentSnapshot)
        return RuntimeMemoryCounters(
            kvCacheBytes: kvCacheBytes,
            quantizedKVCacheBytes: quantizedKVCacheBytes,
            vaultIndexBytes: vaultIndexBytes,
            physicalMemoryBytes: currentSnapshot.physicalMemoryBytes,
            availableMemoryBytes: currentSnapshot.availableMemoryBytes,
            thermalState: currentSnapshot.thermalState,
            hardwareModelIdentifier: currentSnapshot.hardwareModelIdentifier,
            lowPowerModeEnabled: currentSnapshot.lowPowerModeEnabled,
            metalArchitectureName: currentSnapshot.metalArchitectureName,
            metalRecommendedWorkingSetBytes: currentSnapshot.metalRecommendedWorkingSetBytes,
            devicePerformanceClass: profile.performanceClass,
            thermalDownshiftActive: profile.thermalDownshiftActive,
            recommendedContextTokens: profile.recommendedContextTokens,
            recommendedEmbeddingBatchSize: profile.recommendedEmbeddingBatchSize,
            recommendedVectorScanLimit: profile.recommendedVectorScanLimit
        )
    }

    private func availableMemoryBytes() -> Int64? {
        #if os(iOS)
        let available = os_proc_available_memory()
        guard available > 0 else { return nil }
        return Int64(available)
        #else
        return nil
        #endif
    }

    private func hardwareModelIdentifier() -> String? {
        #if canImport(Darwin)
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return nil }
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.compactMap { child -> String? in
            guard let value = child.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(bitPattern: value)))
        }.joined()
        return identifier.isEmpty ? nil : identifier
        #else
        return nil
        #endif
    }

    private func isLowPowerModeEnabled() -> Bool {
        #if os(iOS)
        ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        false
        #endif
    }

    private func metalCapabilities() -> (
        architectureName: String?,
        recommendedWorkingSetBytes: Int64?,
        kernelProfile: PinesCore.TurboQuantKernelProfile?,
        selfTestStatus: PinesCore.TurboQuantSelfTestStatus?
    ) {
        let device = metalDeviceSnapshot()
        return (
            device.architectureName,
            device.recommendedWorkingSetBytes,
            nil,
            nil
        )
    }

    private func metalDeviceSnapshot() -> (
        architectureName: String?,
        recommendedWorkingSetBytes: Int64?
    ) {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else {
            return (nil, nil)
        }
        let recommendedWorkingSetBytes = device.recommendedMaxWorkingSetSize > 0
            ? Int64(device.recommendedMaxWorkingSetSize)
            : nil
        return (device.name, recommendedWorkingSetBytes)
        #else
        return (nil, nil)
        #endif
    }
}

private extension ProcessInfo.ThermalState {
    var pinesRuntimeValue: String {
        switch self {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        @unknown default:
            "unknown"
        }
    }
}
