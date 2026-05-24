# Schema Registry

This document defines versioning rules for every persisted, exported, or cross-repo TurboQuant object. It is intentionally stricter than normal app DTO versioning because stale cache state, stale benchmark evidence, or mismatched model profiles can produce incorrect output.

## Scope

Use schema envelopes for:

- benchmark JSON;
- profile evidence;
- quality gates;
- memory calibration samples and aggregates;
- run decision support exports;
- failure events;
- context assembly support exports;
- KV snapshot manifests;
- snapshot security policies;
- model profile JSON;
- compatibility-pair manifests.

Do not wrap hot-path in-memory structs in `VersionedEnvelope` inside generation loops unless they are being serialized. Hot structs should carry lightweight `schemaVersion` only where needed.

## Universal envelope

```swift
public struct VersionedEnvelope<Payload: Codable>: Codable, Sendable {
    public var schemaName: String
    public var schemaVersion: Int
    public var producer: SchemaProducer
    public var compatibility: SchemaCompatibility
    public var createdAt: Date
    public var payload: Payload
}

public struct SchemaProducer: Codable, Sendable {
    public var repo: String
    public var commit: String?
    public var build: String?
    public var osBuild: String?
}

public struct SchemaCompatibility: Codable, Sendable {
    public var minReaderVersion: Int
    public var maxTestedReaderVersion: Int
    public var failClosedIfNewer: Bool
}
```

## Required schemas

| Schema | Version | Owner | Used by |
| --- | ---: | --- | --- |
| `AdmissionPlan` | 1 | Pines | admission metadata, RunDecision |
| `RuntimeMemoryZones` | 1 | Pines | admission, memory calibration, support export |
| `RunDecision` | 1 | Pines | provider metadata, support export |
| `FailureEvent` | 1 | all | stream failures, support export |
| `BenchmarkReport` | 1 | all | evidence import |
| `ProfileEvidence` | 1 | Pines | compatibility UI, admission |
| `QualityGate` | 1 | LM/Pines | evidence level |
| `MemoryCalibration` | 1 | Pines | admission multiplier |
| `ContextAssemblyPlan` | 1 | Pines | prompt/context metadata |
| `KVSnapshotManifest` | 1 | LM/Pines | snapshot restore |
| `SnapshotSecurityPolicy` | 1 | Pines | snapshot persistence |
| `ModelProfile` | 2 | LM | profile validation |
| `TurboQuantLayout` | 4 | MLX Swift | current compressed layout |
| `TurboQuantLayoutNext` | 5 | MLX Swift | gated future layout |
| `AdaptivePrecisionPolicy` | 1 | all | future adaptive precision |

## Schema rules

1. Missing version is untrusted.
2. Unknown schema is rejected.
3. Newer schema with `failClosedIfNewer == true` is rejected.
4. Older schema may load only through explicit migration.
5. Support exports always include schema envelope.
6. Evidence imports require exact schema name and version.
7. Snapshot manifests require model/tokenizer/profile/RoPE/prefix hashes.
8. Evidence must include compatibility-pair ID and fallback-contract hash.
9. Schema migrations must be deterministic and tested.
10. Persisted data cannot silently drop unknown fields and claim equivalence.

## AdmissionPlan.v1

Owner: Pines.

Purpose:

Represents the decision made before local generation begins.

Required payload fields:

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

Rules:

- `admitted == false` requires `rejectionReason`.
- `admittedContextTokens <= requestedContextTokens`.
- `selectedMode` must follow the mode downgrade rules in [Mode and Fallback Contract](04-mode-fallback-contract.md).
- A plan that allows fallback must include nonzero fallback reserve.
- Cloud retry must be false unless route policy explicitly allows it.

## RuntimeMemoryZones.v1

Owner: Pines.

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

Rules:

- `totalPlannedBytes` must equal the sum of all zones unless future schema explicitly adds an excluded field.
- Negative zones are invalid.
- Full decoded fallback cannot be planned in product modes unless explicitly enabled by fallback contract.

## RunDecision.v1

Owner: Pines.

```swift
public struct TurboQuantRunDecision: Codable, Sendable {
    public var schemaVersion: Int
    public var compatibilityPairID: String?
    public var admission: LocalRuntimeAdmissionPlan?
    public var selectedAttentionPath: LocalTurboQuantAttentionPath?
    public var rejectedPaths: [LocalRejectedTurboQuantPath]
    public var cacheLifecycle: String?
    public var actualKeyBitsPerValue: Double?
    public var actualValueBitsPerValue: Double?
    public var fallbackUsed: Bool
    public var fallbackReason: String?
    public var rawShadowAllocated: Bool?
    public var packedFallbackAllocated: Bool?
    public var compressedKeyBytes: Int64?
    public var compressedValueBytes: Int64?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var contextAssemblyPlanID: String?
    public var memoryCalibrationSampleID: String?
}
```

Rules:

- Every successful local run attaches RunDecision.
- Every local failure attaches partial RunDecision when admission or cache metadata exists.
- `fallbackUsed == true` requires `fallbackReason`.
- Rejected paths must include reasons.

