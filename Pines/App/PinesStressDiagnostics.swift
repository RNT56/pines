import Foundation
import PinesCore

#if DEBUG
enum PinesStressContextMode: String, Codable, Sendable {
    case off
    case sweep
    case high
    case max
    case suite
}

struct PinesStressConfiguration: Sendable {
    var mode: String
    var runID: String
    var iterations: Int
    var perIterationTimeoutSeconds: TimeInterval
    var recoveryCooldownSeconds: TimeInterval
    var prompt: String
    var resetBreadcrumbs: Bool
    var contextMode: PinesStressContextMode
    var contextSweepStartTokens: Int
    var contextSweepStepTokens: Int
    var contextSweepMaxTokens: Int?
    var contextTargetTokens: Int?
    var contextHighWatermarkRatio: Double
    var contextReserveTokens: Int

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PinesStressConfiguration? {
        let mode = environment["PINES_STRESS_MODE"]
            ?? (arguments.contains("--pines-stress-local-generation") ? "local-generation" : nil)
        guard let mode, mode == "local-generation" else { return nil }
        return PinesStressConfiguration(
            mode: mode,
            runID: environment["PINES_STRESS_RUN_ID"] ?? UUID().uuidString,
            iterations: max(1, Int(environment["PINES_STRESS_ITERATIONS"] ?? "") ?? 25),
            perIterationTimeoutSeconds: max(30, TimeInterval(environment["PINES_STRESS_ITERATION_TIMEOUT_SECONDS"] ?? "") ?? 180),
            recoveryCooldownSeconds: max(0, TimeInterval(environment["PINES_STRESS_RECOVERY_COOLDOWN_SECONDS"] ?? "") ?? 15),
            prompt: environment["PINES_STRESS_PROMPT"] ?? "Continue this local stress chat with a concise diagnostic paragraph.",
            resetBreadcrumbs: environment["PINES_STRESS_RESET_BREADCRUMBS"] != "0",
            contextMode: Self.contextMode(environment: environment),
            contextSweepStartTokens: max(512, Int(environment["PINES_STRESS_CONTEXT_START_TOKENS"] ?? "") ?? 1_024),
            contextSweepStepTokens: max(256, Int(environment["PINES_STRESS_CONTEXT_STEP_TOKENS"] ?? "") ?? 2_048),
            contextSweepMaxTokens: Self.optionalTokenCount(environment, key: "PINES_STRESS_CONTEXT_MAX_TOKENS"),
            contextTargetTokens: Self.optionalTokenCount(environment, key: "PINES_STRESS_CONTEXT_TARGET_TOKENS"),
            contextHighWatermarkRatio: Self.contextHighWatermarkRatio(environment: environment),
            contextReserveTokens: max(128, Int(environment["PINES_STRESS_CONTEXT_RESERVE_TOKENS"] ?? "") ?? 1_024)
        )
    }

    func targetContextTokens(iteration: Int, runtimeMaxContextTokens: Int?) -> Int? {
        let maximum = contextCeiling(runtimeMaxContextTokens: runtimeMaxContextTokens)
        switch contextMode {
        case .off:
            return nil
        case .sweep:
            let requested = contextSweepStartTokens + max(0, iteration - 1) * contextSweepStepTokens
            return min(maximum, requested)
        case .high:
            return highWatermarkTarget(maximum: maximum)
        case .max:
            return maximum
        case .suite:
            if iteration == 1 {
                return min(maximum, contextSweepStartTokens)
            }
            if iteration == 2 {
                return highWatermarkTarget(maximum: maximum)
            }
            return maximum
        }
    }

    func requiresRuntimeContextWindow() -> Bool {
        switch contextMode {
        case .off, .sweep:
            false
        case .high, .max, .suite:
            contextSweepMaxTokens == nil && contextTargetTokens == nil
        }
    }

    func contextPlanPreview(iterations: Int, runtimeMaxContextTokens: Int?) -> String {
        let previewCount = min(max(1, iterations), 12)
        let preview = (1...previewCount)
            .map { targetContextTokens(iteration: $0, runtimeMaxContextTokens: runtimeMaxContextTokens).map(String.init) ?? "short" }
            .joined(separator: ",")
        return iterations > previewCount ? "\(preview),..." : preview
    }

    private static func contextMode(environment: [String: String]) -> PinesStressContextMode {
        if let raw = environment["PINES_STRESS_CONTEXT_MODE"] ?? environment["PINES_STRESS_CONTEXT_TEST"],
           let mode = PinesStressContextMode(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return mode
        }
        return environment["PINES_STRESS_CONTEXT_SWEEP"] == "1" ? .sweep : .off
    }

    private static func contextHighWatermarkRatio(environment: [String: String]) -> Double {
        let raw = Double(environment["PINES_STRESS_CONTEXT_HIGH_RATIO"] ?? "") ?? 0.75
        return min(0.95, max(0.10, raw))
    }

    private static func optionalTokenCount(_ environment: [String: String], key: String) -> Int? {
        guard let raw = Int(environment[key] ?? "") else { return nil }
        return max(512, raw)
    }

    private func contextCeiling(runtimeMaxContextTokens: Int?) -> Int {
        if let contextTargetTokens {
            return max(512, contextTargetTokens)
        }
        let runtimeCeiling = runtimeMaxContextTokens.map { max(512, $0 - contextReserveTokens) }
        return contextSweepMaxTokens ?? runtimeCeiling ?? contextSweepStartTokens
    }

    private func highWatermarkTarget(maximum: Int) -> Int {
        let requested = Int(Double(maximum) * contextHighWatermarkRatio)
        return min(maximum, max(512, requested))
    }
}

struct PinesStressStatus: Codable, Sendable {
    var runID: String
    var mode: String
    var state: String
    var iteration: Int
    var iterations: Int
    var threadID: String?
    var modelID: String?
    var contextMode: PinesStressContextMode
    var runtimeMaxContextTokens: Int?
    var targetContextTokens: Int?
    var message: String?
    var updatedAt: Date
}

actor PinesStressStatusWriter {
    static let shared = PinesStressStatusWriter()
    static let statusFileName = "pines-stress-status.json"

    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    static var statusFileURL: URL {
        FreezeBreadcrumbJournal.defaultDiagnosticsDirectoryURL()
            .appendingPathComponent(statusFileName)
    }

    func write(_ status: PinesStressStatus) async {
        do {
            let url = Self.statusFileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(status).write(to: url, options: .atomic)
        } catch {
            // Stress status is diagnostic-only and must not affect the app.
        }
    }
}
#endif
