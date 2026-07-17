import Foundation
import Darwin
import PinesCore

#if DEBUG && PINES_ENABLE_IN_APP_TURBOQUANT_BENCH && canImport(TurboQuantBench) && canImport(MLXLMCommon)
import MLXLMCommon
import TurboQuantBench

private struct PinesTurboQuantBenchConfiguration: Sendable {
    var runID: String
    var contexts: [Int]
    var schemes: [TurboQuantScheme]
    var runtimeModes: [String]
    var precisionPolicies: [String]
    var sparseValuePolicies: [String]
    var iterations: Int
    var warmupIterations: Int

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PinesTurboQuantBenchConfiguration? {
        let enabled = environment["PINES_TURBOQUANT_BENCH"] == "1"
            || environment["PINES_TQ_BENCH"] == "1"
            || arguments.contains("--pines-turboquant-bench")
        guard enabled else { return nil }

        let fullMatrix = environment["PINES_TQ_BENCH_FULL"] == "1"
        return PinesTurboQuantBenchConfiguration(
            runID: environment["PINES_TQ_BENCH_RUN_ID"] ?? UUID().uuidString,
            contexts: Self.contexts(environment: environment, fullMatrix: fullMatrix),
            schemes: Self.schemes(environment: environment, fullMatrix: fullMatrix),
            runtimeModes: Self.stringList(
                environment["PINES_TQ_BENCH_RUNTIME_MODES"],
                defaultValue: fullMatrix
                    ? ["rawPreferred", "throughputTurboQuant", "capacityTurboQuant"]
                    : ["capacityTurboQuant"]
            ),
            precisionPolicies: Self.stringList(
                environment["PINES_TQ_BENCH_PRECISION_POLICIES"],
                defaultValue: fullMatrix
                    ? ["qwen-q4-default", "symmetric-turbo4v2"]
                    : ["qwen-q4-default"]
            ),
            sparseValuePolicies: Self.stringList(
                environment["PINES_TQ_BENCH_SPARSE_V"],
                defaultValue: fullMatrix ? ["off", "auto"] : ["off"]
            ),
            iterations: max(1, Int(environment["PINES_TQ_BENCH_ITERATIONS"] ?? "") ?? (fullMatrix ? 12 : 3)),
            warmupIterations: max(0, Int(environment["PINES_TQ_BENCH_WARMUP"] ?? "") ?? (fullMatrix ? 3 : 1))
        )
    }

    private static func contexts(environment: [String: String], fullMatrix: Bool) -> [Int] {
        if let parsed = parseIntegerList(environment["PINES_TQ_BENCH_CONTEXTS"]), !parsed.isEmpty {
            return parsed
        }
        return fullMatrix ? [8_192, 16_384, 32_768, 65_536, 131_072] : [8_192]
    }

    private static func schemes(environment: [String: String], fullMatrix: Bool) -> [TurboQuantScheme] {
        if let raw = environment["PINES_TQ_BENCH_SCHEMES"] {
            let parsed = raw.split(separator: ",").compactMap {
                TurboQuantScheme(normalizing: String($0))
            }.filter { $0 != .disabled }
            if !parsed.isEmpty {
                return parsed
            }
        }
        return fullMatrix ? [.turbo8, .turbo4v2, .turbo3_5] : [.turbo4v2]
    }

    private static func parseIntegerList(_ value: String?) -> [Int]? {
        guard let value else { return nil }
        return value.split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { $0 > 0 }
    }

    private static func stringList(_ value: String?, defaultValue: [String]) -> [String] {
        guard let value else { return defaultValue }
        let parsed = value.split(separator: ",").map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { !$0.isEmpty }
        return parsed.isEmpty ? defaultValue : parsed
    }
}

private struct PinesTurboQuantBenchStatus: Codable, Sendable {
    var runID: String
    var state: String
    var resultFileName: String?
    var resultCount: Int
    var failedCount: Int
    var skippedCount: Int
    var message: String?
    var updatedAt: Date
}

