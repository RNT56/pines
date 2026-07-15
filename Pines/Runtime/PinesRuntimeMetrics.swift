import Foundation
import OSLog
import PinesCore

#if canImport(MetricKit)
import MetricKit
#endif

enum PinesPerformanceOperation: Sendable {
    case launchToInteractive
    case threadToFirstMessage
    case galleryToFirstThumbnail
    case artifactLibraryDerive
    case thumbnailDecode
    case providerLifecycleRefresh
    case providerPollCycle
    case vaultDetailReady
    case transferStage
    case transferEnqueued
}

struct PinesPerformanceInterval: @unchecked Sendable {
    fileprivate let operation: PinesPerformanceOperation
    fileprivate let state: OSSignpostIntervalState
}

// SAFETY: MetricKit requires an NSObject subscriber. Mutable state is limited to
// `isStarted` and is protected by `lock`; Logger is thread-safe.
final class PinesRuntimeMetrics: NSObject, @unchecked Sendable {
    static let shared = PinesRuntimeMetrics()

    private let logger = Logger(subsystem: "com.schtack.pines", category: "runtime")
    private let signposter = OSSignposter(subsystem: "com.schtack.pines", category: "performance")
    private let lock = NSLock()
    private var isStarted = false

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted else { return }
        isStarted = true
        #if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        #endif
    }

    func begin(_ operation: PinesPerformanceOperation) -> PinesPerformanceInterval {
        let state: OSSignpostIntervalState
        switch operation {
        case .launchToInteractive:
            state = signposter.beginInterval("launch_to_interactive")
        case .threadToFirstMessage:
            state = signposter.beginInterval("thread_to_first_message")
        case .galleryToFirstThumbnail:
            state = signposter.beginInterval("gallery_to_first_thumbnail")
        case .artifactLibraryDerive:
            state = signposter.beginInterval("artifact_library_derive")
        case .thumbnailDecode:
            state = signposter.beginInterval("thumbnail_decode")
        case .providerLifecycleRefresh:
            state = signposter.beginInterval("provider_lifecycle_refresh")
        case .providerPollCycle:
            state = signposter.beginInterval("provider_poll_cycle")
        case .vaultDetailReady:
            state = signposter.beginInterval("vault_detail_ready")
        case .transferStage:
            state = signposter.beginInterval("transfer_stage")
        case .transferEnqueued:
            state = signposter.beginInterval("transfer_enqueued")
        }
        return PinesPerformanceInterval(operation: operation, state: state)
    }

    func end(_ interval: PinesPerformanceInterval) {
        switch interval.operation {
        case .launchToInteractive:
            signposter.endInterval("launch_to_interactive", interval.state)
        case .threadToFirstMessage:
            signposter.endInterval("thread_to_first_message", interval.state)
        case .galleryToFirstThumbnail:
            signposter.endInterval("gallery_to_first_thumbnail", interval.state)
        case .artifactLibraryDerive:
            signposter.endInterval("artifact_library_derive", interval.state)
        case .thumbnailDecode:
            signposter.endInterval("thumbnail_decode", interval.state)
        case .providerLifecycleRefresh:
            signposter.endInterval("provider_lifecycle_refresh", interval.state)
        case .providerPollCycle:
            signposter.endInterval("provider_poll_cycle", interval.state)
        case .vaultDetailReady:
            signposter.endInterval("vault_detail_ready", interval.state)
        case .transferStage:
            signposter.endInterval("transfer_stage", interval.state)
        case .transferEnqueued:
            signposter.endInterval("transfer_enqueued", interval.state)
        }
    }

    func recordGenerationMetrics(_ metrics: InferenceMetrics, modelID: ModelID) {
        logger.info(
            "generation model=\(modelID.rawValue, privacy: .public) prompt_tps=\(metrics.promptTokensPerSecond ?? 0, privacy: .public) completion_tps=\(metrics.completionTokensPerSecond ?? 0, privacy: .public) prompt_tokens=\(metrics.promptTokens, privacy: .public) completion_tokens=\(metrics.completionTokens, privacy: .public)"
        )
    }

    func recordGenerationFinished(modelID: ModelID, outputTokens: Int, elapsedSeconds: TimeInterval) {
        logger.info(
            "generation_finished model=\(modelID.rawValue, privacy: .public) output_tokens=\(outputTokens, privacy: .public) elapsed=\(elapsedSeconds, privacy: .public)"
        )
    }

    func recordGenerationWatchdog(modelID: ModelID, stage: String, elapsedSeconds: TimeInterval) {
        logger.warning(
            "generation_watchdog model=\(modelID.rawValue, privacy: .public) stage=\(stage, privacy: .public) elapsed=\(elapsedSeconds, privacy: .public)"
        )
    }

    func recordInterruptedChatRepair(repairedMessages: Int, elapsedSeconds: TimeInterval) {
        logger.warning(
            "interrupted_chat_repair messages=\(repairedMessages, privacy: .public) elapsed=\(elapsedSeconds, privacy: .public)"
        )
    }

    func recordChatStreamUIUpdate(messageID: UUID, characters: Int, tokenCount: Int, live: Bool) {
        logger.debug(
            "chat_stream_ui_update message=\(messageID.uuidString, privacy: .private(mask: .hash)) chars=\(characters, privacy: .public) tokens=\(tokenCount, privacy: .public) live=\(live, privacy: .public)"
        )
    }

    func recordChatStreamPersistenceUpdate(messageID: UUID, characters: Int, tokenCount: Int) {
        logger.debug(
            "chat_stream_persistence_update message=\(messageID.uuidString, privacy: .private(mask: .hash)) chars=\(characters, privacy: .public) tokens=\(tokenCount, privacy: .public)"
        )
    }

    func recordVaultRetrieval(resultCount: Int, elapsedSeconds: TimeInterval) {
        logger.info(
            "vault_retrieval results=\(resultCount, privacy: .public) elapsed=\(elapsedSeconds, privacy: .public)"
        )
    }

    func recordMemoryPressure(_ counters: RuntimeMemoryCounters) {
        logger.warning(
            "memory_pressure physical=\(counters.physicalMemoryBytes ?? 0, privacy: .public) available=\(counters.availableMemoryBytes ?? -1, privacy: .public) thermal=\(counters.thermalState ?? "unknown", privacy: .public) mlx_active=\(counters.mlxActiveMemoryBytes ?? -1, privacy: .public) mlx_cache=\(counters.mlxCacheMemoryBytes ?? -1, privacy: .public) mlx_peak=\(counters.mlxPeakMemoryBytes ?? -1, privacy: .public) mlx_cache_limit=\(counters.mlxCacheLimitBytes ?? -1, privacy: .public)"
        )
    }

    func recordThermalPressure(_ counters: RuntimeMemoryCounters) {
        logger.warning(
            "thermal_pressure physical=\(counters.physicalMemoryBytes ?? 0, privacy: .public) available=\(counters.availableMemoryBytes ?? -1, privacy: .public) thermal=\(counters.thermalState ?? "unknown", privacy: .public) mlx_active=\(counters.mlxActiveMemoryBytes ?? -1, privacy: .public) mlx_cache=\(counters.mlxCacheMemoryBytes ?? -1, privacy: .public) mlx_peak=\(counters.mlxPeakMemoryBytes ?? -1, privacy: .public) mlx_cache_limit=\(counters.mlxCacheLimitBytes ?? -1, privacy: .public)"
        )
    }

    func recordStartupPhase(_ phase: String, elapsedSeconds: TimeInterval) {
        logger.info(
            "startup_phase phase=\(phase, privacy: .public) elapsed=\(elapsedSeconds, privacy: .public)"
        )
    }

    func recordStartupFailure(_ phase: String, error: any Error) {
        logger.error(
            "startup_failure phase=\(phase, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
    }

    func recordRecoverableIssue(_ component: String, message: String) {
        logger.warning(
            "recoverable_issue component=\(component, privacy: .public) message=\(message, privacy: .public)"
        )
    }
}

#if canImport(MetricKit)
extension PinesRuntimeMetrics: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        logger.info(
            "metrickit_payload_summary count=\(payloads.count, privacy: .public) raw_payload_persisted=false"
        )
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        logger.warning(
            "metrickit_diagnostic_summary count=\(payloads.count, privacy: .public) raw_payload_persisted=false"
        )
    }
}
#endif
