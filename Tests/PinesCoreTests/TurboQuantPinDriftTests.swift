import Foundation
import Testing

@Suite("TurboQuant pin drift")
struct TurboQuantPinDriftTests {
    @Test func compatibilityPairTracksPinnedMLXForks() throws {
        let root = try Self.repoRoot()
        let projectYML = try Self.read("project.yml", root: root)
        let pbxproj = try Self.read("Pines.xcodeproj/project.pbxproj", root: root)
        let xcodeResolvedData = try Data(
            contentsOf: root.appendingPathComponent(
                "Pines.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            )
        )
        let turboQuantDoc = try Self.read("docs/TURBOQUANT.md", root: root)
        let compatibilityData = try Data(
            contentsOf: root.appendingPathComponent(
                "docs/turboquant-implementation/compatibility-pair.json"
            )
        )
        let bridge = try Self.read("Pines/Runtime/MLXRuntimeBridge.swift", root: root)

        let mlxSwift = try Self.revision(packageName: "MLXSwift", in: projectYML)
        let mlxSwiftLM = try Self.revision(packageName: "MLXSwiftLM", in: projectYML)
        try Self.requireSHA(mlxSwift, label: "MLXSwift")
        try Self.requireSHA(mlxSwiftLM, label: "MLXSwiftLM")

        let expectedPair = "mlx-swift-\(mlxSwift)+mlx-swift-lm-\(mlxSwiftLM)"
        let packageResolved = try JSONDecoder().decode(PackageResolved.self, from: xcodeResolvedData)
        let compatibility = try JSONDecoder().decode(CompatibilityPair.self, from: compatibilityData)

        #expect(pbxproj.contains("revision = \(mlxSwift);"))
        #expect(pbxproj.contains("revision = \(mlxSwiftLM);"))
        #expect(packageResolved.revision(identity: "mlx-swift") == mlxSwift)
        #expect(packageResolved.revision(identity: "mlx-swift-lm") == mlxSwiftLM)
        #expect(turboQuantDoc.contains(mlxSwift))
        #expect(turboQuantDoc.contains(mlxSwiftLM))
        #expect(bridge.contains(expectedPair))
        #expect(compatibility.compatibilityPairID == expectedPair)
        #expect(compatibility.mlxSwift.commit == mlxSwift)
        #expect(compatibility.mlxSwiftLM.commit == mlxSwiftLM)
        #expect(compatibility.productionPinPromotion?.pinnedMLXSwift == mlxSwift)
        #expect(compatibility.productionPinPromotion?.pinnedMLXSwiftLM == mlxSwiftLM)
        #expect(compatibility.productionPinPromotion?.compatibilityPairID == expectedPair)
    }

    @Test func compatibilityPairKeepsPinsUnverifiedWhileCurrentGatesFail() throws {
        let root = try Self.repoRoot()
        let compatibilityData = try Data(
            contentsOf: root.appendingPathComponent(
                "docs/turboquant-implementation/compatibility-pair.json"
            )
        )
        let compatibility = try JSONDecoder().decode(CompatibilityPair.self, from: compatibilityData)

        #expect(compatibility.status == "failed")
        #expect(compatibility.statusReason.contains("Authoritative current-pair status is failed"))
        #expect(compatibility.statusReason.contains("performance parity is not achieved"))
        #expect(compatibility.claimPolicy.pinsOnlyEvidenceLevel == "unverified")
        #expect(compatibility.claimPolicy.verifiedOrCertifiedProductClaimsAllowed == false)
        #expect(compatibility.claimPolicy.requiresRealDeviceEvidence == true)
        #expect(compatibility.releaseReadiness.greenAllowed == false)
        #expect(compatibility.releaseReadiness.nativeBackendEvidence == "api_contract_only")
        #expect(compatibility.releaseReadiness.performanceParityEvidence == "failed")
        #expect(compatibility.releaseReadiness.appHostHybridNativeDiagnosticsRequired == true)
        #expect(
            compatibility.releaseReadiness.requiredEvidenceForGreen.contains(
                "native_backend_performance"
            )
        )
        #expect(compatibility.releaseReadiness.requiredEvidenceForGreen.contains("performance_parity"))
        #expect(
            compatibility.releaseReadiness.currentBlockers.contains {
                $0.contains("native segmented performance parity")
            }
        )
        #expect(
            compatibility.releaseReadiness.currentBlockers.contains {
                $0.contains("Full release benchmark-matrix")
            }
        )
        #expect(compatibility.statusReason.contains("Exact-pin physical-device app-host smoke completed"))
        #expect(compatibility.productionPinPromotion?.releaseGate.contains("non-green") == true)
        #expect(compatibility.productionPinPromotion?.releaseGate.contains("Verified or Certified") == true)
        Self.assertGreenStatusReleaseGates(compatibility)

        #expect(compatibility.validationCommands.contains {
            $0.repo == "mlx-swift"
                && $0.command == "swift test --filter TurboQuant"
                && $0.result == "passed"
                && $0.runID != compatibility.wave0Baseline.runID
        })
        #expect(compatibility.historicalValidationCommands.contains {
            $0.repo == "pines"
                && $0.command.contains("run-ios-turboquant-bench.sh")
                && $0.result == "failed_environmental"
                && $0.runID == compatibility.wave0Baseline.runID
        })
        #expect(!compatibility.validationCommands.contains {
            $0.result == "passed"
                && ($0.notes ?? "").contains("Verified or Certified")
        })
        #expect(compatibility.validationCommands.contains {
            $0.repo == "pines"
                && $0.command.contains("run-ios-turboquant-bench.sh")
                && $0.result == "passed"
                && $0.runID == "ios-turboquant-bench-20260531T132622Z"
                && ($0.notes ?? "").contains("hybridNativeDiagnostics")
                && ($0.notes ?? "").contains("not-proven")
        })
        #expect(compatibility.historicalValidationCommands.contains {
            $0.result == "passed"
                && ($0.notes ?? "").contains("App-hosted physical-device smoke completed")
                && $0.historicalStatus == "superseded"
                && $0.supersededByRunID == compatibility.wave0Baseline.runID
        })
    }

    @Test func appHostedBenchmarkPathStaysWired() throws {
        let root = try Self.repoRoot()
        let projectYML = try Self.read("project.yml", root: root)
        let pbxproj = try Self.read("Pines.xcodeproj/project.pbxproj", root: root)
        let rootView = try Self.read("Pines/App/PinesRootView.swift", root: root)
        let diagnostics = try Self.read("Pines/App/PinesTurboQuantBenchmarkDiagnostics.swift", root: root)
        let script = try Self.read("scripts/diagnostics/run-ios-turboquant-bench.sh", root: root)

        #expect(projectYML.contains("product: TurboQuantBench"))
        #expect(pbxproj.contains("productName = TurboQuantBench;"))
        #expect(rootView.contains("runLaunchTurboQuantBenchIfNeeded"))
        #expect(diagnostics.contains("PINES_TURBOQUANT_BENCH"))
        #expect(diagnostics.contains("PinesTurboQuantBenchAppHost"))
        #expect(diagnostics.contains("PINES_TQ_BENCH_DEVICE_ID"))
        #expect(diagnostics.contains("PINES_TQ_BENCH_RUNTIME_MODES"))
        #expect(diagnostics.contains("PINES_TQ_BENCH_PRECISION_POLICIES"))
        #expect(diagnostics.contains("PINES_TQ_BENCH_SPARSE_V"))
        #expect(diagnostics.contains("matrixExecution"))
        #expect(diagnostics.contains("TurboQuantBench.sweep"))
        #expect(diagnostics.contains("pines-turboquant-bench-status.json"))
        #expect(diagnostics.contains("hybridNativeDiagnostics"))
        #expect(diagnostics.contains("PinesTurboQuantBenchHybridNativeDiagnostics"))
        #expect(diagnostics.contains("hybridAttentionKVPolicy"))
        #expect(diagnostics.contains("nativeStateCachePolicy"))
        #expect(diagnostics.contains("requestedNativeBackend"))
        #expect(diagnostics.contains("nativeBackendPerformanceEvidence"))
        #expect(diagnostics.contains("performanceParityEvidence"))
        #expect(script.contains("PINES_TURBOQUANT_BENCH"))
        #expect(script.contains("PINES_TQ_BENCH_DEVICE_ID"))
        #expect(script.contains("PINES_TQ_BENCH_PINES_COMMIT"))
        #expect(script.contains("PINES_TQ_BENCH_RUNTIME_MODES"))
        #expect(script.contains("PINES_TQ_BENCH_PRECISION_POLICIES"))
        #expect(script.contains("PINES_TQ_BENCH_SPARSE_V"))
        #expect(script.contains("devicectl device process launch"))
        #expect(script.contains("pines-turboquant-bench-status.json"))
        #expect(script.contains("hybridNativeDiagnostics"))
        #expect(script.contains("appHost"))
    }

    @Test func wave0CaptureHarnessStaysWired() throws {
        let root = try Self.repoRoot()
        let script = try Self.read("scripts/diagnostics/capture-turboquant-wave0.sh", root: root)
        let schema = try Self.read(
            "docs/turboquant-implementation/compatibility-pair.schema.json",
            root: root
        )

        #expect(script.contains("turboquant-wave0-"))
        #expect(script.contains("repo-state.json"))
        #expect(script.contains("wave0-summary.json"))
        #expect(script.contains("wave0-summary.md"))
        #expect(script.contains("swift build --product TurboQuantBenchmark -c release"))
        #expect(script.contains("TQ_COOP=1"))
        #expect(script.contains("swift test --filter TurboQuant"))
        #expect(script.contains("run-ios-turboquant-bench.sh"))
        #expect(script.contains("performanceParity"))
        #expect(script.contains("speedRatioToPlainP50"))
        #expect(script.contains("WAVE0_IOS_BUILD_TIMEOUT_SECONDS"))
        #expect(schema.contains("failed_environmental"))
        #expect(schema.contains("artifactPath"))
        #expect(schema.contains("runID"))
        #expect(schema.contains("wave0Baseline"))
        #expect(schema.contains("historicalValidationCommands"))
        #expect(schema.contains("pinsOnlyEvidenceLevel"))
        #expect(schema.contains("verifiedOrCertifiedProductClaimsAllowed"))
        #expect(schema.contains("releaseReadiness"))
        #expect(schema.contains("native_backend_performance"))
        #expect(schema.contains("performance_parity"))
        #expect(schema.contains("appHostHybridNativeDiagnosticsRequired"))
    }

    private static func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("project.yml").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("Pines.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw PinDriftError.missingRepoRoot
    }

    private static func read(_ relativePath: String, root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func revision(packageName: String, in projectYML: String) throws -> String {
        let lines = projectYML.split(separator: "\n", omittingEmptySubsequences: false)
        guard let packageIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "\(packageName):"
        }) else {
            throw PinDriftError.missingPackage(packageName)
        }

        for line in lines[(packageIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("revision:") {
                return trimmed.replacingOccurrences(of: "revision:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if !line.hasPrefix("    ") && trimmed.hasSuffix(":") {
                break
            }
        }
        throw PinDriftError.missingRevision(packageName)
    }

    private static func requireSHA(_ value: String, label: String) throws {
        guard value.count == 40,
              value.allSatisfy({ $0.isNumber || ("a"..."f").contains(String($0)) }) else {
            throw PinDriftError.invalidSHA(label, value)
        }
    }

    private static func assertGreenStatusReleaseGates(_ compatibility: CompatibilityPair) {
        if compatibility.status == "green" {
            #expect(compatibility.releaseReadiness.greenAllowed)
            #expect(compatibility.releaseReadiness.nativeBackendEvidence == "passed")
            #expect(compatibility.releaseReadiness.performanceParityEvidence == "passed")
            #expect(compatibility.wave0Baseline.performanceParity)
            #expect(
                compatibility.validationCommands.contains {
                    $0.result == "passed"
                        && ($0.notes ?? "").localizedCaseInsensitiveContains("native")
                        && ($0.notes ?? "").localizedCaseInsensitiveContains("performance")
                }
            )
            #expect(
                compatibility.validationCommands.contains {
                    $0.result == "passed"
                        && ($0.notes ?? "").localizedCaseInsensitiveContains("performance parity")
                }
            )
        } else {
            #expect(!compatibility.releaseReadiness.greenAllowed)
            #expect(
                compatibility.releaseReadiness.nativeBackendEvidence != "passed"
                    || compatibility.releaseReadiness.performanceParityEvidence != "passed"
            )
        }
    }
}