private struct PinesTurboQuantBenchPayload: Codable, Sendable {
    var runID: String
    var modelProfile: String
    var contexts: [Int]
    var schemes: [String]
    var runtimeModes: [String]
    var precisionPolicies: [String]
    var sparseValuePolicies: [String]
    var matrixExecution: String
    var comparisonBasis: String
    var iterations: Int
    var warmupIterations: Int
    var compatibilityPairID: String
    var appHost: PinesTurboQuantBenchAppHost
    var hybridNativeDiagnostics: PinesTurboQuantBenchHybridNativeDiagnostics
    var table: String
    var results: [TurboQuantBenchResult]
    var createdAt: Date
}

private struct PinesTurboQuantBenchAppHost: Codable, Sendable {
    var pinesCommit: String?
    var mlxPinPair: String
    var deviceID: String?
    var hardwareModel: String
    var osVersion: String
    var launchMode: String

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PinesTurboQuantBenchAppHost {
        PinesTurboQuantBenchAppHost(
            pinesCommit: environment["PINES_TQ_BENCH_PINES_COMMIT"],
            mlxPinPair: MLXRuntimeBridge.turboQuantCompatibilityPairID,
            deviceID: environment["PINES_TQ_BENCH_DEVICE_ID"],
            hardwareModel: Self.hardwareModelIdentifier(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            launchMode: "pines-debug-app-host"
        )
    }

    private static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}

private struct PinesTurboQuantBenchHybridNativeDiagnostics: Codable, Sendable {
    var benchmarkModelType: String
    var cacheTopology: String
    var hybridAttentionKVPolicy: String
    var nativeStateCachePolicy: String
    var requestedNativeBackend: String
    var nativeBackendPerformanceEvidence: String
    var performanceParityEvidence: String
    var realModelInferenceEvidence: String
    var productClaimLevel: String

