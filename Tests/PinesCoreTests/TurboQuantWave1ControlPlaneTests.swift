import Foundation
import PinesCore
import Testing

@Suite("TurboQuant Wave 1 control plane")
struct TurboQuantWave1ControlPlaneTests {
    @Test func memoryZoneTotalEqualsSum() {
        let zones = RuntimeMemoryZones(
            modelWeightsBytes: 10,
            compressedKVBytes: 20,
            rawShadowBytes: 30,
            packedFallbackBytes: 40,
            decodedFallbackScratchBytes: 50,
            vaultIndexBytes: 60,
            promptBufferBytes: 70,
            metalScratchReserveBytes: 80,
            uiReserveBytes: 90,
            safetyReserveBytes: 100
        )

        #expect(zones.totalPlannedBytes == 550)
        #expect(zones.totalMatchesZones)
        #expect(zones.allZonesAreNonNegative)
    }

    @Test func admissionRejectsUnsafeContextBeforeRun() {
        let request = Self.request(availableMemoryBytes: 256 * 1_024 * 1_024)

        let plan = LocalRuntimeAdmissionService().admit(request)

        #expect(!plan.admitted)
        #expect(plan.rejectionReason == LocalInferenceFailureKind.memoryAdmissionFailed.rawValue)
        #expect(plan.admittedContextTokens == 0)
        #expect(plan.validationErrors.isEmpty)
    }

    @Test func admissionDowngradesBalancedOnlyToShorterBalancedOrBatterySaver() {
        let request = Self.request(
            availableMemoryBytes: 2_200 * 1_024 * 1_024,
            requestedContextTokens: 16_384,
            compressedKVBytesPerToken: 96 * 1_024
        )

        let plan = LocalRuntimeAdmissionService().admit(request)

        #expect(plan.admitted)
        #expect([TurboQuantUserMode.balanced, .batterySaver].contains(plan.selectedMode))
        #expect(plan.selectedMode != .maxContext)
        #expect(plan.admittedContextTokens < request.requestedContextTokens)
        #expect(plan.downgradeReason != nil)
    }

    @Test func runDecisionRequiresFallbackReason() {
        let invalid = TurboQuantRunDecision(fallbackUsed: true)
        let valid = TurboQuantRunDecision(
            selectedAttentionPath: .mlxPackedFallback,
            fallbackUsed: true,
            fallbackReason: "qk unavailable"
        )

        #expect(invalid.validationErrors.contains("fallbackUsed requires fallbackReason"))
        #expect(valid.validationErrors.isEmpty)
    }

    @Test func streamFailureCarriesWave2ProviderMetadata() throws {
        let contextPlan = ContextAssemblyPlan(
            strategy: "mlx-exact-token-preflight-v1",
            includedRecentMessageCount: 4,
            clippedMessageCount: 1,
            exactInputTokens: 512,
            reservedCompletionTokens: 128,
            truncationReason: "context_window"
        )
        let decision = TurboQuantRunDecision(
            admission: Self.admissionPlan(contextPlanID: contextPlan.id),
            selectedAttentionPath: .twoStageCompressed,
            inputTokens: 512,
            outputTokens: 0,
            contextAssemblyPlanID: contextPlan.id,
            memoryCalibrationSampleID: "sample"
        )
        let failure = InferenceStreamFailure(
            code: LocalInferenceFailureKind.contextWindowExceeded.rawValue,
            message: "too long",
            recoverable: false,
            providerMetadata: [
                LocalProviderMetadataKeys.turboQuantContextAssemblyPlanID: contextPlan.id,
                LocalProviderMetadataKeys.turboQuantRunDecisionID: decision.decisionID,
            ]
        )

        let decoded = try JSONDecoder().decode(
            InferenceStreamFailure.self,
            from: try JSONEncoder().encode(failure)
        )

        #expect(decoded.providerMetadata[LocalProviderMetadataKeys.turboQuantContextAssemblyPlanID] == contextPlan.id)
        #expect(decoded.providerMetadata[LocalProviderMetadataKeys.turboQuantRunDecisionID] == decision.decisionID)
    }

