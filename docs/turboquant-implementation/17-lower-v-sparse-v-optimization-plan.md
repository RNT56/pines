# Lower-V And Sparse-V Optimization Plan

This plan covers the next optimization work after the 2026-06-01 K8/Vx
real-model matrix and the native Sparse-V mode expansion.

Current posture:

- Dense K8/V4 is the real-model reference for compressed long-context work.
- K8/V3 is the most realistic lower-V promotion candidate, but it currently
  fails the P95 max-logit-error gate.
- K8/V2 remains a guarded memory-pressure experiment.
- Native Sparse-V supports threshold, top-k, cumulative mass, and hybrid
  cumulative-plus-top-k selection, but it stays disabled by default until
  real-model quality and throughput gates pass.

## Implementation Status 2026-06-01

The current codebase has the conservative measurement and gate layer wired, but
does not promote lower-V or Sparse-V by default.

Implemented surfaces:

- `mlx-swift` core benchmark reports include a `lowerVAndSparseV` section with
  reference/candidate configs, value-bit policy, canonical Sparse-V mode names,
  split latency fields, retained-mass/token diagnostics, fallback count/reason,
  actual mixed bits/value, and optional layer/head coordinates.
- `mlx-swift-lm` lower-V/Sparse-V benchmark planning has canonical Sparse-V
  names, value-bit policy metadata (`denseV4`, `calibratedV3`,
  `calibratedV2`, `residualVx`), calibration summary records, residual V2/V3
  experiment rows, dense K8/V4 anchored comparison rows, and timing placeholders
  for QK/softmax/selection/mask/AV/reference cost attribution.
- `TurboQuantQwenProof` emits canonical Sparse-V names and per-result
  `lowerVAndSparseV` diagnostics alongside the existing aggregate Sparse-V
  fields. Timing fields are present but remain nil until real-model timing
  probes populate them.
- Pines benchmark reports import the `lowerVAndSparseV` section and reject
  `Verified`/`Certified` lower-V or Sparse-V evidence when dense-reference
  quality/cost fields are missing. Smoke evidence remains allowed, but product
  claims require the full tuple evidence.

Still not promoted:

- Residual/outlier V lanes are represented in benchmark policy and artifacts,
  but the production kernel path still needs the residual storage and in-kernel
  AV decode implementation before those rows can move from experiment to active
  runtime mode.
- Sparse-V timing decomposition is schema-complete; real-model timing
  population and the two-level top-k/cumulative selector optimization still need
  benchmark evidence before activation.
- K8/V3 and K8/V2 remain disabled without exact model/profile/device evidence.

## Evidence Baseline

Latest documented baseline:

- [20260601T144308Z K8/Vx real-model quality and speed](baselines/20260601T144308Z-k8vx-realmodel-quality-speed.md)
- Raw artifact: `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-k8vx-realmodel-20260601T144308Z/k8vx-quality-speed-summary.md`

Promotion decisions must compare new lower-V or Sparse-V rows against this
dense K8/V4 baseline unless a matching FP16 row fits and exists for the same
context.

## Optimization Track A: Measurement First

Every candidate change needs an artifact tuple with:

| Requirement | Target |
| --- | --- |
| Contexts | 32K, 64K, 128K where admitted |
| References | FP16 at 32K/64K, dense K8/V4 at 128K |
| Models | Qwen3.5/Qwen3.6 GQA4 HD256 first, then Gemma/Llama profile families |
| Speed | prefill tok/s, decode tok/s, attention latency p50/p95 |
| Memory | compressed KV bytes, peak memory, memory reduction, fallback scratch |
| Quality | top-1, KL, P95 max abs logit error, cosine |
| Tasks | NIAH/long retrieval, deterministic JSON/tool-call, perplexity or task eval |
| Diagnostics | Sparse-V mode, skipped tokens, considered tokens, retained mass, fallback count |

Do not promote a mode on synthetic attention numbers alone. Synthetic rows are
operator regressions, not product evidence.

## Optimization Track B: Lower-V Quality

K8/V3 and K8/V2 currently fail because value reconstruction error leaks into
the logits even when top-1 survives. Improve quality before optimizing the
runtime policy.

1. Importance-weighted V calibration.
   - Collect dense K8/V4 attention weights by layer/head/token block.
   - Weight V quantization error by observed attention mass instead of raw MSE.
   - Prefer optimizing output-logit KL and P95 max error over standalone
     reconstruction error.

