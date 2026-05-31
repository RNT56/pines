import Foundation
import PinesCore
import Testing

@Suite("TurboQuant Wave 6 speculative control plane")
struct TurboQuantWave6SpeculativeTests {
    @Test func speculativeTelemetryRoundTripsAndAutoDisablesPoorAcceptance() throws {
        let dimensions = Self.speculativeDimensions()
        let telemetry = TurboQuantSpeculativeTelemetry(
            state: .active,
            dimensions: dimensions,
            proposedTokenCount: 128,
            acceptedTokenCount: 16,
            rejectedTokenCount: 112,
            targetVerifiedTokenCount: 17,
            rollbackCount: 0,
            targetSequenceMatched: true,
            tokenizerCompatible: true,
            baselineDecodeTokensPerSecondP50: 20,
            speculativeDecodeTokensPerSecondP50: 24
        )

        let decoded = try JSONDecoder().decode(
            TurboQuantSpeculativeTelemetry.self,
            from: try JSONEncoder().encode(telemetry)
        )
        let decision = TurboQuantSpeculativeAutoDisablePolicy.productDefault.evaluate(decoded)

        #expect(decoded == telemetry)
        #expect(decoded.acceptanceRate == 0.125)
        #expect(decoded.p50DecodeSpeedup == 1.2)
        #expect(decision.shouldDisable)
        #expect(decision.reason == .lowAcceptance)
    }

    @Test func speculativeAdmissionBudgetContributesToMemoryZones() {
        let budget = TurboQuantSpeculativeAdmissionBudget(
            enabled: true,
            draftModelBytes: 100,
            draftKVBytesPerToken: 2,
            rollbackReserveBytes: 50,
            contextTokens: 10,
            maxDraftTokens: 4
        )
        let request = Self.admissionRequest(speculativeBudget: budget)

        let plan = LocalRuntimeAdmissionService().admit(request)

        #expect(plan.speculativeBudget == budget)
        #expect(plan.memoryZones.speculativeDraftModelBytes == 100)
        #expect(plan.memoryZones.speculativeDraftKVBytes == 20)
        #expect(plan.memoryZones.speculativeRollbackReserveBytes == 50)
        #expect(plan.memoryZones.totalPlannedBytes >= budget.totalReserveBytes)
    }

    @Test func runDecisionRequiresAutoDisableOnTargetMismatch() {
        let telemetry = TurboQuantSpeculativeTelemetry(
            state: .active,
            dimensions: Self.speculativeDimensions(),
            proposedTokenCount: 8,
            acceptedTokenCount: 2,
            rejectedTokenCount: 6,
            targetVerifiedTokenCount: 3,
            targetSequenceMatched: false,
            tokenizerCompatible: true
        )
        let invalid = TurboQuantRunDecision(speculativeTelemetry: telemetry)
        let valid = TurboQuantRunDecision(
            speculativeTelemetry: telemetry,
            speculativeAutoDisableDecision: TurboQuantSpeculativeAutoDisableDecision(
                action: .disableUntilEvidenceRefresh,
                reason: .targetMismatch,
                acceptanceRate: telemetry.acceptanceRate,
                evaluatedProposedTokens: telemetry.proposedTokenCount,
                cooldownRunCount: 3,
                message: "target mismatch"
            )
        )

        #expect(invalid.validationErrors.contains("target mismatch requires speculative auto-disable decision"))
        #expect(valid.validationErrors.isEmpty)
    }

    @Test func verifiedSpeculativeEvidenceRequiresTelemetryAndSpeedup() throws {
        var missingTelemetry = Self.report()
        missingTelemetry.metrics.speculativeTelemetry = nil

        #expect(throws: TurboQuantBenchmarkImportFailure.speculativeGateFailed("Speculative evidence requires acceptance telemetry.")) {
            _ = try TurboQuantBenchmarkImporter().importReport(
                missingTelemetry,
                policy: Self.verifiedPolicy()
            )
        }

