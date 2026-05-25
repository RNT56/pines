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

    @Test func benchmarkImporterRejectsUnknownSchemaAndMissingFallbackHash() throws {
        var wrongSchema = Self.report()
        wrongSchema.schemaVersion = 999
        #expect(throws: TurboQuantBenchmarkImportFailure.unsupportedSchema(name: "BenchmarkReport", version: 999)) {
            _ = try TurboQuantBenchmarkImporter().importReport(
                wrongSchema,
                policy: TurboQuantBenchmarkImportPolicy()
            )
        }

        var missingHash = Self.report()
        missingHash.runtime.fallbackContractHash = " "
        #expect(throws: TurboQuantBenchmarkImportFailure.missingFallbackContractHash) {
            _ = try TurboQuantBenchmarkImporter().importReport(
                missingHash,
                policy: TurboQuantBenchmarkImportPolicy()
            )
        }
    }

    @Test func benchmarkImporterCarriesCalibrationSampleIntoEvidence() throws {
        let report = Self.report()
        let result = try TurboQuantBenchmarkImporter().importReport(
            report,
            policy: TurboQuantBenchmarkImportPolicy(requestedEvidenceLevel: .smokeTested)
        )

        #expect(result.memoryCalibrationSample?.id == report.memoryCalibrationSample?.id)
        #expect(result.evidence.memoryCalibrationSampleID == report.memoryCalibrationSample?.id)
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

    @Test func profileEvidenceStoreLookupUsesExactTupleAndSkipsRevokedEvidence() async throws {
        let report = Self.report()
        let store = ProfileEvidenceStore()
        let imported = try await store.importBenchmarkReport(
            report,
            policy: TurboQuantBenchmarkImportPolicy(
                acceptedCompatibilityPairIDs: [report.compatibilityPairID],
                acceptedFallbackContractHashes: [report.runtime.fallbackContractHash],
                requestedEvidenceLevel: .verified,
                allowVerifiedEvidence: true
            )
        )

        let found = await store.evidence(
            modelID: report.model.id,
            modelRevision: report.model.revision,
            tokenizerHash: report.model.tokenizerHash,
            profileHash: report.model.profileHash,
            compatibilityPairID: report.compatibilityPairID,
            deviceClass: report.device.deviceClass,
            hardwareModel: report.device.hardwareModel,
            osBuild: report.device.osBuild,
            mode: report.runtime.userMode,
            fallbackContractHash: report.runtime.fallbackContractHash,
            minimumContextTokens: report.runtime.admittedContextTokens
        )
        let wrongMode = await store.evidence(
            modelID: report.model.id,
            modelRevision: report.model.revision,
            tokenizerHash: report.model.tokenizerHash,
            profileHash: report.model.profileHash,
            compatibilityPairID: report.compatibilityPairID,
            deviceClass: report.device.deviceClass,
            hardwareModel: report.device.hardwareModel,
            osBuild: report.device.osBuild,
            mode: .batterySaver,
            fallbackContractHash: report.runtime.fallbackContractHash,
            minimumContextTokens: report.runtime.admittedContextTokens
        )

        #expect(found?.id == imported.evidence.id)
        #expect(wrongMode == nil)

        _ = await store.revoke(id: imported.evidence.id, reason: "test revoke")
        let revoked = await store.evidence(
            modelID: report.model.id,
            modelRevision: report.model.revision,
            tokenizerHash: report.model.tokenizerHash,
            profileHash: report.model.profileHash,
            compatibilityPairID: report.compatibilityPairID,
            deviceClass: report.device.deviceClass,
            hardwareModel: report.device.hardwareModel,
            osBuild: report.device.osBuild,
            mode: report.runtime.userMode,
            fallbackContractHash: report.runtime.fallbackContractHash,
            minimumContextTokens: report.runtime.admittedContextTokens
        )
        #expect(revoked == nil)
    }

    @Test func profileEvidenceStoreDoesNotRevokeDistinctTuples() async throws {
        let store = ProfileEvidenceStore()
        let first = try await store.importBenchmarkReport(
            Self.report(createdAt: Date(timeIntervalSinceReferenceDate: 1)),
            policy: TurboQuantBenchmarkImportPolicy(requestedEvidenceLevel: .smokeTested)
        )
        var distinctReport = Self.report(createdAt: Date(timeIntervalSinceReferenceDate: 2))
        distinctReport.model.revision = "different-revision"
        _ = try await store.importBenchmarkReport(
            distinctReport,
            policy: TurboQuantBenchmarkImportPolicy(requestedEvidenceLevel: .smokeTested)
        )

        let allEvidence = await store.allEvidence()
        let original = allEvidence.first { $0.id == first.evidence.id }
        let revocations = await store.allRevocations()

        #expect(original?.evidenceLevel == .smokeTested)
        #expect(revocations.isEmpty)
    }

    @Test func coreBenchmarkAdapterWrapsCoreJSONIntoBenchmarkReportEnvelope() throws {
        let core = TurboQuantCoreBenchmarkReport(
            mlxSwiftCommit: "core-commit",
            storageEstimate: TurboQuantCoreStorageEstimate(totalBytes: 512, actualBitsPerValue: 4.25),
            pathDecision: TurboQuantCoreAttentionDecision(selectedPath: .onlineFused, estimatedScratchBytes: 256),
            metrics: TurboQuantCoreBenchmarkMetrics(
                contextTokens: 2048,
                headDimension: 128,
                queryLength: 1,
                preset: "turbo4v2",
                valueBits: 4,
                groupSize: 64,
                firstTokenLatencyMS: 12,
                prefillTokensPerSecond: 900,
                decodeTokensPerSecondP50: 40,
                decodeTokensPerSecondP95: 35,
                totalBytes: 512,
                compressedKVBytes: 512,
                peakMemoryBytes: 1024,
                actualBitsPerValue: 4.25
            ),
            hiddenCopyAudit: TurboQuantCoreHiddenCopyAudit(status: .pass)
        )
        var runtime = Self.report().runtime
        runtime.attentionPath = nil
        let context = TurboQuantCoreBenchmarkAdapterContext(
            compatibilityPairID: "pair-wave3",
            device: Self.report().device,
            model: Self.report().model,
            runtime: runtime,
            qualityGate: Self.report().qualityGate,
            createdAt: Date(timeIntervalSinceReferenceDate: 123)
        )

        let report = try TurboQuantCoreBenchmarkAdapter().benchmarkReport(
            from: core,
            context: context
        )

        #expect(report.producer.repo == "mlx-swift")
        #expect(report.producer.commit == "core-commit")
        #expect(report.runtime.attentionPath == .onlineFused)
        #expect(report.metrics.compressedKVBytes == 512)
        #expect(report.metrics.decodedFallbackScratchBytes == 256)
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

    @Test func evidenceSupportBundleRoundTripsEvidenceAndCalibration() throws {
        let result = try TurboQuantBenchmarkImporter().importReport(
            Self.report(),
            policy: TurboQuantBenchmarkImportPolicy(requestedEvidenceLevel: .smokeTested)
        )
        let bundle = TurboQuantEvidenceSupportBundle(
            evidence: [result.evidence],
            memoryCalibrationSamples: [try #require(result.memoryCalibrationSample)]
        )
        let exporter = TurboQuantEvidenceSupportBundleExporter()
        let decoded = try exporter.decode(try exporter.encode(bundle))

        #expect(decoded.schemaVersion == TurboQuantEvidenceSupportBundle.schemaVersion)
        #expect(decoded.evidence.first?.id == result.evidence.id)
        #expect(decoded.memoryCalibrationSamples.first?.id == result.memoryCalibrationSample?.id)
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