2. Per-layer and per-head adaptive value bits.
   - Keep boundary layers protected.
   - Keep high-error or high-attention-entropy layers at V4.
   - Allow V3 only on layers/heads whose calibration error stays inside the
     gate.
   - Keep V2 restricted to low-mass, low-error regions or memory-emergency
     profiles.

3. Residual and outlier lanes.
   - Store a compact V3/V2 core plus a sparse residual plane for high-error
     channels/tokens.
   - Encode residual indices by block bitset or small top-r list.
   - Keep residual decode in the same AV kernel so the path does not become
     materialization-heavy.

4. Better affine scale policy.
   - Evaluate per-head, per-channel, and smaller group scales.
   - Add percentile clipping candidates for V3/V2.
   - Track symmetric versus asymmetric scale choice by model family.
   - Version scale metadata explicitly so old snapshots do not decode under a
     new convention.

5. Mixed accumulation and high-mass preservation.
   - Use fp32 softmax statistics and stable accumulation for selected high-mass
     blocks.
   - Promote high-mass tokens to V4 inside otherwise V3/V2 blocks when it pays
     for quality.
   - Report actual mixed bits/value rather than just nominal V bits.

Acceptance for lower-V promotion:

- K8/V3 must pass the current real-model gate at 32K and 64K versus FP16.
- At 128K it must pass versus dense K8/V4 unless FP16 is available.
- K8/V2 needs a named profile override plus task evidence; it is not a default
  speed route until it clears the same gates.

## Optimization Track C: Sparse-V Performance

Sparse-V can only help when skipped value work outweighs selection overhead and
quality remains stable.

1. Profile the selection pass.
   - Report selection latency separately from AV latency.
   - Emit skip ratio, retained mass, selected top-k, and fallback reason.
   - Track selection cost per head and per layer.

2. Replace exact global top-k with two-level reductions.
   - Compute per-block top-k/cumulative summaries.
   - Reduce block summaries globally.
   - Avoid full token sorts for K=128/256/512.
   - Keep exact mode available for debug/reference.

3. Optimize retained-mask construction.
   - Build compact block bitmasks instead of dense token masks where possible.
   - Reuse prefix counts across heads when layout permits.
   - Keep retained-token compaction bounded and avoid full-cache temporary
     tensors.

4. Fuse selection and AV when profitable.
   - For threshold and high-skip top-k modes, fuse retained-mask use with AV.
   - For low-skip cases, skip Sparse-V and run dense K8/V4.
   - Add a runtime profitability guard based on retained mass, retained tokens,
     and measured selector latency.

5. Layer/head policy.
   - Enable Sparse-V first on late layers where attention is sharper.
   - Disable it on heads/layers with high entropy or low skip ratio.
   - Keep first-token and boundary-layer behavior conservative.
   - Report per-layer and per-head skip/quality diagnostics from real model
     runs, not only synthetic Qwen-shaped probes.

Acceptance for Sparse-V promotion:

- Dense K8/V4 is the fallback and reference.
- Full decode throughput improves versus dense K8/V4 at the same context.
- Top-1, KL, P95 max error, cosine, NIAH/retrieval, deterministic JSON/tool-call,
  and fallback-count gates pass.
- Fallback count and dense-retry behavior are explainable in the report.

## Optimization Track D: Runtime Policy

Default policy remains conservative:

| Mode | Default |
| --- | --- |
| K8/V4 | available as the main compressed candidate |
| K8/V3 | off unless model/profile evidence passes |
| K8/V2 | guarded memory-pressure experiment only |
| Sparse-V threshold/top-k/cumulative/hybrid | off unless tuple evidence passes |

Runtime activation should:

1. choose K8/V4 for dense compressed long-context by default;
2. try K8/V3 only for layers/heads with calibration evidence;
3. try Sparse-V only when predicted retained mass and selector cost are
   favorable;
4. fall back to dense K8/V4 on low confidence, high selector overhead, high
   retained mass, or quality guard failure;
5. record every downgrade in diagnostics.

## Optimization Track E: iOS Promotion

Mac evidence is necessary but not sufficient for Pines product claims. iPhone
promotion requires:

- physical app-hosted real-model inference evidence;
- thermal and Low Power Mode recorded;
- memory warnings and jetsam absent;
- exact model revision/tokenizer/profile/fallback hash captured;
- the same quality gate suite used on Mac;
- Sparse-V and lower-V disabled on unsupported device classes unless imported
  evidence exists for that class.

Until then, Pines must keep the compatibility pair non-green and must not mark
lower-V or Sparse-V modes `Verified` or `Certified`.