    static func qwen35AppHostCurrent() -> PinesTurboQuantBenchHybridNativeDiagnostics {
        PinesTurboQuantBenchHybridNativeDiagnostics(
            benchmarkModelType: "qwen3_5",
            cacheTopology: PinesTurboQuantCacheTopology.hybridAttentionKVAndNativeState.rawValue,
            hybridAttentionKVPolicy: "turboquant-attention-kv",
            nativeStateCachePolicy: "exact-mlx-native-state",
            requestedNativeBackend: TurboQuantRuntimeBackend.metalPolarQJL.rawValue,
            nativeBackendPerformanceEvidence: "not-proven",
            performanceParityEvidence: "not-proven",
            realModelInferenceEvidence: "missing",
            productClaimLevel: RuntimeEvidenceLevel.unverified.rawValue
        )
    }
}

private actor PinesTurboQuantBenchStatusWriter {
    static let shared = PinesTurboQuantBenchStatusWriter()
    static let statusFileName = "pines-turboquant-bench-status.json"

    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    static var diagnosticsDirectoryURL: URL {
        FreezeBreadcrumbJournal.defaultDiagnosticsDirectoryURL()
    }

    static var statusFileURL: URL {
        diagnosticsDirectoryURL.appendingPathComponent(statusFileName)
    }

    func write(_ status: PinesTurboQuantBenchStatus) async {
        do {
            let url = Self.statusFileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(status).write(to: url, options: .atomic)
        } catch {
            // Benchmark status is diagnostic-only and must not affect normal app launch.
        }
    }

    func writePayload(_ payload: PinesTurboQuantBenchPayload) async throws -> String {
        let fileName = "pines-turboquant-bench-\(payload.runID).json"
        let url = Self.diagnosticsDirectoryURL.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: url.deletingPathExtension().deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(payload).write(to: url, options: .atomic)
        return fileName
    }
}

private enum PinesTurboQuantBenchRunner {
    static func run(configuration: PinesTurboQuantBenchConfiguration) throws -> PinesTurboQuantBenchPayload {
        let profile = try requireProfile()
        #if PINES_TQ_BENCH_WAVE6_API
        let cases = configuration.contexts.flatMap { context in
            configuration.schemes.flatMap { scheme in
                configuration.runtimeModes.compactMap(Self.runtimeMode).flatMap { runtimeMode in
                    configuration.precisionPolicies.compactMap(Self.precisionPolicy).flatMap { precisionPolicy in
                        configuration.sparseValuePolicies.compactMap(Self.sparseValuePolicy).map { sparseValuePolicy in
                            TurboQuantBenchCase.qwen35_2B(
                                contextLength: context,
                                scheme: scheme,
                                runtimeMode: runtimeMode,
                                precisionPolicy: precisionPolicy,
                                sparseValuePolicy: sparseValuePolicy
                            )
                        }
                    }
                }
            }
        }
        let matrixExecution = "wave6-runtime-matrix"
        #else
        let cases = configuration.contexts.flatMap { context in
            configuration.schemes.map {
                TurboQuantBenchCase.qwen35_2B(contextLength: context, scheme: $0)
            }
        }
        let matrixExecution = "legacy-capacity-only"
        #endif
        let results = TurboQuantBench.sweep(
            profile: profile,
            cases: cases,
            iterations: configuration.iterations,
            warmupIterations: configuration.warmupIterations
        )
        return PinesTurboQuantBenchPayload(
            runID: configuration.runID,
            modelProfile: profile.id,
            contexts: configuration.contexts,
            schemes: configuration.schemes.map(\.rawValue),
            runtimeModes: configuration.runtimeModes,
            precisionPolicies: configuration.precisionPolicies,
            sparseValuePolicies: configuration.sparseValuePolicies,
            matrixExecution: matrixExecution,
            comparisonBasis: "synthetic-attention-shape-smoke; release comparisons require real-model-inference-v1",
            iterations: configuration.iterations,
            warmupIterations: configuration.warmupIterations,
            compatibilityPairID: MLXRuntimeBridge.turboQuantCompatibilityPairID,
            appHost: PinesTurboQuantBenchAppHost.current(),
            hybridNativeDiagnostics: .qwen35AppHostCurrent(),
            table: TurboQuantBench.renderTable(results),
            results: results,
            createdAt: Date()
        )
    }

    #if PINES_TQ_BENCH_WAVE6_API
    private static func runtimeMode(_ rawValue: String) -> MLXLMCommon.TurboQuantRuntimeMode? {
        MLXLMCommon.TurboQuantRuntimeMode(rawValue: rawValue)
    }

    private static func precisionPolicy(
        _ rawValue: String
    ) -> MLXLMCommon.TurboQuantKVPrecisionPolicy? {
        switch rawValue {
        case "qwen-q4-default", "qwen":
            return .qwenQ4Default
        case "symmetric-turbo4v2", "turbo4v2":
            return MLXLMCommon.TurboQuantKVPrecisionPolicy(
                key: .turbo4v2,
                value: .turbo4v2,
                boundary: .profileDefault
            )
        case "turbo8":
            return MLXLMCommon.TurboQuantKVPrecisionPolicy(
                key: .turbo8,
                value: .turbo8,
                boundary: .profileDefault
            )
        default:
            return nil
        }
    }

    private static func sparseValuePolicy(
        _ rawValue: String
    ) -> MLXLMCommon.TurboQuantSparseValuePolicy? {
        switch rawValue {
        case "off":
            return .off
        case "auto":
            return .profileDefault
        case "force":
            return .force(threshold: MLXLMCommon.TurboQuantSparseValuePolicy.defaultAutoThreshold)
        default:
            return nil
        }
    }
    #endif