        var lowAcceptance = Self.report()
        lowAcceptance.metrics.speculativeTelemetry = TurboQuantSpeculativeTelemetry(
            state: .active,
            dimensions: Self.speculativeDimensions(),
            proposedTokenCount: 128,
            acceptedTokenCount: 8,
            rejectedTokenCount: 120,
            targetVerifiedTokenCount: 9,
            rollbackCount: 0,
            targetSequenceMatched: true,
            tokenizerCompatible: true,
            baselineDecodeTokensPerSecondP50: 20,
            speculativeDecodeTokensPerSecondP50: 24
        )
        #expect(throws: TurboQuantBenchmarkImportFailure.speculativeGateFailed("Speculative acceptance fell below the policy threshold.")) {
            _ = try TurboQuantBenchmarkImporter().importReport(
                lowAcceptance,
                policy: Self.verifiedPolicy()
            )
        }

        let imported = try TurboQuantBenchmarkImporter().importReport(
            Self.report(),
            policy: Self.verifiedPolicy()
        )

        #expect(imported.evidence.evidenceLevel == .verified)
        #expect(imported.evidence.speculativeDimensions == Self.speculativeDimensions())
        #expect(imported.evidence.speculativeTelemetry?.acceptanceRate == 0.78125)
        #expect(imported.evidence.speculativeAutoDisableDecision?.shouldDisable == false)
    }

    @Test func profileEvidenceStoreMatchesSpeculativeTupleExactly() async throws {
        let report = Self.report()
        let store = ProfileEvidenceStore()
        let imported = try await store.importBenchmarkReport(report, policy: Self.verifiedPolicy())

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
            layoutVersion: report.runtime.layoutVersion,
            speculativeDimensions: Self.speculativeDimensions(),
            minimumContextTokens: report.runtime.admittedContextTokens
        )
        let disabledSpeculation = await store.evidence(
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
            layoutVersion: report.runtime.layoutVersion,
            speculativeDimensions: .disabled,
            minimumContextTokens: report.runtime.admittedContextTokens
        )

        #expect(found?.id == imported.evidence.id)
        #expect(disabledSpeculation == nil)
    }

    @Test func platformFeatureGatesRemainDesignOnlyByDefault() {
        let gates = TurboQuantPlatformFeatureGate.wave6DisabledDefaults

        #expect(gates.count == TurboQuantPlatformFeatureID.allCases.count)
        #expect(gates.allSatisfy { !$0.isProductActive })
        #expect(gates.allSatisfy { $0.killSwitchEnabled })
        #expect(gates.allSatisfy { $0.evidenceRequired })
    }

    private static func speculativeDimensions() -> TurboQuantSpeculativeEvidenceDimensions {
        TurboQuantSpeculativeEvidenceDimensions(
            enabled: true,
            draftModelID: "draft-small",
            draftModelRevision: "draft-rev",
            targetTokenizerHash: "target-tokenizer",
            draftTokenizerHash: "draft-tokenizer",
            pairingHash: "pairing-hash",
            tokenizerCompatible: true,
            maxDraftTokens: 4
        )
    }

    private static func report() -> TurboQuantBenchmarkReport {
        let fallbackContract = TurboQuantFallbackContract.productDefault(for: .fastest)
        let dimensions = speculativeDimensions()
        let telemetry = TurboQuantSpeculativeTelemetry(
            state: .active,
            dimensions: dimensions,
            proposedTokenCount: 128,
            acceptedTokenCount: 100,
            rejectedTokenCount: 28,
            targetVerifiedTokenCount: 101,
            rollbackCount: 0,
            targetSequenceMatched: true,
            tokenizerCompatible: true,
            baselineDecodeTokensPerSecondP50: 20,
            speculativeDecodeTokensPerSecondP50: 24
        )

        return TurboQuantBenchmarkReport(
            compatibilityPairID: "pair-wave6",
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
                userMode: .fastest,
                fallbackContractHash: fallbackContract.contractHash,
                preset: "turbo4v2",
                valueBits: 4,
                requestedRuntimeMode: .auto,
                resolvedRuntimeMode: .capacityTurboQuant,
                keyPrecision: .fp16OrQ8,
                valuePrecision: .turbo4v2,
                precisionPolicy: TurboQuantKVPrecisionPolicy(
                    key: .fp16OrQ8,
                    value: .turbo4v2
                ),
                sparseValuePolicy: .off,
                effectiveBackend: .swiftMetalKernel,
                groupSize: 64,
                layoutVersion: 4,
                attentionPath: .twoStageCompressed,
                kernelProfile: "fast",
                speculativeDimensions: dimensions,
                admittedContextTokens: 4096,
                reservedCompletionTokens: 512
            ),
            metrics: TurboQuantBenchmarkMetrics(
                contextTokens: 4096,
                firstTokenLatencyMS: 70,
                prefillTokensPerSecond: 900,
                decodeTokensPerSecondP50: 24,
                decodeTokensPerSecondP95: 21,
                peakMemoryBytes: 2_100_000_000,
                compressedKVBytes: 128_000_000,
                compressedKeyBytes: 64_000_000,
                compressedValueBytes: 64_000_000,
                memoryWarningsSeen: 0,
                fallbackUsed: false,
                jetsamObserved: false,
                speculativeTelemetry: telemetry
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
            )
        )
    }

    private static func verifiedPolicy() -> TurboQuantBenchmarkImportPolicy {
        let report = Self.report()
        return TurboQuantBenchmarkImportPolicy(
            acceptedCompatibilityPairIDs: [report.compatibilityPairID],
            acceptedFallbackContractHashes: [report.runtime.fallbackContractHash],
            acceptedLayoutVersions: [report.runtime.layoutVersion ?? 0],
            requestedEvidenceLevel: .verified,
            allowVerifiedEvidence: true
        )
    }

    private static func admissionRequest(
        speculativeBudget: TurboQuantSpeculativeAdmissionBudget
    ) -> LocalRuntimeAdmissionRequest {
        LocalRuntimeAdmissionRequest(
            modelID: "test-model",
            requestedContextTokens: 1024,
            reservedCompletionTokens: 128,
            userMode: .fastest,
            fallbackContract: .productDefault(for: .fastest),
            deviceClass: .a17Pro,
            osBuild: "test",
            memoryCounters: RuntimeMemoryCounters(
                availableMemoryBytes: 2_000 * 1_024 * 1_024,
                processResidentMemoryBytes: 128 * 1_024 * 1_024
            ),
            quantizationDiagnostics: RuntimeQuantizationDiagnostics(
                activeAttentionPath: .twoStageCompressed
            ),
            estimatedModelWeightsBytes: 100,
            compressedKVBytesPerToken: 10,
            rawShadowBytes: 0,
            packedFallbackBytesPerToken: 0,
            decodedFallbackScratchBytes: 0,
            promptBufferBytes: 0,
            metalScratchReserveBytes: 0,
            uiReserveBytes: 0,
            speculativeBudget: speculativeBudget
        )
    }
}