    @Test func skeletonSchemasRoundTripCodable() throws {
        let qualityGate = Self.qualityGate()
        let evidence = RuntimeProfileEvidence(
            evidenceLevel: .unverified,
            compatibilityPairID: "pending",
            modelID: "model",
            fallbackContractHash: "hash",
            deviceClass: .a17Pro,
            osBuild: "test",
            userMode: .balanced,
            activeAttentionPath: .twoStageCompressed,
            admittedContextTokens: 1024,
            peakMemoryBytes: 2048,
            qualityGate: qualityGate
        )
        let calibration = RuntimeMemoryCalibrationSample(
            runOutcome: .rejectedBeforeRun,
            rejectionReason: "memory",
            modelID: "model",
            deviceClass: .a17Pro,
            userMode: .balanced,
            requestedContextTokens: 2048,
            admittedContextTokens: 0,
            estimatedCompressedKVBytes: 1,
            estimatedFallbackBytes: 2,
            estimatedScratchBytes: 3,
            availableMemoryAtAdmission: 4,
            memoryWarningsSeen: 0
        )

        try roundTrip(qualityGate)
        try roundTrip(evidence)
        try roundTrip(calibration)
        try roundTrip(
            ContextAssemblyPlan(
                strategy: "mlx-current-history-v1",
                includedRecentMessageCount: 3,
                exactInputTokens: 512,
                reservedCompletionTokens: 128
            )
        )
    }

    private static func request(
        availableMemoryBytes: Int64,
        requestedContextTokens: Int = 8192,
        compressedKVBytesPerToken: Int64 = 256 * 1_024
    ) -> LocalRuntimeAdmissionRequest {
        LocalRuntimeAdmissionRequest(
            modelID: "test-model",
            requestedContextTokens: requestedContextTokens,
            reservedCompletionTokens: 512,
            userMode: .balanced,
            fallbackContract: .productDefault(for: .balanced),
            deviceClass: .a17Pro,
            osBuild: "test",
            memoryCounters: RuntimeMemoryCounters(
                availableMemoryBytes: availableMemoryBytes,
                processResidentMemoryBytes: 128 * 1_024 * 1_024
            ),
            quantizationDiagnostics: RuntimeQuantizationDiagnostics(activeAttentionPath: .twoStageCompressed),
            compressedKVBytesPerToken: compressedKVBytesPerToken,
            rawShadowBytes: 32 * 1_024 * 1_024,
            packedFallbackBytesPerToken: 16 * 1_024,
            decodedFallbackScratchBytes: 32 * 1_024 * 1_024,
            promptBufferBytes: 16 * 1_024 * 1_024,
            metalScratchReserveBytes: 64 * 1_024 * 1_024,
            uiReserveBytes: 64 * 1_024 * 1_024
        )
    }

    private static func qualityGate() -> TurboQuantQualityGate {
        TurboQuantQualityGate(
            benchmarkSuiteID: .tinyDeterministicLogitsV1,
            deterministicTop1MatchRate: 1,
            logitKLDivergenceMean: 0,
            logitMaxAbsErrorP95: 0,
            noNaNOrInf: true,
            fallbackEquivalent: true,
            prefillExact: true,
            passed: true
        )
    }

    private static func admissionPlan(contextPlanID: String) -> LocalRuntimeAdmissionPlan {
        LocalRuntimeAdmissionPlan(
            admitted: true,
            requestedContextTokens: 1024,
            admittedContextTokens: 1024,
            reservedCompletionTokens: 128,
            selectedMode: .balanced,
            selectedKVStrategy: .turboQuant,
            selectedAttentionPath: .twoStageCompressed,
            fallbackContract: .productDefault(for: .balanced),
            memoryZones: RuntimeMemoryZones(
                modelWeightsBytes: 1,
                compressedKVBytes: 2,
                rawShadowBytes: 3,
                packedFallbackBytes: TurboQuantFallbackContract.defaultReserveBytes(for: .balanced),
                decodedFallbackScratchBytes: 4,
                vaultIndexBytes: 5,
                promptBufferBytes: 6,
                metalScratchReserveBytes: 7,
                uiReserveBytes: 8,
                safetyReserveBytes: 9
            ),
            memoryCushionBytes: 10,
            userFacingMessage: "admitted"
        )
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        #expect(decoded == value)
    }
}
