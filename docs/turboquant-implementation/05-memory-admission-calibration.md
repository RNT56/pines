# Memory Admission and Calibration

Admission is the spine of the product. Any feature that affects memory, correctness, fallback, or runtime path must feed into admission before local generation starts.

## Why admission is required

On iOS, the relevant resource is not total device RAM. It is memory currently available to the app, under current thermal state, Low Power Mode, foreground/background policy, model weights, UI allocations, vault indexes, prompt buffers, Metal scratch, and fallback reserves.

TurboQuant reduces the largest dynamic memory component, but the product can still fail if it accidentally keeps multiple cache representations resident.

## Admission rule

```text
plannedBytes * calibrationMultiplier + safetyReserve <= availableMemory
```

Initial safety reserve:

```text
max(512 MiB, 20% of available memory)
```

Use available memory, not total memory. On iOS this should use the runtime device monitor and `os_proc_available_memory` where available.

## RuntimeMemoryZones.v1

```swift
public struct RuntimeMemoryZones: Codable, Sendable {
    public var schemaVersion: Int
    public var modelWeightsBytes: Int64
    public var compressedKVBytes: Int64
    public var rawShadowBytes: Int64
    public var packedFallbackBytes: Int64
    public var decodedFallbackScratchBytes: Int64
    public var vaultIndexBytes: Int64
    public var promptBufferBytes: Int64
    public var metalScratchReserveBytes: Int64
    public var uiReserveBytes: Int64
    public var safetyReserveBytes: Int64
    public var totalPlannedBytes: Int64
}
```

Zone definitions:

- `modelWeightsBytes`: resident model weights and model-side persistent state.
- `compressedKVBytes`: admitted compressed KV for selected context.
- `rawShadowBytes`: raw KV chunks intentionally retained during exact prefill or debug.
- `packedFallbackBytes`: packed quantized fallback cache if allocated or budgeted.
- `decodedFallbackScratchBytes`: transient layer/window decoded fallback scratch.
- `vaultIndexBytes`: local vector index and loaded retrieval structures.
- `promptBufferBytes`: tokenizer, prompt assembly, masks, temporary arrays.
- `metalScratchReserveBytes`: kernel scratch, command buffers, temporary outputs.
- `uiReserveBytes`: app UI and non-inference working set.
- `safetyReserveBytes`: hard cushion to prevent jetsam.

## Admission request

```swift
public struct LocalRuntimeAdmissionRequest: Codable, Sendable {
    public var schemaVersion: Int
    public var modelID: String
    public var modelRevision: String?
    public var parameterCount: Int64?
    public var requestedContextTokens: Int
    public var reservedCompletionTokens: Int
    public var userMode: LocalAIUserMode
    public var fallbackContract: LocalFallbackContract
    public var deviceClass: DevicePerformanceClass
    public var hardwareModel: String?
    public var osBuild: String
    public var memoryCounters: RuntimeMemoryCounters
    public var turboQuantCapabilities: LocalTurboQuantCapabilities?
    public var profileEvidence: RuntimeProfileEvidence?
    public var calibration: RuntimeMemoryCalibration?
    public var contextAssemblyPlan: ContextAssemblyPlan?
}
```

## Admission plan

```swift
public struct LocalRuntimeAdmissionPlan: Codable, Sendable {
    public var schemaVersion: Int
    public var admitted: Bool
    public var requestedContextTokens: Int
    public var admittedContextTokens: Int
    public var reservedCompletionTokens: Int
    public var selectedMode: LocalAIUserMode
    public var selectedKVStrategy: KVCacheStrategy
    public var selectedAttentionPath: LocalTurboQuantAttentionPath?
    public var fallbackContract: LocalFallbackContract
    public var memoryZones: RuntimeMemoryZones
    public var memoryCushionBytes: Int64
    public var calibrationApplied: RuntimeMemoryCalibrationSummary?
    public var downgradeReason: String?
    public var rejectionReason: String?
    public var userFacingMessage: String
}
```

## Estimation responsibilities

Admission must estimate:

