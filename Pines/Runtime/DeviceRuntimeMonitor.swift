import Foundation
import PinesCore

#if canImport(Metal)
import Metal
#endif
#if canImport(MLX)
import MLX
#endif
#if canImport(Darwin)
import Darwin
#endif

struct DeviceRuntimeMonitor: Sendable {
    func snapshot() -> RuntimeMemorySnapshot {
        let mlxCapabilities = metalCapabilities()
        let processMemory = processMemorySnapshot()
        return RuntimeMemorySnapshot(
            physicalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            availableMemoryBytes: availableMemoryBytes(),
            processResidentMemoryBytes: processMemory.resident,
            processPhysicalFootprintBytes: processMemory.physicalFootprint,
            processPeakResidentMemoryBytes: processMemory.peakResident,
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

    func localGenerationSafety() -> LocalRuntimeSafetyAssessment {
        let currentSnapshot = snapshot()
        return LocalRuntimeSafetyPolicy.assess(
            snapshot: currentSnapshot,
            profile: DeviceProfile.recommended(for: currentSnapshot)
        )
    }

    func requireLocalGenerationSafety() throws -> LocalRuntimeSafetyAssessment {
        let safety = localGenerationSafety()
        guard safety.allowed else {
            throw InferenceError.unsupportedCapability(
                safety.reason ?? "Local MLX generation is paused by runtime safety policy."
            )
        }
        return safety
    }

    func memoryCounters(
        kvCacheBytes: Int64? = nil,
        quantizedKVCacheBytes: Int64? = nil,
        vaultIndexBytes: Int64? = nil
    ) -> RuntimeMemoryCounters {
        let currentSnapshot = snapshot()
        let profile = DeviceProfile.recommended(for: currentSnapshot)
        let mlxMemory = mlxMemorySnapshot()
        return RuntimeMemoryCounters(
            kvCacheBytes: kvCacheBytes,
            quantizedKVCacheBytes: quantizedKVCacheBytes,
            vaultIndexBytes: vaultIndexBytes,
            physicalMemoryBytes: currentSnapshot.physicalMemoryBytes,
            availableMemoryBytes: currentSnapshot.availableMemoryBytes,
            processResidentMemoryBytes: currentSnapshot.processResidentMemoryBytes,
            processPhysicalFootprintBytes: currentSnapshot.processPhysicalFootprintBytes,
            processPeakResidentMemoryBytes: currentSnapshot.processPeakResidentMemoryBytes,
            thermalState: currentSnapshot.thermalState,
            hardwareModelIdentifier: currentSnapshot.hardwareModelIdentifier,
            lowPowerModeEnabled: currentSnapshot.lowPowerModeEnabled,
            metalArchitectureName: currentSnapshot.metalArchitectureName,
            metalRecommendedWorkingSetBytes: currentSnapshot.metalRecommendedWorkingSetBytes,
            mlxActiveMemoryBytes: mlxMemory.active,
            mlxCacheMemoryBytes: mlxMemory.cache,
            mlxPeakMemoryBytes: mlxMemory.peak,
            mlxMemoryLimitBytes: mlxMemory.memoryLimit,
            mlxCacheLimitBytes: mlxMemory.cacheLimit,
            devicePerformanceClass: profile.performanceClass,
            thermalDownshiftActive: profile.thermalDownshiftActive,
            runtimePressureReason: profile.runtimePressureReason,
            recommendedContextTokens: profile.recommendedContextTokens,
            recommendedSmallModelContextTokens: profile.recommendedSmallModelContextTokens,
            recommendedPrefillStepSize: profile.recommendedPrefillStepSize,
            recommendedEmbeddingBatchSize: profile.recommendedEmbeddingBatchSize,
            recommendedVectorScanLimit: profile.recommendedVectorScanLimit
        )
    }

    private func mlxMemorySnapshot() -> (
        active: Int64?,
        cache: Int64?,
        peak: Int64?,
        memoryLimit: Int64?,
        cacheLimit: Int64?
    ) {
        #if targetEnvironment(simulator)
        return (nil, nil, nil, nil, nil)
        #else
        #if canImport(MLX)
        let snapshot = MLX.Memory.snapshot()
        return (
            Int64(snapshot.activeMemory),
            Int64(snapshot.cacheMemory),
            Int64(snapshot.peakMemory),
            Int64(MLX.Memory.memoryLimit),
            Int64(MLX.Memory.cacheLimit)
        )
        #else
        return (nil, nil, nil, nil, nil)
        #endif
        #endif
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

    private func processMemorySnapshot() -> (
        resident: Int64?,
        physicalFootprint: Int64?,
        peakResident: Int64?
    ) {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (nil, nil, nil)
        }
        return (
            Int64(info.resident_size),
            Int64(info.phys_footprint),
            Int64(info.resident_size_peak)
        )
        #else
        return (nil, nil, nil)
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
        #if targetEnvironment(simulator)
        return (
            device.architectureName,
            device.recommendedWorkingSetBytes,
            nil,
            nil
        )
        #else
        #if canImport(MLX)
        let availability = MLX.TurboQuantKernelAvailability.current
        return (
            device.architectureName,
            device.recommendedWorkingSetBytes,
            Self.coreTurboQuantKernelProfile(from: availability.selectedKernelProfile),
            Self.coreTurboQuantSelfTestStatus(from: availability.selfTestStatus)
        )
        #else
        return (
            device.architectureName,
            device.recommendedWorkingSetBytes,
            nil,
            nil
        )
        #endif
        #endif
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

    #if canImport(MLX)
    private static func coreTurboQuantKernelProfile(
        from profile: MLX.TurboQuantKernelProfile
    ) -> PinesCore.TurboQuantKernelProfile {
        switch profile {
        case .portableA16A17:
            .portableA16A17
        case .wideA18A19:
            .wideA18A19
        case .sustainedA19Pro:
            .sustainedA19Pro
        case .macAppleSilicon:
            .macAppleSilicon
        case .mlxPackedFallback:
            .mlxPackedFallback
        }
    }

    private static func coreTurboQuantSelfTestStatus(
        from status: MLX.TurboQuantRuntimeSelfTestStatus
    ) -> PinesCore.TurboQuantSelfTestStatus {
        switch status {
        case .notRun:
            .notRun
        case .passed:
            .passed
        case .failed:
            .failed
        }
    }
    #endif
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
