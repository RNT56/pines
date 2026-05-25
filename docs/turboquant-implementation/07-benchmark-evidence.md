# Benchmark Evidence

Compatibility claims are evidence-backed. A profile may exist before evidence, but Pines must not say a model/context/mode is verified until a benchmark report proves memory, speed, correctness, and quality on a device class.

Launch waves: W10 can create the evidence-store skeleton in Wave 1; benchmark import, evidence levels, revocation, and real-device verification activate in Wave 3.

## Evidence thesis

One benchmark report certifies one tuple:

```text
model + revision + tokenizer + profile + fallback contract + device class + OS + mode + context + attention path
```

If any component changes, evidence must be invalidated or explicitly migrated.

## BenchmarkReport.v1 required fields

```swift
public struct TurboQuantBenchmarkReport: Codable, Sendable {
    public var schemaVersion: Int
    public var compatibilityPairID: String
    public var producer: SchemaProducer
    public var device: TurboQuantBenchmarkDevice
    public var model: TurboQuantBenchmarkModel
    public var runtime: TurboQuantBenchmarkRuntime
    public var metrics: TurboQuantBenchmarkMetrics
    public var qualityGate: TurboQuantQualityGate
    public var memoryCalibrationSample: RuntimeMemoryCalibrationSample?
    public var createdAt: Date
}
```

Device:

```swift
public struct TurboQuantBenchmarkDevice: Codable, Sendable {
    public var deviceClass: DevicePerformanceClass
    public var hardwareModel: String
    public var osBuild: String
    public var availableMemoryBytesAtStart: Int64
    public var metalDeviceName: String?
    public var lowPowerMode: Bool
    public var thermalState: String
}
```

Model:

```swift
public struct TurboQuantBenchmarkModel: Codable, Sendable {
    public var id: String
    public var revision: String?
    public var tokenizerHash: String?
    public var profileHash: String?
    public var architecture: String?
    public var layers: Int?
    public var kvHeads: Int?
    public var headDim: Int?
}
```

Runtime:

```swift
public struct TurboQuantBenchmarkRuntime: Codable, Sendable {
    public var userMode: TurboQuantUserMode
    public var fallbackContractHash: String
    public var preset: String?
    public var valueBits: Int?
    public var groupSize: Int?
    public var layoutVersion: Int?
    public var attentionPath: TurboQuantAttentionPath?
    public var kernelProfile: String?
    public var admittedContextTokens: Int
    public var reservedCompletionTokens: Int
}
```

Metrics:

```swift
public struct TurboQuantBenchmarkMetrics: Codable, Sendable {
    public var contextTokens: Int
    public var firstTokenLatencyMS: Double?
    public var prefillTokensPerSecond: Double?
    public var decodeTokensPerSecondP50: Double?
    public var decodeTokensPerSecondP95: Double?
    public var peakMemoryBytes: Int64?
    public var compressedKVBytes: Int64?
    public var rawShadowBytes: Int64?
    public var packedFallbackBytes: Int64?
    public var decodedFallbackScratchBytes: Int64?
    public var memoryWarningsSeen: Int
    public var fallbackUsed: Bool
    public var fallbackReason: String?
    public var jetsamObserved: Bool
}
```

## Evidence import rules

Pines importer must:

1. decode schema envelope;
2. verify schema name/version;
3. verify compatibility pair exists or import as non-release evidence;
4. verify fallback contract hash;
5. verify quality gate passed for Verified/Certified;
6. verify no jetsam and no memory warning pattern that violates gate;
7. store memory calibration sample;
8. store profile evidence;
9. attach evidence level;
10. revoke older conflicting evidence if regression.

## ProfileEvidenceStore

Repository responsibilities:

- add GRDB table;
- import benchmark JSON;
- query by model/revision/device/mode;
- query by fallback contract hash;
- expose evidence level;
- revoke evidence;
- export evidence for support bundle.

Minimum table fields:

- `id`;
- `schemaVersion`;
- `evidenceLevel`;
- `compatibilityPairID`;
- `modelID`;
- `modelRevision`;
- `tokenizerHash`;
- `profileHash`;
- `fallbackContractHash`;
- `deviceClass`;
- `hardwareModel`;
- `osBuild`;
- `userMode`;
- `layoutVersion`;
- `attentionPath`;
- `admittedContextTokens`;
- `peakMemoryBytes`;
- `prefillTokS`;
- `decodeTokSP50`;
- `decodeTokSP95`;
- `firstTokenLatencyMS`;
- `qualityGateJSON`;
- `memoryCalibrationSampleID`;
- `revokedReason`;
- `createdAt`.

## Real-device acceptance

The first evidence-backed release requires at least one verified real iPhone model/device/mode tuple.

The full matrix is release expansion:

- A16 compact;
- A17 Pro;
- A18;
- A18 Pro;
- A19;
- A19 Pro thin;
- A19 Pro sustained;
- M-series iPad 8 GB;
- M-series iPad 12 GB;
- M-series iPad 16 GB.

## Benchmark runner requirements

Pines debug benchmark runner should:

- select fixed prompt suites;
- run fixed context lengths where admitted: 4k, 8k, 16k, 32k, 64k where safe;
- record available memory;
- record thermal and Low Power Mode;
- record admission plan;
- record RunDecision;
- record QualityGate;
- export BenchmarkReport.v1 JSON;
- import the report into ProfileEvidenceStore.

## Product UI states

| State | Evidence condition |
| --- | --- |
| Verified | evidence level Verified/Certified for exact tuple |
| Conservative | missing tuple evidence, safe defaults only |
| Unverified | model may run but no claim |
| Unsupported | profile/capability/admission rejects |
| Degraded | fallback or reduced context used |
| Benchmark Required | user requested larger claim without evidence |

## Tests

Required:

- importer rejects unknown schema;
- importer rejects missing fallback contract hash;
- importer rejects failed quality gate for Verified;
- importer stores calibration sample;
- evidence lookup respects mode and device class;
- revoked evidence is not returned as verified;
- compatibility UI cannot show Verified without evidence.
