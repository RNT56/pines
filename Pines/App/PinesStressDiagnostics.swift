import Foundation
import PinesCore

#if DEBUG
struct PinesStressConfiguration: Sendable {
    var mode: String
    var runID: String
    var iterations: Int
    var perIterationTimeoutSeconds: TimeInterval
    var recoveryCooldownSeconds: TimeInterval
    var prompt: String
    var resetBreadcrumbs: Bool
    var contextSweepEnabled: Bool
    var contextSweepStartTokens: Int
    var contextSweepStepTokens: Int
    var contextSweepMaxTokens: Int?

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
            contextSweepEnabled: environment["PINES_STRESS_CONTEXT_SWEEP"] == "1",
            contextSweepStartTokens: max(512, Int(environment["PINES_STRESS_CONTEXT_START_TOKENS"] ?? "") ?? 1_024),
            contextSweepStepTokens: max(256, Int(environment["PINES_STRESS_CONTEXT_STEP_TOKENS"] ?? "") ?? 2_048),
            contextSweepMaxTokens: Int(environment["PINES_STRESS_CONTEXT_MAX_TOKENS"] ?? "")
        )
    }

    func targetContextTokens(iteration: Int, runtimeMaxContextTokens: Int?) -> Int? {
        guard contextSweepEnabled else { return nil }
        let discoveredMaximum = runtimeMaxContextTokens.map { max(512, $0 - 512) }
        let maximum = contextSweepMaxTokens ?? discoveredMaximum ?? contextSweepStartTokens
        let requested = contextSweepStartTokens + max(0, iteration - 1) * contextSweepStepTokens
        return min(maximum, requested)
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