private struct PackageResolved: Decodable {
    var pins: [Pin]

    func revision(identity: String) -> String? {
        pins.first { $0.identity == identity }?.state.revision
    }

    struct Pin: Decodable {
        var identity: String
        var state: State
    }

    struct State: Decodable {
        var revision: String
    }
}

private struct CompatibilityPair: Decodable {
    var status: String
    var statusReason: String
    var compatibilityPairID: String
    var wave0Baseline: Wave0Baseline
    var claimPolicy: ClaimPolicy
    var releaseReadiness: ReleaseReadiness
    var mlxSwift: RepoRef
    var mlxSwiftLM: RepoRef
    var validationCommands: [ValidationCommand]
    var historicalValidationCommands: [ValidationCommand]
    var productionPinPromotion: ProductionPinPromotion?

    struct Wave0Baseline: Decodable {
        var runID: String
        var performanceParity: Bool
    }

    struct ClaimPolicy: Decodable {
        var pinsOnlyEvidenceLevel: String
        var verifiedOrCertifiedProductClaimsAllowed: Bool
        var requiresRealDeviceEvidence: Bool
    }

    struct RepoRef: Decodable {
        var commit: String
    }

    struct ReleaseReadiness: Decodable {
        var greenAllowed: Bool
        var requiredEvidenceForGreen: [String]
        var nativeBackendEvidence: String
        var performanceParityEvidence: String
        var appHostHybridNativeDiagnosticsRequired: Bool
        var currentBlockers: [String]
    }

    struct ProductionPinPromotion: Decodable {
        var pinnedMLXSwift: String
        var pinnedMLXSwiftLM: String
        var compatibilityPairID: String
        var releaseGate: String
    }

    struct ValidationCommand: Decodable {
        var repo: String
        var command: String
        var result: String
        var notes: String?
        var runID: String?
        var historicalStatus: String?
        var supersededByRunID: String?
    }
}

private enum PinDriftError: Error {
    case missingRepoRoot
    case missingPackage(String)
    case missingRevision(String)
    case invalidSHA(String, String)
}