1. model resident bytes;
2. raw fp16 KV bytes/token;
3. compressed TurboQuant KV bytes/token;
4. packed fallback bytes;
5. decoded fallback scratch bytes;
6. prompt and tokenizer buffers;
7. vault index memory;
8. Metal scratch reserve;
9. UI reserve;
10. safety reserve.

Inputs should prefer real runtime facts:

- MLX Swift symbolic storage estimate before allocation;
- MLX Swift actual storage estimate after cache exists;
- LM runtime cache snapshot after prefill/decode;
- device monitor available memory;
- evidence store peak memory;
- memory calibration p95 multipliers.

## Calibration sample

Record both successful and failed runs. Failed or near-jetsam samples are valuable.

```swift
public struct RuntimeMemoryCalibrationSample: Codable, Sendable {
    public var schemaVersion: Int
    public var id: UUID
    public var compatibilityPairID: String?
    public var runOutcome: String
    public var rejectionReason: String?
    public var modelID: String
    public var modelRevision: String?
    public var deviceClass: DevicePerformanceClass
    public var userMode: LocalAIUserMode
    public var attentionPath: LocalTurboQuantAttentionPath?
    public var requestedContextTokens: Int
    public var admittedContextTokens: Int
    public var estimatedCompressedKVBytes: Int64
    public var actualCompressedKVBytes: Int64?
    public var estimatedFallbackBytes: Int64
    public var actualFallbackBytes: Int64?
    public var estimatedScratchBytes: Int64
    public var observedPeakMemoryBytes: Int64?
    public var availableMemoryAtAdmission: Int64
    public var availableMemoryAtPrefillEnd: Int64?
    public var availableMemoryAtDecodeEnd: Int64?
    public var memoryWarningsSeen: Int
    public var createdAt: Date
}
```

Run outcomes:

```swift
public enum RuntimeMemoryCalibrationOutcome: String, Codable, Sendable {
    case admittedSucceeded
    case rejectedBeforeRun
    case cancelledMemoryWarning
    case fallbackBudgetExceeded
    case runtimeFailed
    case jetsamSuspected
}
```

## Calibration aggregate

```swift
public struct RuntimeMemoryCalibration: Codable, Sendable {
    public var schemaVersion: Int
    public var deviceClass: DevicePerformanceClass
    public var modelFamily: String
    public var attentionPath: LocalTurboQuantAttentionPath
    public var sampleCount: Int
    public var estimatedToActualPeakRatioP95: Double
    public var scratchMultiplier: Double
    public var fallbackMultiplier: Double
    public var safetyReserveBytes: Int64
    public var staleAfter: Date?
    public var updatedAt: Date
}
```

## Calibration invalidation

Invalidate or mark stale when:

- compatibility pair changes;
- model revision changes;
- tokenizer/profile/layout changes;
- OS build changes substantially;
- device class policy changes;
- fallback contract changes;
- hidden-copy audit finds a new issue;
- benchmark regression revokes evidence.

## Admission algorithm

1. Gather device state.
2. Gather model metadata and profile evidence.
3. Build fallback contract from user mode and route policy.
4. Estimate memory zones for requested context.
5. Apply calibration multiplier.
6. Compare against available memory and safety reserve.
7. If unsafe, apply mode-specific downgrade order.
8. If still unsafe, reject before generation.
9. Emit plan and user-facing explanation.
10. Attach plan to RunDecision.

## Hidden duplicate-KV prevention

Admission must explicitly decide whether the run may allocate:

- raw prefill chunk;
- raw shadow cache;
- packed fallback cache;
- decoded fallback scratch;
- compressed cache.

Rules:

- raw prefill chunks must be released after compressed commit unless exact fallback contract explicitly keeps them;
- packed fallback is lazy and budgeted;
- decoded fallback must be layer/window local by default;
- all-layer full decoded fallback is disabled by default;
- Max Context should fail typed rather than allocate unbudgeted fallback.

## Tests

Required:

- unsafe context rejected before model load/run where possible;
- available memory used instead of total memory;
- downgrade order follows mode contract;
- full decoded fallback cannot appear without reserve;
- memory zone total equals sum;
- calibration multiplier changes admission result;
- failed samples are persisted;
- stale calibration is ignored.
