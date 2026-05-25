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

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        #expect(decoded == value)
    }
}
