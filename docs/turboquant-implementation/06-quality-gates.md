# Quality Gates

Evidence-backed compatibility requires correctness and quality gates. A boolean `qualityPassed` is not enough; the system must record what was measured, which thresholds applied, and why evidence is allowed to make product claims.

Launch waves: W22 can define schema and suite IDs in Wave 1; full quality measurement and evidence-level activation happen in Wave 3.

## Quality gate object

```swift
public struct TurboQuantQualityGate: Codable, Sendable {
    public var schemaVersion: Int
    public var gateVersion: Int
    public var benchmarkSuiteID: String
    public var deterministicTop1MatchRate: Double
    public var logitKLDivergenceMean: Double
    public var logitMaxAbsErrorP95: Double
    public var perplexityDeltaPercent: Double?
    public var retrievalNeedlePassRate: Double?
    public var taskEvalDeltaPercent: Double?
    public var attentionOutputCosineMean: Double?
    public var noNaNOrInf: Bool
    public var fallbackEquivalent: Bool
    public var prefillExact: Bool
    public var snapshotRoundtripEquivalent: Bool?
    public var profileQualityThresholdOverride: String?
    public var gateReason: String?
    public var passed: Bool
}
```

## Default initial thresholds

| Metric | Default threshold |
| --- | --- |
| No NaN/Inf | required |
| Prefill exactness | required |
| Fallback equivalence | required |
| Deterministic top-1 match | >= 95% |
| Mean logit KL divergence | <= 0.05 |
| P95 max logit abs error | <= 0.5 unless profile overrides |
| Perplexity delta | <= 5% when measured |
| Task eval delta | <= 2 percentage points when measured |
| Retrieval needle smoke | no regression |
| Snapshot restore | next-token logits within tolerance |

Thresholds are defaults, not global truth. Model profiles may require stricter thresholds or justified overrides. Overrides must be named and recorded in the evidence.

The current `TurboQuantInferenceParity --quality-gates` implementation uses a
focused `real-model-inference-v1` single-token decode gate after cache
conversion. Its current thresholds are stricter on deterministic top-1 and wider
on logit scale:

| Metric | Current real-model inference gate |
| --- | --- |
| No NaN/Inf | required |
| Prefill exactness | required |
| Fallback equivalence | required |
| Deterministic top-1 match | `1.0` |
| Mean logit KL divergence | `<= 0.10` |
| P95 max logit abs error | `<= 2.0` |
| Attention/logit cosine | reported, not currently thresholded |

This gate is intended to catch semantic divergence in the active compressed
decode path. It is not a replacement for perplexity, retrieval, deterministic
JSON/tool-call, or longer decode-sequence gates before product promotion.

The latest K8/Vx real-model run,
[20260601T144308Z](baselines/20260601T144308Z-k8vx-realmodel-quality-speed.md),
uses this gate. Dense K8/V4 passes at 32K and 64K versus FP16. K8/V3 and K8/V2
preserve deterministic top-1 but fail the P95 max-logit-error threshold, and
therefore cannot be promoted without either improving reconstruction quality or
adding a named profile override backed by stronger retrieval, task, and
perplexity evidence. At 128K, dense K8/V4 is the reference on the current 16 GB
Mac because FP16 raw KV alone is about 16 GiB before model/runtime overhead.

Sparse-V threshold, top-k, cumulative-mass, and hybrid modes must pass the same
quality gate against dense K8/V4 or FP16 where available. Sparse-V also needs
retained-mass, skipped-token, fallback-count, and dense-reference diagnostics in
the evidence record.

## Benchmark suites

Every quality gate names a `benchmarkSuiteID`.

Initial suites:

| Suite | Purpose |
| --- | --- |
| `tiny-deterministic-logits-v1` | deterministic token/logit sanity on tiny prompts |
| `prefill-exactness-v1` | verify prefill logits match baseline |
| `fallback-equivalence-v1` | compare compressed path fallback to exact or accepted reference |
| `long-context-needle-v1` | smoke long-context retrieval stability |
| `snapshot-roundtrip-v1` | verify restored KV produces matching next-token logits |
| `mobile-memory-acceptance-v1` | pair quality with no-jetsam memory run |
| `real-model-inference-v1` | release/parity comparison using actual model inference, not synthetic attention-shape kernels |

Synthetic attention-shape suites can remain smoke and kernel-regression diagnostics, but they cannot promote a pair to `Verified`, `Certified`, or parity-complete. Product evidence must use `real-model-inference-v1` with a concrete model revision, tokenizer hash, profile hash, architecture metadata, and a real-model quality delta such as perplexity, task-eval, or needle-pass change.

## Evidence levels

```swift
public enum RuntimeEvidenceLevel: String, Codable, Sendable {
    case unverified
    case smokeTested
    case verified
    case certified
    case revoked
}
```

| Level | Meaning | Product claim allowed |
| --- | --- | --- |
| Unverified | no trusted evidence | no |
| Smoke-tested | basic sanity only | no, conservative runtime only |
| Verified | model/device/mode tuple passed gates | yes for tuple |
| Certified | broader repeated evidence and regression monitoring | yes, stronger wording |
| Revoked | previous evidence invalidated | no |

## Required gate inputs

Quality gate needs:

- model ID;
- model revision;
- tokenizer hash;
- profile hash;
- layout version;
- fallback contract hash;
- compatibility-pair ID;
- device class;
- OS build;
- attention path;
- context length;
- precision/preset/value bits;
- benchmark suite ID;
- reference path used for comparison.

## Prefill exactness

Rule:

Prefill logits must come from the exact path unless a future profile explicitly certifies approximate prefill. Current production path requires exact prefill.

Test:

1. Run baseline exact prefill.
2. Run TurboQuant exact-prefill-compress-side-effect path.
3. Compare logits within strict tolerance.
4. Verify compressed cache commit happens only after evaluation.
5. Verify raw prefill chunks are released according to fallback contract.

## Fallback equivalence

Fallback is allowed only when semantically correct.

Required cases:

- compressed fused fails -> two-stage or packed fallback;
- two-stage fails -> packed fallback if budgeted;
- packed unavailable -> decoded layer-local fallback if budgeted;
- decoded fallback disabled -> typed failure;
- unsupported mask/head dim -> fallback or typed failure;
- no zero output and no guessed tensor.

`fallbackEquivalent == true` means the fallback output is accepted against exact or reference path for the tested suite.

## Regression and revocation

Evidence must be revoked when:

- quality gate fails for the same tuple;
- compatibility pair changes without revalidation;
- fallback contract hash changes;
- model/tokenizer/profile/layout changes;
- hidden-copy audit finds a release-blocking memory issue;
- memory calibration shows admitted tuple is unsafe;
- real-device run jetsams or repeatedly triggers memory warnings.

Revocation records:

```swift
public struct RuntimeEvidenceRevocation: Codable, Sendable {
    public var schemaVersion: Int
    public var evidenceID: UUID
    public var revokedAt: Date
    public var reason: String
    public var replacementEvidenceID: UUID?
}
```

## UI rules

- Verified or Certified evidence may show a product compatibility claim.
- Smoke-tested evidence may show technical diagnostics only.
- Revoked evidence must never show as supported.
- Missing evidence displays Conservative or Benchmark Required.
- The user-facing UI should not show raw KL/logit metrics by default; those belong in technical details.

## Tests

Required:

- quality gate fails when NaN/Inf appears;
- quality gate fails when prefill exactness is false;
- quality gate fails when fallback equivalence is false;
- profile override is recorded and visible;
- evidence cannot become Verified without quality gate;
- revoked evidence prevents compatibility claim;
- benchmark importer rejects missing `benchmarkSuiteID`.
