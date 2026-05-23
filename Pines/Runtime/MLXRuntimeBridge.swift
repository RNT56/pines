import Foundation
import PinesCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(PinesHubXetSupport)
import PinesHubXetSupport
#endif
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLLM)
import MLXLLM
#endif
#if canImport(MLXVLM)
import MLXVLM
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(Tokenizers)
import Tokenizers
#endif

private final class MLXGenerationCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func set(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func clear() {
        lock.lock()
        task = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

private enum LocalRuntimeSupervisorState: String, Sendable {
    case idle
    case loading
    case ready
    case generating
    case cancelling
    case unloading
    case blocked
}

private struct LocalRuntimeSupervisorSnapshot: Sendable {
    var state: LocalRuntimeSupervisorState
    var modelID: ModelID?
    var reason: String?
    var updatedAt: Date
}

private actor LocalRuntimeSupervisor {
    private var snapshot = LocalRuntimeSupervisorSnapshot(
        state: .idle,
        modelID: nil,
        reason: nil,
        updatedAt: Date()
    )

    func currentSnapshot() -> LocalRuntimeSupervisorSnapshot {
        snapshot
    }

    func beginLoading(modelID: ModelID) {
        update(state: .loading, modelID: modelID, reason: nil)
    }

    func markReady(modelID: ModelID) {
        update(state: .ready, modelID: modelID, reason: nil)
    }

    func beginGenerating(modelID: ModelID) {
        update(state: .generating, modelID: modelID, reason: nil)
    }

    func finishGeneration(modelID: ModelID?) {
        update(state: modelID == nil ? .idle : .ready, modelID: modelID, reason: nil)
    }

    func beginCancelling(reason: String) {
        update(state: .cancelling, modelID: snapshot.modelID, reason: reason)
    }

    func beginUnloading(reason: String) {
        update(state: .unloading, modelID: snapshot.modelID, reason: reason)
    }

    func markUnloaded(reason: String? = nil) {
        update(state: .idle, modelID: nil, reason: reason)
    }

    func block(reason: String, modelID: ModelID? = nil) {
        update(state: .blocked, modelID: modelID ?? snapshot.modelID, reason: reason)
    }

    private func update(state: LocalRuntimeSupervisorState, modelID: ModelID?, reason: String?) {
        snapshot = LocalRuntimeSupervisorSnapshot(
            state: state,
            modelID: modelID,
            reason: reason,
            updatedAt: Date()
        )
    }
}

struct MLXRuntimeBridge: Sendable {
    private let state = MLXRuntimeState()
    private let deviceMonitor = DeviceRuntimeMonitor()
    private let supervisor = LocalRuntimeSupervisor()

    private func runtimeMemoryMetadata(
        merging base: [String: String] = [:]
    ) -> [String: String] {
        var metadata = base
        let counters = deviceMonitor.memoryCounters()
        Self.add(counters.physicalMemoryBytes, forKey: "physical_memory_bytes", to: &metadata)
        Self.add(counters.availableMemoryBytes, forKey: "available_memory_bytes", to: &metadata)
        if let thermalState = counters.thermalState {
            metadata["thermal_state"] = thermalState
        }
        if let lowPowerModeEnabled = counters.lowPowerModeEnabled {
            metadata["low_power_mode_enabled"] = String(lowPowerModeEnabled)
        }
        if let hardwareModelIdentifier = counters.hardwareModelIdentifier {
            metadata["hardware_model_identifier"] = hardwareModelIdentifier
        }
        if let performanceClass = counters.devicePerformanceClass {
            metadata["device_performance_class"] = performanceClass.rawValue
        }
        if let runtimePressureReason = counters.runtimePressureReason {
            metadata["runtime_pressure_reason"] = runtimePressureReason.rawValue
        }
        if let thermalDownshiftActive = counters.thermalDownshiftActive {
            metadata["thermal_downshift_active"] = String(thermalDownshiftActive)
        }
        Self.add(counters.recommendedContextTokens, forKey: "recommended_context_tokens", to: &metadata)
        Self.add(counters.recommendedSmallModelContextTokens, forKey: "recommended_small_model_context_tokens", to: &metadata)
        Self.add(counters.recommendedPrefillStepSize, forKey: "recommended_prefill_step_size", to: &metadata)
        Self.add(counters.metalRecommendedWorkingSetBytes, forKey: "metal_recommended_working_set_bytes", to: &metadata)
        Self.add(counters.mlxActiveMemoryBytes, forKey: "mlx_active_memory_bytes", to: &metadata)
        Self.add(counters.mlxCacheMemoryBytes, forKey: "mlx_cache_memory_bytes", to: &metadata)
        Self.add(counters.mlxPeakMemoryBytes, forKey: "mlx_peak_memory_bytes", to: &metadata)
        Self.add(counters.mlxMemoryLimitBytes, forKey: "mlx_memory_limit_bytes", to: &metadata)
        Self.add(counters.mlxCacheLimitBytes, forKey: "mlx_cache_limit_bytes", to: &metadata)
        return metadata
    }

    private static func add(_ value: Int64?, forKey key: String, to metadata: inout [String: String]) {
        guard let value else { return }
        metadata[key] = String(value)
    }

    private static func add(_ value: Int?, forKey key: String, to metadata: inout [String: String]) {
        guard let value else { return }
        metadata[key] = String(value)
    }

    var isLinked: Bool {
        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXEmbedders)
        true
        #else
        false
        #endif
    }

    var id: ProviderID { localProviderID }

    var localProviderID: ProviderID { "mlx-local" }

    var currentDeviceProfile: DeviceProfile {
        deviceMonitor.currentProfile()
    }

    var modelDiscoveryResourcePolicy: ModelDiscoveryResourcePolicy {
        .deviceDefault(for: currentDeviceProfile)
    }

    var capabilities: ProviderCapabilities {
        let profile = deviceMonitor.currentProfile()
        let safety = deviceMonitor.localGenerationSafety()
        return ProviderCapabilities(
            local: true,
            streaming: true,
            textGeneration: safety.allowed,
            vision: safety.allowed && profile.allowsVisionModels,
            imageInputs: safety.allowed && profile.allowsVisionModels,
            embeddings: true,
            toolCalling: true,
            jsonMode: true,
            maxContextTokens: safety.recommendedMaxContextTokens
        )
    }

    var runtimeDiagnostics: RuntimeQuantizationDiagnostics {
        let memoryCounters = deviceMonitor.memoryCounters()
        let backend = turboQuantBackendSnapshot()
        let linked = isLinked
        #if canImport(MLX)
        let ssdMetrics = linked ? MLXFast.ssdMetricsSnapshot() : nil
        let ssdThroughputMBperS = ssdMetrics?.throughputMBperS
        let ssdTotalBytesRead = ssdMetrics?.totalBytesRead
        let ssdTotalChunks = ssdMetrics?.totalChunks
        let ssdAvgChunkLatencyMS = ssdMetrics?.avgChunkLatencyMS
        #else
        let ssdThroughputMBperS: Double? = nil
        let ssdTotalBytesRead: UInt64? = nil
        let ssdTotalChunks: UInt64? = nil
        let ssdAvgChunkLatencyMS: Double? = nil
        #endif
        return RuntimeQuantizationDiagnostics(
            requestedAlgorithm: .turboQuant,
            activeAlgorithm: linked ? .turboQuant : .none,
            preset: .defaultGeneration,
            requestedBackend: backend.requested,
            activeBackend: linked ? backend.active : nil,
            metalCodecAvailable: linked && backend.metalCodecAvailable,
            metalAttentionAvailable: linked && backend.metalAttentionAvailable,
            activeAttentionPath: linked ? backend.activeAttentionPath : .baseline,
            metalKernelProfile: linked ? backend.kernelProfile : .mlxPackedFallback,
            metalSelfTestStatus: linked ? backend.selfTestStatus : nil,
            metalSelfTestFailureReason: backend.selfTestFailureReason,
            rawFallbackAllocated: backend.rawFallbackAllocated,
            devicePerformanceClass: memoryCounters.devicePerformanceClass,
            turboQuantOptimizationPolicy: memoryCounters.devicePerformanceClass == nil
                ? nil
                : deviceMonitor.currentProfile().turboQuantOptimizationPolicy,
            turboQuantValueBits: PinesCore.TurboQuantPreset.defaultGeneration.defaultValueBits,
            thermalDownshiftActive: memoryCounters.thermalDownshiftActive,
            runtimePressureReason: memoryCounters.runtimePressureReason,
            lastUnsupportedAttentionShape: backend.lastUnsupportedAttentionShape,
            activeFallbackReason: linked
                ? backend.fallbackReason
                : "MLX runtime packages are not linked in this build.",
            memoryCounters: memoryCounters,
            ssdThroughputMBperS: ssdThroughputMBperS,
            ssdTotalBytesRead: ssdTotalBytesRead,
            ssdTotalChunks: ssdTotalChunks,
            ssdAvgChunkLatencyMS: ssdAvgChunkLatencyMS
        )
    }

    func defaultRuntimeProfile(for install: ModelInstall) -> RuntimeProfile {
        let deviceProfile = deviceMonitor.currentProfile()
        let hasVision = install.modalities.contains(.vision)
        let isCompact = deviceProfile.memoryTier == .compact
        let isSmallTextModel = (install.parameterCount ?? Int64.max) <= 2_000_000_000
            || install.repository.localizedCaseInsensitiveContains("1B")
        let recommendedMaxKVSize = hasVision
            ? min(deviceProfile.recommendedContextTokens, 4096)
            : (isSmallTextModel ? deviceProfile.recommendedSmallModelContextTokens : deviceProfile.recommendedContextTokens)
        let backend = turboQuantBackendSnapshot()
        let linked = isLinked
        let usesTurboQuant = Self.usesTurboQuantByDefault(for: install)
        let maxKVSize = usesTurboQuant
            ? recommendedMaxKVSize
            : min(recommendedMaxKVSize, 8192)
        let fallbackReason = usesTurboQuant
            ? backend.fallbackReason
            : "Using plain MLX KV cache because TurboQuant is not applicable to this install."
        let turboQuantDefaults = usesTurboQuant
            ? Self.turboQuantRuntimeDefaults(
                for: install,
                contextLength: maxKVSize,
                deviceOptimizationPolicy: deviceProfile.turboQuantOptimizationPolicy
            )
            : nil
        let profile = RuntimeProfile(
            name: hasVision ? "Vision balanced" : "Local balanced",
            quantization: QuantizationProfile(
                weightBits: install.repository.localizedCaseInsensitiveContains("4bit") ? 4 : nil,
                kvBits: nil,
                kvGroupSize: turboQuantDefaults?.groupSize ?? 64,
                quantizedKVStart: 0,
                maxKVSize: maxKVSize,
                algorithm: usesTurboQuant ? .turboQuant : .none,
                kvCacheStrategy: usesTurboQuant ? .turboQuant : .none,
                preset: usesTurboQuant ? turboQuantDefaults?.preset : nil,
                requestedBackend: usesTurboQuant ? (turboQuantDefaults?.requestedBackend ?? backend.requested) : nil,
                activeBackend: usesTurboQuant && linked ? backend.active : nil,
                metalCodecAvailable: usesTurboQuant && linked && backend.metalCodecAvailable,
                metalAttentionAvailable: usesTurboQuant && linked && backend.metalAttentionAvailable,
                activeAttentionPath: usesTurboQuant && linked ? backend.activeAttentionPath : .baseline,
                metalKernelProfile: usesTurboQuant && linked ? backend.kernelProfile : nil,
                metalSelfTestStatus: usesTurboQuant && linked ? backend.selfTestStatus : nil,
                metalSelfTestFailureReason: usesTurboQuant ? backend.selfTestFailureReason : nil,
                rawFallbackAllocated: usesTurboQuant ? backend.rawFallbackAllocated : false,
                devicePerformanceClass: deviceProfile.performanceClass,
                turboQuantOptimizationPolicy: turboQuantDefaults?.optimizationPolicy
                    ?? deviceProfile.turboQuantOptimizationPolicy,
                turboQuantValueBits: turboQuantDefaults?.valueBits,
                thermalDownshiftActive: deviceProfile.thermalDownshiftActive,
                runtimePressureReason: deviceProfile.runtimePressureReason,
                turboQuantProfileID: turboQuantDefaults?.profileID,
                turboQuantProfileSource: turboQuantDefaults?.profileSource,
                lastUnsupportedAttentionShape: usesTurboQuant ? backend.lastUnsupportedAttentionShape : nil,
                activeFallbackReason: linked ? fallbackReason : "MLX runtime packages are not linked in this build.",
                memoryCounters: deviceMonitor.memoryCounters()
            ),
            streamExperts: false,
            expertStreamingMode: .disabled,
            gpuLayerCount: nil,
            mtpEnabled: false,
            audioEnabled: install.modalities.contains(.audio),
            dflashEnabled: false,
            prefillStepSize: hasVision || isCompact
                ? min(deviceProfile.recommendedPrefillStepSize, 256)
                : deviceProfile.recommendedPrefillStepSize,
            promptCacheEnabled: !hasVision,
            promptCacheIdentifier: install.repository,
            speculativeDraftModelID: nil,
            speculativeDecodingEnabled: false,
            unloadOnMemoryPressure: true,
            repetitionContextSize: isCompact ? 16 : 20,
            maxConcurrentSessions: 1
        )
        return deviceMonitor.localGenerationSafety().constrainedRuntimeProfile(profile)
    }

    private static func usesTurboQuantByDefault(for install: ModelInstall) -> Bool {
        install.modalities.contains(.text)
    }

    private struct TurboQuantRuntimeDefaults {
        var preset: PinesCore.TurboQuantPreset
        var requestedBackend: PinesCore.TurboQuantRuntimeBackend
        var groupSize: Int
        var valueBits: Int?
        var optimizationPolicy: PinesCore.TurboQuantOptimizationPolicy
        var profileID: String?
        var profileSource: String
    }

    private static func turboQuantRuntimeDefaults(
        for install: ModelInstall,
        contextLength: Int?,
        deviceOptimizationPolicy: PinesCore.TurboQuantOptimizationPolicy
    ) -> TurboQuantRuntimeDefaults {
        #if canImport(MLXLMCommon) && canImport(MLX)
        let registry = MLXLMCommon.TurboQuantProfileRegistry.bundled
        let identifiers = [install.repository, install.modelID.rawValue, install.displayName]
        for identifier in identifiers {
	            guard let profile = registry.profile(
	                for: identifier,
	                modelType: install.modelType,
	                textConfigModelType: install.textConfigModelType,
	                modality: Self.turboQuantModality(for: install),
	                parameterCountB: Self.parameterCountBillionScale(for: install),
	                routedExperts: install.routedExperts,
	                expertsPerToken: install.expertsPerToken,
	                keyHeadDimension: install.keyHeadDimension,
	                valueHeadDimension: install.valueHeadDimension,
                contextLength: contextLength
            ) else { continue }
            let profilePolicy = Self.coreTurboQuantOptimizationPolicy(from: profile.optimizationPolicy)
            return TurboQuantRuntimeDefaults(
                preset: Self.coreTurboQuantPreset(from: profile.recommendedScheme.preset),
                requestedBackend: Self.coreTurboQuantBackend(from: profile.backend),
                groupSize: profile.groupSize,
                valueBits: profile.valueBits,
                optimizationPolicy: profilePolicy == .auto ? deviceOptimizationPolicy : profilePolicy,
                profileID: profile.id,
                profileSource: "bundled"
            )
        }
        #endif

        return TurboQuantRuntimeDefaults(
            preset: .conservativeFallback,
            requestedBackend: .metalPolarQJL,
            groupSize: 64,
            valueBits: PinesCore.TurboQuantPreset.conservativeFallback.defaultValueBits,
            optimizationPolicy: deviceOptimizationPolicy,
            profileID: nil,
            profileSource: "generic_conservative_fallback"
        )
    }

    private func turboQuantBackendSnapshot() -> (
        requested: PinesCore.TurboQuantRuntimeBackend,
        active: PinesCore.TurboQuantRuntimeBackend?,
        metalCodecAvailable: Bool,
        metalAttentionAvailable: Bool,
        activeAttentionPath: PinesCore.TurboQuantAttentionPath,
        kernelProfile: PinesCore.TurboQuantKernelProfile?,
        selfTestStatus: PinesCore.TurboQuantSelfTestStatus?,
        selfTestFailureReason: String?,
        rawFallbackAllocated: Bool?,
        lastUnsupportedAttentionShape: String?,
        fallbackReason: String?
    ) {
        #if targetEnvironment(simulator)
        return (
            .metalPolarQJL,
            nil,
            false,
            false,
            .baseline,
            .mlxPackedFallback,
            nil,
            nil,
            nil,
            nil,
            "MLX TurboQuant Metal probing is disabled on iOS Simulator."
        )
        #else
        #if canImport(MLX)
        let requested = MLX.TurboQuantBackend.metalPolarQJL
        let availability = MLX.TurboQuantKernelAvailability.current
        let activeBackend = availability.runtimeBackend(for: requested)
        let attentionPath: PinesCore.TurboQuantAttentionPath =
            activeBackend == .metalPolarQJL && availability.supportsMetalPolarQJLAttention
            ? .tiledOnlineFused
            : .mlxPackedFallback
        return (
            .metalPolarQJL,
            Self.coreTurboQuantBackend(from: activeBackend),
            availability.supportsMetalPolarQJLCodec,
            availability.supportsMetalPolarQJLAttention,
            attentionPath,
            Self.coreTurboQuantKernelProfile(from: availability.selectedKernelProfile),
            Self.coreTurboQuantSelfTestStatus(from: availability.selfTestStatus),
            availability.selfTestFailureReason,
            false,
            nil,
            availability.fallbackReason(for: requested)
        )
        #else
        return (
            .metalPolarQJL,
            nil,
            false,
            false,
            .baseline,
            .mlxPackedFallback,
            nil,
            nil,
            nil,
            nil,
            "MLX runtime packages are not linked in this build."
        )
        #endif
        #endif
    }

    #if canImport(MLX)
    private static func coreTurboQuantPreset(
        from preset: MLX.TurboQuantPreset
    ) -> PinesCore.TurboQuantPreset {
        PinesCore.TurboQuantPreset(rawValue: preset.rawValue) ?? .conservativeFallback
    }

    private static func coreTurboQuantBackend(
        from backend: MLX.TurboQuantBackend
    ) -> PinesCore.TurboQuantRuntimeBackend {
        switch backend {
        case .mlxPacked:
            .mlxPacked
        case .polarQJLReference:
            .polarQJLReference
        case .metalPolarQJL:
            .metalPolarQJL
        }
    }

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

    #if canImport(MLXLMCommon)
    private static func turboQuantModality(
        for install: ModelInstall
    ) -> MLXLMCommon.TurboQuantModelModality {
        if install.modalities.contains(.vision) {
            return .visionText
        }
        return .text
    }

    private static func coreTurboQuantOptimizationPolicy(
        from policy: MLXLMCommon.TurboQuantOptimizationPolicy
    ) -> PinesCore.TurboQuantOptimizationPolicy {
        PinesCore.TurboQuantOptimizationPolicy(rawValue: policy.rawValue) ?? .auto
    }
    #endif

    private static func parameterCountBillionScale(for install: ModelInstall) -> Double? {
        install.parameterCount.map { Double($0) / 1_000_000_000 }
    }

    func load(_ install: ModelInstall, profile: RuntimeProfile? = nil) async throws {
        await supervisor.beginLoading(modelID: install.modelID)
        #if DEBUG
        await FreezeBreadcrumbJournal.shared.record(
            stage: "mlx.load.start",
            metadata: runtimeMemoryMetadata(merging: [
                "model_id": install.modelID.rawValue,
                "repository": install.repository,
            ])
        )
        #endif
        do {
            let safety = try deviceMonitor.requireLocalGenerationSafety()
            try await state.load(
                install,
                profile: safety.constrainedRuntimeProfile(profile ?? defaultRuntimeProfile(for: install))
            )
            await supervisor.markReady(modelID: install.modelID)
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.load.complete",
                metadata: runtimeMemoryMetadata(merging: ["model_id": install.modelID.rawValue])
            )
            #endif
        } catch {
            await supervisor.block(reason: error.localizedDescription, modelID: install.modelID)
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.load.failed",
                detail: error.localizedDescription,
                metadata: runtimeMemoryMetadata(merging: ["model_id": install.modelID.rawValue])
            )
            #endif
            throw error
        }
    }

    func unload() async {
        await supervisor.beginUnloading(reason: "explicit_unload")
        #if DEBUG
        await FreezeBreadcrumbJournal.shared.record(
            stage: "mlx.unload.start",
            metadata: runtimeMemoryMetadata()
        )
        #endif
        await state.unload()
        await supervisor.markUnloaded()
        #if DEBUG
        await FreezeBreadcrumbJournal.shared.record(
            stage: "mlx.unload.complete",
            metadata: runtimeMemoryMetadata()
        )
        #endif
    }

    func setForegroundActive(_ active: Bool) async {
        if !active {
            await supervisor.beginCancelling(reason: "background")
        }
        await state.setForegroundActive(active)
        if !active {
            await supervisor.markUnloaded(reason: "background")
        }
    }

    func handleMemoryPressure() async {
        let handling = await state.handleMemoryPressure {
            await supervisor.beginCancelling(reason: "memory_pressure")
        }
        switch handling {
        case .unloaded:
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.memory_pressure.cancel_unload",
                metadata: runtimeMemoryMetadata()
            )
            #endif
            await supervisor.markUnloaded(reason: "memory_pressure")
        case .ignoredDuringLoad:
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.memory_pressure.ignored_during_load",
                metadata: runtimeMemoryMetadata()
            )
            #endif
        }
    }

    func handleThermalPressure() async {
        let handling = await state.handlePressureUnload {
            await supervisor.beginCancelling(reason: "thermal_pressure")
        }
        switch handling {
        case .unloaded:
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.thermal_pressure.cancel_unload",
                metadata: runtimeMemoryMetadata()
            )
            #endif
            await supervisor.markUnloaded(reason: "thermal_pressure")
        case .ignoredDuringLoad:
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.thermal_pressure.ignored_during_load",
                metadata: runtimeMemoryMetadata()
            )
            #endif
        }
    }

}

