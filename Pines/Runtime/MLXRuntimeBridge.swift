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

private let activeGenerationEmergencyMinimumAvailableBytes: Int64 = 650_000_000

private struct StableLocalDigest: Sendable {
    private var value: UInt64 = 0xcbf29ce484222325

    mutating func append(_ string: String) {
        for byte in string.utf8 {
            append(byte)
        }
        append(0)
    }

    mutating func append(_ int: Int) {
        append(Int64(int))
    }

    mutating func append(_ int: Int64) {
        append(UInt64(bitPattern: int))
    }

    mutating func append(_ int: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            append(UInt8(truncatingIfNeeded: int >> shift))
        }
    }

    mutating func append(contentsOf data: Data) {
        for byte in data {
            append(byte)
        }
    }

    var hexString: String {
        String(format: "%016llx", value)
    }

    private mutating func append(_ byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 0x100000001b3
    }
}

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

private final class MLXGenerationTelemetryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var contextPlan: ContextAssemblyPlan?
    private var admissionPlan: LocalRuntimeAdmissionPlan?
    private var failureMetadata: [String: String] = [:]
    private var inputTokens: Int?
    private var outputTokens: Int?

    func setContextPlan(_ plan: ContextAssemblyPlan?) {
        lock.lock()
        contextPlan = plan
        lock.unlock()
    }

    func setAdmissionPlan(_ plan: LocalRuntimeAdmissionPlan?) {
        lock.lock()
        admissionPlan = plan
        lock.unlock()
    }

    func setFailureMetadata(_ metadata: [String: String]) {
        lock.lock()
        failureMetadata = metadata
        lock.unlock()
    }

    func setInputTokens(_ tokens: Int?) {
        lock.lock()
        inputTokens = tokens
        lock.unlock()
    }

    func setOutputTokens(_ tokens: Int?) {
        lock.lock()
        outputTokens = tokens
        lock.unlock()
    }

    func snapshot() -> (
        contextPlan: ContextAssemblyPlan?,
        admissionPlan: LocalRuntimeAdmissionPlan?,
        failureMetadata: [String: String],
        inputTokens: Int?,
        outputTokens: Int?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (contextPlan, admissionPlan, failureMetadata, inputTokens, outputTokens)
    }
}

#if canImport(MLX)
private final class MLXCachePressureController: @unchecked Sendable {
    static let shared = MLXCachePressureController()

    private let lock = NSLock()
    private var delayedIdleClear: Task<Void, Never>?
    private let idleClearDelayNanoseconds: UInt64 = 15_000_000_000

    private init() {}

    func configureActive(limit: Int) {
        lock.lock()
        delayedIdleClear?.cancel()
        delayedIdleClear = nil
        lock.unlock()
        setCacheLimit(limit)
    }

    func settleAfterGeneration(idleLimit: Int, clearImmediately: Bool) {
        lock.lock()
        delayedIdleClear?.cancel()
        delayedIdleClear = nil
        lock.unlock()

        setCacheLimit(idleLimit)
        if clearImmediately {
            Self.synchronizeAndClearCache(limit: idleLimit)
            return
        }

        let task = Task { [idleClearDelayNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: idleClearDelayNanoseconds)
            } catch {
                return
            }
            Self.synchronizeAndClearCache(limit: idleLimit)
        }

        lock.lock()
        delayedIdleClear = task
        lock.unlock()
    }

    func clearImmediately(limit: Int) {
        lock.lock()
        delayedIdleClear?.cancel()
        delayedIdleClear = nil
        lock.unlock()
        Self.synchronizeAndClearCache(limit: limit)
    }

    private func setCacheLimit(_ limit: Int) {
        #if targetEnvironment(simulator)
        return
        #else
        Memory.cacheLimit = limit
        #endif
    }

    private static func synchronizeAndClearCache(limit: Int) {
        #if targetEnvironment(simulator)
        return
        #else
        if Memory.cacheLimit > limit {
            Memory.cacheLimit = limit
        }
        Stream.gpu.synchronize()
        Memory.clearCache()
        #endif
    }
}
#endif

#if canImport(MLXLMCommon)
private struct LocalPromptKVCacheKey: Hashable, Sendable {
    var modelID: String
    var repository: String
    var revision: String
    var tokenizerTemplateDigest: String
    var quantizationStrategy: String
    var turboQuantPreset: String
    var turboQuantBackend: String
    var turboQuantSeed: String
    var turboQuantValueBits: String
    var kvBits: String
    var kvGroupSize: Int
    var quantizedKVStart: Int
    var maxKVSize: String
    var capabilityShape: String
}

private struct LocalPromptKVCacheEntry: @unchecked Sendable {
    var key: LocalPromptKVCacheKey
    var tokenIDs: [Int32]
    var tokenDigest: String
    var cache: [KVCache]
    var storedAt: Date
}

private struct LocalPromptKVCacheLookup: @unchecked Sendable {
    var entry: LocalPromptKVCacheEntry?
    var reusedPrefixTokenCount: Int
    var suffixPrefillTokenCount: Int
    var missReason: String?

    static func miss(_ reason: String) -> LocalPromptKVCacheLookup {
        LocalPromptKVCacheLookup(
            entry: nil,
            reusedPrefixTokenCount: 0,
            suffixPrefillTokenCount: 0,
            missReason: reason
        )
    }
}

private actor LocalPromptKVCacheStore {
    private var entries: [LocalPromptKVCacheKey: LocalPromptKVCacheEntry] = [:]
    private(set) var lastEvictionReason: String?

    func take(
        key: LocalPromptKVCacheKey,
        promptTokenIDs: [Int32]
    ) -> LocalPromptKVCacheLookup {
        guard var entry = entries.removeValue(forKey: key) else {
            return .miss("empty")
        }
        guard !promptTokenIDs.isEmpty, !entry.tokenIDs.isEmpty else {
            lastEvictionReason = "empty_prompt"
            return .miss("empty_prompt")
        }

        let prefix = Self.commonPrefixLength(entry.tokenIDs, promptTokenIDs)
        guard prefix > 0 else {
            lastEvictionReason = "prefix_mismatch"
            return .miss("prefix_mismatch")
        }

        let cachedSuffixTokenCount = entry.tokenIDs.count - prefix
        if cachedSuffixTokenCount > 0 {
            guard canTrimPromptCache(entry.cache) else {
                lastEvictionReason = "prefix_mismatch_untrimmable"
                return .miss("prefix_mismatch_untrimmable")
            }
            let trimmed = trimPromptCache(entry.cache, numTokens: cachedSuffixTokenCount)
            guard trimmed == cachedSuffixTokenCount else {
                lastEvictionReason = "prefix_trim_failed"
                return .miss("prefix_trim_failed")
            }
            entry.tokenIDs = Array(entry.tokenIDs.prefix(prefix))
            entry.tokenDigest = Self.tokenDigest(entry.tokenIDs)
        }

        let cachedTokenCount = entry.cache.map(\.offset).min() ?? 0
        guard cachedTokenCount >= prefix else {
            lastEvictionReason = "cache_offset_mismatch"
            return .miss("cache_offset_mismatch")
        }

        return LocalPromptKVCacheLookup(
            entry: entry,
            reusedPrefixTokenCount: prefix,
            suffixPrefillTokenCount: max(0, promptTokenIDs.count - prefix),
            missReason: nil
        )
    }

    func store(_ entry: LocalPromptKVCacheEntry) {
        guard !entry.tokenIDs.isEmpty, !entry.cache.isEmpty else { return }
        entries[entry.key] = entry
    }

    @discardableResult
    func evictAll(reason: String) -> Int {
        let count = entries.count
        entries.removeAll(keepingCapacity: true)
        lastEvictionReason = reason
        return count
    }

    static func tokenDigest(_ tokenIDs: [Int32]) -> String {
        var digest = StableLocalDigest()
        digest.append(tokenIDs.count)
        for tokenID in tokenIDs {
            digest.append(Int64(tokenID))
        }
        return digest.hexString
    }

    private static func commonPrefixLength(_ lhs: [Int32], _ rhs: [Int32]) -> Int {
        let count = min(lhs.count, rhs.count)
        var index = 0
        while index < count, lhs[index] == rhs[index] {
            index += 1
        }
        return index
    }
}
#endif

private enum LocalRuntimeSupervisorState: String, Sendable {
    case idle
    case loading
    case ready
    case generating
    case cancelling
    case unloading
    case blocked
}

private enum LocalMemoryPressureDowngradeStep: String, CaseIterable, Sendable {
    case releaseRawPrefillShadow = "release_raw_prefill_shadow"
    case releasePackedFallback = "release_packed_fallback"
    case reduceLiveContext = "reduce_live_context"
    case switchBalancedToMaxContext = "switch_balanced_to_max_context"
    case slidingWindowPinnedSystemPrompt = "sliding_window_pinned_system_prompt"
    case summarizeOlderTurns = "summarize_older_turns"
    case askUserReduceContextOrSwitchModel = "ask_user_reduce_context_or_switch_model"
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
    static let turboQuantCompatibilityPairID =
        "mlx-swift-210fb8983784e17276aa84f60850158535502bb4+mlx-swift-lm-ab52b3d978bca2eaa4fa7a4b7bc8bd9aa63fc18d"
    private static let shortContextPlainKVTokenThreshold = 4_096
    private static let forceTurboQuantShortContextEnvironmentKey =
        "PINES_FORCE_TURBOQUANT_SHORT_CONTEXT"
    static var turboQuantLayoutVersion: Int {
        #if canImport(MLX)
        MLX.TurboQuantAttentionLayout.currentVersion
        #else
        TurboQuantLayoutVersion.current
        #endif
    }
    static var turboQuantRuntimeCapabilities: PinesTurboQuantRuntimeCapabilityRegistry {
        #if canImport(MLXLLM)
        return PinesTurboQuantRuntimeCapabilityRegistry(
            capabilities: MLXLLM.MLXTurboQuantRuntimeCapabilityRegistry.capabilities.map { capability in
                PinesTurboQuantRuntimeModelCapability(
                    modelType: capability.modelType,
                    supportsThrowingTurboQuantAttention: capability.supportsThrowingTurboQuantAttention,
                    cacheTopology: Self.pinesTurboQuantCacheTopology(from: capability.cacheTopology),
                    note: capability.note
                )
            }
        )
        #else
        return .bundledFallback
        #endif
    }

    private let state = MLXRuntimeState()
    private let deviceMonitor = DeviceRuntimeMonitor()
    private let supervisor = LocalRuntimeSupervisor()

    #if canImport(MLXLLM)
    private static func pinesTurboQuantCacheTopology(
        from topology: MLXLLM.MLXTurboQuantCacheTopology
    ) -> PinesTurboQuantCacheTopology {
        switch topology {
        case .standardAttentionKV:
            .standardAttentionKV
        case .hybridAttentionKVAndNativeState:
            .hybridAttentionKVAndNativeState
        case .gatedVLMOrDualModel:
            .gatedVLMOrDualModel
        case .unsupported:
            .unsupported
        }
    }
    #endif