## FailureEvent.v1

Owner: all repos, mapped in Pines.

Required fields:

```swift
public struct LocalInferenceFailureEvent: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: LocalInferenceFailureKind
    public var sourceRepo: String
    public var sourceType: String?
    public var message: String
    public var recoverable: Bool
    public var recommendedAction: String?
    public var admissionPlanID: String?
    public var runDecisionID: String?
}
```

Failure kinds:

```swift
public enum LocalInferenceFailureKind: String, Codable, Sendable {
    case memoryAdmissionFailed
    case turboQuantPathUnavailable
    case turboQuantFallbackUnavailable
    case fallbackBudgetExceeded
    case modelProfileUnverified
    case modelProfileMismatch
    case unsupportedAttentionShape
    case contextWindowExceeded
    case snapshotInvalid
    case snapshotCorrupt
    case mlxRuntimeFailure
    case cloudRouteDisallowed
}
```

Rules:

- Product failures must be typed before reaching UI.
- Generic `mlxRuntimeFailure` is allowed only as the outer fallback when no narrower mapping exists, and it must carry the original type/message.

## BenchmarkReport.v1

Owner: all repos.

Required high-level fields:

- producer repo and commit;
- compatibility-pair ID;
- device class;
- hardware model;
- OS build;
- available memory;
- model ID and revision;
- tokenizer hash;
- profile hash;
- fallback contract hash;
- TurboQuant preset/value bits/group size/layout version;
- attention path;
- context tokens;
- compressed KV bytes;
- peak memory;
- first-token latency;
- prefill tok/s;
- decode tok/s p50/p95;
- quality gate block;
- memory calibration sample block.

Rules:

- One benchmark report certifies one model/device/mode/fallback-contract tuple.
- Reports without quality gate cannot produce Verified evidence.
- Reports without compatibility pair cannot be imported as release evidence.

## ProfileEvidence.v1

Owner: Pines.

Required fields:

```swift
public struct RuntimeProfileEvidence: Codable, Sendable, Identifiable {
    public var id: UUID
    public var schemaVersion: Int
    public var evidenceLevel: RuntimeEvidenceLevel
    public var compatibilityPairID: String
    public var modelID: String
    public var modelRevision: String?
    public var tokenizerHash: String?
    public var profileHash: String?
    public var fallbackContractHash: String
    public var deviceClass: DevicePerformanceClass
    public var hardwareModel: String?
    public var osBuild: String
    public var userMode: LocalAIUserMode
    public var turboQuantPreset: String?
    public var valueBits: Int?
    public var groupSize: Int?
    public var layoutVersion: Int?
    public var activeAttentionPath: LocalTurboQuantAttentionPath?
    public var admittedContextTokens: Int
    public var peakMemoryBytes: Int64
    public var promptTokensPerSecond: Double?
    public var decodeTokensPerSecondP50: Double?
    public var decodeTokensPerSecondP95: Double?
    public var firstTokenLatencyMS: Double?
    public var qualityGate: TurboQuantQualityGate
    public var memoryCalibrationSampleID: UUID?
    public var revokedReason: String?
    public var createdAt: Date
}
```

Evidence levels:

```swift
public enum RuntimeEvidenceLevel: String, Codable, Sendable {
    case unverified
    case smokeTested
    case verified
    case certified
    case revoked
}
```

Rules:

- Only `verified` and `certified` can produce product compatibility claims.
- Evidence is invalid if fallback contract hash changes.
- Evidence is invalid if model revision, tokenizer hash, profile hash, layout version, or compatibility pair changes unless explicit migration certifies equivalence.

## QualityGate.v1

Defined in [Quality Gates](06-quality-gates.md).

## MemoryCalibration.v1

Defined in [Memory Admission and Calibration](05-memory-admission-calibration.md).

## ContextAssemblyPlan.v1

Defined in [Context Memory Planner](10-context-memory-planner.md).

## KVSnapshotManifest.v1

Defined in [KV Snapshot Security](11-kv-snapshot-security.md).

## ModelProfile.v2

Owned by `mlx-swift-lm`.

Required profile shape:

```json
{
  "schema_version": 2,
  "architecture": "",
  "requires": {
    "hidden_size": 0,
    "num_hidden_layers": 0,
    "num_attention_heads": 0,
    "num_key_value_heads": 0,
    "head_dim": 0,
    "rope_type": ""
  },
  "turboquant": {
    "layout_version": 4,
    "key_preset": "turbo3_5",
    "value_bits": 4,
    "group_size": 64,
    "preferred_paths": ["onlineFused", "twoStageCompressed", "mlxPackedFallback"]
  }
}
```

Rules:

- No model-name-only TurboQuant activation.
- Model config must match profile requirements.
- Mismatch disables TurboQuant and surfaces reason to Pines.

## Schema registry maintenance

When adding or changing a schema:

1. Add/modify the schema section here.
2. Add migration notes.
3. Add tests for missing, older, newer, and unknown versions.
4. Update `compatibility-pair.json` schema set.
5. Update benchmark import/export if relevant.
6. Update support export if relevant.
