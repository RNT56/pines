import PinesCore
import Testing

private let mb: Int64 = 1_024 * 1_024

/// Tests for the dynamic FP16↔TurboQuant decision in `LocalRuntimeAdmissionService.admit`.
///
/// The policy is a memory-feasibility ladder, not a static token threshold:
///   * FP16 (`.none`) is chosen whenever its uncompressed KV cache fits the live budget —
///     it is strictly faster and higher-quality.
///   * TurboQuant (`.turboQuant`) is chosen only when FP16 will not fit, to reach a context
///     that otherwise would not fit RAM.
///   * `.fastest` never compresses — it caps the context to a shorter FP16 window instead.
///   * `.maxContext` goes straight to compression (reaching far is the point).
@Suite("TurboQuant KV strategy ladder")
struct TurboQuantKVStrategyLadderTests {
    /// Builds an admission request with explicit per-token KV costs and a live memory budget.
    private static func request(
        availableMemoryBytes: Int64,
        requestedContextTokens: Int = 4096,
        fp16KVBytesPerToken: Int64 = 400_000,        // ~all-layers FP16, large on purpose
        compressedKVBytesPerToken: Int64 = 120_000,  // ~0.3× of FP16 (turbo4v2-ish)
        estimatedModelWeightsBytes: Int64 = 200 * mb,
        userMode: TurboQuantUserMode = .balanced
    ) -> LocalRuntimeAdmissionRequest {
        LocalRuntimeAdmissionRequest(
            modelID: "ladder-test",
            requestedContextTokens: requestedContextTokens,
            reservedCompletionTokens: 256,
            userMode: userMode,
            fallbackContract: .productDefault(for: userMode),
            deviceClass: .a17Pro,
            osBuild: "test",
            memoryCounters: RuntimeMemoryCounters(
                availableMemoryBytes: availableMemoryBytes,
                processResidentMemoryBytes: 128 * mb
            ),
            estimatedModelWeightsBytes: estimatedModelWeightsBytes,
            compressedKVBytesPerToken: compressedKVBytesPerToken,
            fp16KVBytesPerToken: fp16KVBytesPerToken,
            rawShadowBytes: 32 * mb,
            packedFallbackBytesPerToken: 16 * 1_024,
            decodedFallbackScratchBytes: 32 * mb,
            promptBufferBytes: 16 * mb,
            metalScratchReserveBytes: 64 * mb,
            uiReserveBytes: 64 * mb
        )
    }

    private static let service = LocalRuntimeAdmissionService()

    @Test("FP16 is chosen when its uncompressed KV cache fits the budget")
    func fp16WhenItFits() {
        // 6 GB available: FP16 KV (≈1.6 GB @4096) + weights + safety fits comfortably.
        let plan = Self.service.admit(Self.request(availableMemoryBytes: 6_144 * mb))
        #expect(plan.admitted)
        #expect(plan.selectedKVStrategy == .none)          // .none == plain FP16
        #expect(plan.admittedContextTokens == 4096)        // full requested length
    }

    @Test("Falls to TurboQuant when FP16 will not fit but compressed will")
    func turboQuantWhenFP16TooLarge() {
        // 2.4 GB: FP16 (≈2.49 GB required) overflows; compressed (≈1.48 GB) fits at full length.
        let plan = Self.service.admit(Self.request(availableMemoryBytes: 2_400 * mb))
        #expect(plan.admitted)
        #expect(plan.selectedKVStrategy == .turboQuant)
        #expect(plan.admittedContextTokens == 4096)        // full context, just compressed
    }

    @Test(".fastest caps to a shorter FP16 window instead of compressing")
    func fastestCapsContextRatherThanCompress() {
        // 2.0 GB: FP16-full overflows; compressed-full would fit, but .fastest must prefer a
        // shorter FP16 window over switching codecs.
        let plan = Self.service.admit(
            Self.request(availableMemoryBytes: 2_000 * mb, userMode: .fastest))
        #expect(plan.admitted)
        #expect(plan.selectedKVStrategy == .none)          // still FP16
        #expect(plan.admittedContextTokens < 4096)         // but a shorter window
        #expect(plan.downgradeReason == "fp16_context_capped_to_fit")
    }

    @Test(".maxContext goes straight to compression even when FP16 would fit")
    func maxContextPrefersCompression() {
        // Plenty of memory (FP16 would fit), but .maxContext reaches far via compression.
        let plan = Self.service.admit(
            Self.request(availableMemoryBytes: 6_144 * mb, userMode: .maxContext))
        #expect(plan.admitted)
        #expect(plan.selectedKVStrategy == .turboQuant)
    }

    @Test("FP16 is skipped when its per-token cost is unknown (back-compat)")
    func fp16SkippedWhenCostUnknown() {
        // fp16KVBytesPerToken == 0 → the legacy callers' behavior: compressed only.
        let plan = Self.service.admit(
            Self.request(availableMemoryBytes: 6_144 * mb, fp16KVBytesPerToken: 0))
        #expect(plan.admitted)
        #expect(plan.selectedKVStrategy == .turboQuant)
    }

    @Test("Rejects when nothing fits, even compressed at the shortest context")
    func rejectsWhenNothingFits() {
        // 600 MB < model weights (200 MB) + safety reserve (512 MB): impossible regardless of KV.
        let plan = Self.service.admit(Self.request(availableMemoryBytes: 600 * mb))
        #expect(!plan.admitted)
        #expect(plan.rejectionReason != nil)
        #expect(plan.admittedContextTokens == 0)
    }

    @Test("Lower budget pushes FP16 to a shorter admitted context, not compression, for .fastest")
    func fastestMonotonicallyShortens() {
        let roomy = Self.service.admit(
            Self.request(availableMemoryBytes: 6_144 * mb, userMode: .fastest))
        let tight = Self.service.admit(
            Self.request(availableMemoryBytes: 2_000 * mb, userMode: .fastest))
        #expect(roomy.selectedKVStrategy == .none)
        #expect(tight.selectedKVStrategy == .none)
        #expect(tight.admittedContextTokens <= roomy.admittedContextTokens)
    }
}
