import Foundation
import Darwin
import PinesCore

// DEBUG-only, launch-gated REAL-MODEL TurboQuant device benchmark.
//
// Loads the ACTUAL on-device model weights and runs real token generation, comparing
// compressed (affineK8V4) vs plain FP16 KV through the canonical InferenceParityBenchmark
// engine — the `real-model-inference-v1` evidence the promotion gate requires. Gated by
// `PINES_TQ_REAL_BENCH=1`; writes JSON to Documents/PinesDiagnostics. Inert in release.
//
// Extended run: per-context isolation (a 64K OOM doesn't lose 32K), bootstrap 95% CIs on each
// arm's median decode tok/s AND on the compressed/FP16 ratio, and multi-model support
// (`PINES_TQ_REAL_MODELS` csv) so a smaller fallback model can cover long contexts the primary
// model's weights+KV won't fit.
#if DEBUG && PINES_ENABLE_IN_APP_TURBOQUANT_BENCH && canImport(IntegrationTestHelpers) && canImport(MLXLMCommon)
    import IntegrationTestHelpers
    import MLXLMCommon
    import MLXLLM

    // Deterministic seedable RNG so bootstrap CIs reproduce across runs.
    private struct PinesSplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
    private func pinesMedian(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted(); let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
    /// Percentile bootstrap 95% CI of the median of `samples`.
    private func pinesBootstrapMedianCI95(
        _ samples: [Double], resamples: Int = 2000, seed: UInt64 = 0x5EED_C0DE
    ) -> (lo: Double, hi: Double) {
        guard samples.count >= 2 else { let v = samples.first ?? 0; return (v, v) }
        var rng = PinesSplitMix64(seed: seed)
        let n = samples.count
        var meds: [Double] = []; meds.reserveCapacity(resamples)
        for _ in 0 ..< resamples {
            var d: [Double] = []; d.reserveCapacity(n)
            for _ in 0 ..< n { d.append(samples[Int.random(in: 0 ..< n, using: &rng)]) }
            meds.append(pinesMedian(d))
        }
        meds.sort()
        func pct(_ p: Double) -> Double {
            let i = Swift.max(0, Swift.min(meds.count - 1, Int((p * Double(meds.count)).rounded(.down))))
            return meds[i]
        }
        return (pct(0.025), pct(0.975))
    }
    /// Bootstrap 95% CI of the ratio median(candidate)/median(reference) (independent resampling).
    private func pinesBootstrapRatioCI95(
        candidate: [Double], reference: [Double], resamples: Int = 2000, seed: UInt64 = 0x1234_5678
    ) -> (lo: Double, hi: Double) {
        guard candidate.count >= 2, reference.count >= 2 else {
            let r = (reference.first ?? 0) > 0 ? (candidate.first ?? 0) / (reference.first ?? 1) : 0
            return (r, r)
        }
        var rng = PinesSplitMix64(seed: seed)
        func draw(_ xs: [Double]) -> Double {
            var d: [Double] = []; d.reserveCapacity(xs.count)
            for _ in 0 ..< xs.count { d.append(xs[Int.random(in: 0 ..< xs.count, using: &rng)]) }
            return pinesMedian(d)
        }
        var ratios: [Double] = []; ratios.reserveCapacity(resamples)
        for _ in 0 ..< resamples {
            let mref = draw(reference)
            ratios.append(mref > 0 ? draw(candidate) / mref : 0)
        }
        ratios.sort()
        func pct(_ p: Double) -> Double {
            let i = Swift.max(0, Swift.min(ratios.count - 1, Int((p * Double(ratios.count)).rounded(.down))))
            return ratios[i]
        }
        return (pct(0.025), pct(0.975))
    }

    private struct PinesRealModelTQHost: Codable, Sendable {
        var hardwareModel: String
        var osVersion: String
        var deviceID: String?
        var mlxPinPair: String
    }
    private struct PinesRealModelTQArm: Codable, Sendable {
        var label: String
        var samples: [Double]
        var medianTokensPerSecond: Double
        var ci95Lo: Double
        var ci95Hi: Double
        var peakActiveMemoryBytes: Int
        var activeMemoryEndBytes: Int
    }
    private struct PinesRealModelTQContextRow: Codable, Sendable {
        var model: String
        var context: Int
        var status: String  // ok | failed
        var detail: String?
        var fp16: PinesRealModelTQArm?
        var compressed: PinesRealModelTQArm?
        var ratioCompressedOverFP16Median: Double?
        var ratioCi95Lo: Double?
        var ratioCi95Hi: Double?
        // quality (compressed vs FP16 reference)
        var deterministicTop1MatchRate: Double?
        var attentionOutputCosineMean: Double?
        var logitKLDivergenceMean: Double?
        var logitMaxAbsErrorP95: Double?
        var qualityPassed: Bool?
        var rawFallbackAllocated: Bool?
        var selectedAttentionPaths: [String]?
        var fallbackReasons: [String]?
    }
    private struct PinesRealModelTQPayload: Codable, Sendable {
        var schemaVersion = 2
        var runID: String
        var models: [String]
        var contexts: [Int]
        var generateTokens: Int
        var throughputRepeats: Int
        var bootstrapResamples: Int
        var host: PinesRealModelTQHost
        var rows: [PinesRealModelTQContextRow]
        var comparisonBasis: String
        var createdAt: Date
    }
    private struct PinesRealModelTQStatus: Codable, Sendable {
        var runID: String
        var state: String
        var resultFileName: String?
        var message: String?
        var updatedAt: Date
    }

    private actor PinesRealModelTQWriter {
        static let shared = PinesRealModelTQWriter()
        static let statusFileName = "pines-realmodel-tq-status.json"
        private let encoder: JSONEncoder
        init() {
            encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
        }
        private static var directoryURL: URL {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return documents.appendingPathComponent("PinesDiagnostics", isDirectory: true)
        }
        func write(state: String, runID: String, resultFileName: String? = nil, message: String? = nil) {
            let status = PinesRealModelTQStatus(
                runID: runID, state: state, resultFileName: resultFileName, message: message,
                updatedAt: Date())
            do {
                let url = Self.directoryURL.appendingPathComponent(Self.statusFileName)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try encoder.encode(status).write(to: url, options: .atomic)
            } catch {}
        }
        func writePayload(_ payload: PinesRealModelTQPayload) throws -> String {
            let fileName = "pines-realmodel-tq-\(payload.runID).json"
            let url = Self.directoryURL.appendingPathComponent(fileName)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(payload).write(to: url, options: .atomic)
            return fileName
        }
    }

    private func pinesRealModelHardwareModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    extension PinesAppModel {
        func runLaunchRealModelTurboQuantBenchIfNeeded(services: PinesAppServices) async {
            let env = ProcessInfo.processInfo.environment
            guard env["PINES_TQ_REAL_BENCH"] == "1" else { return }
            let runID = env["PINES_TQ_REAL_RUN_ID"] ?? UUID().uuidString
            // Multi-model: PINES_TQ_REAL_MODELS csv (primary first, smaller fallback after);
            // falls back to single PINES_TQ_REAL_MODEL.
            let models: [String] = {
                if let csv = env["PINES_TQ_REAL_MODELS"] {
                    let list = csv.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }.filter { !$0.isEmpty }
                    if !list.isEmpty { return list }
                }
                return [env["PINES_TQ_REAL_MODEL"] ?? "mlx-community/Qwen3.5-2B-OptiQ-4bit"]
            }()
            let contexts = (env["PINES_TQ_REAL_CONTEXTS"] ?? "16384,32768,65536")
                .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { $0 > 0 }.sorted()
            let generateTokens = max(8, Int(env["PINES_TQ_REAL_GEN_TOKENS"] ?? "") ?? 48)
            let repeats = max(2, Int(env["PINES_TQ_REAL_REPEATS"] ?? "") ?? 6)
            let resamples = max(200, Int(env["PINES_TQ_REAL_BOOTSTRAP"] ?? "") ?? 2000)

            await PinesRealModelTQWriter.shared.write(
                state: "starting", runID: runID,
                message: "models=\(models.joined(separator: ",")) ctx=\(contexts)")

            let configs = InferenceParityBenchmark.defaultConfigs.filter {
                $0.label == "fp16" || $0.label == "affineK8V4"
            }
            guard let fp16Config = configs.first(where: { $0.label == "fp16" }),
                let tqConfig = configs.first(where: { $0.label == "affineK8V4" })
            else {
                await PinesRealModelTQWriter.shared.write(
                    state: "failed", runID: runID, message: "fp16/affineK8V4 CacheConfig unavailable")
                return
            }

            var rows: [PinesRealModelTQContextRow] = []
            for repo in models {
                do {
                    if let lifecycle = services.modelLifecycleService {
                        await PinesRealModelTQWriter.shared.write(
                            state: "downloading", runID: runID, message: "Ensuring \(repo) downloaded")
                        try? await lifecycle.install(repository: repo)
                    }
                    let localURL = try await Self.resolveRealModelDirectory(repo: repo, services: services)
                    await PinesRealModelTQWriter.shared.write(
                        state: "loading", runID: runID, message: "Loading \(repo)")
                    let configuration = MLXLMCommon.ModelConfiguration(directory: localURL)
                    let container = try await LLMModelFactory.shared.loadContainer(
                        from: PinesHubDownloader(), using: PinesTokenizerLoader(),
                        configuration: configuration)

                    for context in contexts {
                        await PinesRealModelTQWriter.shared.write(
                            state: "running", runID: runID,
                            message: "\(repo.split(separator: "/").last ?? "") @ \(context): FP16 vs affineK8V4")
                        do {
                            let tp = try await InferenceParityBenchmark.runDetailed(
                                container: container, contexts: [context], generateTokens: generateTokens,
                                configs: configs, throughputRepeats: repeats, randomizeOrder: true,
                                cooldownSeconds: 0.3, turboQuantTimingEnabled: true)
                            let quality = try? await InferenceParityBenchmark.runQualityGates(
                                container: container, contexts: [context], configs: [tqConfig],
                                referenceConfig: fp16Config)
                            rows.append(
                                Self.buildContextRow(
                                    model: repo, context: context, resamples: resamples,
                                    samples: tp.samples, quality: quality?.first))
                        } catch {
                            rows.append(
                                PinesRealModelTQContextRow(
                                    model: repo, context: context, status: "failed",
                                    detail: "\(error)"))
                            await PinesRealModelTQWriter.shared.write(
                                state: "running", runID: runID,
                                message: "\(repo) @ \(context) failed: \(error)")
                        }
                    }
                } catch {
                    rows.append(
                        PinesRealModelTQContextRow(
                            model: repo, context: 0, status: "failed",
                            detail: "model load/resolve failed: \(error)"))
                }
            }

            let host = PinesRealModelTQHost(
                hardwareModel: pinesRealModelHardwareModel(),
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                deviceID: env["PINES_TQ_REAL_DEVICE_ID"],
                mlxPinPair: MLXRuntimeBridge.turboQuantCompatibilityPairID)
            let payload = PinesRealModelTQPayload(
                runID: runID, models: models, contexts: contexts, generateTokens: generateTokens,
                throughputRepeats: repeats, bootstrapResamples: resamples, host: host, rows: rows,
                comparisonBasis: "real-model-inference-v1 (actual weights, real generation; affineK8V4 vs FP16; bootstrap 95% CIs)",
                createdAt: Date())
            do {
                let file = try await PinesRealModelTQWriter.shared.writePayload(payload)
                let okCount = rows.filter { $0.status == "ok" }.count
                await PinesRealModelTQWriter.shared.write(
                    state: "completed", runID: runID, resultFileName: file,
                    message: "Real-model TurboQuant benchmark completed (\(okCount)/\(rows.count) rows ok).")
            } catch {
                await PinesRealModelTQWriter.shared.write(
                    state: "failed", runID: runID, message: "writePayload failed: \(error)")
            }
        }

        private static func resolveRealModelDirectory(
            repo: String, services: PinesAppServices
        ) async throws -> URL {
            if let installs = try? await services.modelInstallRepository?.listInstalledAndCuratedModels(),
                let match = installs.first(where: { $0.repository == repo }),
                let url = match.localURL,
                FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path)
            {
                return url
            }
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let safe = repo.replacingOccurrences(of: "/", with: "__")
            let dir = appSupport.appendingPathComponent("Pines/Models/\(safe)", isDirectory: true)
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) else {
                throw PinesRealModelTQError.modelNotResolved(repo)
            }
            return dir
        }

        private static func buildContextRow(
            model: String, context: Int, resamples: Int,
            samples: [InferenceParityBenchmark.ThroughputSample],
            quality: InferenceParityBenchmark.QualityMeasurement?
        ) -> PinesRealModelTQContextRow {
            func arm(_ label: String) -> PinesRealModelTQArm? {
                // Per-repeat measurements (one per throughputRepeats sample) — the bootstrap
                // population. `.measurements` is the single aggregate per arm, hence N=1.
                let ms = samples.compactMap { $0.label == label ? $0.measurement : nil }
                guard !ms.isEmpty else { return nil }
                let tps = ms.map { $0.decodeTokensPerSecond }
                let ci = pinesBootstrapMedianCI95(tps, resamples: resamples)
                return PinesRealModelTQArm(
                    label: label, samples: tps, medianTokensPerSecond: pinesMedian(tps),
                    ci95Lo: ci.lo, ci95Hi: ci.hi,
                    peakActiveMemoryBytes: ms.map { $0.peakActiveMemoryBytes }.max() ?? 0,
                    activeMemoryEndBytes: ms.last?.memoryEnd.activeMemory ?? 0)
            }
            let fp16 = arm("fp16")
            let compressed = arm("affineK8V4")
            var ratio: Double?
            var ratioLo: Double?
            var ratioHi: Double?
            if let f = fp16, let c = compressed, f.medianTokensPerSecond > 0 {
                ratio = c.medianTokensPerSecond / f.medianTokensPerSecond
                let rci = pinesBootstrapRatioCI95(
                    candidate: c.samples, reference: f.samples, resamples: resamples)
                ratioLo = rci.lo; ratioHi = rci.hi
            }
            return PinesRealModelTQContextRow(
                model: model, context: context, status: "ok", detail: nil,
                fp16: fp16, compressed: compressed,
                ratioCompressedOverFP16Median: ratio, ratioCi95Lo: ratioLo, ratioCi95Hi: ratioHi,
                deterministicTop1MatchRate: quality?.quality.deterministicTop1MatchRate,
                attentionOutputCosineMean: quality?.quality.attentionOutputCosineMean,
                logitKLDivergenceMean: quality?.quality.logitKLDivergenceMean,
                logitMaxAbsErrorP95: quality?.quality.logitMaxAbsErrorP95,
                qualityPassed: quality?.quality.passed,
                rawFallbackAllocated: quality?.rawFallbackAllocated,
                selectedAttentionPaths: quality?.selectedAttentionPaths,
                fallbackReasons: quality?.fallbackReasons)
        }
    }

    private enum PinesRealModelTQError: Error, LocalizedError {
        case modelNotResolved(String)
        var errorDescription: String? {
            switch self {
            case let .modelNotResolved(repo): "Could not resolve a local model directory for \(repo)."
            }
        }
    }
#elseif DEBUG
    // The app target intentionally does not link IntegrationTestHelpers. `canImport`
    // can still see transitive package modules, so the explicit build flag above is
    // required before any helper symbols are referenced. Normal Debug builds keep
    // this launch hook inert; benchmarks run through standalone SwiftPM diagnostics.
    extension PinesAppModel {
        func runLaunchRealModelTurboQuantBenchIfNeeded(services: PinesAppServices) async {
            _ = services
        }
    }
#endif
