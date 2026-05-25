import Foundation
import PinesCore
import Testing

@Suite("TurboQuant Wave 3 evidence loop")
struct TurboQuantWave3EvidenceTests {
    @Test func benchmarkImporterRejectsVerifiedEvidenceWhenPolicyDisallowsIt() throws {
        let report = Self.report()
        let policy = TurboQuantBenchmarkImportPolicy(
            acceptedCompatibilityPairIDs: [report.compatibilityPairID],
            acceptedFallbackContractHashes: [report.runtime.fallbackContractHash],
            requestedEvidenceLevel: .verified,
            allowVerifiedEvidence: false
        )

        #expect(throws: TurboQuantBenchmarkImportFailure.verifiedEvidenceDisabled) {
            _ = try TurboQuantBenchmarkImporter().importReport(report, policy: policy)
        }
    }

    @Test func benchmarkImporterCreatesSmokeEvidenceUntilVerifiedPolicyIsEnabled() throws {
        let report = Self.report()
        let result = try TurboQuantBenchmarkImporter().importReport(
            report,
            policy: TurboQuantBenchmarkImportPolicy(requestedEvidenceLevel: .smokeTested)
        )

        #expect(result.evidence.evidenceLevel == .smokeTested)
        #expect(result.evidence.compatibilityPairID == report.compatibilityPairID)
        #expect(result.evidence.fallbackContractHash == report.runtime.fallbackContractHash)
        #expect(result.evidence.qualityGate.benchmarkSuiteID == TurboQuantBenchmarkSuiteID.mobileMemoryAcceptanceV1.rawValue)
    }

    @Test func benchmarkImporterRequiresPassingQualityForVerifiedEvidence() throws {
        var report = Self.report()
        report.qualityGate.passed = false
        report.qualityGate.gateReason = "forced failure"

        #expect(throws: TurboQuantBenchmarkImportFailure.qualityGateFailed("forced failure")) {
            _ = try TurboQuantBenchmarkImporter().importReport(
                report,
                policy: TurboQuantBenchmarkImportPolicy(
                    acceptedCompatibilityPairIDs: [report.compatibilityPairID],
                    acceptedFallbackContractHashes: [report.runtime.fallbackContractHash],
                    requestedEvidenceLevel: .verified,
                    allowVerifiedEvidence: true
                )
            )
        }
    }

    @Test func profileEvidenceStoreRevokesConflictingEvidence() async throws {
        let store = ProfileEvidenceStore()
        let first = try await store.importBenchmarkReport(
            Self.report(createdAt: Date(timeIntervalSinceReferenceDate: 1)),
            policy: TurboQuantBenchmarkImportPolicy(requestedEvidenceLevel: .smokeTested)
        )
        let second = try await store.importBenchmarkReport(
            Self.report(createdAt: Date(timeIntervalSinceReferenceDate: 2)),
            policy: TurboQuantBenchmarkImportPolicy(requestedEvidenceLevel: .smokeTested)
        )

        let allEvidence = await store.allEvidence()
        let revocations = await store.allRevocations()

        #expect(first.evidence.id != second.evidence.id)
        #expect(allEvidence.count == 2)
        #expect(revocations.count == 1)
        #expect(revocations.first?.evidenceID == first.evidence.id)
    }

    @Test func qualityGateEvaluatorRecordsReasons() {
        let evaluated = TurboQuantQualityGateEvaluator().evaluated(
            TurboQuantQualityGate(
                benchmarkSuiteID: .prefillExactnessV1,
                deterministicTop1MatchRate: 0.5,
                logitKLDivergenceMean: 1,
                logitMaxAbsErrorP95: 2,
                noNaNOrInf: true,
                fallbackEquivalent: true,
                prefillExact: false,
                passed: true
            )
        )

        #expect(!evaluated.passed)
        #expect(evaluated.gateReason?.contains("prefill exactness failed") == true)
        #expect(evaluated.gateReason?.contains("top-1 match below threshold") == true)
    }

    @Test func calibrationAggregatorProducesP95MultiplierAndStaleGuard() {
        let samples = [
            Self.sample(id: UUID(), estimated: 100, observed: 125),
            Self.sample(id: UUID(), estimated: 100, observed: 160, memoryWarningsSeen: 1),
        ]

        let calibration = RuntimeMemoryCalibrationAggregator().aggregate(
            samples: samples,
            deviceClass: .a17Pro,
            modelFamily: "model",
            attentionPath: .twoStageCompressed,
            staleAfter: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 1)
        )

        #expect(calibration?.sampleCount == 2)
        #expect(calibration?.estimatedToActualPeakRatioP95 == 1.6)
        #expect(calibration?.safetyReserveBytes ?? 0 > 512 * 1_024 * 1_024)
        #expect(calibration?.isStale(at: Date(timeIntervalSinceReferenceDate: 11)) == true)
    }

    @Test func compatibilityStateDoesNotPromoteCuratedMetadataToVerified() {
        let state = RuntimeCompatibilityState.resolve(
            installVerification: .verified,
            evidence: nil,
            admission: nil
        )

        #expect(state == .conservative)
        #expect(!state.allowsProductClaim)
    }

    @Test func deviceAcceptanceExportRoundTripsWithoutFabricatingVerifiedEvidence() throws {
        let report = Self.report()
        let runner = TurboQuantDeviceAcceptanceRunner()
        let export = runner.importAcceptanceReport(
            report,
            policy: TurboQuantBenchmarkImportPolicy(
                acceptedCompatibilityPairIDs: [report.compatibilityPairID],
                acceptedFallbackContractHashes: [report.runtime.fallbackContractHash],
                requestedEvidenceLevel: .verified,
                allowVerifiedEvidence: false
            )
        )
        let decoded = try runner.decodeExport(try runner.encodeExport(export))

        #expect(decoded.importedEvidence == nil)
        #expect(decoded.importFailure?.contains("verifiedEvidenceDisabled") == true)
        #expect(decoded.report.compatibilityPairID == report.compatibilityPairID)
    }

    private static func report(createdAt: Date = Date()) -> TurboQuantBenchmarkReport {
        let fallbackContract = TurboQuantFallbackContract.productDefault(for: .balanced)
        return TurboQuantBenchmarkReport(
            compatibilityPairID: "pair-wave3",
            producer: SchemaProducer(repo: "pines-tests", commit: "test"),
            device: TurboQuantBenchmarkDevice(
                deviceClass: .a17Pro,
                hardwareModel: "iPhone16,2",
                osBuild: "23F",
                availableMemoryBytesAtStart: 3_000_000_000,
                metalDeviceName: "Apple GPU",
                thermalState: "nominal"
            ),
            model: TurboQuantBenchmarkModel(
                id: "model",
                revision: "rev",
                tokenizerHash: "tok",
                profileHash: "profile",
                architecture: "qwen",
                layers: 24,
                kvHeads: 8,
                headDim: 128
            ),
            runtime: TurboQuantBenchmarkRuntime(
                userMode: .balanced,
                fallbackContractHash: fallbackContract.contractHash,
                preset: "turbo4v2",
                valueBits: 4,
                groupSize: 64,
                layoutVersion: 4,
                attentionPath: .twoStageCompressed,
                kernelProfile: "balanced",
                admittedContextTokens: 4096,
                reservedCompletionTokens: 512
            ),
            metrics: TurboQuantBenchmarkMetrics(
                contextTokens: 4096,
                firstTokenLatencyMS: 80,
                prefillTokensPerSecond: 900,
                decodeTokensPerSecondP50: 25,
                decodeTokensPerSecondP95: 21,
                peakMemoryBytes: 2_100_000_000,
                compressedKVBytes: 128_000_000,
                memoryWarningsSeen: 0,
                fallbackUsed: false,
                jetsamObserved: false
            ),
            qualityGate: TurboQuantQualityGate(
                benchmarkSuiteID: .mobileMemoryAcceptanceV1,
                deterministicTop1MatchRate: 0.99,
                logitKLDivergenceMean: 0.01,
                logitMaxAbsErrorP95: 0.1,
                noNaNOrInf: true,
                fallbackEquivalent: true,
                prefillExact: true,
                passed: true
            ),
            memoryCalibrationSample: Self.sample(id: UUID(), estimated: 100, observed: 125),
            createdAt: createdAt
        )
    }

    private static func sample(
        id: UUID,
        estimated: Int64,
        observed: Int64,
        memoryWarningsSeen: Int = 0
    ) -> RuntimeMemoryCalibrationSample {
        RuntimeMemoryCalibrationSample(
            id: id,
            compatibilityPairID: "pair-wave3",
            runOutcome: .admittedSucceeded,
            modelID: "model",
            deviceClass: .a17Pro,
            userMode: .balanced,
            attentionPath: .twoStageCompressed,
            requestedContextTokens: 4096,
            admittedContextTokens: 4096,
            estimatedCompressedKVBytes: estimated,
            actualCompressedKVBytes: observed,
            estimatedFallbackBytes: 0,
            actualFallbackBytes: 0,
            estimatedScratchBytes: 0,
            observedPeakMemoryBytes: observed,
            availableMemoryAtAdmission: 1_000_000_000,
            availableMemoryAtPrefillEnd: 999_999_990,
            availableMemoryAtDecodeEnd: 999_999_980,
            memoryWarningsSeen: memoryWarningsSeen
        )
    }
}