    private static func requireProfile() throws -> TurboQuantProfile {
        guard let profile = TurboQuantProfileRegistry.bundled.profile(
            for: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
            modelType: "qwen3_5",
            keyHeadDimension: 256,
            valueHeadDimension: 256
        ) else {
            throw PinesTurboQuantBenchError.missingQwenProfile
        }
        return profile
    }
}

private enum PinesTurboQuantBenchError: Error, LocalizedError {
    case missingQwenProfile

    var errorDescription: String? {
        switch self {
        case .missingQwenProfile:
            "Qwen3.5-2B TurboQuant benchmark profile is unavailable."
        }
    }
}
#endif

#if DEBUG
extension PinesAppModel {
    func runLaunchTurboQuantBenchIfNeeded() async {
        #if PINES_ENABLE_IN_APP_TURBOQUANT_BENCH && canImport(TurboQuantBench) && canImport(MLXLMCommon)
        guard let configuration = PinesTurboQuantBenchConfiguration.current() else { return }
        await PinesTurboQuantBenchStatusWriter.shared.write(
            PinesTurboQuantBenchStatus(
                runID: configuration.runID,
                state: "starting",
                resultFileName: nil,
                resultCount: 0,
                failedCount: 0,
                skippedCount: 0,
                message: "TurboQuant benchmark is starting.",
                updatedAt: Date()
            )
        )
        await FreezeBreadcrumbJournal.shared.record(
            stage: "turboquant_bench.launch.detected",
            runID: configuration.runID,
            metadata: [
                "contexts": configuration.contexts.map(String.init).joined(separator: ","),
                "schemes": configuration.schemes.map(\.rawValue).joined(separator: ","),
                "runtime_modes": configuration.runtimeModes.joined(separator: ","),
                "precision_policies": configuration.precisionPolicies.joined(separator: ","),
                "sparse_v": configuration.sparseValuePolicies.joined(separator: ","),
                "iterations": String(configuration.iterations),
                "warmup_iterations": String(configuration.warmupIterations),
                "compatibility_pair_id": MLXRuntimeBridge.turboQuantCompatibilityPairID,
            ],
            enabled: true
        )

        do {
            let payload = try await Task.detached(priority: .utility) {
                try PinesTurboQuantBenchRunner.run(configuration: configuration)
            }.value
            let resultFileName = try await PinesTurboQuantBenchStatusWriter.shared.writePayload(payload)
            let failedCount = payload.results.filter { $0.status == .failed }.count
            let skippedCount = payload.results.filter { $0.status == .skipped }.count
            await PinesTurboQuantBenchStatusWriter.shared.write(
                PinesTurboQuantBenchStatus(
                    runID: configuration.runID,
                    state: failedCount > 0 ? "failed" : "completed",
                    resultFileName: resultFileName,
                    resultCount: payload.results.count,
                    failedCount: failedCount,
                    skippedCount: skippedCount,
                    message: failedCount > 0
                        ? "TurboQuant benchmark completed with \(failedCount) failed case(s)."
                        : "TurboQuant benchmark completed.",
                    updatedAt: Date()
                )
            )
            await FreezeBreadcrumbJournal.shared.record(
                stage: failedCount > 0 ? "turboquant_bench.run.failed" : "turboquant_bench.run.complete",
                runID: configuration.runID,
                metadata: [
                    "result_file": resultFileName,
                    "result_count": String(payload.results.count),
                    "failed_count": String(failedCount),
                    "skipped_count": String(skippedCount),
                ],
                enabled: true
            )
        } catch {
            await PinesTurboQuantBenchStatusWriter.shared.write(
                PinesTurboQuantBenchStatus(
                    runID: configuration.runID,
                    state: "failed",
                    resultFileName: nil,
                    resultCount: 0,
                    failedCount: 1,
                    skippedCount: 0,
                    message: error.localizedDescription,
                    updatedAt: Date()
                )
            )
            await FreezeBreadcrumbJournal.shared.record(
                stage: "turboquant_bench.run.failed",
                runID: configuration.runID,
                metadata: ["error": error.localizedDescription],
                enabled: true
            )
        }
        #endif
    }
}
#endif
