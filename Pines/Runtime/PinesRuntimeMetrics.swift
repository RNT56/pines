import Foundation
import OSLog
import PinesCore

#if canImport(MetricKit)
import MetricKit
#endif

final class PinesRuntimeMetrics: NSObject, @unchecked Sendable {
    static let shared = PinesRuntimeMetrics()

    private let logger = Logger(subsystem: "com.schtack.pines", category: "runtime")
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        #if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        #endif
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

    func recordVaultRetrieval(resultCount: Int, elapsedSeconds: TimeInterval) {
        logger.info(
            "vault_retrieval results=\(resultCount, privacy: .public) elapsed=\(elapsedSeconds, privacy: .public)"
        )
    }

    func recordMemoryPressure(_ counters: RuntimeMemoryCounters) {
        logger.warning(
            "memory_pressure physical=\(counters.physicalMemoryBytes ?? 0, privacy: .public) available=\(counters.availableMemoryBytes ?? -1, privacy: .public) thermal=\(counters.thermalState ?? "unknown", privacy: .public)"
        )
    }

    func recordStartupPhase(_ phase: String, elapsedSeconds: TimeInterval) {
        logger.info(
            "startup_phase phase=\(phase, privacy: .public) elapsed=\(elapsedSeconds, privacy: .public)"
        )
    }
}

#if canImport(MetricKit)
extension PinesRuntimeMetrics: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        logger.info("metrickit_payloads count=\(payloads.count, privacy: .public)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        logger.warning("metrickit_diagnostics count=\(payloads.count, privacy: .public)")
    }
}
#endif