    private func runtimeMemoryMetadata(
        merging base: [String: String] = [:]
    ) -> [String: String] {
        var metadata = base
        let counters = deviceMonitor.memoryCounters()
        Self.add(counters.physicalMemoryBytes, forKey: "physical_memory_bytes", to: &metadata)
        Self.add(counters.availableMemoryBytes, forKey: "available_memory_bytes", to: &metadata)
        Self.add(counters.processResidentMemoryBytes, forKey: "process_resident_memory_bytes", to: &metadata)
        Self.add(counters.processPhysicalFootprintBytes, forKey: "process_physical_footprint_bytes", to: &metadata)
        Self.add(counters.processPeakResidentMemoryBytes, forKey: "process_peak_resident_memory_bytes", to: &metadata)
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

    fileprivate static func metadataJSON<Value: Encodable>(_ value: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    fileprivate static func minimalContextAssemblyPlan(
        exactInputTokens: Int,
        reservedCompletionTokens: Int,
        historyMessageCount: Int,
        reducedHistoryForContext: Bool
    ) -> ContextAssemblyPlan {
        ContextAssemblyPlan(
            strategy: reducedHistoryForContext
                ? "mlx-exact-token-preflight-v1"
                : "mlx-current-history-v1",
            includedRecentMessageCount: historyMessageCount,
            clippedMessageCount: reducedHistoryForContext ? 1 : 0,
            exactInputTokens: exactInputTokens,
            reservedCompletionTokens: reservedCompletionTokens,
            truncationReason: reducedHistoryForContext ? "context_window" : nil
        )
    }

    fileprivate static func runtimeProfileForPreparedGeneration(
        baseProfile: RuntimeProfile,
        exactInputTokens: Int,
        reservedCompletionTokens: Int
    ) -> RuntimeProfile {
        guard baseProfile.quantization.kvCacheStrategy == .turboQuant else {
            return baseProfile
        }
        guard baseProfile.quantization.turboQuantUserMode != .maxContext else {
            return baseProfile
        }
        guard ProcessInfo.processInfo.environment[forceTurboQuantShortContextEnvironmentKey] != "1" else {
            return baseProfile
        }

        let requestTokens = max(0, exactInputTokens) + max(0, reservedCompletionTokens)
        guard requestTokens > 0, requestTokens <= shortContextPlainKVTokenThreshold else {
            return baseProfile
        }

        var profile = baseProfile
        profile.name = "\(baseProfile.name) Short Context Plain KV"
        profile.promptCacheIdentifier = [
            baseProfile.promptCacheIdentifier,
            "plain-short-context-v1",
        ]
        .compactMap { $0 }
        .joined(separator: "|")
        profile.quantization.algorithm = .none
        profile.quantization.kvCacheStrategy = .none
        profile.quantization.kvBits = nil
        profile.quantization.maxKVSize = min(
            baseProfile.quantization.maxKVSize ?? shortContextPlainKVTokenThreshold,
            shortContextPlainKVTokenThreshold
        )
        profile.quantization.preset = nil
        profile.quantization.requestedBackend = nil
        profile.quantization.activeBackend = nil
        profile.quantization.activeAttentionPath = nil
        profile.quantization.rawFallbackAllocated = nil
        profile.quantization.turboQuantValueBits = nil
        profile.quantization.turboQuantAdmission = nil
        profile.quantization.activeFallbackReason =
            "Plain KV selected for short local request (\(requestTokens) tokens <= \(shortContextPlainKVTokenThreshold)); TurboQuant remains reserved for extended context."
        profile.quantization.turboQuantProfileDiagnostics.append(
            "Short-context router selected plain KV because request_tokens=\(requestTokens) <= \(shortContextPlainKVTokenThreshold)."
        )
        return profile
    }

    fileprivate static func localRuntimeAdmissionPlan(
        request: ChatRequest,
        install: ModelInstall?,
        profile: RuntimeProfile,
        contextPlan: ContextAssemblyPlan,
        memoryCounters inputCounters: RuntimeMemoryCounters
    ) -> LocalRuntimeAdmissionPlan? {
        guard profile.quantization.kvCacheStrategy == .turboQuant else {
            return nil
        }

        var memoryCounters = inputCounters
        if memoryCounters.availableMemoryBytes == nil {
            memoryCounters.availableMemoryBytes = memoryCounters.physicalMemoryBytes.map { max(0, $0 / 2) }
                ?? 4 * 1_024 * 1_024 * 1_024
        }

        let legacyPlan = profile.quantization.turboQuantAdmission?.memoryPlan
        let requestedContext = max(
            profile.quantization.maxKVSize ?? 0,
            contextPlan.exactInputTokens + contextPlan.reservedCompletionTokens
        )
        let fallbackReserve = Int64(
            legacyPlan?.runtimeZones.fallbackReserveBytes
                ?? Int(TurboQuantFallbackContract.defaultReserveBytes(for: profile.quantization.turboQuantUserMode))
        )
        let fallbackContract = TurboQuantFallbackContract.productDefault(
            for: profile.quantization.turboQuantUserMode,
            allowCloudRetry: false,
            reserveBytes: fallbackReserve
        )

        let admissionRequest = LocalRuntimeAdmissionRequest(
            modelID: install?.repository ?? request.modelID.rawValue,
            modelRevision: install?.revision,
            parameterCount: install?.resolvedParameterCount,
            requestedContextTokens: requestedContext,
            reservedCompletionTokens: contextPlan.reservedCompletionTokens,
            userMode: profile.quantization.turboQuantUserMode,
            fallbackContract: fallbackContract,
            deviceClass: memoryCounters.devicePerformanceClass
                ?? profile.quantization.devicePerformanceClass
                ?? .futureVerified,
            hardwareModel: memoryCounters.hardwareModelIdentifier,
            osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
            memoryCounters: memoryCounters,
            quantizationDiagnostics: RuntimeQuantizationDiagnostics(
                preset: profile.quantization.preset,
                requestedBackend: profile.quantization.requestedBackend,
                activeBackend: profile.quantization.activeBackend,
                metalCodecAvailable: profile.quantization.metalCodecAvailable,
                metalAttentionAvailable: profile.quantization.metalAttentionAvailable,
                activeAttentionPath: profile.quantization.activeAttentionPath,
                metalKernelProfile: profile.quantization.metalKernelProfile,
                metalSelfTestStatus: profile.quantization.metalSelfTestStatus,
                metalSelfTestFailureReason: profile.quantization.metalSelfTestFailureReason,
                rawFallbackAllocated: profile.quantization.rawFallbackAllocated,
                devicePerformanceClass: profile.quantization.devicePerformanceClass,
                turboQuantOptimizationPolicy: profile.quantization.turboQuantOptimizationPolicy,
                turboQuantValueBits: profile.quantization.turboQuantValueBits,
                thermalDownshiftActive: profile.quantization.thermalDownshiftActive,
                runtimePressureReason: profile.quantization.runtimePressureReason,
                turboQuantProfileID: profile.quantization.turboQuantProfileID,
                turboQuantProfileSource: profile.quantization.turboQuantProfileSource,
                lastUnsupportedAttentionShape: profile.quantization.lastUnsupportedAttentionShape,
                activeFallbackReason: profile.quantization.activeFallbackReason,
                memoryCounters: memoryCounters
            ),
            estimatedModelWeightsBytes: incrementalModelWeightBytesForGenerationAdmission(
                install: install,
                memoryCounters: memoryCounters
            ),
            compressedKVBytesPerToken: Int64(legacyPlan?.compressedBytesPerToken ?? 256 * 1_024),
            rawShadowBytes: Int64(legacyPlan?.runtimeZones.rawShadowBytes ?? 0),
            packedFallbackBytesPerToken: Int64(legacyPlan?.packedFallbackBytesPerToken ?? 0),
            decodedFallbackScratchBytes: Int64(legacyPlan?.runtimeZones.scratchBytes ?? 64 * 1_024 * 1_024),
            vaultIndexBytes: memoryCounters.vaultIndexBytes ?? 0,
            promptBufferBytes: max(1_024 * 1_024, Int64(contextPlan.exactInputTokens * 8)),
            metalScratchReserveBytes: Int64(legacyPlan?.runtimeZones.scratchBytes ?? 64 * 1_024 * 1_024),
            uiReserveBytes: Int64(legacyPlan?.runtimeZones.uiReserveBytes ?? 256 * 1_024 * 1_024),
            contextAssemblyPlanID: contextPlan.id
        )

        return LocalRuntimeAdmissionService().admit(admissionRequest)
    }

    private static func incrementalModelWeightBytesForGenerationAdmission(
        install: ModelInstall?,
        memoryCounters: RuntimeMemoryCounters
    ) -> Int64 {
        let mlxActive = memoryCounters.mlxActiveMemoryBytes ?? 0
        let processFootprint = memoryCounters.processPhysicalFootprintBytes ?? 0
        let processResident = memoryCounters.processResidentMemoryBytes ?? 0
        let modelAppearsLoaded = mlxActive > 0
            || processFootprint > 512 * 1_024 * 1_024
            || processResident > 512 * 1_024 * 1_024
        guard !modelAppearsLoaded else { return 0 }
        return install?.estimatedBytes ?? 0
    }

    fileprivate static func localFailureKind(from error: Error) -> LocalInferenceFailureKind {
        if let inferenceError = error as? InferenceError {
            switch inferenceError {
            case .invalidRequest:
                return .contextWindowExceeded
            case .cloudNotAllowed:
                return .cloudRouteDisallowed
            case .localRuntimeFailure:
                break
            case .providerUnavailable, .modelNotLoaded, .unsupportedCapability, .cancelled:
                break
            }
        }
        let message = String(describing: error).lowercased()
        if message.contains("fallback budget") || message.contains("budget exceeded") {
            return .fallbackBudgetExceeded
        }
        if message.contains("fallback") {
            return .turboQuantFallbackUnavailable
        }
        if message.contains("unsupported attention shape") || message.contains("head dimension") {
            return .unsupportedAttentionShape
        }
        if message.contains("unsupported attention mask") || message.contains("mask") {
            return .unsupportedAttentionMask
        }
        if message.contains("unsupported tensor dtype") || message.contains("dtype") {
            return .unsupportedTensorDType
        }
        if message.contains("layout") {
            return .cacheLayoutInvalid
        }
        if message.contains("lifecycle") {
            return .cacheLifecycleInvalid
        }
        if message.contains("profile mismatch") {
            return .modelProfileMismatch
        }
        if message.contains("profile") && message.contains("unverified") {
            return .modelProfileUnverified
        }
        if message.contains("compressed attention") || message.contains("turboquant") {
            return .turboQuantPathUnavailable
        }
        return .mlxRuntimeFailure
    }

    #if canImport(MLXLMCommon)
    fileprivate static func appendTurboQuantWave2Metadata(
        to metadata: inout [String: String],
        cache: [KVCache]?,
        request: ChatRequest,
        install: ModelInstall?,
        profile: RuntimeProfile,
        contextPlan: ContextAssemblyPlan?,
        admissionPlan: LocalRuntimeAdmissionPlan?,
        memoryCounters: RuntimeMemoryCounters,
        outcome: RuntimeMemoryCalibrationOutcome,
        failureKind: LocalInferenceFailureKind? = nil,
        failureMessage: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        speculativeTelemetry: TurboQuantSpeculativeTelemetry? = nil,
        speculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision? = nil
    ) {
        guard profile.quantization.kvCacheStrategy == .turboQuant
            || admissionPlan != nil
            || contextPlan != nil
            || speculativeTelemetry != nil
        else { return }

        let turboQuantPlanned = profile.quantization.kvCacheStrategy == .turboQuant
        let snapshot = cache?.compactMap { ($0 as? TurboQuantCompressedKVCacheProtocol)?.runtimeSnapshot() }.first
        let selectedPath =
            snapshot?.lastAttentionPath.flatMap(PinesCore.TurboQuantAttentionPath.init(rawValue:))
            ?? admissionPlan?.selectedAttentionPath
            ?? (turboQuantPlanned ? profile.quantization.activeAttentionPath : nil)
        let fallbackReason =
            failureMessage
            ?? snapshot?.lastFailure
            ?? metadata[LocalProviderMetadataKeys.turboQuantFallbackReason]
            ?? profile.quantization.activeFallbackReason
        let fallbackUsed =
            fallbackReason != nil
            || snapshot?.packedFallbackAllocated == true
            || selectedPath == .mlxPackedFallback
            || selectedPath == .baseline
        let estimatedCompressedBytes = admissionPlan?.memoryZones.compressedKVBytes
            ?? Int64(profile.quantization.turboQuantAdmission?.memoryPlan?.runtimeZones.compressedKVBytes ?? 0)
        let estimatedFallbackBytes =
            (admissionPlan?.memoryZones.packedFallbackBytes ?? 0)
            + (admissionPlan?.memoryZones.decodedFallbackScratchBytes ?? 0)
        let estimatedScratchBytes = admissionPlan?.memoryZones.metalScratchReserveBytes ?? 0
        let actualCompressedBytes = snapshot.map { Int64($0.keyBytes + $0.valueBytes) }
        let actualFallbackBytes = snapshot?.packedFallbackAllocated == true ? estimatedFallbackBytes : nil
        let calibrationSample = RuntimeMemoryCalibrationSample(
            compatibilityPairID: Self.turboQuantCompatibilityPairID,
            runOutcome: outcome,
            rejectionReason: failureKind?.rawValue,
            modelID: install?.repository ?? request.modelID.rawValue,
            modelRevision: install?.revision,
            deviceClass: memoryCounters.devicePerformanceClass
                ?? profile.quantization.devicePerformanceClass
                ?? .futureVerified,
            userMode: admissionPlan?.selectedMode ?? profile.quantization.turboQuantUserMode,
            attentionPath: selectedPath,
            requestedContextTokens: admissionPlan?.requestedContextTokens
                ?? profile.quantization.maxKVSize
                ?? contextPlan?.exactInputTokens
                ?? 0,
            admittedContextTokens: admissionPlan?.admittedContextTokens
                ?? profile.quantization.maxKVSize
                ?? 0,
            estimatedCompressedKVBytes: estimatedCompressedBytes,
            actualCompressedKVBytes: actualCompressedBytes,
            estimatedFallbackBytes: estimatedFallbackBytes,
            actualFallbackBytes: actualFallbackBytes,
            estimatedScratchBytes: estimatedScratchBytes,
            observedPeakMemoryBytes: memoryCounters.mlxPeakMemoryBytes
                ?? memoryCounters.processPeakResidentMemoryBytes,
            availableMemoryAtAdmission: memoryCounters.availableMemoryBytes ?? 0,
            availableMemoryAtPrefillEnd: memoryCounters.availableMemoryBytes,
            availableMemoryAtDecodeEnd: memoryCounters.availableMemoryBytes,
            memoryWarningsSeen: 0
        )
        let decision = TurboQuantRunDecision(
            compatibilityPairID: Self.turboQuantCompatibilityPairID,
            admission: admissionPlan,
            selectedAttentionPath: selectedPath,
            rejectedPaths: failureKind.map {
                [RejectedPath(path: selectedPath?.rawValue ?? "local-runtime", reason: $0.rawValue)]
            } ?? [],
            cacheLifecycle: snapshot?.lifecycleDescription,
            fallbackUsed: fallbackUsed,
            fallbackReason: fallbackUsed ? fallbackReason : nil,
            rawShadowAllocated: snapshot?.rawShadowAllocated
                ?? profile.quantization.rawFallbackAllocated,
            packedFallbackAllocated: snapshot?.packedFallbackAllocated,
            compressedKeyBytes: snapshot.map { Int64($0.keyBytes) },
            compressedValueBytes: snapshot.map { Int64($0.valueBytes) },
            inputTokens: inputTokens ?? contextPlan?.exactInputTokens,
            outputTokens: outputTokens,
            speculativeTelemetry: speculativeTelemetry,
            speculativeAutoDisableDecision: speculativeAutoDisableDecision,
            contextAssemblyPlanID: contextPlan?.id,
            memoryCalibrationSampleID: calibrationSample.id.uuidString
        )

        metadata[LocalProviderMetadataKeys.turboQuantCloudRetryPermitted] =
            String(admissionPlan?.fallbackContract.allowCloudRetry ?? false)
        metadata[LocalProviderMetadataKeys.turboQuantCloudFallbackSuppressed] =
            String(!(admissionPlan?.fallbackContract.allowCloudRetry ?? false))
        if let contextPlan {
            metadata[LocalProviderMetadataKeys.turboQuantContextAssemblyPlanID] = contextPlan.id
            metadata[LocalProviderMetadataKeys.turboQuantContextAssemblyPlanJSON] = metadataJSON(contextPlan)
        }
        if let admissionPlan {
            metadata[LocalProviderMetadataKeys.turboQuantAdmissionPlanJSON] = metadataJSON(admissionPlan)
            metadata[LocalProviderMetadataKeys.turboQuantFallbackContractHash] =
                admissionPlan.fallbackContract.contractHash
            metadata[LocalProviderMetadataKeys.turboQuantSelectedMode] = admissionPlan.selectedMode.rawValue
            metadata[LocalProviderMetadataKeys.turboQuantAdmittedContext] =
                String(admissionPlan.admittedContextTokens)
            metadata[LocalProviderMetadataKeys.turboQuantRuntimeBudgetBytes] =
                String(admissionPlan.memoryZones.totalPlannedBytes)
            metadata[LocalProviderMetadataKeys.turboQuantRuntimeHeadroomBytes] =
                String(admissionPlan.memoryCushionBytes)
            metadata[LocalProviderMetadataKeys.turboQuantCompressedKVBytes] =
                String(admissionPlan.memoryZones.compressedKVBytes)
            metadata[LocalProviderMetadataKeys.turboQuantFallbackReserveBytes] =
                String(
                    admissionPlan.memoryZones.packedFallbackBytes
                    + admissionPlan.memoryZones.decodedFallbackScratchBytes
                )
        }
        if let speculativeTelemetry {
            appendSpeculativeMetadata(
                to: &metadata,
                telemetry: speculativeTelemetry,
                decision: speculativeAutoDisableDecision
            )
        }
        metadata[LocalProviderMetadataKeys.turboQuantRunDecisionID] = decision.decisionID
        metadata[LocalProviderMetadataKeys.turboQuantRunDecisionJSON] = metadataJSON(decision)
        metadata[LocalProviderMetadataKeys.turboQuantMemoryCalibrationSampleID] =
            calibrationSample.id.uuidString
        metadata[LocalProviderMetadataKeys.turboQuantMemoryCalibrationSampleJSON] =
            metadataJSON(calibrationSample)

        if let failureKind, let failureMessage {
            let failureEvent = LocalInferenceFailureEvent(
                kind: failureKind,
                sourceRepo: "pines",
                sourceType: "MLXRuntimeBridge",
                message: failureMessage,
                recoverable: false,
                recommendedAction: LocalInferenceFailureMatrix.rulesByKind[failureKind]?.productMessage,
                admissionPlanID: nil,
                runDecisionID: decision.decisionID
            )
            metadata[LocalProviderMetadataKeys.turboQuantFailureEventJSON] =
                metadataJSON(failureEvent)
        }
    }

    fileprivate static func speculativeTelemetry(
        from info: GenerateCompletionInfo?,
        profile: RuntimeProfile
    ) -> (
        telemetry: TurboQuantSpeculativeTelemetry?,
        decision: TurboQuantSpeculativeAutoDisableDecision?
    ) {
        guard let metrics = info?.speculativeAcceptanceMetrics else {
            return (nil, nil)
        }
        let settings = profile.speculativeSettings ?? profile.quantization.turboQuantSpeculativeSettings
        guard profile.quantization.kvCacheStrategy == .turboQuant
            || profile.speculativeDecodingEnabled
            || settings?.enabled == true
        else {
            return (nil, nil)
        }
        let dimensions = TurboQuantSpeculativeEvidenceDimensions(
            enabled: true,
            draftModelID: settings?.draftModelID ?? profile.speculativeDraftModelID?.rawValue,
            draftModelRevision: settings?.draftModelRevision,
            tokenizerCompatible: settings?.requireTokenizerCompatibility == false ? nil : true,
            maxDraftTokens: settings?.maxDraftTokens
        )
        let telemetry = TurboQuantSpeculativeTelemetry(
            state: .active,
            dimensions: dimensions,
            proposedTokenCount: metrics.proposedDraftTokens,
            acceptedTokenCount: metrics.acceptedDraftTokens,
            rejectedTokenCount: metrics.rejectedDraftTokens,
            targetVerifiedTokenCount: metrics.emittedTokens,
            rollbackCount: 0,
            targetSequenceMatched: true,
            tokenizerCompatible: dimensions.tokenizerCompatible
        )
        let policy = settings?.autoDisablePolicy ?? .productDefault
        return (telemetry, policy.evaluate(telemetry))
    }

    fileprivate static func appendSpeculativeMetadata(
        to metadata: inout [String: String],
        telemetry: TurboQuantSpeculativeTelemetry,
        decision: TurboQuantSpeculativeAutoDisableDecision?
    ) {
        metadata[LocalProviderMetadataKeys.turboQuantSpeculativeState] = telemetry.state.rawValue
        metadata[LocalProviderMetadataKeys.turboQuantSpeculativeEnabled] =
            String(telemetry.dimensions.enabled)
        if let draftModelID = telemetry.dimensions.draftModelID {
            metadata[LocalProviderMetadataKeys.turboQuantSpeculativeDraftModelID] = draftModelID
        }
        if let draftModelRevision = telemetry.dimensions.draftModelRevision {
            metadata[LocalProviderMetadataKeys.turboQuantSpeculativeDraftModelRevision] =
                draftModelRevision
        }
        if let pairingHash = telemetry.dimensions.pairingHash {
            metadata[LocalProviderMetadataKeys.turboQuantSpeculativePairingHash] = pairingHash
        }
        if let tokenizerCompatible = telemetry.tokenizerCompatible {
            metadata[LocalProviderMetadataKeys.turboQuantSpeculativeTokenizerCompatible] =
                String(tokenizerCompatible)
        }
        if let acceptanceRate = telemetry.acceptanceRate {
            metadata[LocalProviderMetadataKeys.turboQuantSpeculativeAcceptanceRate] =
                String(acceptanceRate)
        }
        metadata[LocalProviderMetadataKeys.turboQuantSpeculativeProposedTokens] =
            String(telemetry.proposedTokenCount)
        metadata[LocalProviderMetadataKeys.turboQuantSpeculativeAcceptedTokens] =
            String(telemetry.acceptedTokenCount)
        metadata[LocalProviderMetadataKeys.turboQuantSpeculativeRejectedTokens] =
            String(telemetry.rejectedTokenCount)
        metadata[LocalProviderMetadataKeys.turboQuantSpeculativeRollbackCount] =
            String(telemetry.rollbackCount)
        if let disabledReason = telemetry.disabledReason {
            metadata[LocalProviderMetadataKeys.turboQuantSpeculativeDisableReason] =
                disabledReason.rawValue
        }
        metadata[LocalProviderMetadataKeys.turboQuantSpeculativeTelemetryJSON] =
            metadataJSON(telemetry)
        if let decision {
            if decision.shouldDisable {
                metadata[LocalProviderMetadataKeys.turboQuantSpeculativeDisableReason] =
                    decision.reason.rawValue
            }
            metadata[LocalProviderMetadataKeys.turboQuantSpeculativeAutoDisableJSON] =
                metadataJSON(decision)
        }
    }
    #endif

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

    func defaultRuntimeProfile(
        for install: ModelInstall,
        userMode: PinesCore.TurboQuantUserMode = .balanced,
        requestedContextLength: Int? = nil
    ) -> RuntimeProfile {
        let deviceProfile = deviceMonitor.currentProfile()
        let memoryCounters = deviceMonitor.memoryCounters()
        let effectiveModalities = install.effectiveTurboQuantModalities
        let hasVision = effectiveModalities.contains(.vision)
        let isCompact = deviceProfile.memoryTier == .compact
        let isSmallTextModel = install.isSmallTextGenerationModel
        let recommendedMaxKVSize = hasVision
            ? min(deviceProfile.recommendedContextTokens, 4096)
            : (isSmallTextModel ? deviceProfile.recommendedSmallModelContextTokens : deviceProfile.recommendedContextTokens)
        let backend = turboQuantBackendSnapshot()
        let linked = isLinked
        let usesTurboQuant = Self.usesTurboQuantByDefault(for: install)
        let turboQuantDisabledReason = Self.turboQuantDefaultDisabledReason(for: install)
        let normalizedRequestedContextLength = AppSettingsSnapshot.normalizedLocalContextTokens(
            requestedContextLength ?? (usesTurboQuant ? recommendedMaxKVSize : min(recommendedMaxKVSize, 8192))
        )
        let requestedMaxKVSize = usesTurboQuant
            ? normalizedRequestedContextLength
            : min(normalizedRequestedContextLength, recommendedMaxKVSize, 8192)
        let fallbackReason = usesTurboQuant
            ? backend.fallbackReason
            : turboQuantDisabledReason
                ?? "Using plain MLX KV cache because TurboQuant is not applicable to this install."
        let turboQuantDefaults = usesTurboQuant
            ? Self.turboQuantRuntimeDefaults(
                for: install,
                contextLength: requestedMaxKVSize,
                deviceOptimizationPolicy: deviceProfile.turboQuantOptimizationPolicy
            )
            : nil
        let admission = Self.kvCacheAdmission(
            for: install,
            requestedTurboQuant: usesTurboQuant,
            requestedMaxKVSize: requestedMaxKVSize,
            userMode: userMode,
            backend: backend,
            defaults: turboQuantDefaults,
            turboQuantDisabledReason: turboQuantDisabledReason,
            memoryCounters: memoryCounters
        )
        var turboQuantProfileDiagnostics = [
            "TurboQuant family support stored=\(install.turboQuantFamilySupport.rawValue) effective=\(install.effectiveTurboQuantFamilySupport.rawValue)",
            "TurboQuant runtime selection=\(usesTurboQuant ? "throwing_attention" : "plain_kv")",
        ]
        if let turboQuantDisabledReason {
            turboQuantProfileDiagnostics.append(turboQuantDisabledReason)
        }
        turboQuantProfileDiagnostics.append(contentsOf: admission.diagnostics)
        let profile = RuntimeProfile(
            name: hasVision ? "Vision \(userMode.displayName)" : "Local \(userMode.displayName)",
            quantization: QuantizationProfile(
                weightBits: install.repository.localizedCaseInsensitiveContains("4bit") ? 4 : nil,
                kvBits: nil,
                kvGroupSize: admission.useTurboQuant ? turboQuantDefaults?.groupSize ?? 64 : 64,
                quantizedKVStart: 0,
                maxKVSize: admission.maxKVSize,
                algorithm: admission.useTurboQuant ? .turboQuant : .none,
                kvCacheStrategy: admission.useTurboQuant ? .turboQuant : .none,
                preset: admission.useTurboQuant ? turboQuantDefaults?.preset : nil,
                requestedBackend: admission.useTurboQuant ? (turboQuantDefaults?.requestedBackend ?? backend.requested) : nil,
                activeBackend: admission.useTurboQuant && linked ? backend.active : nil,
                metalCodecAvailable: admission.useTurboQuant && linked && backend.metalCodecAvailable,
                metalAttentionAvailable: admission.useTurboQuant && linked && backend.metalAttentionAvailable,
                activeAttentionPath: admission.useTurboQuant && linked ? backend.activeAttentionPath : .baseline,
                metalKernelProfile: admission.useTurboQuant && linked ? backend.kernelProfile : nil,
                metalSelfTestStatus: admission.useTurboQuant && linked ? backend.selfTestStatus : nil,
                metalSelfTestFailureReason: admission.useTurboQuant ? backend.selfTestFailureReason : nil,
                rawFallbackAllocated: admission.useTurboQuant ? backend.rawFallbackAllocated : false,
                devicePerformanceClass: deviceProfile.performanceClass,
                turboQuantOptimizationPolicy: turboQuantDefaults?.optimizationPolicy
                    ?? deviceProfile.turboQuantOptimizationPolicy,
                turboQuantValueBits: admission.useTurboQuant ? turboQuantDefaults?.valueBits : nil,
                turboQuantLayoutVersion: admission.useTurboQuant ? Self.turboQuantLayoutVersion : nil,
                thermalDownshiftActive: deviceProfile.thermalDownshiftActive,
                runtimePressureReason: deviceProfile.runtimePressureReason,
                turboQuantProfileID: admission.useTurboQuant ? turboQuantDefaults?.profileID : nil,
                turboQuantProfileSource: turboQuantDefaults?.profileSource,
                turboQuantProfileDiagnostics: turboQuantProfileDiagnostics,
                lastUnsupportedAttentionShape: admission.useTurboQuant ? backend.lastUnsupportedAttentionShape : nil,
                activeFallbackReason: admission.reason ?? (linked ? fallbackReason : "MLX runtime packages are not linked in this build."),
                memoryCounters: memoryCounters,
                turboQuantUserMode: userMode,
                turboQuantAdmission: admission.admission
            ),
            streamExperts: false,
            expertStreamingMode: .disabled,
            gpuLayerCount: nil,
            mtpEnabled: false,
            audioEnabled: effectiveModalities.contains(.audio),
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
        TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
            repository: install.repository,
            modelType: install.modelType,
            textConfigModelType: install.textConfigModelType,
            modalities: install.effectiveTurboQuantModalities,
            familySupport: install.effectiveTurboQuantFamilySupport,
            runtimeCapabilities: Self.turboQuantRuntimeCapabilities
        )
    }

    private static func turboQuantDefaultDisabledReason(for install: ModelInstall) -> String? {
        TurboQuantRuntimeSupport.defaultDisabledReason(
            repository: install.repository,
            modelType: install.modelType,
            textConfigModelType: install.textConfigModelType,
            modalities: install.effectiveTurboQuantModalities,
            familySupport: install.effectiveTurboQuantFamilySupport,
            runtimeCapabilities: Self.turboQuantRuntimeCapabilities
        )
    }

    private struct TurboQuantRuntimeDefaults {
        var preset: PinesCore.TurboQuantPreset
        var requestedBackend: PinesCore.TurboQuantRuntimeBackend
        var groupSize: Int
        var valueBits: Int?
        var optimizationPolicy: PinesCore.TurboQuantOptimizationPolicy
        var profileID: String?
        var profileSource: String
        var profileDiagnostics: [String]
    }

    private struct KVCacheAdmission {
        var useTurboQuant: Bool
        var maxKVSize: Int
        var reason: String?
        var diagnostics: [String]
        var admission: PinesCore.TurboQuantAdmission?
    }

    private static func kvCacheAdmission(
        for install: ModelInstall,
        requestedTurboQuant: Bool,
        requestedMaxKVSize: Int,
        userMode: PinesCore.TurboQuantUserMode,
        backend: (
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
        ),
        defaults: TurboQuantRuntimeDefaults?,
        turboQuantDisabledReason: String?,
        memoryCounters: RuntimeMemoryCounters
    ) -> KVCacheAdmission {
        var diagnostics = defaults?.profileDiagnostics ?? []
        guard requestedTurboQuant else {
            let reason = turboQuantDisabledReason
                ?? "plain KV selected because this install does not advertise TurboQuant-compatible attention KV support"
            diagnostics.append(reason)
            return KVCacheAdmission(
                useTurboQuant: false,
                maxKVSize: min(requestedMaxKVSize, 8192),
                reason: reason,
                diagnostics: diagnostics,
                admission: nil
            )
        }

        let productAdmission = mobileTurboQuantAdmission(
            for: install,
            requestedContextLength: requestedMaxKVSize,
            userMode: userMode,
            defaults: defaults,
            memoryCounters: memoryCounters
        )
        diagnostics.append(productAdmission.userMessage)
        if let primaryDowngrade = productAdmission.primaryDowngradeReason {
            diagnostics.append("Admission downgrade: \(primaryDowngrade.rawValue)")
        }
        guard productAdmission.admitted else {
            return KVCacheAdmission(
                useTurboQuant: true,
                maxKVSize: 0,
                reason: productAdmission.userMessage,
                diagnostics: diagnostics,
                admission: productAdmission
            )
        }

        let smallDenseOrHybridModel = (install.resolvedParameterCount ?? Int64.max) <= 2_500_000_000
        if backend.metalAttentionAvailable == false,
           smallDenseOrHybridModel {
            let reason = backend.fallbackReason
                ?? "plain rotating KV selected because TurboQuant Metal attention is unavailable for this small local model"
            diagnostics.append(reason)
            return KVCacheAdmission(
                useTurboQuant: false,
                maxKVSize: min(productAdmission.admittedContextLength, 8192),
                reason: reason,
                diagnostics: diagnostics,
                admission: productAdmission
            )
        }

        diagnostics.append("TurboQuant admitted for compressed attention KV")
        return KVCacheAdmission(
            useTurboQuant: true,
            maxKVSize: productAdmission.admittedContextLength,
            reason: backend.fallbackReason ?? productAdmission.userMessage,
            diagnostics: diagnostics,
            admission: productAdmission
        )
    }

    private static func mobileTurboQuantAdmission(
        for install: ModelInstall,
        requestedContextLength: Int,
        userMode: PinesCore.TurboQuantUserMode,
        defaults: TurboQuantRuntimeDefaults?,
        memoryCounters: RuntimeMemoryCounters
    ) -> PinesCore.TurboQuantAdmission {
        #if canImport(MLXLMCommon) && canImport(MLX)
        if let memoryProfile = mlxModelMemoryProfile(for: install) {
            let planner = MLXLMCommon.TurboQuantAdmissionPlanner()
            let memorySample = mlxAdmissionMemorySample(
                counters: memoryCounters,
                modelResidentBytes: memoryProfile.resolvedWeightBytes
            )
            let admission = planner.admit(
                profile: memoryProfile,
                requestedContextLength: requestedContextLength,
                userMode: mlxTurboQuantUserMode(from: userMode),
                fallbackPolicy: mlxTurboQuantFallbackPolicy(
                    from: TurboQuantFallbackContract.productDefault(for: userMode)
                ),
                preset: mlxTurboQuantAdmissionPreset(from: defaults?.preset ?? .conservativeFallback),
                valueBits: defaults?.valueBits,
                groupSize: defaults?.groupSize ?? 64,
                memorySample: memorySample
            )
            return coreTurboQuantAdmission(from: admission)
        }
        #endif

        return heuristicTurboQuantAdmission(
            for: install,
            requestedContextLength: requestedContextLength,
            userMode: userMode,
            defaults: defaults,
            memoryCounters: memoryCounters
        )
    }

    private static func heuristicTurboQuantAdmission(
        for install: ModelInstall,
        requestedContextLength: Int,
        userMode: PinesCore.TurboQuantUserMode,
        defaults: TurboQuantRuntimeDefaults?,
        memoryCounters: RuntimeMemoryCounters
    ) -> PinesCore.TurboQuantAdmission {
        let requestedContext = max(1, requestedContextLength)
        let available = intClamped(memoryCounters.availableMemoryBytes)
            ?? intClamped(memoryCounters.physicalMemoryBytes).map { max(0, $0 / 2) }
            ?? 4 * 1024 * 1024 * 1024
        let safetyReserve = min(available, max(512 * 1024 * 1024, available / 5))
        let runtimeBudget = max(0, available - safetyReserve)
        let preset = defaults?.preset ?? .conservativeFallback
        let valueBits = defaults?.valueBits ?? preset.defaultValueBits
        let groupSize = max(1, defaults?.groupSize ?? 64)
        let shape = heuristicModelShape(for: install)
        let bytesPerElement = 2
        let rawBytesPerToken = 2 * bytesPerElement * shape.layerCount * shape.kvHeadCount * shape.headDimension
        let compressedBytesPerToken = max(
            1,
            Int(
                (Double(rawBytesPerToken) * max(2.0, Double(valueBits)) / 16.0)
                    + Double(shape.layerCount * shape.kvHeadCount * ((shape.headDimension + groupSize - 1) / groupSize) * 24)
            )
        )
        let packedFallbackBytesPerToken = max(1, compressedBytesPerToken * 2)
        let modelResidentBytes = intClamped(install.estimatedBytes) ?? intClamped(memoryCounters.mlxActiveMemoryBytes) ?? 0
        let mlxCacheBytes = intClamped(memoryCounters.mlxCacheMemoryBytes) ?? 0
        let mlxActiveBytes = intClamped(memoryCounters.mlxActiveMemoryBytes) ?? 0
        let promptAndTokenizerBytes = 64 * 1024 * 1024
        let uiReserveBytes = 256 * 1024 * 1024
        let scratchBytes = max(96 * 1024 * 1024, rawBytesPerToken * min(requestedContext, 512) / max(1, shape.layerCount))
        var downgrades: [PinesCore.TurboQuantAdmissionDowngrade] = []
        var selectedMode = userMode
        var admittedContext = requestedContext
        var usesRawShadow = userMode == .balanced || userMode == .fastest
        var packedFallbackEnabled = userMode == .balanced
        var usesRollingSummary = false
        var selectedPreset = preset
        var selectedValueBits = valueBits

        if memoryCounters.lowPowerModeEnabled == true || memoryCounters.runtimePressureReason?.isThermal == true {
            selectedMode = userMode == .balanced ? .batterySaver : userMode
            if selectedMode == .batterySaver {
                downgrades.append(
                    .init(
                        reason: .thermalOrBatterySaver,
                        message: "Selected Battery Saver settings because power or thermal state is constrained."
                    )
                )
                admittedContext = min(admittedContext, 4096)
                usesRawShadow = false
                packedFallbackEnabled = false
            }
        }

        switch selectedMode {
        case .fastest:
            admittedContext = min(admittedContext, 8192)
            selectedValueBits = max(selectedValueBits, preset.defaultValueBits)
            packedFallbackEnabled = false
        case .balanced:
            break
        case .maxContext:
            selectedPreset = .turbo2_5
            selectedValueBits = min(selectedValueBits, 2)
            usesRawShadow = false
            packedFallbackEnabled = false
        case .batterySaver:
            admittedContext = min(admittedContext, 4096)
            selectedValueBits = min(selectedValueBits, 4)
            usesRawShadow = false
            packedFallbackEnabled = false
        }

        func makePlan(context: Int, rawShadow: Bool, packedFallback: Bool, rollingSummary: Bool) -> PinesCore.TurboQuantMemoryPlan {
            let currentCompressedBytesPerToken = max(
                1,
                Int(
                    (Double(rawBytesPerToken) * max(2.0, Double(selectedValueBits)) / 16.0)
                        + Double(shape.layerCount * shape.kvHeadCount * ((shape.headDimension + groupSize - 1) / groupSize) * 24)
                )
            )
            let rawShadowBytes = rawShadow ? rawBytesPerToken * min(context, 512) : 0
            let fallbackReserveBytes = packedFallback ? packedFallbackBytesPerToken * context : rawBytesPerToken * min(context, 512) / max(1, shape.layerCount)
            let rollingBytes = rollingSummary ? 16 * 1024 * 1024 : 0
            let footprint = PinesCore.TurboQuantLayerCacheFootprint(
                layerCount: shape.layerCount,
                kvHeadCount: shape.kvHeadCount,
                headDimension: shape.headDimension,
                groupSize: groupSize,
                preset: selectedPreset,
                valueBits: selectedValueBits,
                groupsPerVector: (shape.headDimension + groupSize - 1) / groupSize,
                bitsetWordsPerGroup: (groupSize + 31) / 32,
                keyMagnitudeWordsPerGroup: max(1, (groupSize * selectedPreset.baseBits + 31) / 32),
                valueMagnitudeWordsPerGroup: max(1, (groupSize * selectedValueBits + 31) / 32),
                keyBytesPerTokenPerLayer: currentCompressedBytesPerToken / max(1, shape.layerCount * 2),
                valueBytesPerTokenPerLayer: currentCompressedBytesPerToken / max(1, shape.layerCount * 2),
                bytesPerTokenPerLayer: currentCompressedBytesPerToken / max(1, shape.layerCount),
                bytesPerTokenAllLayers: currentCompressedBytesPerToken,
                actualBitsPerValue: Double(currentCompressedBytesPerToken * 8) / Double(max(1, shape.layerCount * shape.kvHeadCount * shape.headDimension * 2))
            )
            let zones = PinesCore.TurboQuantRuntimeMemoryZones(
                availableAppMemoryBytes: available,
                runtimeBudgetBytes: runtimeBudget,
                mlxActiveBytes: mlxActiveBytes,
                mlxCacheBytes: mlxCacheBytes,
                modelResidentBytes: max(modelResidentBytes, mlxActiveBytes),
                compressedKVBytes: currentCompressedBytesPerToken * context,
                rawShadowBytes: rawShadowBytes,
                fallbackReserveBytes: fallbackReserveBytes,
                scratchBytes: scratchBytes,
                promptAndTokenizerBytes: promptAndTokenizerBytes,
                uiReserveBytes: uiReserveBytes,
                safetyReserveBytes: safetyReserve,
                rollingSummaryBytes: rollingBytes
            )
            return PinesCore.TurboQuantMemoryPlan(
                requestedContextLength: requestedContext,
                admittedContextLength: context,
                requestedMode: userMode,
                effectiveMode: selectedMode,
                preset: selectedPreset,
                valueBits: selectedValueBits,
                groupSize: groupSize,
                fallbackPolicy: coreTurboQuantFallbackPolicy(
                    from: TurboQuantFallbackContract.productDefault(for: selectedMode)
                ),
                rawBytesPerToken: rawBytesPerToken,
                packedFallbackBytesPerToken: packedFallbackBytesPerToken,
                compressedBytesPerToken: currentCompressedBytesPerToken,
                layerFootprint: footprint,
                usesRawShadow: rawShadow,
                packedFallbackEnabled: packedFallback,
                usesRollingSummaryMemory: rollingSummary,
                runtimeZones: zones
            )
        }

        var plan = makePlan(context: admittedContext, rawShadow: usesRawShadow, packedFallback: packedFallbackEnabled, rollingSummary: usesRollingSummary)
        if plan.runtimeZones.totalRuntimeBytes > available, usesRawShadow {
            usesRawShadow = false
            downgrades.append(.init(reason: .releasedRawShadow, message: "Released the raw prefill shadow reserve."))
            plan = makePlan(context: admittedContext, rawShadow: usesRawShadow, packedFallback: packedFallbackEnabled, rollingSummary: usesRollingSummary)
        }
        if plan.runtimeZones.totalRuntimeBytes > available, packedFallbackEnabled {
            packedFallbackEnabled = false
            downgrades.append(.init(reason: .disabledPackedFallback, message: "Disabled the packed fallback reserve."))
            plan = makePlan(context: admittedContext, rawShadow: usesRawShadow, packedFallback: packedFallbackEnabled, rollingSummary: usesRollingSummary)
        }
        if plan.runtimeZones.totalRuntimeBytes > available, selectedValueBits > 2 {
            selectedValueBits = 2
            selectedPreset = .turbo2_5
            downgrades.append(.init(reason: .loweredValueBits, message: "Lowered TurboQuant value bits to 2."))
            plan = makePlan(context: admittedContext, rawShadow: usesRawShadow, packedFallback: packedFallbackEnabled, rollingSummary: usesRollingSummary)
        }
        if plan.runtimeZones.totalRuntimeBytes > available, selectedMode == .balanced {
            selectedMode = .maxContext
            selectedPreset = .turbo2_5
            selectedValueBits = 2
            usesRawShadow = false
            packedFallbackEnabled = false
            downgrades.append(.init(reason: .movedBalancedToMaxContext, message: "Moved Balanced mode to Max Context memory settings."))
            plan = makePlan(context: admittedContext, rawShadow: usesRawShadow, packedFallback: packedFallbackEnabled, rollingSummary: usesRollingSummary)
        }
        if plan.runtimeZones.totalRuntimeBytes > available {
            let fixedBytes = plan.runtimeZones.totalRuntimeBytes - plan.runtimeZones.compressedKVBytes
            let possibleContext = max(0, (available - fixedBytes) / max(1, plan.compressedBytesPerToken))
            if possibleContext >= AppSettingsSnapshot.minLocalContextTokens, possibleContext < admittedContext {
                admittedContext = possibleContext
                downgrades.append(.init(reason: .reducedContext, message: "Reduced admitted context to \(admittedContext) tokens."))
                plan = makePlan(context: admittedContext, rawShadow: usesRawShadow, packedFallback: packedFallbackEnabled, rollingSummary: usesRollingSummary)
            }
        }
        if plan.runtimeZones.totalRuntimeBytes > available {
            admittedContext = min(admittedContext, 1024)
            usesRollingSummary = true
            downgrades.append(.init(reason: .rollingSummaryMemory, message: "Using rolling summary memory for older turns."))
            plan = makePlan(context: admittedContext, rawShadow: usesRawShadow, packedFallback: packedFallbackEnabled, rollingSummary: usesRollingSummary)
        }
        guard plan.runtimeZones.totalRuntimeBytes <= available else {
            let message = "This model cannot safely run at the requested context on the current memory budget. Reduce context, switch models, or free memory before generation."
            let refusal = PinesCore.TurboQuantAdmissionDowngrade(reason: .refusedInsufficientMemory, message: message)
            return PinesCore.TurboQuantAdmission(
                admitted: false,
                requestedContextLength: requestedContext,
                admittedContextLength: 0,
                requestedMode: userMode,
                selectedMode: selectedMode,
                memoryPlan: plan,
                downgradeReasons: downgrades + [refusal],
                rejectedPaths: [.init(path: "pines-mobile-admission", reason: message)],
                userMessage: message
            )
        }

        let contextPart = admittedContext == requestedContext
            ? "\(admittedContext) tokens"
            : "\(admittedContext) of \(requestedContext) requested tokens"
        let downgradePart = downgrades.isEmpty
            ? "No memory downgrade was needed."
            : downgrades.map(\.message).joined(separator: " ")
        return PinesCore.TurboQuantAdmission(
            admitted: true,
            requestedContextLength: requestedContext,
            admittedContextLength: admittedContext,
            requestedMode: userMode,
            selectedMode: selectedMode,
            memoryPlan: plan,
            downgradeReasons: downgrades,
            rejectedPaths: [],
            userMessage: "TurboQuant can run \(contextPart) in \(selectedMode.rawValue) mode. \(downgradePart)"
        )
    }

    fileprivate static func heuristicModelShape(for install: ModelInstall) -> (
        layerCount: Int,
        kvHeadCount: Int,
        headDimension: Int
    ) {
        let parameterCount = install.resolvedParameterCount ?? 3_000_000_000
        let headDimension = install.keyHeadDimension ?? install.valueHeadDimension ?? 128
        let totalLayerCount: Int
        if parameterCount <= 1_500_000_000 {
            totalLayerCount = 24
        } else if parameterCount <= 3_500_000_000 {
            totalLayerCount = 28
        } else if parameterCount <= 9_000_000_000 {
            totalLayerCount = 32
        } else {
            totalLayerCount = 48
        }
        return (
            turboQuantKVLayerCount(for: install, totalLayerCount: totalLayerCount),
            8,
            headDimension
        )
    }

    private static func turboQuantKVLayerCount(
        for install: ModelInstall,
        totalLayerCount: Int
    ) -> Int {
        guard install.cacheTopology == .hybridAttentionAndNativeState
            || install.effectiveTurboQuantFamilySupport == .hybridFull
        else {
            return max(1, totalLayerCount)
        }

        let modelTypes = [
            install.modelType?.lowercased(),
            install.textConfigModelType?.lowercased(),
            install.repository.lowercased(),
        ].compactMap { $0 }
        if modelTypes.contains(where: { $0.contains("qwen3_5") || $0.contains("qwen3.5") }) {
            return max(1, totalLayerCount / 4)
        }
        return max(1, totalLayerCount)
    }

    private static func intClamped(_ value: Int64?) -> Int? {
        guard let value else { return nil }
        if value <= 0 { return 0 }
        if value >= Int64(Int.max) { return Int.max }
        return Int(value)
    }

    private static func mlxModelMemoryProfile(for install: ModelInstall) -> MLXLMCommon.ModelMemoryProfile? {
        if let localURL = install.localURL,
           let profile = try? MLXLMCommon.ModelMemoryProfile.profile(
               modelDirectory: localURL,
               modelID: install.repository
           ) {
            return profile
        }

        let shape = heuristicModelShape(for: install)
        let hiddenSize = max(shape.headDimension, shape.headDimension * max(1, shape.kvHeadCount * 4))
        return MLXLMCommon.ModelMemoryProfile(
            modelID: install.repository,
            modelType: install.modelType ?? install.textConfigModelType ?? "unknown",
            layerCount: shape.layerCount,
            hiddenSize: hiddenSize,
            attentionHeadCount: max(1, hiddenSize / max(1, shape.headDimension)),
            kvHeadCount: shape.kvHeadCount,
            headDimension: shape.headDimension,
            quantizationBits: MLXLMCommon.ModelMemoryProfile.detectQuantizationBits(modelID: install.repository),
            isMixtureOfExperts: (install.routedExperts ?? 0) > 1,
            expertCount: install.routedExperts,
            activeExpertCount: install.expertsPerToken,
            weightBytes: intClamped(install.estimatedBytes)
        )
    }

    private static func mlxAdmissionMemorySample(
        counters: RuntimeMemoryCounters,
        modelResidentBytes: Int
    ) -> MLXLMCommon.TurboQuantRuntimeMemorySample? {
        guard let available = intClamped(counters.availableMemoryBytes), available > 0 else {
            return nil
        }
        return MLXLMCommon.TurboQuantRuntimeMemorySample(
            availableAppMemoryBytes: available,
            mlxActiveBytes: intClamped(counters.mlxActiveMemoryBytes) ?? 0,
            mlxCacheBytes: intClamped(counters.mlxCacheMemoryBytes) ?? 0,
            modelResidentBytes: max(modelResidentBytes, intClamped(counters.mlxActiveMemoryBytes) ?? 0),
            tokenizerBytes: 64 * 1024 * 1024,
            promptBytes: 0,
            uiReserveBytes: 256 * 1024 * 1024,
            thermalState: mlxTurboQuantThermalState(counters.thermalState),
            lowPowerModeEnabled: counters.lowPowerModeEnabled ?? false
        )
    }

    private static func mlxTurboQuantUserMode(
        from mode: PinesCore.TurboQuantUserMode
    ) -> MLXLMCommon.TurboQuantUserMode {
        switch mode {
        case .fastest:
            .fastest
        case .balanced:
            .balanced
        case .maxContext:
            .maxContext
        case .batterySaver:
            .batterySaver
        }
    }

    private static func mlxTurboQuantAdmissionPreset(
        from preset: PinesCore.TurboQuantPreset
    ) -> MLX.TurboQuantPreset {
        MLX.TurboQuantPreset(rawValue: preset.rawValue)
            ?? MLX.TurboQuantPreset(rawValue: PinesCore.TurboQuantPreset.conservativeFallback.rawValue)
            ?? .turbo3_5
    }

    private static func mlxTurboQuantFallbackPolicy(
        from contract: PinesCore.TurboQuantFallbackContract
    ) -> MLXLMCommon.TurboQuantFallbackPolicy {
        if contract.failIfCompressedPathUnavailable {
            return .exactRequired
        }
        if contract.allowDecodedLayerLocalFallback || contract.allowFullDecodedFallback {
            return .compressedDecodeAllowed
        }
        if contract.allowPackedFallback {
            return .packedAllowed
        }
        return .exactRequired
    }

    private static func mlxTurboQuantFallbackPolicy(
        from policy: PinesCore.TurboQuantFallbackPolicy
    ) -> MLXLMCommon.TurboQuantFallbackPolicy {
        switch policy {
        case .exactRequired:
            .exactRequired
        case .packedAllowed:
            .packedAllowed
        case .compressedDecodeAllowed:
            .compressedDecodeAllowed
        case .fatalOnFailure:
            .fatalOnFailure
        }
    }

    fileprivate static func mlxTurboQuantAdmission(
        from plan: LocalRuntimeAdmissionPlan,
        profile: RuntimeProfile,
        install: ModelInstall?
    ) -> MLXLMCommon.TurboQuantAdmission? {
        let requestedMode = mlxTurboQuantUserMode(from: profile.quantization.turboQuantUserMode)
        let selectedMode = mlxTurboQuantUserMode(from: plan.selectedMode)
        let preset = mlxTurboQuantAdmissionPreset(from: profile.quantization.preset ?? .conservativeFallback)
        let valueBits = profile.quantization.turboQuantValueBits
            ?? profile.quantization.preset?.defaultValueBits
            ?? PinesCore.TurboQuantPreset.conservativeFallback.defaultValueBits
        let groupSize = max(1, profile.quantization.kvGroupSize)
        let admittedContext = max(1, plan.admittedContextTokens)
        let shape = install.map(heuristicModelShape(for:)) ?? (layerCount: 1, kvHeadCount: 1, headDimension: 128)
        let footprint = MLXLMCommon.TurboQuantLayerCacheFootprint(
            layerCount: shape.layerCount,
            kvHeadCount: shape.kvHeadCount,
            headDimension: shape.headDimension,
            groupSize: groupSize,
            preset: preset,
            valueBits: valueBits
        )
        let compressedBytesPerToken = max(
            1,
            intClamped(plan.memoryZones.compressedKVBytes / Int64(admittedContext)) ?? footprint.bytesPerTokenAllLayers
        )
        let rawShadowTokenCount = max(1, min(admittedContext, 512))
        let rawBytesPerToken = max(
            footprint.bytesPerTokenAllLayers,
            intClamped(plan.memoryZones.rawShadowBytes / Int64(rawShadowTokenCount)) ?? footprint.bytesPerTokenAllLayers
        )
        let fallbackBytes = plan.memoryZones.packedFallbackBytes + plan.memoryZones.decodedFallbackScratchBytes
        let packedFallbackBytesPerToken = max(
            0,
            intClamped(fallbackBytes / Int64(admittedContext)) ?? 0
        )
        let availableBytes = max(
            plan.memoryZones.totalPlannedBytes,
            plan.memoryZones.totalPlannedBytes + max(0, plan.memoryCushionBytes)
        )
        let zones = MLXLMCommon.TurboQuantRuntimeMemoryZones(
            availableAppMemoryBytes: intClamped(availableBytes) ?? Int.max,
            runtimeBudgetBytes: intClamped(max(0, availableBytes - plan.memoryZones.safetyReserveBytes)) ?? Int.max,
            mlxActiveBytes: 0,
            mlxCacheBytes: 0,
            modelResidentBytes: intClamped(plan.memoryZones.modelWeightsBytes) ?? 0,
            compressedKVBytes: intClamped(plan.memoryZones.compressedKVBytes) ?? 0,
            rawShadowBytes: intClamped(plan.memoryZones.rawShadowBytes) ?? 0,
            fallbackReserveBytes: intClamped(fallbackBytes) ?? 0,
            scratchBytes: intClamped(plan.memoryZones.metalScratchReserveBytes) ?? 0,
            promptAndTokenizerBytes: intClamped(plan.memoryZones.promptBufferBytes) ?? 0,
            uiReserveBytes: intClamped(plan.memoryZones.uiReserveBytes) ?? 0,
            safetyReserveBytes: intClamped(plan.memoryZones.safetyReserveBytes) ?? 0
        )
        let memoryPlan = MLXLMCommon.TurboQuantMemoryPlan(
            requestedContextLength: max(1, plan.requestedContextTokens),
            admittedContextLength: admittedContext,
            requestedMode: requestedMode,
            effectiveMode: selectedMode,
            preset: preset,
            valueBits: valueBits,
            groupSize: groupSize,
            fallbackPolicy: mlxTurboQuantFallbackPolicy(from: plan.fallbackContract),
            rawBytesPerToken: rawBytesPerToken,
            packedFallbackBytesPerToken: packedFallbackBytesPerToken,
            compressedBytesPerToken: compressedBytesPerToken,
            layerFootprint: footprint,
            usesRawShadow: plan.memoryZones.rawShadowBytes > 0,
            packedFallbackEnabled: plan.memoryZones.packedFallbackBytes > 0,
            usesRollingSummaryMemory: false,
            runtimeZones: zones
        )
        return MLXLMCommon.TurboQuantAdmission(
            admitted: plan.admitted,
            requestedContextLength: max(1, plan.requestedContextTokens),
            admittedContextLength: plan.admitted ? admittedContext : 0,
            requestedMode: requestedMode,
            selectedMode: selectedMode,
            memoryPlan: memoryPlan,
            downgradeReasons: mlxTurboQuantAdmissionDowngrades(from: plan),
            rejectedPaths: plan.rejectionReason.map {
                [MLXLMCommon.RejectedPath(path: "pines-local-runtime-admission", reason: $0)]
            } ?? [],
            userMessage: plan.userFacingMessage
        )
    }

    fileprivate static func mlxTurboQuantAdmission(
        from admission: PinesCore.TurboQuantAdmission
    ) -> MLXLMCommon.TurboQuantAdmission? {
        guard let memoryPlan = admission.memoryPlan,
              let mlxMemoryPlan = mlxTurboQuantMemoryPlan(from: memoryPlan) else {
            return nil
        }
        return MLXLMCommon.TurboQuantAdmission(
            admitted: admission.admitted,
            requestedContextLength: admission.requestedContextLength,
            admittedContextLength: admission.admittedContextLength,
            requestedMode: mlxTurboQuantUserMode(from: admission.requestedMode),
            selectedMode: mlxTurboQuantUserMode(from: admission.selectedMode),
            memoryPlan: mlxMemoryPlan,
            downgradeReasons: admission.downgradeReasons.map {
                MLXLMCommon.TurboQuantAdmissionDowngrade(
                    reason: mlxTurboQuantAdmissionDowngradeReason(from: $0.reason),
                    message: $0.message
                )
            },
            rejectedPaths: admission.rejectedPaths.map {
                MLXLMCommon.RejectedPath(path: $0.path, reason: $0.reason)
            },
            userMessage: admission.userMessage
        )
    }

    private static func mlxTurboQuantMemoryPlan(
        from plan: PinesCore.TurboQuantMemoryPlan
    ) -> MLXLMCommon.TurboQuantMemoryPlan? {
        guard let footprint = plan.layerFootprint else { return nil }
        return MLXLMCommon.TurboQuantMemoryPlan(
            requestedContextLength: plan.requestedContextLength,
            admittedContextLength: plan.admittedContextLength,
            requestedMode: mlxTurboQuantUserMode(from: plan.requestedMode),
            effectiveMode: mlxTurboQuantUserMode(from: plan.effectiveMode),
            preset: mlxTurboQuantAdmissionPreset(from: plan.preset),
            valueBits: plan.valueBits,
            groupSize: plan.groupSize,
            fallbackPolicy: mlxTurboQuantFallbackPolicy(from: plan.fallbackPolicy),
            rawBytesPerToken: plan.rawBytesPerToken,
            packedFallbackBytesPerToken: plan.packedFallbackBytesPerToken,
            compressedBytesPerToken: plan.compressedBytesPerToken,
            layerFootprint: MLXLMCommon.TurboQuantLayerCacheFootprint(
                layerCount: footprint.layerCount,
                kvHeadCount: footprint.kvHeadCount,
                headDimension: footprint.headDimension,
                groupSize: footprint.groupSize,
                preset: mlxTurboQuantAdmissionPreset(from: footprint.preset),
                valueBits: footprint.valueBits
            ),
            usesRawShadow: plan.usesRawShadow,
            packedFallbackEnabled: plan.packedFallbackEnabled,
            usesRollingSummaryMemory: plan.usesRollingSummaryMemory,
            runtimeZones: MLXLMCommon.TurboQuantRuntimeMemoryZones(
                availableAppMemoryBytes: plan.runtimeZones.availableAppMemoryBytes,
                runtimeBudgetBytes: plan.runtimeZones.runtimeBudgetBytes,
                mlxActiveBytes: plan.runtimeZones.mlxActiveBytes,
                mlxCacheBytes: plan.runtimeZones.mlxCacheBytes,
                modelResidentBytes: plan.runtimeZones.modelResidentBytes,
                compressedKVBytes: plan.runtimeZones.compressedKVBytes,
                rawShadowBytes: plan.runtimeZones.rawShadowBytes,
                fallbackReserveBytes: plan.runtimeZones.fallbackReserveBytes,
                scratchBytes: plan.runtimeZones.scratchBytes,
                promptAndTokenizerBytes: plan.runtimeZones.promptAndTokenizerBytes,
                uiReserveBytes: plan.runtimeZones.uiReserveBytes,
                safetyReserveBytes: plan.runtimeZones.safetyReserveBytes,
                rollingSummaryBytes: plan.runtimeZones.rollingSummaryBytes
            )
        )
    }

    private static func mlxTurboQuantAdmissionDowngrades(
        from plan: LocalRuntimeAdmissionPlan
    ) -> [MLXLMCommon.TurboQuantAdmissionDowngrade] {
        var downgrades: [MLXLMCommon.TurboQuantAdmissionDowngrade] = []
        if plan.admittedContextTokens < plan.requestedContextTokens {
            downgrades.append(
                MLXLMCommon.TurboQuantAdmissionDowngrade(
                    reason: .reducedContext,
                    message: plan.downgradeReason
                        ?? "Reduced context from \(plan.requestedContextTokens) to \(plan.admittedContextTokens) tokens."
                )
            )
        } else if let downgradeReason = plan.downgradeReason {
            downgrades.append(
                MLXLMCommon.TurboQuantAdmissionDowngrade(
                    reason: .reducedContext,
                    message: downgradeReason
                )
            )
        }
        if !plan.admitted, let rejectionReason = plan.rejectionReason {
            downgrades.append(
                MLXLMCommon.TurboQuantAdmissionDowngrade(
                    reason: .refusedInsufficientMemory,
                    message: rejectionReason
                )
            )
        }
        return downgrades
    }

    private static func mlxTurboQuantAdmissionDowngradeReason(
        from reason: PinesCore.TurboQuantAdmissionDowngradeReason
    ) -> MLXLMCommon.TurboQuantAdmissionDowngradeReason {
        switch reason {
        case .releasedRawShadow:
            .releasedRawShadow
        case .disabledPackedFallback:
            .disabledPackedFallback
        case .loweredValueBits:
            .loweredValueBits
        case .movedBalancedToMaxContext:
            .movedBalancedToMaxContext
        case .reducedContext:
            .reducedContext
        case .rollingSummaryMemory:
            .rollingSummaryMemory
        case .thermalOrBatterySaver:
            .thermalOrBatterySaver
        case .refusedInsufficientMemory:
            .refusedInsufficientMemory
        }
    }

    private static func mlxTurboQuantPerCacheResidentBudgetBytes(
        admissionPlan: LocalRuntimeAdmissionPlan?,
        install: ModelInstall?
    ) -> Int? {
        guard let admissionPlan else { return nil }
        let layerCount = install.map { heuristicModelShape(for: $0).layerCount } ?? 1
        let totalResidentBytes =
            admissionPlan.memoryZones.compressedKVBytes
            + admissionPlan.memoryZones.rawShadowBytes
            + admissionPlan.memoryZones.packedFallbackBytes
            + admissionPlan.memoryZones.decodedFallbackScratchBytes
        return intClamped(max(1, totalResidentBytes / Int64(max(1, layerCount))))
    }

    private static func mlxTurboQuantThermalState(_ state: String?) -> MLXLMCommon.TurboQuantThermalState {
        switch state?.lowercased() {
        case "nominal":
            .nominal
        case "fair":
            .fair
        case "serious":
            .serious
        case "critical":
            .critical
        default:
            .unknown
        }
    }

    private static func coreTurboQuantAdmission(
        from admission: MLXLMCommon.TurboQuantAdmission
    ) -> PinesCore.TurboQuantAdmission {
        PinesCore.TurboQuantAdmission(
            admitted: admission.admitted,
            requestedContextLength: admission.requestedContextLength,
            admittedContextLength: admission.admittedContextLength,
            requestedMode: coreTurboQuantUserMode(from: admission.requestedMode),
            selectedMode: coreTurboQuantUserMode(from: admission.selectedMode),
            memoryPlan: coreTurboQuantMemoryPlan(from: admission.memoryPlan),
            downgradeReasons: admission.downgradeReasons.map {
                PinesCore.TurboQuantAdmissionDowngrade(
                    reason: coreTurboQuantAdmissionDowngradeReason(from: $0.reason),
                    message: $0.message
                )
            },
            rejectedPaths: admission.rejectedPaths.map {
                PinesCore.RejectedPath(path: $0.path, reason: $0.reason)
            },
            userMessage: admission.userMessage
        )
    }

    private static func coreTurboQuantMemoryPlan(
        from plan: MLXLMCommon.TurboQuantMemoryPlan
    ) -> PinesCore.TurboQuantMemoryPlan {
        PinesCore.TurboQuantMemoryPlan(
            requestedContextLength: plan.requestedContextLength,
            admittedContextLength: plan.admittedContextLength,
            requestedMode: coreTurboQuantUserMode(from: plan.requestedMode),
            effectiveMode: coreTurboQuantUserMode(from: plan.effectiveMode),
            preset: coreTurboQuantPreset(from: plan.preset),
            valueBits: plan.valueBits,
            groupSize: plan.groupSize,
            fallbackPolicy: coreTurboQuantFallbackPolicy(from: plan.fallbackPolicy),
            rawBytesPerToken: plan.rawBytesPerToken,
            packedFallbackBytesPerToken: plan.packedFallbackBytesPerToken,
            compressedBytesPerToken: plan.compressedBytesPerToken,
            layerFootprint: coreTurboQuantLayerCacheFootprint(from: plan.layerFootprint),
            usesRawShadow: plan.usesRawShadow,
            packedFallbackEnabled: plan.packedFallbackEnabled,
            usesRollingSummaryMemory: plan.usesRollingSummaryMemory,
            runtimeZones: coreTurboQuantRuntimeMemoryZones(from: plan.runtimeZones)
        )
    }

    private static func coreTurboQuantLayerCacheFootprint(
        from footprint: MLXLMCommon.TurboQuantLayerCacheFootprint
    ) -> PinesCore.TurboQuantLayerCacheFootprint {
        PinesCore.TurboQuantLayerCacheFootprint(
            layerCount: footprint.layerCount,
            kvHeadCount: footprint.kvHeadCount,
            headDimension: footprint.headDimension,
            groupSize: footprint.groupSize,
            preset: coreTurboQuantPreset(from: footprint.preset),
            valueBits: footprint.valueBits,
            groupsPerVector: footprint.groupsPerVector,
            bitsetWordsPerGroup: footprint.bitsetWordsPerGroup,
            keyMagnitudeWordsPerGroup: footprint.keyMagnitudeWordsPerGroup,
            valueMagnitudeWordsPerGroup: footprint.valueMagnitudeWordsPerGroup,
            keyBytesPerTokenPerLayer: footprint.keyBytesPerTokenPerLayer,
            valueBytesPerTokenPerLayer: footprint.valueBytesPerTokenPerLayer,
            bytesPerTokenPerLayer: footprint.bytesPerTokenPerLayer,
            bytesPerTokenAllLayers: footprint.bytesPerTokenAllLayers,
            actualBitsPerValue: footprint.actualBitsPerValue
        )
    }

    private static func coreTurboQuantRuntimeMemoryZones(
        from zones: MLXLMCommon.TurboQuantRuntimeMemoryZones
    ) -> PinesCore.TurboQuantRuntimeMemoryZones {
        PinesCore.TurboQuantRuntimeMemoryZones(
            availableAppMemoryBytes: zones.availableAppMemoryBytes,
            runtimeBudgetBytes: zones.runtimeBudgetBytes,
            mlxActiveBytes: zones.mlxActiveBytes,
            mlxCacheBytes: zones.mlxCacheBytes,
            modelResidentBytes: zones.modelResidentBytes,
            compressedKVBytes: zones.compressedKVBytes,
            rawShadowBytes: zones.rawShadowBytes,
            fallbackReserveBytes: zones.fallbackReserveBytes,
            scratchBytes: zones.scratchBytes,
            promptAndTokenizerBytes: zones.promptAndTokenizerBytes,
            uiReserveBytes: zones.uiReserveBytes,
            safetyReserveBytes: zones.safetyReserveBytes,
            rollingSummaryBytes: zones.rollingSummaryBytes,
            totalRuntimeBytes: zones.totalRuntimeBytes,
            headroomBytes: zones.headroomBytes
        )
    }

    private static func coreTurboQuantUserMode(
        from mode: MLXLMCommon.TurboQuantUserMode
    ) -> PinesCore.TurboQuantUserMode {
        switch mode {
        case .fastest:
            .fastest
        case .balanced:
            .balanced
        case .maxContext:
            .maxContext
        case .batterySaver:
            .batterySaver
        }
    }

    private static func coreTurboQuantFallbackPolicy(
        from policy: MLXLMCommon.TurboQuantFallbackPolicy
    ) -> PinesCore.TurboQuantFallbackPolicy {
        switch policy {
        case .exactRequired:
            .exactRequired
        case .packedAllowed:
            .packedAllowed
        case .compressedDecodeAllowed:
            .compressedDecodeAllowed
        case .fatalOnFailure:
            .fatalOnFailure
        }
    }

    private static func coreTurboQuantFallbackPolicy(
        from contract: PinesCore.TurboQuantFallbackContract
    ) -> PinesCore.TurboQuantFallbackPolicy {
        if contract.failIfCompressedPathUnavailable {
            return .exactRequired
        }
        if contract.allowDecodedLayerLocalFallback || contract.allowFullDecodedFallback {
            return .compressedDecodeAllowed
        }
        if contract.allowPackedFallback {
            return .packedAllowed
        }
        return .exactRequired
    }

    private static func coreTurboQuantAdmissionDowngradeReason(
        from reason: MLXLMCommon.TurboQuantAdmissionDowngradeReason
    ) -> PinesCore.TurboQuantAdmissionDowngradeReason {
        switch reason {
        case .releasedRawShadow:
            .releasedRawShadow
        case .disabledPackedFallback:
            .disabledPackedFallback
        case .loweredValueBits:
            .loweredValueBits
        case .movedBalancedToMaxContext:
            .movedBalancedToMaxContext
        case .reducedContext:
            .reducedContext
        case .rollingSummaryMemory:
            .rollingSummaryMemory
        case .thermalOrBatterySaver:
            .thermalOrBatterySaver
        case .refusedInsufficientMemory:
            .refusedInsufficientMemory
        }
    }

    private static func turboQuantRuntimeDefaults(
        for install: ModelInstall,
        contextLength: Int?,
        deviceOptimizationPolicy: PinesCore.TurboQuantOptimizationPolicy
    ) -> TurboQuantRuntimeDefaults {
        var rejectionDiagnostics: [String] = []
        #if canImport(MLXLMCommon) && canImport(MLX)
        let registry = MLXLMCommon.TurboQuantProfileRegistry.bundled
        let identifiers = [install.repository, install.modelID.rawValue, install.displayName]
        for identifier in identifiers {
            let descriptor = MLXLMCommon.TurboQuantModelDescriptor(
                modelID: identifier,
                modelType: install.modelType,
                textConfigModelType: install.textConfigModelType,
                modality: Self.turboQuantModality(for: install),
                parameterCountB: Self.parameterCountBillionScale(for: install),
                routedExperts: install.routedExperts,
                expertsPerToken: install.expertsPerToken
            )
            let selection = registry.selection(
                for: descriptor,
                keyHeadDimension: install.keyHeadDimension,
                valueHeadDimension: install.valueHeadDimension,
                contextLength: contextLength
            )
            if rejectionDiagnostics.isEmpty {
                rejectionDiagnostics = Array(selection.rejectionReasons.prefix(6))
            }
            guard let profile = selection.profile else { continue }
            let profilePolicy = Self.coreTurboQuantOptimizationPolicy(from: profile.optimizationPolicy)
            return TurboQuantRuntimeDefaults(
                preset: Self.coreTurboQuantPreset(from: profile.recommendedScheme.preset),
                requestedBackend: Self.coreTurboQuantBackend(from: profile.backend),
                groupSize: profile.groupSize,
                valueBits: profile.valueBits,
                optimizationPolicy: profilePolicy,
                profileID: profile.id,
                profileSource: "bundled",
                profileDiagnostics: Array(selection.rejectionReasons.prefix(6))
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
            profileSource: "generic_conservative_fallback",
            profileDiagnostics: rejectionDiagnostics
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
        if install.effectiveTurboQuantModalities.contains(.vision) {
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
        install.resolvedParameterCount.map { Double($0) / 1_000_000_000 }
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
        case .softRecovered:
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.memory_pressure.soft_recover",
                metadata: runtimeMemoryMetadata()
            )
            #endif
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
        case .softRecovered:
            assertionFailure("Critical thermal pressure must not soft-recover.")
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
    case softRecovered
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
                                        finish.message = "Local generation was cancelled because iOS reported critical thermal pressure for on-device MLX inference."
                                    }
                                }
                                eventToYield = .finish(finish)
                            }
                            #if DEBUG
                            var finishMetadata = finish.providerMetadata
                            finishMetadata.merge([
                                "model_id": modelID.rawValue,
                                "reason": finish.reason.rawValue,
                                "token_count": String(emittedTokenCount),
                            ]) { _, new in new }
                            await FreezeBreadcrumbJournal.shared.record(
                                stage: "mlx.stream.finish",
                                detail: finish.message,
                                metadata: runtimeMemoryMetadata(merging: finishMetadata)
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
    private static let memoryPressureSoftRecoveryMinimumAvailableBytes: Int64 = 1_250_000_000
    private static let maxSoftMemoryWarningsPerGeneration = 4

    private let deviceMonitor = DeviceRuntimeMonitor()
    private var activeInstall: ModelInstall?
    private var activeProfile = RuntimeProfile()
    private var activePartitionSummary: String?
    private var activeStopStrings = Set<String>()
    private var didRegisterModelAliases = false
    private var foregroundActive = true
    private var activeGenerationCancellation: MLXGenerationCancellationBox?
    private var activeGenerationSoftMemoryWarningCount = 0
    private var isLoading = false

    private func runtimeMemoryMetadata(
        merging base: [String: String] = [:]
    ) -> [String: String] {
        var metadata = base
        let counters = deviceMonitor.memoryCounters()
        Self.add(counters.physicalMemoryBytes, forKey: "physical_memory_bytes", to: &metadata)
        Self.add(counters.availableMemoryBytes, forKey: "available_memory_bytes", to: &metadata)
        Self.add(counters.processResidentMemoryBytes, forKey: "process_resident_memory_bytes", to: &metadata)
        Self.add(counters.processPhysicalFootprintBytes, forKey: "process_physical_footprint_bytes", to: &metadata)
        Self.add(counters.processPeakResidentMemoryBytes, forKey: "process_peak_resident_memory_bytes", to: &metadata)
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
    private let promptKVCacheStore = LocalPromptKVCacheStore()
    #endif

    #if canImport(MLXEmbedders) && canImport(MLXLMCommon) && canImport(MLX) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
    private let embeddingRuntime = MLXEmbeddingRuntime()
    #endif

    func load(_ install: ModelInstall, profile: RuntimeProfile) async throws {
        try ensureForegroundActive()
        try Self.validateRuntimeCompatibility(install)
        if let admission = profile.quantization.turboQuantAdmission,
           !admission.admitted {
            throw InferenceError.invalidRequest(admission.userMessage)
        }
        #if canImport(MLX)
        Self.configureMLXMemoryPolicy(profile: profile)
        #endif
        #if canImport(MLXLMCommon)
        let runtimeModalities = install.effectiveTurboQuantModalities
        let matchingInstall = activeInstall?.modelID == install.modelID
            && activeInstall?.repository == install.repository
        if matchingInstall {
            let hasCompatibleContainer: Bool
            if runtimeModalities.contains(.vision) || runtimeModalities.contains(.audio) {
                hasCompatibleContainer = visionContainer != nil
            } else if runtimeModalities.contains(.text) {
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
                if !profileMatches {
                    await promptKVCacheStore.evictAll(reason: "runtime_profile_changed")
                }
                activeProfile = profile
                return
            }
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        #if canImport(MLXLMCommon)
        if activeInstall?.modelID != install.modelID
            || activeInstall?.repository != install.repository
            || activeProfile != profile {
            await promptKVCacheStore.evictAll(reason: "model_or_profile_changed")
        }
        #endif
        activeInstall = install
        activeProfile = profile

        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXLMCommon) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
        await registerModelAliasesIfNeeded()
        try Self.configureGlobalRuntimePolicy(profile: profile, install: install)
        if runtimeModalities.contains(.vision) || runtimeModalities.contains(.audio) {
            var resolvedConfiguration = try Self.lmConfiguration(for: install, kind: .visionLanguage)
            resolvedConfiguration.configuration.lazyLoad = profile.streamExperts
            activeStopStrings = resolvedConfiguration.hints.stopStrings
            visionContainer = try await MLX.withError {
                try await VLMModelFactory.shared.loadContainer(
                    from: PinesHubDownloader(),
                    using: PinesTokenizerLoader(),
                    configuration: resolvedConfiguration.configuration
                )
            }
            activePartitionSummary = await Self.configureLoadedContainer(
                visionContainer, profile: profile)
            textContainer = nil
        } else if runtimeModalities.contains(.text) {
            var resolvedConfiguration = try Self.lmConfiguration(for: install, kind: .language)
            resolvedConfiguration.configuration.lazyLoad = profile.streamExperts
            activeStopStrings = resolvedConfiguration.hints.stopStrings
            textContainer = try await MLX.withError {
                try await LLMModelFactory.shared.loadContainer(
                    from: PinesHubDownloader(),
                    using: PinesTokenizerLoader(),
                    configuration: resolvedConfiguration.configuration
                )
            }
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
        MLXCachePressureController.shared.configureActive(limit: mlxCacheLimit(for: profile))
        #endif
    }

    private static func mlxCacheLimit(for profile: RuntimeProfile) -> Int {
        #if os(iOS)
        let megabyte = 1_024 * 1_024
        let contextTokens = profile.quantization.maxKVSize ?? 4_096
        if profile.quantization.thermalDownshiftActive {
            return 64 * megabyte
        }
        if profile.quantization.runtimePressureReason == .lowMemory {
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

    private static func mlxIdleCacheLimit(for profile: RuntimeProfile) -> Int {
        #if os(iOS)
        min(mlxCacheLimit(for: profile), 64 * 1_024 * 1_024)
        #else
        Memory.cacheLimit
        #endif
    }

    private static func mlxPressureCacheLimit() -> Int {
        #if os(iOS)
        64 * 1_024 * 1_024
        #else
        Memory.cacheLimit
        #endif
    }

    private static func clearCachedMLXBuffers() {
        #if targetEnvironment(simulator)
        return
        #else
        MLXCachePressureController.shared.clearImmediately(limit: mlxPressureCacheLimit())
        #endif
    }

    private static func settleMLXBuffersAfterGeneration(profile: RuntimeProfile) {
        #if targetEnvironment(simulator)
        return
        #else
        MLXCachePressureController.shared.settleAfterGeneration(
            idleLimit: mlxIdleCacheLimit(for: profile),
            clearImmediately: profile.quantization.runtimePressureReason == .lowMemory
                || profile.quantization.thermalDownshiftActive
        )
        #endif
    }

    private static func applySoftMemoryPressureMLXPolicy() {
        #if targetEnvironment(simulator)
        return
        #else
        MLXCachePressureController.shared.clearImmediately(limit: mlxPressureCacheLimit())
        #endif
    }

    private static func resetMLXPeakMemory() {
        #if targetEnvironment(simulator)
        return
        #else
        Memory.peakMemory = 0
        #endif
    }

    private static func localRuntimeFailure(from error: Error) -> InferenceError {
        if let inferenceError = error as? InferenceError {
            return inferenceError
        }
        if let mlxError = error as? MLX.MLXError {
            switch mlxError {
            case let .caught(message):
                return .localRuntimeFailure(message)
            }
        }
        #if canImport(MLXLMCommon)
        if let turboQuantError = error as? MLXLMCommon.TurboQuantGenerationError {
            return .localRuntimeFailure(turboQuantError.description)
        }
        #endif
        let diagnostic = String(describing: error)
        if !diagnostic.isEmpty && diagnostic != error.localizedDescription {
            return .localRuntimeFailure(diagnostic)
        }
        return .localRuntimeFailure(error.localizedDescription)
    }

    private static func validateTurboQuantRuntimeSupport(
        model: any LanguageModel,
        profile: RuntimeProfile
    ) throws {
        guard profile.quantization.kvCacheStrategy == .turboQuant else { return }
        guard model is any ThrowingLanguageModel else {
            let modelName = String(describing: Swift.type(of: model))
            throw InferenceError.localRuntimeFailure(
                "\(TurboQuantRuntimeSupport.nonThrowingRuntimeReason) Loaded MLX model: \(modelName)."
            )
        }
    }
    #endif

    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private func registerModelAliasesIfNeeded() async {
        guard !didRegisterModelAliases else { return }
        didRegisterModelAliases = true

        await LLMTypeRegistry.shared.registerModelType(
            "gemma4_assistant",
            creator: { data in
                guard Self.hasGemma4AssistantRuntimeSupport else {
                    throw InferenceError.unsupportedCapability(
                        ModelPreflightClassifier.gemma4AssistantCapabilityGateReason
                    )
                }
                return try Self.llmCreator(GemmaConfiguration.self, GemmaModel.init)(data)
            }
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
            creator: { data in
                guard Self.hasCanonicalDeepSeekV4RuntimeSupport else {
                    throw InferenceError.unsupportedCapability(
                        ModelPreflightClassifier.deepSeekV4CapabilityGateReason
                    )
                }
                return try Self.llmCreator(PinesDeepseekV4Configuration.self, PinesDeepseekV4Model.init)(data)
            }
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
        if install.modelType == "gemma4_assistant" {
            guard hasGemma4AssistantRuntimeSupport else {
                throw InferenceError.unsupportedCapability(
                    ModelPreflightClassifier.gemma4AssistantCapabilityGateReason
                )
            }
        }
        if install.modelType == "deepseek_v4" {
            guard hasCanonicalDeepSeekV4RuntimeSupport else {
                throw InferenceError.unsupportedCapability(
                    ModelPreflightClassifier.deepSeekV4CapabilityGateReason
                )
            }
        }
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
            activeGenerationSoftMemoryWarningCount = 0
        }
    }

    private func enforceActiveGenerationSafety(
        tokenCount: Int,
        modelID: ModelID
    ) async throws {
        let safety = deviceMonitor.localGenerationSafety()
        guard !safety.allowed else { return }
        guard safety.pressureReason == .lowMemory else {
            throw InferenceError.unsupportedCapability(
                safety.reason ?? "Local MLX generation is paused by runtime safety policy."
            )
        }

        #if canImport(MLX)
        Self.applySoftMemoryPressureMLXPolicy()
        #endif
        #if canImport(MLXLMCommon)
        await promptKVCacheStore.evictAll(reason: "active_generation_memory_pressure")
        #endif
        let downgradeSteps = Self.memoryPressureDowngradeSteps(for: activeProfile)

        let counters = deviceMonitor.memoryCounters()
        if let availableMemoryBytes = counters.availableMemoryBytes,
           availableMemoryBytes >= activeGenerationEmergencyMinimumAvailableBytes {
            #if DEBUG
            await FreezeBreadcrumbJournal.shared.record(
                stage: "mlx.memory_pressure.in_generation_soft_recover",
                metadata: runtimeMemoryMetadata(merging: [
                    "model_id": modelID.rawValue,
                    "token_count": String(tokenCount),
                    "active_generation_memory_floor_bytes": String(
                        activeGenerationEmergencyMinimumAvailableBytes
                    ),
                    "downgrade_steps": downgradeSteps.map(\.rawValue).joined(separator: ","),
                ])
            )
            #endif
            return
        }

        throw InferenceError.unsupportedCapability(
            safety.reason
                ?? "Local MLX generation is paused by runtime safety policy after trying \(downgradeSteps.map(\.rawValue).joined(separator: ", "))."
        )
    }

    func unload() async {
        activeInstall = nil
        activeGenerationSoftMemoryWarningCount = 0
        #if canImport(MLXLMCommon)
        await promptKVCacheStore.evictAll(reason: "model_unload")
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
        await handlePressureUnload(willCancel: willCancel, allowsSoftRecovery: true)
    }

    func handlePressureUnload(
        willCancel: @Sendable () async -> Void
    ) async -> MLXMemoryPressureHandling {
        await handlePressureUnload(willCancel: willCancel, allowsSoftRecovery: false)
    }

    private func handlePressureUnload(
        willCancel: @Sendable () async -> Void,
        allowsSoftRecovery: Bool
    ) async -> MLXMemoryPressureHandling {
        if isLoading {
            return .ignoredDuringLoad
        }
        #if canImport(MLX)
        Self.applySoftMemoryPressureMLXPolicy()
        #endif
        #if canImport(MLXLMCommon)
        await promptKVCacheStore.evictAll(reason: "memory_pressure")
        #endif
        let generationCancellation = activeGenerationCancellation
        let availableMemoryBytes = deviceMonitor.memoryCounters().availableMemoryBytes
        let hasHardMemoryPressure = availableMemoryBytes
            .map { $0 < LocalRuntimeSafetyPolicy.minimumAvailableMemoryBytes } ?? true
        let hasSoftRecoveryHeadroom = availableMemoryBytes
            .map { $0 >= Self.memoryPressureSoftRecoveryMinimumAvailableBytes } ?? false
        let activeGenerationHasEmergencyHeadroom = availableMemoryBytes
            .map { $0 >= activeGenerationEmergencyMinimumAvailableBytes } ?? false
        if allowsSoftRecovery,
           generationCancellation != nil,
           (!hasHardMemoryPressure || activeGenerationHasEmergencyHeadroom),
           (hasSoftRecoveryHeadroom || activeGenerationHasEmergencyHeadroom),
           activeGenerationSoftMemoryWarningCount < Self.maxSoftMemoryWarningsPerGeneration {
            activeGenerationSoftMemoryWarningCount += 1
            return .softRecovered
        }
        await willCancel()
        generationCancellation?.cancel()
        if let generationCancellation {
            await waitForActiveGenerationCancellationToDrain(generationCancellation)
        }
        await unload()
        return .unloaded
    }

    private static func memoryPressureDowngradeSteps(for profile: RuntimeProfile) -> [LocalMemoryPressureDowngradeStep] {
        var steps: [LocalMemoryPressureDowngradeStep] = [
            .releaseRawPrefillShadow,
            .releasePackedFallback,
            .reduceLiveContext,
        ]
        if profile.quantization.turboQuantUserMode == .balanced {
            steps.append(.switchBalancedToMaxContext)
        }
        steps.append(contentsOf: [
            .slidingWindowPinnedSystemPrompt,
            .summarizeOlderTurns,
            .askUserReduceContextOrSwitchModel,
        ])
        return steps
    }

    private func waitForActiveGenerationCancellationToDrain(_ box: MLXGenerationCancellationBox) async {
        let deadline = Date().addingTimeInterval(Self.pressureUnloadDrainTimeoutSeconds)
        while activeGenerationCancellation === box, Date() < deadline {
            try? await Task.sleep(nanoseconds: Self.pressureUnloadDrainPollNanoseconds)
        }
    }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXLMCommon)
        try ensureForegroundActive()
        let requiresVLM = request.messages.contains { message in
            message.attachments.contains { attachment in
                attachment.kind == .image || attachment.kind == .video || attachment.kind == .audio
            }
        }
        let loadedInstall = activeInstall
        let loadedInstallMatchesRequest = loadedInstall?.modelID == request.modelID
        let loadedRuntimeModalities = loadedInstall?.effectiveTurboQuantModalities
        let loadedInstallUsesVLMRuntime = loadedInstallMatchesRequest
            && (loadedRuntimeModalities?.contains(.vision) == true
                || loadedRuntimeModalities?.contains(.audio) == true)
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
        #if canImport(MLX)
        Self.configureMLXMemoryPolicy(profile: profile)
        #endif
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
        activeGenerationSoftMemoryWarningCount = 0

        return AsyncThrowingStream<InferenceStreamEvent, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                let latestTurboQuantTelemetry = MLXGenerationTelemetryBox()
                defer {
                    generationCancellation.cancel()
                    #if canImport(MLX)
                    Self.settleMLXBuffersAfterGeneration(profile: profile)
                    #endif
                    Task {
                        self.clearActiveGenerationCancellation(generationCancellation)
                    }
                }
                do {
	                    let result = try await withTaskCancellationHandler {
	                        try await container.perform {
	                            (context: MLXLMCommon.ModelContext) async throws -> (
	                                tokenCount: Int,
	                                finish: InferenceFinish?,
	                                terminalFailureEmitted: Bool
	                            ) in
                        let images = imageURLs.map(UserInput.Image.url)
                        let audio = audioURLs.map(UserInput.Audio.url)
                        var tokenCount = 0
                        var finish: InferenceFinish?
                        let generationSafety = try deviceMonitor.requireLocalGenerationSafety()
                        let initialHistoryCharacterBudget = Self.localHistoryCharacterBudget(
                            maxContextTokens: profile.quantization.maxKVSize
                        )
                        let initialGenerationAvailableMemoryBytes = deviceMonitor.memoryCounters().availableMemoryBytes
                        var generationPlan = LocalGenerationPipelinePlan(
                            requestedCompletionTokens: request.sampling.maxTokens,
                            profile: profile,
                            safety: generationSafety,
                            initialAvailableMemoryBytes: initialGenerationAvailableMemoryBytes
                        )
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
                              input.text.tokens.size + generationPlan.reservedCompletionTokens > maxContextTokens,
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
                        let profile = MLXRuntimeBridge.runtimeProfileForPreparedGeneration(
                            baseProfile: profile,
                            exactInputTokens: input.text.tokens.size,
                            reservedCompletionTokens: generationPlan.reservedCompletionTokens
                        )
                        let prepareElapsedSeconds = Date().timeIntervalSince(prepareStartedAt)
                        var turboQuantContextPlan = MLXRuntimeBridge.minimalContextAssemblyPlan(
                            exactInputTokens: input.text.tokens.size,
                            reservedCompletionTokens: generationPlan.reservedCompletionTokens,
                            historyMessageCount: historyMessages.count + 1,
                            reducedHistoryForContext: reducedHistoryForContext
                        )
                        let admissionMemoryCounters = deviceMonitor.memoryCounters()
                        var turboQuantAdmissionPlan = MLXRuntimeBridge.localRuntimeAdmissionPlan(
                            request: request,
                            install: install,
                            profile: profile,
                            contextPlan: turboQuantContextPlan,
                            memoryCounters: admissionMemoryCounters
                        )
                        latestTurboQuantTelemetry.setContextPlan(turboQuantContextPlan)
                        latestTurboQuantTelemetry.setAdmissionPlan(turboQuantAdmissionPlan)
                        latestTurboQuantTelemetry.setInputTokens(input.text.tokens.size)

                        if let admissionPlan = turboQuantAdmissionPlan,
                           !admissionPlan.admitted {
                            var failureMetadata: [String: String] = [:]
                            MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                                to: &failureMetadata,
                                cache: nil,
                                request: request,
                                install: install,
                                profile: profile,
                                contextPlan: turboQuantContextPlan,
                                admissionPlan: admissionPlan,
                                memoryCounters: admissionMemoryCounters,
                                outcome: .rejectedBeforeRun,
                                failureKind: .memoryAdmissionFailed,
                                failureMessage: admissionPlan.userFacingMessage,
                                inputTokens: input.text.tokens.size,
                                outputTokens: 0
                            )
                            latestTurboQuantTelemetry.setFailureMetadata(failureMetadata)
                            continuation.yield(
                                InferenceStreamEvent.failure(
                                    InferenceStreamFailure(
                                        code: LocalInferenceFailureKind.memoryAdmissionFailed.rawValue,
                                        message: admissionPlan.userFacingMessage,
                                        recoverable: false,
                                        providerMetadata: failureMetadata
                                    )
                                )
                            )
                            return (tokenCount: 0, finish: nil, terminalFailureEmitted: true)
                        }

                        let activeMaxContextTokens = turboQuantAdmissionPlan?.admittedContextTokens
                            ?? profile.quantization.maxKVSize
                        if let maxContextTokens = activeMaxContextTokens {
                            if !generationPlan.fitPreparedPrompt(
                                promptTokenCount: input.text.tokens.size,
                                maxContextTokens: maxContextTokens
                            ) {
                                let message = "This local request needs \(input.text.tokens.size + generationPlan.reservedCompletionTokens) tokens (\(input.text.tokens.size) prompt + \(generationPlan.reservedCompletionTokens) completion), but \(request.modelID.rawValue) is admitted for \(maxContextTokens). Shorten the latest message or reduce local completion tokens."
                                var failureMetadata: [String: String] = [:]
                                MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                                    to: &failureMetadata,
                                    cache: nil,
                                    request: request,
                                    install: install,
                                    profile: profile,
                                    contextPlan: turboQuantContextPlan,
                                    admissionPlan: turboQuantAdmissionPlan,
                                    memoryCounters: admissionMemoryCounters,
                                    outcome: .rejectedBeforeRun,
                                    failureKind: .contextWindowExceeded,
                                    failureMessage: message,
                                    inputTokens: input.text.tokens.size,
                                    outputTokens: 0
                                )
                                latestTurboQuantTelemetry.setFailureMetadata(failureMetadata)
                                continuation.yield(
                                    InferenceStreamEvent.failure(
                                        InferenceStreamFailure(
                                            code: LocalInferenceFailureKind.contextWindowExceeded.rawValue,
                                            message: message,
                                            recoverable: false,
                                            providerMetadata: failureMetadata
                                        )
                                    )
                                )
                                return (tokenCount: 0, finish: nil, terminalFailureEmitted: true)
                            }
                        }
                        turboQuantContextPlan = MLXRuntimeBridge.minimalContextAssemblyPlan(
                            exactInputTokens: input.text.tokens.size,
                            reservedCompletionTokens: generationPlan.reservedCompletionTokens,
                            historyMessageCount: historyMessages.count + 1,
                            reducedHistoryForContext: reducedHistoryForContext
                        )
                        turboQuantAdmissionPlan = MLXRuntimeBridge.localRuntimeAdmissionPlan(
                            request: request,
                            install: install,
                            profile: profile,
                            contextPlan: turboQuantContextPlan,
                            memoryCounters: admissionMemoryCounters
                        )
                        latestTurboQuantTelemetry.setContextPlan(turboQuantContextPlan)
                        latestTurboQuantTelemetry.setAdmissionPlan(turboQuantAdmissionPlan)

                        if let admissionPlan = turboQuantAdmissionPlan,
                           !admissionPlan.admitted {
                            var failureMetadata: [String: String] = [:]
                            MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                                to: &failureMetadata,
                                cache: nil,
                                request: request,
                                install: install,
                                profile: profile,
                                contextPlan: turboQuantContextPlan,
                                admissionPlan: admissionPlan,
                                memoryCounters: admissionMemoryCounters,
                                outcome: .rejectedBeforeRun,
                                failureKind: .memoryAdmissionFailed,
                                failureMessage: admissionPlan.userFacingMessage,
                                inputTokens: input.text.tokens.size,
                                outputTokens: 0
                            )
                            latestTurboQuantTelemetry.setFailureMetadata(failureMetadata)
                            continuation.yield(
                                InferenceStreamEvent.failure(
                                    InferenceStreamFailure(
                                        code: LocalInferenceFailureKind.memoryAdmissionFailed.rawValue,
                                        message: admissionPlan.userFacingMessage,
                                        recoverable: false,
                                        providerMetadata: failureMetadata
                                    )
                                )
                            )
                            return (tokenCount: 0, finish: nil, terminalFailureEmitted: true)
                        }

                        if let maxContextTokens = turboQuantAdmissionPlan?.admittedContextTokens
                            ?? profile.quantization.maxKVSize,
                           !generationPlan.fitPreparedPrompt(
                               promptTokenCount: input.text.tokens.size,
                               maxContextTokens: maxContextTokens
                           ) {
                            let message = "This local request needs \(input.text.tokens.size + generationPlan.reservedCompletionTokens) tokens (\(input.text.tokens.size) prompt + \(generationPlan.reservedCompletionTokens) completion), but \(request.modelID.rawValue) is admitted for \(maxContextTokens). Shorten the latest message or reduce local completion tokens."
                            var failureMetadata: [String: String] = [:]
                            MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                                to: &failureMetadata,
                                cache: nil,
                                request: request,
                                install: install,
                                profile: profile,
                                contextPlan: turboQuantContextPlan,
                                admissionPlan: turboQuantAdmissionPlan,
                                memoryCounters: admissionMemoryCounters,
                                outcome: .rejectedBeforeRun,
                                failureKind: .contextWindowExceeded,
                                failureMessage: message,
                                inputTokens: input.text.tokens.size,
                                outputTokens: 0
                            )
                            latestTurboQuantTelemetry.setFailureMetadata(failureMetadata)
                            continuation.yield(
                                InferenceStreamEvent.failure(
                                    InferenceStreamFailure(
                                        code: LocalInferenceFailureKind.contextWindowExceeded.rawValue,
                                        message: message,
                                        recoverable: false,
                                        providerMetadata: failureMetadata
                                    )
                                )
                            )
                            return (tokenCount: 0, finish: nil, terminalFailureEmitted: true)
                        }
                        let parameters = Self.generateParameters(
                            from: request,
                            profile: profile,
                            install: install,
                            maxTokensOverride: generationPlan.effectiveMaxTokens,
                            maxKVSizeOverride: generationPlan.effectiveMaxKVSize,
                            turboQuantAdmissionPlan: turboQuantAdmissionPlan,
                            promptTokenCount: input.text.tokens.size
                        )
                        var contextMetadata: [String: String] = [
                            ChatContextMetadataKeys.exactInputTokens: String(input.text.tokens.size),
                            ChatContextMetadataKeys.reservedCompletionTokens: String(
                                generationPlan.reservedCompletionTokens
                            ),
                            LocalProviderMetadataKeys.runtimePressureReason: profile.quantization.runtimePressureReason.rawValue,
                            LocalProviderMetadataKeys.runtimePrefillStepSize: String(profile.prefillStepSize),
                            LocalProviderMetadataKeys.turboQuantProfileSource: profile.quantization.turboQuantProfileSource ?? "none",
                            LocalProviderMetadataKeys.cacheTopology: install?.cacheTopology.rawValue ?? ModelCacheTopology.unsupported.rawValue,
                            LocalProviderMetadataKeys.turboQuantFamilySupport: install?.effectiveTurboQuantFamilySupport.rawValue ?? TurboQuantFamilySupport.none.rawValue,
                            LocalProviderMetadataKeys.turboQuantAdmissionDecision: turboQuantAdmissionPlan?.admitted == false
                                ? "refused"
                                : (profile.quantization.kvCacheStrategy == .turboQuant ? "turboQuant" : "plain_rotating_kv"),
                            LocalProviderMetadataKeys.turboQuantAdmissionReason:
                                turboQuantAdmissionPlan?.userFacingMessage
                                ?? profile.quantization.activeFallbackReason
                                ?? "TurboQuant admitted",
                            LocalProviderMetadataKeys.turboQuantUserMode: profile.quantization.turboQuantUserMode.rawValue,
                            LocalProviderMetadataKeys.generationPrepareElapsedSeconds: String(prepareElapsedSeconds),
                            LocalProviderMetadataKeys.generationPreflightAttempts: String(preflightAttempts),
                        ]
                        if let repetitionPenalty = parameters.repetitionPenalty {
                            contextMetadata[LocalProviderMetadataKeys.generationRepetitionPenalty] =
                                String(repetitionPenalty)
                        }
                        if let admission = profile.quantization.turboQuantAdmission {
                            contextMetadata[LocalProviderMetadataKeys.turboQuantSelectedMode] = admission.selectedMode.rawValue
                            contextMetadata[LocalProviderMetadataKeys.turboQuantAdmittedContext] = String(admission.admittedContextLength)
                            contextMetadata[LocalProviderMetadataKeys.turboQuantMemoryMessage] = admission.userMessage
                            if let reason = admission.primaryDowngradeReason {
                                contextMetadata[LocalProviderMetadataKeys.turboQuantDowngradeReason] = reason.rawValue
                            }
                            if let zones = admission.memoryPlan?.runtimeZones {
                                contextMetadata[LocalProviderMetadataKeys.turboQuantRuntimeBudgetBytes] = String(zones.runtimeBudgetBytes)
                                contextMetadata[LocalProviderMetadataKeys.turboQuantRuntimeHeadroomBytes] = String(zones.headroomBytes)
                                contextMetadata[LocalProviderMetadataKeys.turboQuantCompressedKVBytes] = String(zones.compressedKVBytes)
                                contextMetadata[LocalProviderMetadataKeys.turboQuantFallbackReserveBytes] = String(zones.fallbackReserveBytes)
                            }
                        }
                        contextMetadata[LocalProviderMetadataKeys.turboQuantContextAssemblyPlanID] =
                            turboQuantContextPlan.id
                        contextMetadata[LocalProviderMetadataKeys.turboQuantContextAssemblyPlanJSON] =
                            MLXRuntimeBridge.metadataJSON(turboQuantContextPlan)
                        if let turboQuantAdmissionPlan {
                            contextMetadata[LocalProviderMetadataKeys.turboQuantAdmissionPlanJSON] =
                                MLXRuntimeBridge.metadataJSON(turboQuantAdmissionPlan)
                            contextMetadata[LocalProviderMetadataKeys.turboQuantFallbackContractHash] =
                                turboQuantAdmissionPlan.fallbackContract.contractHash
                            contextMetadata[LocalProviderMetadataKeys.turboQuantSelectedMode] =
                                turboQuantAdmissionPlan.selectedMode.rawValue
                            contextMetadata[LocalProviderMetadataKeys.turboQuantAdmittedContext] =
                                String(turboQuantAdmissionPlan.admittedContextTokens)
                            contextMetadata[LocalProviderMetadataKeys.turboQuantRuntimeBudgetBytes] =
                                String(turboQuantAdmissionPlan.memoryZones.totalPlannedBytes)
                            contextMetadata[LocalProviderMetadataKeys.turboQuantRuntimeHeadroomBytes] =
                                String(turboQuantAdmissionPlan.memoryCushionBytes)
                            contextMetadata[LocalProviderMetadataKeys.turboQuantCompressedKVBytes] =
                                String(turboQuantAdmissionPlan.memoryZones.compressedKVBytes)
                            contextMetadata[LocalProviderMetadataKeys.turboQuantFallbackReserveBytes] =
                                String(
                                    turboQuantAdmissionPlan.memoryZones.packedFallbackBytes
                                    + turboQuantAdmissionPlan.memoryZones.decodedFallbackScratchBytes
                                )
                            contextMetadata[LocalProviderMetadataKeys.turboQuantCloudRetryPermitted] =
                                String(turboQuantAdmissionPlan.fallbackContract.allowCloudRetry)
                            contextMetadata[LocalProviderMetadataKeys.turboQuantCloudFallbackSuppressed] =
                                String(!turboQuantAdmissionPlan.fallbackContract.allowCloudRetry)
                        }
                        contextMetadata.merge(generationPlan.providerMetadata()) { _, new in new }
                        latestTurboQuantTelemetry.setFailureMetadata(contextMetadata)
                        if install?.effectiveTurboQuantFamilySupport == .hybridFull,
                           profile.quantization.kvCacheStrategy == .turboQuant {
                            contextMetadata[LocalProviderMetadataKeys.hybridStateExplanation] = "Attention KV caches use TurboQuant; architecture-specific native state caches remain exact."
                        }
                        if let profileID = profile.quantization.turboQuantProfileID {
                            contextMetadata[LocalProviderMetadataKeys.turboQuantProfileID] = profileID
                        }
                        if !profile.quantization.turboQuantProfileDiagnostics.isEmpty {
                            contextMetadata[LocalProviderMetadataKeys.turboQuantProfileDiagnostics] = profile.quantization.turboQuantProfileDiagnostics.joined(separator: " | ")
                        }
                        if let maxContextTokens = turboQuantAdmissionPlan?.admittedContextTokens
                            ?? profile.quantization.maxKVSize {
                            contextMetadata[ChatContextMetadataKeys.contextWindowTokens] = String(maxContextTokens)
                            contextMetadata[ChatContextMetadataKeys.inputBudgetTokens] = String(
                                max(0, maxContextTokens - generationPlan.reservedCompletionTokens)
                            )
                            contextMetadata[LocalProviderMetadataKeys.runtimeMaxKVSize] = String(maxContextTokens)
                        }
                        if reducedHistoryForContext {
                            contextMetadata[ChatContextMetadataKeys.truncationApplied] = "true"
                            contextMetadata[ChatContextMetadataKeys.strategy] = "mlx-exact-token-preflight-v1"
                            contextMetadata[ChatContextMetadataKeys.clippedMessageCount] = "1"
                        }
                        let cacheStartedAt = Date()
                        let hasToolSpecs = !(toolSpecs?.isEmpty ?? true)
                        let promptTokenIDs = Self.promptTokenIDs(from: input.text.tokens)
                        try Self.validateTurboQuantRuntimeSupport(model: context.model, profile: profile)
                        let promptCacheSkipReason = Self.promptCacheMissReason(
                            input: input,
                            promptTokenIDs: promptTokenIDs,
                            profile: profile,
                            hasTools: hasToolSpecs,
                            hasVisionInput: !imageURLs.isEmpty,
                            hasAudioInput: !audioURLs.isEmpty
                        )
                        let promptCacheKey: LocalPromptKVCacheKey?
                        let promptCacheStoreEligible: Bool
                        let cache: [KVCache]
                        if let promptCacheSkipReason {
                            promptCacheKey = nil
                            promptCacheStoreEligible = false
                            cache = context.model.newCache(parameters: parameters)
                            contextMetadata[LocalProviderMetadataKeys.promptKVCacheStatus] = "disabled"
                            contextMetadata[LocalProviderMetadataKeys.promptKVCacheMissReason] = promptCacheSkipReason
                            contextMetadata[LocalProviderMetadataKeys.promptKVCacheReusedPrefixTokens] = "0"
                            contextMetadata[LocalProviderMetadataKeys.promptKVCacheSuffixPrefillTokens] = String(promptTokenIDs.count)
                        } else {
                            let key = Self.localPromptKVCacheKey(
                                request: request,
                                install: install,
                                profile: profile,
                                parameters: parameters,
                                hasTools: hasToolSpecs,
                                hasVisionInput: false,
                                hasAudioInput: false
                            )
                            promptCacheKey = key
                            promptCacheStoreEligible = true
                            let lookup = await promptKVCacheStore.take(
                                key: key,
                                promptTokenIDs: promptTokenIDs
                            )
                            if let entry = lookup.entry {
                                cache = entry.cache
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheStatus] = "hit"
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheReusedPrefixTokens] = String(
                                    lookup.reusedPrefixTokenCount
                                )
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheSuffixPrefillTokens] = String(
                                    lookup.suffixPrefillTokenCount
                                )
                            } else {
                                cache = context.model.newCache(parameters: parameters)
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheStatus] = "miss"
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheMissReason] = lookup.missReason ?? "unknown"
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheReusedPrefixTokens] = "0"
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheSuffixPrefillTokens] = String(promptTokenIDs.count)
                            }
                        }
                        contextMetadata[LocalProviderMetadataKeys.mlxCachePressureAction] =
                            Self.mlxCachePressureAction(for: profile)
                        contextMetadata[LocalProviderMetadataKeys.generationCacheCreateElapsedSeconds] = String(
                            Date().timeIntervalSince(cacheStartedAt)
                        )
                        #if DEBUG
                        await FreezeBreadcrumbJournal.shared.record(
                            stage: "mlx.generation.preflight",
                            metadata: runtimeMemoryMetadata(merging: contextMetadata.merging([
                                "model_id": request.modelID.rawValue,
                                "prompt_tokens": String(input.text.tokens.size),
                                "reserved_completion_tokens": String(
                                    generationPlan.reservedCompletionTokens
                                ),
                                "history_character_budget": String(historyCharacterBudget),
                                "reduced_history_for_context": String(reducedHistoryForContext),
                                "kv_cache_strategy": profile.quantization.kvCacheStrategy.rawValue,
                                "turboquant_preset": profile.quantization.preset?.rawValue ?? "none",
                                "turboquant_requested_backend": profile.quantization.requestedBackend?.rawValue ?? "none",
                            ]) { _, new in new })
                        )
                        #endif
                        let generationArtifacts: (
                            stream: AsyncStream<Generation>,
                            task: Task<Void, Never>,
                            errorBox: MLX.ErrorBox
                        )
                        var stopFilter = TextStopSequenceFilter(stopSequences: stopStrings)
                        generationArtifacts = try MLX.withError { errorBox in
                            let stream: AsyncStream<Generation>
                            let generationTask: Task<Void, Never>
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
                            return (stream: stream, task: generationTask, errorBox: errorBox)
                        }
                        let stream = generationArtifacts.stream
                        let generationTask = generationArtifacts.task
                        generationCancellation.set(generationTask)
                        var completionInfo: GenerateCompletionInfo?

                        generationLoop: for await item in stream {
                            guard !Task.isCancelled else { throw InferenceError.cancelled }
                            switch item {
                            case let .chunk(text):
                                tokenCount += 1
                                if tokenCount == 1 || tokenCount.isMultiple(of: 16) {
                                    try await enforceActiveGenerationSafety(
                                        tokenCount: tokenCount,
                                        modelID: request.modelID
                                    )
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
                                    latestTurboQuantTelemetry.setOutputTokens(tokenCount)
                                    MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                                        to: &providerMetadata,
                                        cache: cache,
                                        request: request,
                                        install: install,
                                        profile: profile,
                                        contextPlan: turboQuantContextPlan,
                                        admissionPlan: turboQuantAdmissionPlan,
                                        memoryCounters: deviceMonitor.memoryCounters(),
                                        outcome: .admittedSucceeded,
                                        inputTokens: input.text.tokens.size,
                                        outputTokens: tokenCount
                                    )
                                    latestTurboQuantTelemetry.setFailureMetadata(providerMetadata)
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
                        try generationArtifacts.errorBox.check()
                        generationCancellation.clear()
                        let pendingText = stopFilter.flush()
                        if !pendingText.isEmpty {
                            continuation.yield(.token(TokenDelta(kind: .token, text: pendingText, tokenCount: 1)))
                        }
                        if promptCacheStoreEligible, let promptCacheKey {
                            if canTrimPromptCache(cache) {
                                let generatedTokenCount = completionInfo?.generationTokenCount ?? tokenCount
                                let trimmedGeneratedTokens = generatedTokenCount > 0
                                    ? trimPromptCache(cache, numTokens: generatedTokenCount)
                                    : 0
                                if trimmedGeneratedTokens == generatedTokenCount {
                                    await promptKVCacheStore.store(
                                        LocalPromptKVCacheEntry(
                                            key: promptCacheKey,
                                            tokenIDs: promptTokenIDs,
                                            tokenDigest: LocalPromptKVCacheStore.tokenDigest(promptTokenIDs),
                                            cache: cache,
                                            storedAt: Date()
                                        )
                                    )
                                    contextMetadata[LocalProviderMetadataKeys.promptKVCacheStoredTokens] = String(
                                        promptTokenIDs.count
                                    )
                                } else {
                                    await promptKVCacheStore.evictAll(reason: "generated_token_trim_failed")
                                    contextMetadata[LocalProviderMetadataKeys.promptKVCacheEvictionReason] =
                                        "generated_token_trim_failed"
                                }
                            } else {
                                await promptKVCacheStore.evictAll(reason: "untrimmable_cache")
                                contextMetadata[LocalProviderMetadataKeys.promptKVCacheEvictionReason] =
                                    "untrimmable_cache"
                            }
                        }
                        if var existingFinish = finish {
                            existingFinish.providerMetadata.merge(contextMetadata) { _, new in new }
                            finish = existingFinish
                        }
                        if finish == nil, let completionInfo {
                            var providerMetadata = Self.localProviderMetadata(
                                from: cache,
                                fallbackProfile: profile,
                                partitionSummary: partitionSummary
                            )
                            providerMetadata.merge(contextMetadata) { _, new in new }
                            let speculative = MLXRuntimeBridge.speculativeTelemetry(
                                from: completionInfo,
                                profile: profile
                            )
                            latestTurboQuantTelemetry.setOutputTokens(completionInfo.generationTokenCount)
                            MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                                to: &providerMetadata,
                                cache: cache,
                                request: request,
                                install: install,
                                profile: profile,
                                contextPlan: turboQuantContextPlan,
                                admissionPlan: turboQuantAdmissionPlan,
                                memoryCounters: deviceMonitor.memoryCounters(),
                                outcome: .admittedSucceeded,
                                inputTokens: input.text.tokens.size,
                                outputTokens: completionInfo.generationTokenCount,
                                speculativeTelemetry: speculative.telemetry,
                                speculativeAutoDisableDecision: speculative.decision
                            )
                            latestTurboQuantTelemetry.setFailureMetadata(providerMetadata)
                            let resolvedFinishReason = Self.finishReason(
                                from: completionInfo.stopReason,
                                generatedTokens: completionInfo.generationTokenCount,
                                emittedTokenCount: tokenCount,
                                maxTokens: generationPlan.effectiveMaxTokens
                            )
                            if resolvedFinishReason == .length {
                                providerMetadata[LocalProviderMetadataKeys.generationIncompleteReason] =
                                    "max_tokens"
                            }
                            finish = InferenceFinish(
                                reason: resolvedFinishReason,
                                message: resolvedFinishReason == .length
                                    ? "Local generation stopped at the active max-token budget before the model emitted a stop sequence."
                                    : nil,
                                providerMetadata: providerMetadata
                            )
                        }
                        if finish == nil {
                            var providerMetadata = Self.localProviderMetadata(
                                from: cache,
                                fallbackProfile: profile,
                                partitionSummary: partitionSummary
                            )
                            providerMetadata.merge(contextMetadata) { _, new in new }
                            latestTurboQuantTelemetry.setOutputTokens(tokenCount)
                            MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                                to: &providerMetadata,
                                cache: cache,
                                request: request,
                                install: install,
                                profile: profile,
                                contextPlan: turboQuantContextPlan,
                                admissionPlan: turboQuantAdmissionPlan,
                                memoryCounters: deviceMonitor.memoryCounters(),
                                outcome: .admittedSucceeded,
                                inputTokens: input.text.tokens.size,
                                outputTokens: tokenCount
                            )
                            latestTurboQuantTelemetry.setFailureMetadata(providerMetadata)
                            finish = InferenceFinish(reason: .stop, providerMetadata: providerMetadata)
                        }
                        return (tokenCount: tokenCount, finish: finish, terminalFailureEmitted: false)
                        }
                    } onCancel: {
                        generationCancellation.cancel()
                    }

                    if let finish = result.finish {
                        continuation.yield(.finish(finish))
                    } else if result.tokenCount == 0 && !result.terminalFailureEmitted {
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
                    let reportedError = Self.localRuntimeFailure(from: error)
                    let failureMessage = reportedError.localizedDescription
                    let failureKind = MLXRuntimeBridge.localFailureKind(from: error)
                    let calibrationOutcome: RuntimeMemoryCalibrationOutcome =
                        failureKind == .fallbackBudgetExceeded ? .fallbackBudgetExceeded : .runtimeFailed
                    let telemetrySnapshot = latestTurboQuantTelemetry.snapshot()
                    var failureMetadata = telemetrySnapshot.failureMetadata
                    MLXRuntimeBridge.appendTurboQuantWave2Metadata(
                        to: &failureMetadata,
                        cache: nil,
                        request: request,
                        install: install,
                        profile: profile,
                        contextPlan: telemetrySnapshot.contextPlan,
                        admissionPlan: telemetrySnapshot.admissionPlan,
                        memoryCounters: deviceMonitor.memoryCounters(),
                        outcome: calibrationOutcome,
                        failureKind: failureKind,
                        failureMessage: failureMessage,
                        inputTokens: telemetrySnapshot.inputTokens,
                        outputTokens: telemetrySnapshot.outputTokens
                    )
                    #if DEBUG
                    await FreezeBreadcrumbJournal.shared.record(
                        stage: "mlx.generation.failed",
                        detail: failureMessage,
                        metadata: runtimeMemoryMetadata(merging: failureMetadata.merging([
                            "model_id": request.modelID.rawValue,
                        ]) { _, new in new })
                    )
                    #endif
                    continuation.yield(
                        InferenceStreamEvent.failure(
                            InferenceStreamFailure(
                                code: failureKind.rawValue,
                                message: failureMessage,
                                recoverable: false,
                                providerMetadata: failureMetadata
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
        return AsyncThrowingStream<InferenceStreamEvent, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(
                InferenceStreamEvent.failure(
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
            try validateLocalChatAssets(for: install, directory: resolvedURL)
            let hints = ModelRuntimeConfigurationHints.infer(
                repository: install.repository,
                modelType: install.modelType,
                processorClass: install.processorClass,
                directory: resolvedURL
            )
            return ResolvedRuntimeModelConfiguration(
                configuration: MLXLMCommon.ModelConfiguration(
                    directory: resolvedURL,
                    // Installed models must use their downloaded tokenizer/template. A registry tokenizer
                    // override can mismatch local weights and produce nonsense completions.
                    tokenizerSource: nil,
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

    private static func validateLocalChatAssets(for install: ModelInstall, directory: URL) throws {
        guard install.modalities.contains(.text),
              localModelRequiresChatTemplate(install)
        else { return }

        let hasTemplateFile = FileManager.default.fileExists(
            atPath: directory.appending(path: "chat_template.jinja").path
        )
        guard hasTemplateFile || localTokenizerConfigHasChatTemplate(in: directory) else {
            throw InferenceError.invalidRequest(
                "Installed chat model \(install.repository) is missing a tokenizer chat template. Delete it and download a compatible MLX Instruct/Chat build; Pines will not use the MLX plain-text fallback because it can produce invalid output."
            )
        }
    }

    private static func localModelRequiresChatTemplate(_ install: ModelInstall) -> Bool {
        let identifiers = [
            install.repository,
            install.modelID.rawValue,
            install.displayName,
            install.modelType,
            install.textConfigModelType,
            install.processorClass,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if identifiers.contains("instruct")
            || identifiers.contains("chat")
            || identifiers.contains("-it")
            || identifiers.contains("_it")
            || identifiers.contains(" it ")
            || identifiers.contains("qwen")
            || identifiers.contains("gemma")
            || identifiers.contains("llama-3")
            || identifiers.contains("llama3") {
            return true
        }
        return false
    }

    private static func localTokenizerConfigHasChatTemplate(in directory: URL) -> Bool {
        let url = directory.appending(path: "tokenizer_config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        if let template = object["chat_template"] as? String,
           !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let templates = object["chat_template"] as? [[String: Any]] {
            return templates.contains { entry in
                guard let template = entry["template"] as? String else { return false }
                return !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        return false
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
        maxTokensOverride: Int? = nil,
        maxKVSizeOverride: Int? = nil,
        turboQuantAdmissionPlan: LocalRuntimeAdmissionPlan? = nil,
        promptTokenCount: Int = 0
    ) -> GenerateParameters {
        func modelShape(for install: ModelInstall) -> (
            layerCount: Int,
            kvHeadCount: Int,
            headDimension: Int
        ) {
            MLXRuntimeBridge.heuristicModelShape(for: install)
        }

        func intClamped(_ value: Int64?) -> Int? {
            guard let value else { return nil }
            if value <= 0 { return 0 }
            if value >= Int64(Int.max) { return Int.max }
            return Int(value)
        }

        func modelMemoryProfile(for install: ModelInstall) -> MLXLMCommon.ModelMemoryProfile? {
            if let localURL = install.localURL,
               let profile = try? MLXLMCommon.ModelMemoryProfile.profile(
                   modelDirectory: localURL,
                   modelID: install.repository
               ) {
                return profile
            }

            let shape = modelShape(for: install)
            let hiddenSize = max(shape.headDimension, shape.headDimension * max(1, shape.kvHeadCount * 4))
            return MLXLMCommon.ModelMemoryProfile(
                modelID: install.repository,
                modelType: install.modelType ?? install.textConfigModelType ?? "unknown",
                layerCount: shape.layerCount,
                hiddenSize: hiddenSize,
                attentionHeadCount: max(1, hiddenSize / max(1, shape.headDimension)),
                kvHeadCount: shape.kvHeadCount,
                headDimension: shape.headDimension,
                quantizationBits: MLXLMCommon.ModelMemoryProfile.detectQuantizationBits(modelID: install.repository),
                isMixtureOfExperts: (install.routedExperts ?? 0) > 1,
                expertCount: install.routedExperts,
                activeExpertCount: install.expertsPerToken,
                weightBytes: intClamped(install.estimatedBytes)
            )
        }

        func turboQuantUserMode(
            from mode: PinesCore.TurboQuantUserMode
        ) -> MLXLMCommon.TurboQuantUserMode {
            switch mode {
            case .fastest:
                .fastest
            case .balanced:
                .balanced
            case .maxContext:
                .maxContext
            case .batterySaver:
                .batterySaver
            }
        }

        func makeMLXTurboQuantFallbackPolicy(
            from contract: PinesCore.TurboQuantFallbackContract
        ) -> MLXLMCommon.TurboQuantFallbackPolicy {
            if contract.failIfCompressedPathUnavailable {
                return .exactRequired
            }
            if contract.allowDecodedLayerLocalFallback || contract.allowFullDecodedFallback {
                return .compressedDecodeAllowed
            }
            if contract.allowPackedFallback {
                return .packedAllowed
            }
            return .exactRequired
        }

        func makeMLXTurboQuantFallbackPolicy(
            from policy: PinesCore.TurboQuantFallbackPolicy
        ) -> MLXLMCommon.TurboQuantFallbackPolicy {
            switch policy {
            case .exactRequired:
                .exactRequired
            case .packedAllowed:
                .packedAllowed
            case .compressedDecodeAllowed:
                .compressedDecodeAllowed
            case .fatalOnFailure:
                .fatalOnFailure
            }
        }

        func turboQuantPerCacheResidentBudgetBytes() -> Int? {
            guard let admissionPlan = turboQuantAdmissionPlan else { return nil }
            let layerCount = install.map { modelShape(for: $0).layerCount } ?? 1
            let totalResidentBytes =
                admissionPlan.memoryZones.compressedKVBytes
                + admissionPlan.memoryZones.rawShadowBytes
                + admissionPlan.memoryZones.packedFallbackBytes
                + admissionPlan.memoryZones.decodedFallbackScratchBytes
            return intClamped(max(1, totalResidentBytes / Int64(max(1, layerCount))))
        }

        let turboQuantSeed: UInt64? =
            profile.quantization.kvCacheStrategy == .turboQuant
            ? MLX.TurboQuantConfiguration.deterministicSeed(
                modelID: install?.repository ?? request.modelID.rawValue,
                revision: install?.revision ?? "main",
                cacheLayoutVersion: MLXRuntimeBridge.turboQuantLayoutVersion
            )
            : nil
        let turboQuantFallbackPolicy: MLXLMCommon.TurboQuantFallbackPolicy
        if let admissionPlan = turboQuantAdmissionPlan {
            turboQuantFallbackPolicy = makeMLXTurboQuantFallbackPolicy(from: admissionPlan.fallbackContract)
        } else if let fallbackPolicy = profile.quantization.turboQuantAdmission?.memoryPlan?.fallbackPolicy {
            turboQuantFallbackPolicy = makeMLXTurboQuantFallbackPolicy(from: fallbackPolicy)
        } else {
            turboQuantFallbackPolicy = .compressedDecodeAllowed
        }
        let turboQuantAdmissionProfile = install.flatMap { modelMemoryProfile(for: $0) }
        let turboQuantRequestedContextLength =
            turboQuantAdmissionPlan?.admittedContextTokens
            ?? profile.quantization.turboQuantAdmission?.admittedContextLength
            ?? maxKVSizeOverride
            ?? profile.quantization.maxKVSize
        let turboQuantAdmission =
            turboQuantAdmissionPlan.flatMap {
                MLXRuntimeBridge.mlxTurboQuantAdmission(from: $0, profile: profile, install: install)
            }
            ?? profile.quantization.turboQuantAdmission.flatMap {
                MLXRuntimeBridge.mlxTurboQuantAdmission(from: $0)
            }
        let resolvedMaxKVSize: Int? =
            if profile.quantization.kvCacheStrategy == .turboQuant,
               let admittedContext = turboQuantAdmissionPlan?.admittedContextTokens {
                min(maxKVSizeOverride ?? admittedContext, admittedContext)
            } else {
                maxKVSizeOverride ?? profile.quantization.maxKVSize
            }

        let resolvedRepetitionPenalty =
            request.sampling.repetitionPenalty
            ?? Self.localTurboQuantDefaultRepetitionPenalty(for: install, profile: profile)

        return GenerateParameters(
            maxTokens: maxTokensOverride ?? request.sampling.maxTokens,
            maxKVSize: resolvedMaxKVSize,
            kvBits: profile.quantization.kvCacheStrategy == .turboQuant ? nil : profile.quantization.kvBits,
            kvGroupSize: profile.quantization.kvGroupSize,
            quantizedKVStart: profile.quantization.quantizedKVStart,
            kvCacheStrategy: Self.mlxKVCacheStrategy(from: profile.quantization.kvCacheStrategy),
            turboQuantPreset: Self.mlxTurboQuantPreset(from: profile.quantization.preset),
            turboQuantBackend: Self.mlxTurboQuantBackend(from: profile.quantization.requestedBackend),
            turboQuantOptimizationPolicy: Self.mlxTurboQuantOptimizationPolicy(
                from: profile.quantization.turboQuantOptimizationPolicy
            ),
            turboQuantSeed: turboQuantSeed,
            turboQuantValueBits: Self.resolvedTurboQuantValueBits(for: profile, install: install),
            turboQuantAdmissionPolicy: profile.quantization.kvCacheStrategy == .turboQuant ? .required : .disabled,
            turboQuantAdmission: turboQuantAdmission,
            turboQuantPerCacheResidentBudgetBytes: turboQuantPerCacheResidentBudgetBytes(),
            turboQuantAdmissionProfile: turboQuantAdmissionProfile,
            turboQuantRequestedContextLength: turboQuantRequestedContextLength,
            turboQuantPromptTokenCount: promptTokenCount,
            turboQuantUserMode: turboQuantUserMode(
                from: turboQuantAdmissionPlan?.selectedMode
                    ?? profile.quantization.turboQuantAdmission?.selectedMode
                    ?? profile.quantization.turboQuantUserMode
            ),
            turboQuantFallbackPolicy: turboQuantFallbackPolicy,
            temperature: request.sampling.temperature,
            topP: request.sampling.topP,
            repetitionPenalty: resolvedRepetitionPenalty,
            repetitionContextSize: profile.repetitionContextSize,
            prefillStepSize: profile.prefillStepSize
        )
    }

    private static func localTurboQuantDefaultRepetitionPenalty(
        for install: ModelInstall?,
        profile: RuntimeProfile
    ) -> Float? {
        guard profile.quantization.kvCacheStrategy == .turboQuant else { return nil }
        let identifiers = [
            profile.quantization.turboQuantProfileID,
            install?.repository,
            install?.modelID.rawValue,
            install?.modelType,
            install?.textConfigModelType,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if identifiers.contains("qwen3.5") || identifiers.contains("qwen3_5")
            || identifiers.contains("qwen3.6") || identifiers.contains("qwen3_6") {
            return 1.12
        }
        if identifiers.contains("llama") || identifiers.contains("gemma") {
            return 1.08
        }
        return nil
    }

    #if canImport(MLX) && canImport(MLXLMCommon)
    private static func promptTokenIDs(from tokens: MLXArray) -> [Int32] {
        tokens.asArray(Int32.self)
    }

    private static func localPromptKVCacheKey(
        request: ChatRequest,
        install: ModelInstall?,
        profile: RuntimeProfile,
        parameters: GenerateParameters,
        hasTools: Bool,
        hasVisionInput: Bool,
        hasAudioInput: Bool
    ) -> LocalPromptKVCacheKey {
        LocalPromptKVCacheKey(
            modelID: request.modelID.rawValue,
            repository: install?.repository ?? request.modelID.rawValue,
            revision: install?.revision ?? "main",
            tokenizerTemplateDigest: tokenizerTemplateDigest(for: install),
            quantizationStrategy: profile.quantization.kvCacheStrategy.rawValue,
            turboQuantPreset: parameters.turboQuantPreset.rawValue,
            turboQuantBackend: parameters.turboQuantBackend.rawValue,
            turboQuantSeed: parameters.turboQuantSeed.map(String.init) ?? "none",
            turboQuantValueBits: parameters.turboQuantValueBits.map(String.init) ?? "none",
            kvBits: parameters.kvBits.map(String.init) ?? "none",
            kvGroupSize: parameters.kvGroupSize,
            quantizedKVStart: parameters.quantizedKVStart,
            maxKVSize: parameters.maxKVSize.map(String.init) ?? "none",
            capabilityShape: [
                "tools=\(hasTools)",
                "vision=\(hasVisionInput)",
                "audio=\(hasAudioInput)",
                "mtp=\(profile.mtpEnabled)",
                "dflash=\(profile.dflashEnabled)",
            ].joined(separator: ";")
        )
    }

    private static func tokenizerTemplateDigest(for install: ModelInstall?) -> String {
        var digest = StableLocalDigest()
        digest.append(install?.repository ?? "unknown")
        digest.append(install?.revision ?? "main")
        guard let install,
              let directory = try? resolvedModelDirectory(for: install)
        else {
            digest.append("no-local-tokenizer")
            return digest.hexString
        }

        for fileName in ["tokenizer_config.json", "chat_template.jinja", "tokenizer.json"] {
            let url = directory.appending(path: fileName)
            digest.append(fileName)
            appendFileDigest(url, to: &digest)
        }
        return digest.hexString
    }

    private static func appendFileDigest(_ url: URL, to digest: inout StableLocalDigest) {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            digest.append("missing")
            return
        }
        defer {
            try? handle.close()
        }
        while let chunk = try? handle.read(upToCount: 64 * 1_024),
              !chunk.isEmpty {
            digest.append(contentsOf: chunk)
        }
    }

    private static func promptCacheMissReason(
        input: LMInput,
        promptTokenIDs: [Int32],
        profile: RuntimeProfile,
        hasTools: Bool,
        hasVisionInput: Bool,
        hasAudioInput: Bool
    ) -> String? {
        guard profile.promptCacheEnabled else { return "profile_disabled" }
        guard !profile.mtpEnabled else { return "mtp_enabled" }
        guard !hasTools else { return "tools_enabled" }
        guard !hasVisionInput, input.image == nil, input.video == nil else { return "vision_or_video_input" }
        guard !hasAudioInput, input.audio == nil else { return "audio_input" }
        guard !promptTokenIDs.isEmpty else { return "empty_prompt" }
        guard profile.quantization.runtimePressureReason != .lowMemory,
              !profile.quantization.thermalDownshiftActive else {
            return "runtime_pressure"
        }
        return nil
    }

    private static func mlxCachePressureAction(for profile: RuntimeProfile) -> String {
        if profile.quantization.runtimePressureReason == .lowMemory
            || profile.quantization.thermalDownshiftActive {
            return "immediate_clear"
        }
        return "idle_decay"
    }
    #endif

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
               modality: install.effectiveTurboQuantModalities.contains(.vision) ? .visionText : .text,
	               parameterCountB: install.resolvedParameterCount.map { Double($0) / 1_000_000_000 },
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

    private static func cacheCounts(from cache: [KVCache]) -> (attention: Int, nativeState: Int) {
        let nativeState = cache.filter { cacheEntry in
            String(describing: Swift.type(of: cacheEntry)).localizedCaseInsensitiveContains("mamba")
        }.count
        return (attention: max(0, cache.count - nativeState), nativeState: nativeState)
    }

    private static func localProviderMetadata(
        from cache: [KVCache],
        fallbackProfile profile: RuntimeProfile,
        partitionSummary: String? = nil
    ) -> [String: String] {
        let cacheCounts = cacheCounts(from: cache)
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
                LocalProviderMetadataKeys.turboQuantAdmissionDecision: "turboQuant",
                LocalProviderMetadataKeys.turboQuantAdmissionReason: profile.quantization.activeFallbackReason ?? "TurboQuant admitted",
                LocalProviderMetadataKeys.runtimePressureReason: profile.quantization.runtimePressureReason.rawValue,
                LocalProviderMetadataKeys.runtimeLowPowerMode: String(profile.quantization.memoryCounters.lowPowerModeEnabled ?? false),
                LocalProviderMetadataKeys.runtimePrefillStepSize: String(profile.prefillStepSize),
                LocalProviderMetadataKeys.mtpEnabled: String(profile.mtpEnabled),
                LocalProviderMetadataKeys.audioEnabled: String(profile.audioEnabled),
                LocalProviderMetadataKeys.dflashEnabled: String(profile.dflashEnabled),
                LocalProviderMetadataKeys.attentionCacheCount: String(cacheCounts.attention),
                LocalProviderMetadataKeys.nativeStateCacheCount: String(cacheCounts.nativeState),
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
            if !profile.quantization.turboQuantProfileDiagnostics.isEmpty {
                metadata[LocalProviderMetadataKeys.turboQuantProfileDiagnostics] = profile.quantization.turboQuantProfileDiagnostics.joined(separator: " | ")
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
            LocalProviderMetadataKeys.turboQuantAdmissionDecision: quantization.kvCacheStrategy == .turboQuant ? "turboQuant" : "plain_rotating_kv",
            LocalProviderMetadataKeys.turboQuantAdmissionReason: quantization.activeFallbackReason ?? "TurboQuant not active for this request",
            LocalProviderMetadataKeys.runtimePressureReason: quantization.runtimePressureReason.rawValue,
            LocalProviderMetadataKeys.runtimeLowPowerMode: String(quantization.memoryCounters.lowPowerModeEnabled ?? false),
            LocalProviderMetadataKeys.runtimePrefillStepSize: String(profile.prefillStepSize),
            LocalProviderMetadataKeys.mtpEnabled: String(profile.mtpEnabled),
            LocalProviderMetadataKeys.audioEnabled: String(profile.audioEnabled),
            LocalProviderMetadataKeys.dflashEnabled: String(profile.dflashEnabled),
            LocalProviderMetadataKeys.attentionCacheCount: String(cacheCounts.attention),
            LocalProviderMetadataKeys.nativeStateCacheCount: String(cacheCounts.nativeState),
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
        if !quantization.turboQuantProfileDiagnostics.isEmpty {
            metadata[LocalProviderMetadataKeys.turboQuantProfileDiagnostics] = quantization.turboQuantProfileDiagnostics.joined(separator: " | ")
        }
        appendRuntimeFeatureMetadata(to: &metadata, partitionSummary: partitionSummary)
        let turboQuantPlanned = quantization.kvCacheStrategy == .turboQuant
        if turboQuantPlanned, let preset = quantization.preset {
            metadata[LocalProviderMetadataKeys.turboQuantPreset] = preset.rawValue
        }
        if turboQuantPlanned, let valueBits = quantization.turboQuantValueBits {
            metadata[LocalProviderMetadataKeys.turboQuantValueBits] = String(valueBits)
        }
        if turboQuantPlanned, let requestedBackend = quantization.requestedBackend {
            metadata[LocalProviderMetadataKeys.turboQuantRequestedBackend] = requestedBackend.rawValue
        }
        if turboQuantPlanned, let activeBackend = quantization.activeBackend {
            metadata[LocalProviderMetadataKeys.turboQuantActiveBackend] = activeBackend.rawValue
        }
        if turboQuantPlanned, let attentionPath = quantization.activeAttentionPath {
            metadata[LocalProviderMetadataKeys.turboQuantAttentionPath] = attentionPath.rawValue
        }
        if turboQuantPlanned, let kernelProfile = quantization.metalKernelProfile {
            metadata[LocalProviderMetadataKeys.turboQuantKernelProfile] = kernelProfile.rawValue
        }
        if turboQuantPlanned, let selfTestStatus = quantization.metalSelfTestStatus {
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

    private static func finishReason(
        from reason: GenerateStopReason,
        generatedTokens: Int,
        emittedTokenCount: Int,
        maxTokens: Int?
    ) -> InferenceFinishReason {
        switch reason {
        case .stop:
            return .stop
        case .length:
            return .length
        case .cancelled:
            if let maxTokens, max(generatedTokens, emittedTokenCount) >= maxTokens {
                return .length
            }
            return .cancelled
        }
    }

    private nonisolated static var hasCanonicalDeepSeekV4RuntimeSupport: Bool {
        false
    }

    private nonisolated static var hasGemma4AssistantRuntimeSupport: Bool {
        false
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