private enum MLXMemoryPressureHandling: Sendable {
    case unloaded
    case ignoredDuringLoad
}

extension MLXRuntimeBridge: InferenceProvider {
    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        do {
            _ = try deviceMonitor.requireLocalGenerationSafety()
            await supervisor.beginGenerating(modelID: request.modelID)
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.stream.start",
                metadata: runtimeMemoryMetadata(merging: ["model_id": request.modelID.rawValue])
            )
            #endif
            let stream = try await state.streamEvents(request)
            return supervised(stream, modelID: request.modelID)
        } catch {
            await supervisor.block(reason: error.localizedDescription, modelID: request.modelID)
            throw error
        }
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        try await state.embed(request)
    }

    private func supervised(
        _ source: AsyncThrowingStream<InferenceStreamEvent, Error>,
        modelID: ModelID
    ) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var terminalFailureReason: String?
                var emittedTokenCount = 0
                var didRecordFirstToken = false
                do {
                    for try await event in source {
                        var eventToYield = event
                        switch event {
                        case let .token(delta):
                            emittedTokenCount += max(1, delta.tokenCount)
                            #if DEBUG
                            if !didRecordFirstToken {
                                didRecordFirstToken = true
                                await FreezeBreadcrumbJournal.shared.record(
                                    stage: "mlx.stream.first_token",
                                    metadata: [
                                        "model_id": modelID.rawValue,
                                        "token_count": String(emittedTokenCount),
                                    ]
                                )
                            } else if emittedTokenCount.isMultiple(of: 32) {
                                await FreezeBreadcrumbJournal.shared.record(
                                    stage: "mlx.stream.token_milestone",
                                    metadata: [
                                        "model_id": modelID.rawValue,
                                        "token_count": String(emittedTokenCount),
                                    ]
                                )
                            }
                            #endif
                        case let .finish(finish) where finish.reason == .error:
                            terminalFailureReason = finish.message ?? "local_generation_error"
                            #if DEBUG
                            await FreezeBreadcrumbJournal.shared.record(
                                stage: "mlx.stream.finish_error",
                                detail: terminalFailureReason,
                                metadata: runtimeMemoryMetadata(merging: [
                                    "model_id": modelID.rawValue,
                                    "token_count": String(emittedTokenCount),
                                ])
                            )
                            #endif
                        case let .finish(finish):
                            var finish = finish
                            if finish.reason == .cancelled {
                                let snapshot = await supervisor.currentSnapshot()
                                if let reason = snapshot.reason {
                                    finish.providerMetadata[LocalProviderMetadataKeys.generationCancellationReason] = reason
                                    if reason == "memory_pressure", finish.message == nil {
                                        finish.message = "Local generation was cancelled because iOS reported memory pressure."
                                    } else if reason == "thermal_pressure", finish.message == nil {
                                        finish.message = "Local generation was cancelled because the device became too hot for on-device MLX inference."
                                    }
                                }
                                eventToYield = .finish(finish)
                            }
                            #if DEBUG
                            await FreezeBreadcrumbJournal.shared.record(
                                stage: "mlx.stream.finish",
                                detail: finish.message,
                                metadata: runtimeMemoryMetadata(merging: [
                                    "model_id": modelID.rawValue,
                                    "reason": finish.reason.rawValue,
                                    "token_count": String(emittedTokenCount),
                                ])
                            )
                            #endif
                        case let .failure(failure):
                            terminalFailureReason = failure.message
                            #if DEBUG
                            await FreezeBreadcrumbJournal.shared.record(
                                stage: "mlx.stream.failure",
                                detail: failure.message,
                                metadata: runtimeMemoryMetadata(merging: [
                                    "model_id": modelID.rawValue,
                                    "code": failure.code,
                                    "recoverable": String(failure.recoverable),
                                    "token_count": String(emittedTokenCount),
                                ])
                            )
                            #endif
                        case .toolCall, .metrics:
                            break
                        }
                        continuation.yield(eventToYield)
                    }
                    if let terminalFailureReason {
                        await supervisor.block(reason: terminalFailureReason, modelID: modelID)
                    } else {
                        await supervisor.finishGeneration(modelID: modelID)
                    }
                    #if DEBUG
                    await FreezeBreadcrumbJournal.shared.record(
                        stage: "mlx.stream.closed",
                        detail: terminalFailureReason,
                        metadata: runtimeMemoryMetadata(merging: [
                            "model_id": modelID.rawValue,
                            "token_count": String(emittedTokenCount),
                        ])
                    )
                    #endif
                    continuation.finish()
                } catch is CancellationError {
                    let snapshot = await supervisor.currentSnapshot()
                    if snapshot.reason == nil {
                        await supervisor.beginCancelling(reason: "stream_cancelled")
                    }
                    #if DEBUG
                    await FreezeBreadcrumbJournal.shared.record(
                        stage: "mlx.stream.cancelled",
                        metadata: runtimeMemoryMetadata(merging: [
                            "model_id": modelID.rawValue,
                            "token_count": String(emittedTokenCount),
                        ])
                    )
                    #endif
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    await supervisor.block(reason: error.localizedDescription, modelID: modelID)
                    #if DEBUG
                    await FreezeBreadcrumbJournal.shared.record(
                        stage: "mlx.stream.thrown",
                        detail: error.localizedDescription,
                        metadata: runtimeMemoryMetadata(merging: [
                            "model_id": modelID.rawValue,
                            "token_count": String(emittedTokenCount),
                        ])
                    )
                    #endif
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private actor MLXRuntimeState {
    private static let pressureUnloadDrainTimeoutSeconds: TimeInterval = 5
    private static let pressureUnloadDrainPollNanoseconds: UInt64 = 100_000_000

    private let deviceMonitor = DeviceRuntimeMonitor()
    private var activeInstall: ModelInstall?
    private var activeProfile = RuntimeProfile()
    private var activePartitionSummary: String?
    private var activeStopStrings = Set<String>()
    private var didRegisterModelAliases = false
    private var foregroundActive = true
    private var activeGenerationCancellation: MLXGenerationCancellationBox?
    private var isLoading = false

    private func runtimeMemoryMetadata(
        merging base: [String: String] = [:]
    ) -> [String: String] {
        var metadata = base
        let counters = deviceMonitor.memoryCounters()
        Self.add(counters.physicalMemoryBytes, forKey: "physical_memory_bytes", to: &metadata)
        Self.add(counters.availableMemoryBytes, forKey: "available_memory_bytes", to: &metadata)
        if let thermalState = counters.thermalState {
            metadata["thermal_state"] = thermalState
        }
        if let lowPowerModeEnabled = counters.lowPowerModeEnabled {
            metadata["low_power_mode_enabled"] = String(lowPowerModeEnabled)
        }
        if let hardwareModelIdentifier = counters.hardwareModelIdentifier {
            metadata["hardware_model_identifier"] = hardwareModelIdentifier
        }
        if let performanceClass = counters.devicePerformanceClass {
            metadata["device_performance_class"] = performanceClass.rawValue
        }
        if let runtimePressureReason = counters.runtimePressureReason {
            metadata["runtime_pressure_reason"] = runtimePressureReason.rawValue
        }
        if let thermalDownshiftActive = counters.thermalDownshiftActive {
            metadata["thermal_downshift_active"] = String(thermalDownshiftActive)
        }
        Self.add(counters.recommendedContextTokens, forKey: "recommended_context_tokens", to: &metadata)
        Self.add(counters.recommendedSmallModelContextTokens, forKey: "recommended_small_model_context_tokens", to: &metadata)
        Self.add(counters.recommendedPrefillStepSize, forKey: "recommended_prefill_step_size", to: &metadata)
        Self.add(counters.metalRecommendedWorkingSetBytes, forKey: "metal_recommended_working_set_bytes", to: &metadata)
        Self.add(counters.mlxActiveMemoryBytes, forKey: "mlx_active_memory_bytes", to: &metadata)
        Self.add(counters.mlxCacheMemoryBytes, forKey: "mlx_cache_memory_bytes", to: &metadata)
        Self.add(counters.mlxPeakMemoryBytes, forKey: "mlx_peak_memory_bytes", to: &metadata)
        Self.add(counters.mlxMemoryLimitBytes, forKey: "mlx_memory_limit_bytes", to: &metadata)
        Self.add(counters.mlxCacheLimitBytes, forKey: "mlx_cache_limit_bytes", to: &metadata)
        return metadata
    }

    private static func add(_ value: Int64?, forKey key: String, to metadata: inout [String: String]) {
        guard let value else { return }
        metadata[key] = String(value)
    }

    private static func add(_ value: Int?, forKey key: String, to metadata: inout [String: String]) {
        guard let value else { return }
        metadata[key] = String(value)
    }

    #if canImport(MLXLMCommon)
    private var textContainer: MLXLMCommon.ModelContainer?
    private var visionContainer: MLXLMCommon.ModelContainer?
    #endif

    #if canImport(MLXEmbedders) && canImport(MLXLMCommon) && canImport(MLX) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
    private let embeddingRuntime = MLXEmbeddingRuntime()
    #endif

    func load(_ install: ModelInstall, profile: RuntimeProfile) async throws {
        try ensureForegroundActive()
        try Self.validateRuntimeCompatibility(install)
        #if canImport(MLX)
        Self.configureMLXMemoryPolicy(profile: profile)
        #endif
        #if canImport(MLXLMCommon)
        let matchingInstall = activeInstall?.modelID == install.modelID
            && activeInstall?.repository == install.repository
        if matchingInstall {
            let hasCompatibleContainer: Bool
            if install.modalities.contains(.vision) || install.modalities.contains(.audio) {
                hasCompatibleContainer = visionContainer != nil
            } else if install.modalities.contains(.text) {
                hasCompatibleContainer = textContainer != nil
            } else {
                hasCompatibleContainer = false
            }
            if hasCompatibleContainer {
                let profileMatches = activeProfile == profile
                #if DEBUG
                await FreezeBreadcrumbJournal.shared.record(
                    stage: "mlx.load.reuse",
                    metadata: [
                        "model_id": install.modelID.rawValue,
                        "profile_matches": String(profileMatches),
                    ]
                )
                #endif
                activeProfile = profile
                return
            }
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        activeInstall = install
        activeProfile = profile

        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXLMCommon) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
        await registerModelAliasesIfNeeded()
        try Self.configureGlobalRuntimePolicy(profile: profile, install: install)
        if install.modalities.contains(.vision) || install.modalities.contains(.audio) {
            var resolvedConfiguration = try Self.lmConfiguration(for: install, kind: .visionLanguage)
            resolvedConfiguration.configuration.lazyLoad = profile.streamExperts
            activeStopStrings = resolvedConfiguration.hints.stopStrings
            visionContainer = try await VLMModelFactory.shared.loadContainer(
                from: PinesHubDownloader(),
                using: PinesTokenizerLoader(),
                configuration: resolvedConfiguration.configuration
            )
            activePartitionSummary = await Self.configureLoadedContainer(
                visionContainer, profile: profile)
            textContainer = nil
        } else if install.modalities.contains(.text) {
            var resolvedConfiguration = try Self.lmConfiguration(for: install, kind: .language)
            resolvedConfiguration.configuration.lazyLoad = profile.streamExperts
            activeStopStrings = resolvedConfiguration.hints.stopStrings
            textContainer = try await LLMModelFactory.shared.loadContainer(
                from: PinesHubDownloader(),
                using: PinesTokenizerLoader(),
                configuration: resolvedConfiguration.configuration
            )
            activePartitionSummary = await Self.configureLoadedContainer(
                textContainer, profile: profile)
            visionContainer = nil
        }
        #else
        throw InferenceError.providerUnavailable("mlx-local")
        #endif
    }

    #if canImport(MLX)
    private static func configureMLXMemoryPolicy(profile: RuntimeProfile) {
        #if targetEnvironment(simulator)
        return
        #else
        Memory.cacheLimit = mlxCacheLimit(for: profile)
        #endif
    }

    private static func mlxCacheLimit(for profile: RuntimeProfile) -> Int {
        #if os(iOS)
        let megabyte = 1_024 * 1_024
        let contextTokens = profile.quantization.maxKVSize ?? 4_096
        if profile.quantization.thermalDownshiftActive {
            return 64 * megabyte
        }
        if contextTokens <= 4_096 {
            return 64 * megabyte
        }
        if contextTokens <= 8_192 {
            return 96 * megabyte
        }
        if contextTokens <= 16_384 {
            return 128 * megabyte
        }
        return 192 * megabyte
        #else
        return Memory.cacheLimit
        #endif
    }

    private static func clearCachedMLXBuffers() {
        #if targetEnvironment(simulator)
        return
        #else
        Stream.gpu.synchronize()
        Memory.clearCache()
        #endif
    }

    private static func resetMLXPeakMemory() {
        #if targetEnvironment(simulator)
        return
        #else
        Memory.peakMemory = 0
        #endif
    }
    #endif

    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private func registerModelAliasesIfNeeded() async {
        guard !didRegisterModelAliases else { return }
        didRegisterModelAliases = true

        await LLMTypeRegistry.shared.registerModelType(
            "gemma4_assistant",
            creator: Self.llmCreator(Gemma4Configuration.self, Gemma4Model.init)
        )
        await LLMTypeRegistry.shared.registerModelType(
            "llama4",
            creator: Self.llmCreator(PinesLlama4Configuration.self, PinesLlama4Model.init)
        )
        await LLMTypeRegistry.shared.registerModelType(
            "llama4_text",
            creator: Self.llmCreator(PinesLlama4TextConfiguration.self, PinesLlama4TextModel.init)
        )
        await LLMTypeRegistry.shared.registerModelType(
            "deepseek_v32",
            creator: { _ in
                throw InferenceError.unsupportedCapability("deepseek_v32 is recognized, but the linked MLX runtime does not expose a public DeepSeek V3.2 initializer.")
            }
        )
        await LLMTypeRegistry.shared.registerModelType(
            "deepseek_v4",
            creator: Self.llmCreator(PinesDeepseekV4Configuration.self, PinesDeepseekV4Model.init)
        )
        await LLMTypeRegistry.shared.registerModelType(
            "minimax_m2",
            creator: Self.llmCreator(MiniMaxConfiguration.self, MiniMaxModel.init)
        )
    }

    private nonisolated static func llmCreator<C: Decodable, M: LanguageModel>(
        _ configurationType: C.Type,
        _ modelInit: @escaping (C) -> M
    ) -> (Data) throws -> LanguageModel {
        { data in
            let configuration = try JSONDecoder.json5().decode(configurationType, from: data)
            return modelInit(configuration)
        }
    }

    private static func validateRuntimeCompatibility(_ install: ModelInstall) throws {
        if install.verification == .experimental,
           ModelPreflightClassifier.requiresRuntimeCompatibilityGate(
               repository: install.repository,
               modelType: install.modelType
           ) {
            try validateTurboQuantRuntimeGate()
        }
    }

    private static func validateTurboQuantRuntimeGate() throws {
        #if targetEnvironment(simulator)
        throw InferenceError.unsupportedCapability("MLX TurboQuant Metal probing is disabled on iOS Simulator.")
        #else
        #if canImport(MLX)
        let availability = MLX.TurboQuantKernelAvailability.current
        guard availability.selfTestStatus == .passed,
              availability.runtimeBackend(for: .metalPolarQJL) == .metalPolarQJL else {
            throw InferenceError.unsupportedCapability(
                availability.fallbackReason(for: .metalPolarQJL)
                    ?? ModelPreflightClassifier.runtimeCompatibilityGateReason
            )
        }
        #else
        throw InferenceError.unsupportedCapability("MLX runtime packages are not linked in this build.")
        #endif
        #endif
    }
    #endif

    func setForegroundActive(_ active: Bool) async {
        foregroundActive = active
        if !active {
            activeGenerationCancellation?.cancel()
            await unload()
        }
    }

    private func ensureForegroundActive() throws {
        guard foregroundActive else {
            throw InferenceError.invalidRequest("Local MLX inference is available only while Pines is active in the foreground.")
        }
    }

    private func clearActiveGenerationCancellation(_ box: MLXGenerationCancellationBox) {
        if activeGenerationCancellation === box {
            activeGenerationCancellation = nil
        }
    }

    func unload() async {
        activeInstall = nil
        #if canImport(MLXLMCommon)
        textContainer = nil
        visionContainer = nil
        activePartitionSummary = nil
        activeStopStrings = []
        ExpertStreamingConfig.shared.deactivate()
        MTPConfig.retainMTPWeights = false
        #endif
        #if canImport(MLXEmbedders) && canImport(MLXLMCommon) && canImport(MLX) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
        await embeddingRuntime.unload()
        #endif
        #if canImport(MLX)
        Self.clearCachedMLXBuffers()
        Self.resetMLXPeakMemory()
        #endif
    }

    func handleMemoryPressure(
        willCancel: @Sendable () async -> Void
    ) async -> MLXMemoryPressureHandling {
        await handlePressureUnload(willCancel: willCancel)
    }

    func handlePressureUnload(
        willCancel: @Sendable () async -> Void
    ) async -> MLXMemoryPressureHandling {
        if isLoading {
            return .ignoredDuringLoad
        }
        await willCancel()
        let generationCancellation = activeGenerationCancellation
        generationCancellation?.cancel()
        if let generationCancellation {
            await waitForActiveGenerationCancellationToDrain(generationCancellation)
        }
        await unload()
        return .unloaded
    }

    private func waitForActiveGenerationCancellationToDrain(_ box: MLXGenerationCancellationBox) async {
        let deadline = Date().addingTimeInterval(Self.pressureUnloadDrainTimeoutSeconds)
        while activeGenerationCancellation === box, Date() < deadline {
            try? await Task.sleep(nanoseconds: Self.pressureUnloadDrainPollNanoseconds)
        }
    }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXLMCommon)
        try ensureForegroundActive()
        let requiresVLM = request.messages.contains { message in
            message.attachments.contains { attachment in
                attachment.kind == .image || attachment.kind == .video || attachment.kind == .audio
            }
        }
        let loadedInstall = activeInstall
        let loadedInstallMatchesRequest = loadedInstall?.modelID == request.modelID
        let loadedInstallUsesVLMRuntime = loadedInstallMatchesRequest
            && (loadedInstall?.modalities.contains(.vision) == true
                || loadedInstall?.modalities.contains(.audio) == true)
        let useVLMRuntime = requiresVLM || loadedInstallUsesVLMRuntime
        let container: MLXLMCommon.ModelContainer
        if useVLMRuntime {
            if visionContainer == nil || activeInstall?.modelID != request.modelID {
                try await load(
                    loadedInstallMatchesRequest
                        ? loadedInstall!
                        : Self.install(for: request.modelID, modalities: [.text, .vision, .audio]),
                    profile: activeProfile
                )
            }
            guard let visionContainer else { throw InferenceError.modelNotLoaded(request.modelID) }
            container = visionContainer
        } else {
            if textContainer == nil || activeInstall?.modelID != request.modelID {
                try await load(
                    loadedInstallMatchesRequest
                        ? loadedInstall!
                        : Self.install(for: request.modelID, modalities: [.text]),
                    profile: activeProfile
                )
            }
            guard let textContainer else { throw InferenceError.modelNotLoaded(request.modelID) }
            container = textContainer
        }

        let generationSafety = try deviceMonitor.requireLocalGenerationSafety()
        let profile = generationSafety.constrainedRuntimeProfile(activeProfile)
        guard let latestUserIndex = request.messages.lastIndex(where: { $0.role == .user }) else {
            throw InferenceError.invalidRequest("A local chat request requires a user message.")
        }
        let latestUser = request.messages[latestUserIndex]
        let latestPrompt = latestUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latestPrompt.isEmpty else {
            throw InferenceError.invalidRequest("A local chat request requires a non-empty user message.")
        }
        let instructions = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        let imageURLs = latestUser.attachments.compactMap { attachment -> URL? in
            guard attachment.kind == .image, let localURL = attachment.localURL else { return nil }
            return localURL
        }
        let audioURLs = latestUser.attachments.compactMap { attachment -> URL? in
            guard attachment.kind == .audio, let localURL = attachment.localURL else { return nil }
            return localURL
        }
        if !audioURLs.isEmpty && !profile.audioEnabled {
            throw InferenceError.unsupportedCapability("Audio input is disabled for this local runtime profile.")
        }
        let partitionSummary = activePartitionSummary
        let usesAgentTranscript = request.executionContext == .agent
        let historyMessages = usesAgentTranscript ? request.messages : Array(request.messages[..<latestUserIndex])
        let install = activeInstall
        let toolSpecs = request.allowsTools ? Self.mlxToolSpecs(from: request.availableTools) : nil
        let stopStrings = activeStopStrings
        let generationCancellation = MLXGenerationCancellationBox()
        activeGenerationCancellation = generationCancellation

        return AsyncThrowingStream { continuation in
            let task = Task {
                defer {
                    generationCancellation.cancel()
                    #if canImport(MLX)
                    Self.clearCachedMLXBuffers()
                    #endif
                    Task {
                        self.clearActiveGenerationCancellation(generationCancellation)
                    }
                }
                do {
                    let result = try await withTaskCancellationHandler {
                        try await container.perform { context in
                        let images = imageURLs.map(UserInput.Image.url)
                        let audio = audioURLs.map(UserInput.Audio.url)
                        var tokenCount = 0
                        var finish: InferenceFinish?
                        _ = try deviceMonitor.requireLocalGenerationSafety()
                        let initialHistoryCharacterBudget = Self.localHistoryCharacterBudget(
                            maxContextTokens: profile.quantization.maxKVSize
                        )
                        let requestedCompletionTokens = request.sampling.maxTokens
                        var reservedCompletionTokens = requestedCompletionTokens ?? 0
                        var clampedCompletionTokens = false
                        var historyCharacterBudget = initialHistoryCharacterBudget
                        var reducedHistoryForContext = false

                        func makeMessages(historyCharacterBudget: Int) -> [Chat.Message] {
                            var messages = [Chat.Message]()
                            if !instructions.isEmpty {
                                messages.append(.system(instructions))
                            }
                            if usesAgentTranscript {
                                messages.append(
                                    contentsOf: Self.agentChatHistory(
                                        from: historyMessages[...],
                                        latestUserID: latestUser.id,
                                        latestUserImages: images,
                                        latestUserAudio: audio,
                                        maxCharacters: historyCharacterBudget,
                                        latestUserMaxCharacters: Self.localAgentLatestUserCharacterBudget(
                                            maxContextTokens: profile.quantization.maxKVSize
                                        )
                                    )
                                )
                            } else {
                                messages.append(
                                    contentsOf: Self.chatHistory(
                                        from: historyMessages[...],
                                        maxCharacters: historyCharacterBudget
                                    )
                                )
                                messages.append(.user(latestPrompt, images: images, videos: [], audio: audio))
                            }
                            return messages
                        }

                        let prepareStartedAt = Date()
                        var preflightAttempts = 1
                        var userInput = UserInput(
                            chat: makeMessages(historyCharacterBudget: historyCharacterBudget),
                            processing: .init(resize: CGSize(width: 512, height: 512)),
                            tools: toolSpecs
                        )
                        var input = try await context.processor.prepare(input: userInput)
                        while let maxContextTokens = profile.quantization.maxKVSize,
                              input.text.tokens.size + reservedCompletionTokens > maxContextTokens,
                              historyCharacterBudget > 0 {
                            reducedHistoryForContext = true
                            preflightAttempts += 1
                            historyCharacterBudget = historyCharacterBudget <= 512 ? 0 : historyCharacterBudget / 2
                            userInput = UserInput(
                                chat: makeMessages(historyCharacterBudget: historyCharacterBudget),
                                processing: .init(resize: CGSize(width: 512, height: 512)),
                                tools: toolSpecs
                            )
                            input = try await context.processor.prepare(input: userInput)
                        }
                        let prepareElapsedSeconds = Date().timeIntervalSince(prepareStartedAt)
                        if let maxContextTokens = profile.quantization.maxKVSize,
                           input.text.tokens.size + reservedCompletionTokens > maxContextTokens {
                            let availableCompletionTokens = maxContextTokens - input.text.tokens.size
                            if requestedCompletionTokens != nil, availableCompletionTokens > 0 {
                                reservedCompletionTokens = min(reservedCompletionTokens, availableCompletionTokens)
                                clampedCompletionTokens = true
                            } else {
                                throw InferenceError.invalidRequest(
                                    "This local request needs \(input.text.tokens.size + reservedCompletionTokens) tokens (\(input.text.tokens.size) prompt + \(reservedCompletionTokens) completion), but \(request.modelID.rawValue) is configured for \(maxContextTokens). Shorten the latest message or reduce local completion tokens."
                                )
                            }
                        }
                        let parameters = Self.generateParameters(
                            from: request,
                            profile: profile,
                            install: install,
                            maxTokensOverride: requestedCompletionTokens == nil ? nil : reservedCompletionTokens
                        )
                        var contextMetadata: [String: String] = [
                            ChatContextMetadataKeys.exactInputTokens: String(input.text.tokens.size),
                            ChatContextMetadataKeys.reservedCompletionTokens: String(reservedCompletionTokens),
                            LocalProviderMetadataKeys.runtimePressureReason: profile.quantization.runtimePressureReason.rawValue,
                            LocalProviderMetadataKeys.runtimePrefillStepSize: String(profile.prefillStepSize),
                            LocalProviderMetadataKeys.turboQuantProfileSource: profile.quantization.turboQuantProfileSource ?? "none",
                            LocalProviderMetadataKeys.generationPrepareElapsedSeconds: String(prepareElapsedSeconds),
                            LocalProviderMetadataKeys.generationPreflightAttempts: String(preflightAttempts),
                            "local.generation.requested_max_tokens": requestedCompletionTokens.map(String.init) ?? "none",
                            "local.generation.effective_max_tokens": requestedCompletionTokens == nil ? "none" : String(reservedCompletionTokens),
                            "local.generation.max_tokens_clamped": String(clampedCompletionTokens),
                        ]
                        if let profileID = profile.quantization.turboQuantProfileID {
                            contextMetadata[LocalProviderMetadataKeys.turboQuantProfileID] = profileID
                        }
                        if let maxContextTokens = profile.quantization.maxKVSize {
                            contextMetadata[ChatContextMetadataKeys.contextWindowTokens] = String(maxContextTokens)
                            contextMetadata[ChatContextMetadataKeys.inputBudgetTokens] = String(max(0, maxContextTokens - reservedCompletionTokens))
                            contextMetadata[LocalProviderMetadataKeys.runtimeMaxKVSize] = String(maxContextTokens)
                        }
                        if reducedHistoryForContext {
                            contextMetadata[ChatContextMetadataKeys.truncationApplied] = "true"
                            contextMetadata[ChatContextMetadataKeys.strategy] = "mlx-exact-token-preflight-v1"
                            contextMetadata[ChatContextMetadataKeys.clippedMessageCount] = "1"
                        }
                        let cacheStartedAt = Date()
                        let cache = context.model.newCache(parameters: parameters)
                        contextMetadata[LocalProviderMetadataKeys.generationCacheCreateElapsedSeconds] = String(
                            Date().timeIntervalSince(cacheStartedAt)
                        )
                        #if DEBUG
                        await FreezeBreadcrumbJournal.shared.record(
                            stage: "mlx.generation.preflight",
                            metadata: runtimeMemoryMetadata(merging: contextMetadata.merging([
                                "model_id": request.modelID.rawValue,
                                "prompt_tokens": String(input.text.tokens.size),
                                "reserved_completion_tokens": String(reservedCompletionTokens),
                                "history_character_budget": String(historyCharacterBudget),
                                "reduced_history_for_context": String(reducedHistoryForContext),
                                "kv_cache_strategy": profile.quantization.kvCacheStrategy.rawValue,
                                "turboquant_preset": profile.quantization.preset?.rawValue ?? "none",
                                "turboquant_requested_backend": profile.quantization.requestedBackend?.rawValue ?? "none",
                            ]) { _, new in new })
                        )
                        #endif
                        let stream: AsyncStream<Generation>
                        let generationTask: Task<Void, Never>
                        var stopFilter = TextStopSequenceFilter(stopSequences: stopStrings)
                        if profile.mtpEnabled,
                           let mtpModel = context.model as? any MTPLanguageModel {
                            let iterator = try MTPTokenIterator(
                                input: input,
                                model: mtpModel,
                                cache: cache,
                                parameters: parameters,
                                numMTPTokens: 1
                            )
                            (stream, generationTask) = MLXLMCommon.generateTask(
                                promptTokenCount: input.text.tokens.size,
                                modelConfiguration: context.configuration,
                                tokenizer: context.tokenizer,
                                iterator: iterator,
                                tools: toolSpecs
                            )
                        } else {
                            let iterator = try TokenIterator(
                                input: input,
                                model: context.model,
                                cache: cache,
                                parameters: parameters
                            )
                            (stream, generationTask) = MLXLMCommon.generateTask(
                                promptTokenCount: input.text.tokens.size,
                                modelConfiguration: context.configuration,
                                tokenizer: context.tokenizer,
                                iterator: iterator,
                                tools: toolSpecs
                            )
                        }
                        generationCancellation.set(generationTask)
                        var completionInfo: GenerateCompletionInfo?

                        generationLoop: for await item in stream {
                            guard !Task.isCancelled else { throw InferenceError.cancelled }
                            switch item {
                            case let .chunk(text):
                                tokenCount += 1
                                if tokenCount == 1 || tokenCount.isMultiple(of: 16) {
                                    _ = try deviceMonitor.requireLocalGenerationSafety()
                                }
                                let filtered = stopFilter.append(text)
                                if !filtered.text.isEmpty {
                                    continuation.yield(.token(TokenDelta(kind: .token, text: filtered.text, tokenCount: 1)))
                                }
                                if filtered.didStop {
                                    var providerMetadata = Self.localProviderMetadata(
                                        from: cache,
                                        fallbackProfile: profile,
                                        partitionSummary: partitionSummary
                                    )
                                    providerMetadata.merge(contextMetadata) { _, new in new }
                                    finish = InferenceFinish(
                                        reason: .stop,
                                        providerMetadata: providerMetadata
                                    )
                                    generationTask.cancel()
                                    break generationLoop
                                }
                            case let .toolCall(call):
                                let pendingText = stopFilter.flush()
                                if !pendingText.isEmpty {
                                    continuation.yield(.token(TokenDelta(kind: .token, text: pendingText, tokenCount: 1)))
                                }
                                let argumentsData = try JSONSerialization.data(
                                    withJSONObject: call.function.arguments.mapValues(\.anyValue)
                                )
                                continuation.yield(
                                    .toolCall(
                                        ToolCallDelta(
                                            id: UUID().uuidString,
                                            name: call.function.name,
                                            argumentsFragment: String(decoding: argumentsData, as: UTF8.self),
                                            isComplete: true
                                        )
                                    )
                                )
                            case let .info(info):
                                let pendingText = stopFilter.flush()
                                if !pendingText.isEmpty {
                                    continuation.yield(.token(TokenDelta(kind: .token, text: pendingText, tokenCount: 1)))
                                }
                                continuation.yield(
                                    .metrics(
                                        InferenceMetrics(
                                            promptTokens: info.promptTokenCount,
                                            completionTokens: info.generationTokenCount,
                                            promptTokensPerSecond: info.promptTokensPerSecond.isFinite ? info.promptTokensPerSecond : nil,
                                            completionTokensPerSecond: info.tokensPerSecond.isFinite ? info.tokensPerSecond : nil
                                        )
                                    )
                                )
                                completionInfo = info
                            }
                        }

                        await generationTask.value
                        generationCancellation.clear()
                        let pendingText = stopFilter.flush()
                        if !pendingText.isEmpty {
                            continuation.yield(.token(TokenDelta(kind: .token, text: pendingText, tokenCount: 1)))
                        }
                        if finish == nil, let completionInfo {
                            var providerMetadata = Self.localProviderMetadata(
                                from: cache,
                                fallbackProfile: profile,
                                partitionSummary: partitionSummary
                            )
                            providerMetadata.merge(contextMetadata) { _, new in new }
                            finish = InferenceFinish(
                                reason: Self.finishReason(from: completionInfo.stopReason),
                                providerMetadata: providerMetadata
                            )
                        }
                        return (tokenCount: tokenCount, finish: finish)
                        }
                    } onCancel: {
                        generationCancellation.cancel()
                    }

                    if let finish = result.finish {
                        continuation.yield(.finish(finish))
                    } else if result.tokenCount == 0 {
                        continuation.yield(.finish(InferenceFinish(reason: .stop)))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch InferenceError.cancelled {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch {
                    continuation.yield(
                        .failure(
                            InferenceStreamFailure(
                                code: "mlx_generation_failed",
                                message: error.localizedDescription,
                                recoverable: true
                            )
                        )
                    )
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                generationCancellation.cancel()
                task.cancel()
            }
        }
        #else
        return AsyncThrowingStream { continuation in
            continuation.yield(
                .failure(
                    InferenceStreamFailure(
                        code: "mlx_unlinked",
                        message: "MLX runtime packages are not linked in this build.",
                        recoverable: false
                    )
                )
            )
            continuation.finish()
        }
        #endif
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        #if canImport(MLXEmbedders) && canImport(MLXLMCommon) && canImport(MLX) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
        try ensureForegroundActive()
        return try await embeddingRuntime.embed(request)
        #else
        throw InferenceError.unsupportedCapability("MLXEmbedders is not linked in this build.")
        #endif
    }

    #if canImport(MLXLMCommon)
    private enum ModelConfigurationKind {
        case language
        case visionLanguage
    }

    private struct ResolvedRuntimeModelConfiguration {
        var configuration: MLXLMCommon.ModelConfiguration
        var hints: ModelRuntimeConfigurationHints
    }

    private static func lmConfiguration(
        for install: ModelInstall,
        kind: ModelConfigurationKind
    ) throws -> ResolvedRuntimeModelConfiguration {
        let registryConfiguration: MLXLMCommon.ModelConfiguration
        switch kind {
        case .language:
            registryConfiguration = LLMModelFactory.shared.configuration(id: install.repository)
        case .visionLanguage:
            registryConfiguration = VLMModelFactory.shared.configuration(id: install.repository)
        }

        if install.localURL != nil {
            let resolvedURL = try resolvedModelDirectory(for: install)
            let hints = ModelRuntimeConfigurationHints.infer(
                repository: install.repository,
                modelType: install.modelType,
                processorClass: install.processorClass,
                directory: resolvedURL
            )
            return ResolvedRuntimeModelConfiguration(
                configuration: MLXLMCommon.ModelConfiguration(
                    directory: resolvedURL,
                    tokenizerSource: registryConfiguration.tokenizerSource,
                    defaultPrompt: registryConfiguration.defaultPrompt,
                    extraEOSTokens: registryConfiguration.extraEOSTokens.union(hints.extraEOSTokens),
                    eosTokenIds: registryConfiguration.eosTokenIds,
                    toolCallFormat: registryConfiguration.toolCallFormat
                ),
                hints: ModelRuntimeConfigurationHints(
                    extraEOSTokens: registryConfiguration.extraEOSTokens.union(hints.extraEOSTokens),
                    stopStrings: registryConfiguration.extraEOSTokens.union(hints.stopStrings)
                )
            )
        }

        let inferredHints = ModelRuntimeConfigurationHints.infer(
            repository: install.repository,
            modelType: install.modelType,
            processorClass: install.processorClass,
            metadataFiles: [:]
        )
        var configuration = registryConfiguration
        configuration.id = .id(install.repository, revision: install.revision ?? "main")
        configuration.extraEOSTokens.formUnion(inferredHints.extraEOSTokens)
        let hints = ModelRuntimeConfigurationHints(
            extraEOSTokens: configuration.extraEOSTokens,
            stopStrings: configuration.extraEOSTokens.union(inferredHints.stopStrings)
        )
        return ResolvedRuntimeModelConfiguration(configuration: configuration, hints: hints)
    }

    private static func resolvedModelDirectory(for install: ModelInstall) throws -> URL {
        guard let resolvedURL = try ModelLifecycleService.installedModelDirectory(for: install) else {
            throw InferenceError.invalidRequest(
                "The installed model \(install.repository) is incomplete. Delete it and download it again."
            )
        }
        return resolvedURL
    }

    private static func configureGlobalRuntimePolicy(
        profile: RuntimeProfile,
        install: ModelInstall
    ) throws {
        MTPConfig.retainMTPWeights = profile.mtpEnabled
        guard profile.streamExperts, profile.expertStreamingMode != .disabled else {
            ExpertStreamingConfig.shared.deactivate()
            return
        }

        let directory = try resolvedModelDirectory(for: install)
        ExpertStreamingConfig.shared.activate(
            modelDirectory: directory,
            useDirectIO: profile.expertStreamingMode == .directNVMe
        )
    }

    private static func configureLoadedContainer(
        _ container: MLXLMCommon.ModelContainer?,
        profile: RuntimeProfile
    ) async -> String? {
        guard let container else { return nil }
        let clampedGPULayers = await container.setGPULayers(profile.gpuLayerCount)
        _ = await container.setStreamExperts(profile.streamExperts)

        if let requested = profile.gpuLayerCount {
            guard let clampedGPULayers else {
                return "Layer partition unsupported"
            }
            return requested == clampedGPULayers
                ? "GPU layers: \(clampedGPULayers)"
                : "GPU layers: \(clampedGPULayers) (requested \(requested))"
        }
        return nil
    }

    private static func generateParameters(
        from request: ChatRequest,
        profile: RuntimeProfile,
        install: ModelInstall?,
        maxTokensOverride: Int? = nil
    ) -> GenerateParameters {
        let turboQuantSeed: UInt64? =
            profile.quantization.kvCacheStrategy == .turboQuant
            ? MLX.TurboQuantConfiguration.deterministicSeed(
                modelID: install?.repository ?? request.modelID.rawValue,
                revision: install?.revision ?? "main",
                cacheLayoutVersion: 3
            )
            : nil

        return GenerateParameters(
            maxTokens: maxTokensOverride ?? request.sampling.maxTokens,
            maxKVSize: profile.quantization.maxKVSize,
            kvBits: profile.quantization.kvCacheStrategy == .turboQuant ? nil : profile.quantization.kvBits,
            kvGroupSize: profile.quantization.kvGroupSize,
            quantizedKVStart: profile.quantization.quantizedKVStart,
            kvCacheStrategy: mlxKVCacheStrategy(from: profile.quantization.kvCacheStrategy),
            turboQuantPreset: mlxTurboQuantPreset(from: profile.quantization.preset),
            turboQuantBackend: mlxTurboQuantBackend(from: profile.quantization.requestedBackend),
            turboQuantOptimizationPolicy: mlxTurboQuantOptimizationPolicy(
                from: profile.quantization.turboQuantOptimizationPolicy
            ),
            turboQuantSeed: turboQuantSeed,
            turboQuantValueBits: resolvedTurboQuantValueBits(for: profile, install: install),
            temperature: request.sampling.temperature,
            topP: request.sampling.topP,
            repetitionPenalty: request.sampling.repetitionPenalty,
            repetitionContextSize: profile.repetitionContextSize,
            prefillStepSize: profile.prefillStepSize
        )
    }

    private static func mlxKVCacheStrategy(
        from strategy: PinesCore.KVCacheStrategy
    ) -> MLXLMCommon.KVCacheStrategy {
        switch strategy {
        case .none:
            .none
        case .mlxAffine:
            .mlxAffine
        case .turboQuant:
            .turboQuant
        }
    }

    private static func mlxTurboQuantPreset(from preset: PinesCore.TurboQuantPreset?) -> MLX.TurboQuantPreset {
        let rawValue = preset?.rawValue ?? PinesCore.TurboQuantPreset.defaultGeneration.rawValue
        return MLX.TurboQuantPreset(rawValue: rawValue)
            ?? MLX.TurboQuantPreset(rawValue: PinesCore.TurboQuantPreset.conservativeFallback.rawValue)
            ?? .turbo3_5
    }

    private static func resolvedTurboQuantValueBits(
        for profile: RuntimeProfile,
        install: ModelInstall?
    ) -> Int? {
        guard profile.quantization.kvCacheStrategy == .turboQuant else { return nil }
        if let valueBits = profile.quantization.turboQuantValueBits {
            return valueBits
        }
        #if canImport(MLXLMCommon)
        if let install,
	           let registryProfile = MLXLMCommon.TurboQuantProfileRegistry.bundled.profile(
	               for: install.repository,
	               modelType: install.modelType,
	               textConfigModelType: install.textConfigModelType,
	               modality: install.modalities.contains(.vision) ? .visionText : .text,
	               parameterCountB: install.parameterCount.map { Double($0) / 1_000_000_000 },
	               routedExperts: install.routedExperts,
	               expertsPerToken: install.expertsPerToken,
	               keyHeadDimension: install.keyHeadDimension,
               valueHeadDimension: install.valueHeadDimension,
               contextLength: profile.quantization.maxKVSize
           ) {
            return registryProfile.valueBits
        }
        #endif
        return profile.quantization.preset?.defaultValueBits
            ?? PinesCore.TurboQuantPreset.conservativeFallback.defaultValueBits
    }

    private static func mlxTurboQuantBackend(
        from backend: PinesCore.TurboQuantRuntimeBackend?
    ) -> MLXLMCommon.TurboQuantBackend {
        guard let backend else { return .metalPolarQJL }
        return MLXLMCommon.TurboQuantBackend(rawValue: backend.rawValue) ?? .metalPolarQJL
    }

    private static func turboQuantValueBits(from cache: any TurboQuantCompressedKVCacheProtocol) -> Int {
        if let cache = cache as? TurboQuantKVCache {
            return cache.valueBits
        }
        if let cache = cache as? RotatingTurboQuantKVCache {
            return cache.valueBits
        }
        return cache.preset.defaultValueBits
    }

    private static func localProviderMetadata(
        from cache: [KVCache],
        fallbackProfile profile: RuntimeProfile,
        partitionSummary: String? = nil
    ) -> [String: String] {
        if let turboQuantCache = cache.compactMap({ $0 as? TurboQuantCompressedKVCacheProtocol }).first {
            let diagnostics = turboQuantCache.attentionDiagnostics
            var metadata: [String: String] = [
                LocalProviderMetadataKeys.turboQuantPreset: turboQuantCache.preset.rawValue,
                LocalProviderMetadataKeys.turboQuantRequestedBackend: turboQuantCache.requestedBackend.rawValue,
                LocalProviderMetadataKeys.turboQuantActiveBackend: turboQuantCache.activeBackend.rawValue,
                LocalProviderMetadataKeys.turboQuantValueBits: String(turboQuantValueBits(from: turboQuantCache)),
                LocalProviderMetadataKeys.turboQuantAttentionPath: diagnostics.activeAttentionPath.rawValue,
                LocalProviderMetadataKeys.turboQuantKernelProfile: diagnostics.selectedKernelProfile.rawValue,
                LocalProviderMetadataKeys.turboQuantSelfTestStatus: diagnostics.selfTestStatus.rawValue,
                LocalProviderMetadataKeys.turboQuantRawFallbackAllocated: String(diagnostics.rawFallbackAllocated),
                LocalProviderMetadataKeys.runtimePressureReason: profile.quantization.runtimePressureReason.rawValue,
                LocalProviderMetadataKeys.runtimeLowPowerMode: String(profile.quantization.memoryCounters.lowPowerModeEnabled ?? false),
                LocalProviderMetadataKeys.runtimePrefillStepSize: String(profile.prefillStepSize),
                LocalProviderMetadataKeys.mtpEnabled: String(profile.mtpEnabled),
                LocalProviderMetadataKeys.audioEnabled: String(profile.audioEnabled),
                LocalProviderMetadataKeys.dflashEnabled: String(profile.dflashEnabled),
            ]
            if let maxKVSize = profile.quantization.maxKVSize {
                metadata[LocalProviderMetadataKeys.runtimeMaxKVSize] = String(maxKVSize)
            }
            if let profileID = profile.quantization.turboQuantProfileID {
                metadata[LocalProviderMetadataKeys.turboQuantProfileID] = profileID
            }
            if let profileSource = profile.quantization.turboQuantProfileSource {
                metadata[LocalProviderMetadataKeys.turboQuantProfileSource] = profileSource
            }
            appendRuntimeFeatureMetadata(to: &metadata, partitionSummary: partitionSummary)
            if let fallbackReason = diagnostics.fallbackReason {
                metadata[LocalProviderMetadataKeys.turboQuantFallbackReason] = fallbackReason
            }
            if let unsupportedShape = diagnostics.lastUnsupportedShape {
                metadata[LocalProviderMetadataKeys.turboQuantLastUnsupportedShape] = unsupportedShape
            }
            return metadata
        }

        let quantization = profile.quantization
        var metadata: [String: String] = [
            LocalProviderMetadataKeys.turboQuantRawFallbackAllocated: String(quantization.rawFallbackAllocated ?? false),
            LocalProviderMetadataKeys.runtimePressureReason: quantization.runtimePressureReason.rawValue,
            LocalProviderMetadataKeys.runtimeLowPowerMode: String(quantization.memoryCounters.lowPowerModeEnabled ?? false),
            LocalProviderMetadataKeys.runtimePrefillStepSize: String(profile.prefillStepSize),
            LocalProviderMetadataKeys.mtpEnabled: String(profile.mtpEnabled),
            LocalProviderMetadataKeys.audioEnabled: String(profile.audioEnabled),
            LocalProviderMetadataKeys.dflashEnabled: String(profile.dflashEnabled),
        ]
        if let maxKVSize = quantization.maxKVSize {
            metadata[LocalProviderMetadataKeys.runtimeMaxKVSize] = String(maxKVSize)
        }
        if let profileID = quantization.turboQuantProfileID {
            metadata[LocalProviderMetadataKeys.turboQuantProfileID] = profileID
        }
        if let profileSource = quantization.turboQuantProfileSource {
            metadata[LocalProviderMetadataKeys.turboQuantProfileSource] = profileSource
        }
        appendRuntimeFeatureMetadata(to: &metadata, partitionSummary: partitionSummary)
        if let preset = quantization.preset {
            metadata[LocalProviderMetadataKeys.turboQuantPreset] = preset.rawValue
        }
        if let valueBits = quantization.turboQuantValueBits {
            metadata[LocalProviderMetadataKeys.turboQuantValueBits] = String(valueBits)
        }
        if let requestedBackend = quantization.requestedBackend {
            metadata[LocalProviderMetadataKeys.turboQuantRequestedBackend] = requestedBackend.rawValue
        }
        if let activeBackend = quantization.activeBackend {
            metadata[LocalProviderMetadataKeys.turboQuantActiveBackend] = activeBackend.rawValue
        }
        if let attentionPath = quantization.activeAttentionPath {
            metadata[LocalProviderMetadataKeys.turboQuantAttentionPath] = attentionPath.rawValue
        }
        if let kernelProfile = quantization.metalKernelProfile {
            metadata[LocalProviderMetadataKeys.turboQuantKernelProfile] = kernelProfile.rawValue
        }
        if let selfTestStatus = quantization.metalSelfTestStatus {
            metadata[LocalProviderMetadataKeys.turboQuantSelfTestStatus] = selfTestStatus.rawValue
        }
        if let fallbackReason = quantization.activeFallbackReason {
            metadata[LocalProviderMetadataKeys.turboQuantFallbackReason] = fallbackReason
        }
        if let unsupportedShape = quantization.lastUnsupportedAttentionShape {
            metadata[LocalProviderMetadataKeys.turboQuantLastUnsupportedShape] = unsupportedShape
        }
        return metadata
    }

    private static func appendRuntimeFeatureMetadata(
        to metadata: inout [String: String],
        partitionSummary: String?
    ) {
        #if canImport(MLX)
        let ssdMetrics = MLXFast.ssdMetricsSnapshot()
        metadata[LocalProviderMetadataKeys.ssdThroughputMBperS] = String(ssdMetrics.throughputMBperS)
        metadata[LocalProviderMetadataKeys.ssdTotalBytesRead] = String(ssdMetrics.totalBytesRead)
        metadata[LocalProviderMetadataKeys.ssdTotalChunks] = String(ssdMetrics.totalChunks)
        metadata[LocalProviderMetadataKeys.ssdAvgChunkLatencyMS] = String(ssdMetrics.avgChunkLatencyMS)
        #endif
        if let partitionSummary {
            metadata[LocalProviderMetadataKeys.partitionSummary] = partitionSummary
        }
    }

    private static func mlxTurboQuantOptimizationPolicy(
        from policy: PinesCore.TurboQuantOptimizationPolicy
    ) -> MLXLMCommon.TurboQuantOptimizationPolicy {
        MLXLMCommon.TurboQuantOptimizationPolicy(rawValue: policy.rawValue) ?? .auto
    }

    private static func mlxToolSpecs(from tools: [AnyToolSpec]) -> [MLXLMCommon.ToolSpec]? {
        let schemas = tools.map { $0.openAIFunctionToolObject() }
        return schemas.isEmpty ? nil : schemas
    }

    private static func localHistoryCharacterBudget(maxContextTokens: Int?) -> Int {
        guard let maxContextTokens else { return 24_000 }
        return min(96_000, max(24_000, maxContextTokens * 2))
    }

    private static func localAgentLatestUserCharacterBudget(maxContextTokens: Int?) -> Int {
        guard let maxContextTokens else { return 8_000 }
        return min(32_000, max(8_000, maxContextTokens))
    }

    private static func chatHistory(
        from messages: ArraySlice<ChatMessage>,
        maxCharacters: Int = 24_000
    ) -> [Chat.Message] {
        var selected = [Chat.Message]()
        var remaining = maxCharacters

        for message in messages.reversed() {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, message.role != .system else { continue }
            guard remaining > 0 else { break }

            let clippedContent: String
            if content.count <= remaining {
                clippedContent = content
            } else {
                clippedContent = String(content.suffix(remaining))
            }
            remaining -= clippedContent.count

            switch message.role {
            case .assistant:
                selected.append(.assistant(clippedContent))
            case .tool:
                selected.append(.tool(clippedContent))
            case .user:
                selected.append(.user(clippedContent))
            case .system:
                break
            }
        }

        return selected.reversed()
    }

    private static func agentChatHistory(
        from messages: ArraySlice<ChatMessage>,
        latestUserID: UUID,
        latestUserImages: [UserInput.Image],
        latestUserAudio: [UserInput.Audio],
        maxCharacters: Int = 24_000,
        latestUserMaxCharacters: Int = 8_000
    ) -> [Chat.Message] {
        let indexed = messages.enumerated().map { (offset: $0.offset, message: $0.element) }
        let latestUser = indexed.first { $0.message.id == latestUserID }
        let latestUserContent = latestUser?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var selected = [(offset: Int, message: ChatMessage)]()
        let clippedLatestUserContent = clippedAgentContent(latestUserContent, maxCharacters: latestUserMaxCharacters)
        var remaining = max(0, maxCharacters - clippedLatestUserContent.count)

        for item in indexed.reversed() where item.message.id != latestUserID {
            let content = item.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, item.message.role != .system else { continue }
            guard remaining > 0 else { break }
            var message = item.message
            if content.count > remaining {
                message.content = String(content.suffix(remaining))
                remaining = 0
            } else {
                message.content = content
                remaining -= content.count
            }
            selected.append((offset: item.offset, message: message))
        }
        if let latestUser {
            var message = latestUser.message
            message.content = clippedLatestUserContent
            selected.append((offset: latestUser.offset, message: message))
        }

        return selected
            .sorted { $0.offset < $1.offset }
            .compactMap { item in
                let content = item.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return nil }
                switch item.message.role {
                case .assistant:
                    return .assistant(content)
                case .tool:
                    return .tool(content)
                case .user:
                    if item.message.id == latestUserID {
                        return .user(content, images: latestUserImages, videos: [], audio: latestUserAudio)
                    }
                    return .user(content)
                case .system:
                    return nil
                }
            }
    }

    private static func clippedAgentContent(_ content: String, maxCharacters: Int) -> String {
        guard content.count > maxCharacters else { return content }
        return String(content.suffix(maxCharacters))
    }

    private static func finishReason(from reason: GenerateStopReason) -> InferenceFinishReason {
        switch reason {
        case .stop:
            .stop
        case .length:
            .length
        case .cancelled:
            .cancelled
        }
    }
    #endif

    private struct TextStopSequenceFilter {
        private let stopSequences: [String]
        private var buffer = ""

        init(stopSequences: Set<String>) {
            self.stopSequences = stopSequences
                .filter { !$0.isEmpty }
                .sorted { lhs, rhs in
                    if lhs.count != rhs.count {
                        return lhs.count > rhs.count
                    }
                    return lhs < rhs
                }
        }

        mutating func append(_ text: String) -> (text: String, didStop: Bool) {
            guard !stopSequences.isEmpty else {
                return (text, false)
            }

            buffer.append(text)
            if let stopRange = firstStopRange(in: buffer) {
                let output = String(buffer[..<stopRange.lowerBound])
                buffer.removeAll()
                return (output, true)
            }

            let keepCount = pendingStopPrefixSuffixLength(in: buffer)
            guard keepCount < buffer.count else {
                return ("", false)
            }

            let splitIndex = buffer.index(buffer.endIndex, offsetBy: -keepCount)
            let output = String(buffer[..<splitIndex])
            buffer = String(buffer[splitIndex...])
            return (output, false)
        }

        mutating func flush() -> String {
            defer { buffer.removeAll() }
            return buffer
        }

        private func firstStopRange(in text: String) -> Range<String.Index>? {
            var selected: Range<String.Index>?
            for stopSequence in stopSequences {
                guard let range = text.range(of: stopSequence) else { continue }
                if let current = selected {
                    if range.lowerBound < current.lowerBound {
                        selected = range
                    }
                } else {
                    selected = range
                }
            }
            return selected
        }

        private func pendingStopPrefixSuffixLength(in text: String) -> Int {
            var best = 0
            for stopSequence in stopSequences {
                let maxLength = min(max(stopSequence.count - 1, 0), text.count)
                guard maxLength > best else { continue }
                for length in stride(from: maxLength, through: best + 1, by: -1) {
                    if text.hasSuffix(stopSequence.prefix(length)) {
                        best = length
                        break
                    }
                }
            }
            return best
        }
    }

    private static func install(for modelID: ModelID, modalities: Set<ModelModality>) -> ModelInstall {
        ModelInstall(
            modelID: modelID,
            displayName: modelID.rawValue.components(separatedBy: "/").last ?? modelID.rawValue,
            repository: modelID.rawValue,
            modalities: modalities,
            verification: .installable,
            state: .remote
        )
    }

    private static func prompt(from messages: [ChatMessage]) -> String {
        let maxCharacters = 24_000
        let usableMessages = messages
            .filter { message in
                message.role != .system
                    && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .suffix(24)

        var packed = [String]()
        var remaining = maxCharacters
        for message in usableMessages.reversed() {
            let label: String
            switch message.role {
            case .user:
                label = "User"
            case .assistant:
                label = "Assistant"
            case .tool:
                label = "Tool"
            case .system:
                label = "System"
            }
            let entry = "\(label): \(message.content)"
            guard remaining > 0 else { break }
            if entry.count <= remaining {
                packed.append(entry)
                remaining -= entry.count
            } else if message.role == .user, packed.isEmpty {
                packed.append(String(entry.suffix(remaining)))
                break
            }
        }
        return packed.reversed().joined(separator: "\n\n")
    }
}

struct LocalRuntimeStatus: Hashable {
    var mlxLinked: Bool
    var installedModels: Int
    var activeModelName: String?
    var memoryTier: DeviceMemoryTier

    static let preview = LocalRuntimeStatus(
        mlxLinked: false,
        installedModels: CuratedModelManifest.default.entries.count,
        activeModelName: "Llama 3.2 1B 4-bit",
        memoryTier: .balanced
    )
}
