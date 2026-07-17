# TurboQuant Integration

Pines requests TurboQuant as the default local KV-cache strategy and stores vault embeddings with a compressed TurboQuant-compatible code path. The app consumes additive APIs from the maintained MLX forks so the runtime can be rebased as MLX Swift evolves.

The current MLX fork pins are:

- `RNT56/mlx-swift`: `bcf93af23f11428f6f01efb0bb4b9020cd2eb383`
- `RNT56/mlx-swift-lm`: `aeaa8e3024a82b25969741b53c749b28ddc64d1a`

The current pair is intentionally non-green. Local Pines gates pass. An immediately-prior-pair `iPhone16,2` synthetic attention-shape smoke completed on 2026-07-12, and a focused Qwen 3.5 0.8B real-model comparison passed at 4K. The current core revision changes only SwiftPM manifest compatibility, but the immutable pair identity changed; those device results are therefore historical. The two-repeat diagnostic is not a complete acceptance matrix or imported product evidence tuple, and neither it nor earlier Mac K8/V4 measurements can promote or green the current pair.

This does not promote any model/device/mode to `Verified` or `Certified`. Those labels still require imported real-device evidence for the exact model revision, tokenizer/profile/fallback hashes, device class, context length, quality gate, memory behavior, and active TurboQuant path.

The pinned pair supports Layout V6 for explicit device testing. Layout V6 uses a fixed-tail split-magnitude key layout for lower-bit Qwen precision candidates, while Layout V4 remains the production default for new attention layout requests until real-device evidence decides the promotion surface.

Current testable runtime paths are documented in
`docs/turboquant-implementation/16-current-paths-and-benchmarks.md`. The short
version is:

| Path | Label / strategy | Current role |
| --- | --- | --- |
| FP16 raw SDPA | `fp16`, `KVCacheStrategy.none` | Baseline and short-context production route when memory fits. |
| Affine K8/V4 | `affineK8V4`, `.affineK8V4` | Main compressed speed/quality candidate. |
| Affine K8/V3 | `affineK8V3`, `.affineK8Vx`, value bits `3` | Guarded lower-V experiment. |
| Affine K8/V2 | `affineK8V2`, `.affineK8Vx`, value bits `2` | Guarded lower-V experiment. |
| MLX affine Q8 | `mlxAffine-q8`, `.mlxAffine` | MLX-native affine comparison route. |
| Affine int4 | `affineInt4`, `.affineInt4` | Fast comparison route; quality-gated per model. |
| Polar/QJL TurboQuant | `turbo8`, `turbo4v2`, `turbo3_5`, `.turboQuant` | Capacity/diagnostic routes. |
| Hybrid selector | `.hybridTurboQuant` | Hot/cold cache and selector diagnostics; product promotion still requires real fused selected-block evidence. |
| Sparse-V | threshold/top-k/cumulative/hybrid | Native value-skip diagnostics are wired, but disabled by default until real-model quality and throughput gates pass. |

The current benchmark runner for these paths is:

```bash
cd /Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm
TQ_MODEL_DIR=/path/to/mlx-model scripts/run-turboquant-current-benchmarks.sh
```

## Runtime Strategy

- Pine runtime profiles request `QuantizationAlgorithm.turboQuant` and use the bundled `mlx-swift-lm` TurboQuant profile registry where possible. Qwen3.5/Qwen3.6 production profiles use adaptive raw-first TurboQuant routing: raw MLX SDPA remains the short-context path when admitted, while compressed TurboQuant is selected when raw KV does not fit or when context extends past the 16K raw window. Lower-bit `turbo4v2` and `turbo3_5` Qwen candidates remain guarded for product certification but now route through the same fused proof path; `turbo4v2` is 4-bit keys/4-bit values, while `turbo3_5` is mixed 3/4-bit keys with 4-bit values. Gemma and Llama quality-sensitive profiles still use `turbo8` with exact initial prefill and raw-free compressed decode.
- The app runs a local control plane before generation: it computes an admission plan, memory zones, a mode-specific fallback contract, selected context length, and a user-facing downgrade/rejection reason before creating the MLX cache.
- Every local run can attach a TurboQuant RunDecision with admission, context plan, active attention path, fallback state, cache lifecycle, measured compressed bytes, calibration sample, speculative telemetry when present, and explicit no-cloud-fallback metadata.
- Runtime profiles are adapted from `hw.machine`, memory, thermal state, Low Power Mode, Metal architecture, MLX working-set size, and the MLX TurboQuant self-test. Device names are diagnostic hints; verified MLX capabilities decide whether compressed Metal attention is active.
- 6 GB A16-class devices use compact defaults. A17 Pro, A18, A18 Pro, A19, A19 Pro thin, A19 Pro sustained, and future verified devices get progressively larger prefill and context defaults, with conservative downshifts under thermal, Low Power Mode, or available-memory pressure.
- Low-memory constrained generation clamps completion tokens from measured generation-start headroom so optimized TurboQuant can finish before crossing the emergency memory floor.
- iOS memory warnings soft-recover through the runtime bridge while active generation still has emergency headroom; otherwise they stop the active local run and unload transient MLX containers.
- Pine pins `RNT56/mlx-swift` and `RNT56/mlx-swift-lm` to exact TurboQuant fork revisions in `project.yml` and the generated Xcode project. CI rejects drift back to the pre-fix revisions.
- Current pins:
  - `RNT56/mlx-swift`: `bcf93af23f11428f6f01efb0bb4b9020cd2eb383`
  - `RNT56/mlx-swift-lm`: `aeaa8e3024a82b25969741b53c749b28ddc64d1a`
  - Nested `mlx` inside `RNT56/mlx-swift`: `e230d124a1fdcb5f4b3daab6321744a7a8b6a9f2`
  - Nested `mlx-c` inside `RNT56/mlx-swift`: `2fbeccd5a6ec6f7aadedaf1d3dfb2894ef44fbc1`
- `mlx-swift` exposes additive TurboQuant packed tensor APIs over MLX native packed quantization and quantized matmul, a deterministic PolarQuant/QJL reference codec, custom Metal encode/decode kernels, row-wise compressed-attention code blobs, runtime-layout direct compressed `QK^T`, runtime-layout direct compressed `AV`, runtime-layout compressed decode, `turbo8` high-precision KV-cache mode, device-profile-gated online fused decode, block-parallel fused partial/reduce kernels for long-context decode, automatic block-token planning for 32K/64K/128K/256K decode, fp16/bf16 block-partial value storage with float32 stats/reduce accumulation, a Mac Apple silicon kernel profile, Mac-gated grouped-query block fused decode for Qwen-style GQA, grouped GQA softmax reductions, four-repeat Qwen GQA key reuse, fixed-tail split-magnitude Turbo3.5/Turbo2.5 key reads without prefix scans, compact derived high-lane masks, aligned affine value reads, active-block dispatch for reserved larger caches, reduce-width tuning for block-parallel reductions, Qwen-shaped benchmark head-count and block-token controls, p50/p95 benchmark reporting, word-level packed bit read/write helpers for fixed and mixed TurboQuant schemes, runtime device capabilities, selected kernel profiles, tiny latency probes, opt-in long-context fused warmup, cooperative coalesced QK decode behind `TQ_COOP=1` for A-series validation, per-group QJL residual scaling, quality-gate metrics, and a runtime self-tested backend availability contract.
- `mlx-swift-lm` exposes `KVCacheStrategy.turboQuant`, `KVCacheStrategy.adaptiveTurboQuant`, `TurboQuantKVCache`, a physical-slot `RotatingTurboQuantKVCache` for supported `.metalPolarQJL` `maxKVSize` paths, a shared packed quantized-attention fallback before raw decode, typed throwing TurboQuant generation paths and an exported runtime capability registry for the profile-backed Llama, Gemma, Qwen, Mistral, Phi, Granite, Exaone4, SmolLM3, LFM2, and GLM4 MoE Lite families, prepared-prefix generation, prompt-cache serialization hooks, `TurboQuantCompressedKVCacheProtocol`, the bundled `TurboQuantProfileRegistry`, corrected profile/exported JSON bit metadata, direct initial compressed-cache commits, lightweight compressed update checkpoints, compact v6 state restore/snapshot validation, guarded throughput routing for lower-bit `turbo4v2` and `turbo3_5` profiles, Qwen3.5/Qwen3.6 adaptive raw-first grouped-query fused compressed decode policies, duplicate decode-copy/validation trimming, Qwen production and large-context experiment p50/p95 proof modes, reserved-capacity proof reporting, schema-v6 production-route/recommended/effective block-token proof reporting, the `TurboQuantBench` app-hostable A-series attention harness, and `GenerateParameters` fields for cache strategy, preset, requested backend selection, value bits, fallback policy, raw SDPA threshold, device-adaptive optimization policy, model metadata, KV head dimensions, and compressed-attention diagnostics.
- Pines keeps a local prompt KV cache for text-only MLX turns. Cache entries are keyed by model/runtime/tokenizer and quantization shape, reused only on token-prefix match, trimmed after successful generation, and evicted before model unload under memory pressure or thermal downshift.
- Pines marks Qwen3.5/Qwen3.6 and LFM2 hybrid models as Hybrid Full: standard attention KV caches use TurboQuant, while linear/conv/native state caches remain exact MLX state. Gemma 3/3n/4, text Llama, Mistral/Ministral, Qwen2/Qwen3, Phi/Phi3, Granite, Exaone, SmolLM3, and GLM4 MoE Lite are marked TurboQuant full when metadata matches the pinned profile registry. Llama 3.2 Vision, Pixtral, and draft-only Gemma4 assistant paths stay gated until the pinned runtime exposes complete VLM or dual-model orchestration coverage.
- The app-level runtime smoke tests link MLX/MLXLMCommon, assert those fixed pins are present, validate high-bit TurboQuant seed propagation, and run a tiny Metal codec round trip when the executing device exposes the TurboQuant Metal codec.
- The Debug app also exposes a hidden `--pines-turboquant-bench` launch mode, driven by `scripts/diagnostics/run-ios-turboquant-bench.sh`, so the synthetic Qwen3.5-2B compressed-vs-FP16 attention sweep runs inside the real Pines app host on a physical iPhone instead of relying on tool-hosted package tests.
- `tools/update-mlx-pins.sh` advances the reproducible SHAs, regenerates `Pines.xcodeproj`, and can run the package plus iOS smoke-test checks. Renovate proposes these pin moves by PR instead of switching Pines to non-reproducible branch pins.
- Pine requests the paper-exact `metalPolarQJL` backend by default. Devices with Metal compressed-attention support report the direct compressed attention path; unsupported shapes or devices use the shared MLX packed quantized-attention fallback before raw decode.
- Context assembly is segment-aware: pinned prompt material, hot recent chat, retrieved vault evidence, summaries, dropped spans, and exact-prefix compressed KV pages are tracked separately. Warm compressed KV pages are never treated as semantic retrieval chunks unless the exact prefix identity is valid.
- Encrypted local KV snapshot storage is implemented behind fail-closed restore gates. Snapshot manifests bind to model, tokenizer, profile, RoPE, prefix, layout version, and compatibility pair; corrupted or partial writes are quarantined, and snapshots are excluded from CloudKit sync by default.
- Speculative decode support is wired through explicit telemetry and evidence gates. Fast/speculative behavior remains disabled or conservative unless tokenizer compatibility, target verification, acceptance rate, and quality/speed evidence pass.
- Platform unlock contracts for adaptive precision, semantic/multimodal memory, agent memory, open KV descriptors, device mesh, personalization/adapters, and kill switches are present but disabled by default. Activation requires compatibility-pair status, feature-specific policy, and evidence.

## Vault Retrieval

- Imported document chunks store an FP16 embedding for exact rerank and a compressed TurboQuant vector code for approximate candidate retrieval.
- Vault vector codes default to `turbo4v2`, matching the current MLX TurboQuant generation recommendation for new installs. Codes still carry their preset and seed in the blob, so explicit older `turbo3_5` rows remain decodable if developer or pre-release data exists.
- Embedding ingestion is batched according to the active device profile to avoid avoidable jetsam on compact iOS devices.
- Search uses compressed candidates first, filters by embedding model when available, bounds the scanned candidate set by device profile, reranks with the FP16 vector, and falls back to SQLite FTS when embeddings are unavailable.
- Embeddings and compressed vector codes remain local-only unless the user explicitly enables both private iCloud sync and embedding sync through settings.

## Diagnostics

- Models and Settings show the requested codec, requested/active backend, Metal codec availability, Metal compressed-attention availability, active attention path, selected kernel variant, MLX self-test status, performance class, optimization policy, raw fallback allocation state, active fallback, preset, profile ID/source, profile diagnostics, cache topology, family support level, context window, thermal downshift, thermal state, device identifier, Metal architecture, MLX working set, and memory counters exposed by the runtime monitor.
- Model compatibility surfaces distinguish `Unverified`, `Smoke-tested`, `Verified`, `Certified`, and `Revoked` evidence. Curated metadata alone cannot create a verified claim; evidence must match the active compatibility pair and exact tuple.
- Runtime throughput, vault retrieval latency, memory-pressure events, and MetricKit payload availability are logged through `PinesRuntimeMetrics`.

## Wave 0 Baseline

Wave 0 artifact set: `turboquant-wave0-20260531T024557Z`.

| Surface | Result | Artifact |
| --- | --- | --- |
| Repo state | Captured for `mlx`, `mlx-c`, `mlx-swift`, `mlx-swift-lm`, and `pines` | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-wave0-20260531T024557Z/repo-state.json` |
| Mac benchmark matrix | Completed for `8K/16K/32K/64K/128K`, `turbo8/turbo4v2/turbo3_5`, default and `TQ_COOP=1` | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-wave0-20260531T024557Z/wave0-summary.json` |
| Core benchmark schema smoke | Passed after adding plain/compressed speed ratio fields | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-wave0-20260531T024557Z/benchmarks/smoke/core-turbo4v2-8192-with-plain-smoke.json` |
| `mlx-swift` TurboQuant tests | Failed in lower-bit QK reference checks | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-wave0-20260531T024557Z/logs/mlx-swift-test-turboquant.log` |
| `mlx-swift-lm` TurboQuant tests/builds | Passed | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-wave0-20260531T024557Z/logs/mlx-swift-lm-test-turboquant.log` |
| Pines pin/build gates | Passed pin drift, package-pin checks, and generic iOS build | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-wave0-20260531T024557Z/logs/pines-xcodebuild-generic-ios.log` |
| Pines app-hosted iOS smoke | `failed_environmental`; device build stalled during code signing before install/launch | `/Users/mt/Programming/Schtack/pines/artifacts/turboquant-wave0-20260531T024557Z/logs/ios-smoke.log` |

Wave 0 parity verdict: `performanceParity=false`, `stabilityParity=partial`, `supportParity=partial`. This is expected for the current architecture: compressed equal-context throughput is below raw FP16, and TurboQuant remains a capacity route until later hybrid/native-backend waves prove otherwise.

## Mac Real-Model Evidence

The current pins add the native affine K8/Vx route family: keys stay affine K8,
values use V4, V3, or V2 affine lanes, and QK/softmax/AV execute through the
mixed quantized SDPA path. Sparse-V threshold, top-k, cumulative-mass, and
hybrid selection modes are also wired for diagnostics. None of these rows is a
parity claim until the real-model and device gates pass.

| Model | Artifact | Context | Result |
| --- | --- | ---: | --- |
| `mlx-community/Qwen3.5-2B-4bit` | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-k8vx-realmodel-20260601T144308Z/k8vx-quality-speed-summary.md` | 32K speed | FP16 `20.50 tok/s`; K8/V4 `32.40 tok/s` (`1.581x`); K8/V3 `14.16 tok/s` (`0.691x`); K8/V2 `15.54 tok/s` (`0.758x`). |
| `mlx-community/Qwen3.5-2B-4bit` | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-k8vx-realmodel-20260601T144308Z/k8vx-quality-speed-summary.md` | 64K speed | FP16 `43.06 tok/s`; K8/V4 `21.54 tok/s` (`0.500x`); K8/V3 `21.39 tok/s` (`0.497x`); K8/V2 `21.36 tok/s` (`0.496x`). |
| `mlx-community/Qwen3.5-2B-4bit` | `/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-k8vx-realmodel-20260601T144308Z/k8vx-quality-speed-summary.md` | 128K speed | K8/V4 `15.72 tok/s`; K8/V3 `13.24 tok/s`; K8/V2 `8.54 tok/s`. FP16 was not run because raw KV alone is about `16 GiB` at this shape before weights and runtime overhead. |
| `mlx-community/Qwen3.5-2B-4bit` | `/Users/mt/Programming/Schtack/pines/docs/turboquant-implementation/baselines/20260601T144308Z-k8vx-realmodel-quality-speed.md` | 32K/64K quality | K8/V4 passes current FP16-referenced real-model gates. K8/V3 and K8/V2 preserve top-1 but fail the P95 max-logit-error gate. |
| `mlx-community/Qwen3.5-2B-4bit` | `/Users/mt/Programming/Schtack/pines/docs/turboquant-implementation/baselines/20260601T144308Z-k8vx-realmodel-quality-speed.md` | 128K quality | K8/V3 and K8/V2 fail against dense K8/V4 under the current P95 max-logit-error gate. Dense K8/V4 remains the 128K compressed reference on this 16 GB Mac. |

## Physical Device Evidence

Immediately-prior-pair app-hosted attention smoke validation ran on `iPhone16,2` / A17 Pro / iPhone 15 Pro Max (`7BFB7B72-C40C-58A7-B2C6-F075BDE21116`) on 2026-07-12 and is summarized in [the signed iOS baseline](turboquant-implementation/baselines/20260712T150706Z-ios-exact-pair-smoke.md). It proves that pair's signed app-host, native compressed path, and diagnostics export, but it is synthetic attention-shape evidence. The current core revision changes only SwiftPM manifest compatibility, yet the immutable pair identity changed, so the run remains historical rather than exact-current-pair evidence. Parity, `Verified`, and `Certified` gates still require `real-model-inference-v1` evidence from actual model generation/inference comparisons on the current tuple.

A focused immediately-prior-pair [Qwen 3.5 0.8B real-model smoke](turboquant-implementation/baselines/20260712T151432Z-ios-qwen35-08b-realmodel-smoke.md) also passed on the same phone at 4K with actual weights and a passing FP16-referenced quality gate. Its two-repeat throughput result is useful historical diagnostic evidence, but the changed immutable pair identity, wide ratio interval, and missing selected-path diagnostics prevent current-pair native-performance or parity promotion; the full release matrix remains required.

| Model | Artifact | Result | Active profile/path | Observed result |
| --- | --- | --- | --- | --- |
| synthetic `qwen3.5-2b` attention shape | `ios-turboquant-bench-20260531T132622Z` | Historical prior-pair smoke only | `turbo4v2`, 8K context, app-hosted physical-device benchmark | Compressed `48.95 tok/s`, plain FP16 `643.10 tok/s`, speed ratio `0.0761`, cosine `0.999992`, KV memory reduction `2.21x`; this is not evidence for the current pin tuple. |
| synthetic `qwen3.5-2b` attention shape | `ios-turboquant-bench-20260531T020455Z` | Completed, historical/superseded | `turbo4v2`, 8K context, app-hosted physical-device benchmark | Compressed `22.22 tok/s`, plain FP16 `634.54 tok/s`, speed ratio `0.0350`, cosine `0.999824`, KV memory reduction `3.05x`. |

Earlier imported real-device smoke validation ran on `iPhone16,2` / A17 Pro (`7BFB7B72-C40C-58A7-B2C6-F075BDE21116`) on 2026-05-26 before the block-parallel fused pair was promoted. These runs are retained as raw-shadow recovery evidence for the exact local artifact tuple only; they do not certify the current fused path or lower-bit compressed attention paths.

| Model | Artifact | Result | Active profile/path | Observed result |
| --- | --- | --- | --- | --- |
| `mlx-community/Qwen3.5-2B-OptiQ-4bit` | `ios-freeze-stress-20260526T110210Z` | Completed | `turbo8`, exact raw shadow, baseline attention | Coherent output, no repeated bigram/trigram issue, `3.27 tok/s`, first token `1.66s`, stopped at the 192-token guard. |
| `mlx-community/gemma-3-1b-it-4bit` | `ios-freeze-stress-20260526T110605Z` | Failed stress gate | `turbo8`, exact raw shadow configured | Runtime loaded and emitted 14 tokens, but only `0.71 tok/s`; the stress harness still saw the assistant in `streaming`. |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | `ios-freeze-stress-20260526T110703Z` | Completed | `turbo8`, exact raw shadow, baseline attention | Coherent stop, no repeated bigram/trigram issue, `0.90 tok/s`; active KV window fell to 2048 under low-memory/thermal pressure. |
| `mlx-community/Qwen3.5-0.8B-MLX-4bit` | `ios-freeze-stress-20260526T110824Z` | Completed | `turbo8`, exact raw shadow, baseline attention | Coherent stop, no repeated bigram/trigram issue, `2.62 tok/s`, first token `1.32s`; context was thermally constrained to 4096. |

Current conclusion: short-context parity is handled by adaptive routing rather than by forcing compressed attention to beat raw SDPA. Dense K8/V4 is the best current compressed long-context reference and passes the active 32K/64K real-model logit gate on this Mac. K8/V3, K8/V2, Sparse-V, and lower-bit Polar/QJL modes remain guarded for product `Verified` or `Certified` claims until real-device compressed attention passes speed, memory, quality, fallback, repetition, stop, NIAH/retrieval, and deterministic task gates for the exact model/device/profile tuple.

## Fork Maintenance

- Do not edit Xcode DerivedData package checkouts.
- Maintain the Schtack/RNT56 forks of `mlx-swift` and `mlx-swift-lm`; Pine is pinned to known-good fork commits.
- Keep `project.yml`, `Pines.xcodeproj`, and this document synchronized whenever a fork revision changes.
- Keep `docs/turboquant-implementation/compatibility-pair.json` synchronized with the active pins. `green` there means the local compatibility pair passed release gates; it does not replace real-device profile evidence.
- Current fork PRs:
  - `RNT56/mlx-swift#1`: TurboQuant packed tensor API, Polar/QJL reference backend contract, Metal codec and compressed-attention kernels, and deterministic quality gates.
  - `RNT56/mlx-swift-lm#1`: TurboQuant KV cache strategy, compressed attention routing, backend diagnostics, and Metal availability.
  - `RNT56/mlx-swift#4`: TurboQuant capability routing, storage validation, compact unused bitsets, and conversion metadata.
  - `RNT56/mlx-swift-lm#5`: TurboQuant generation admission hardening, rollback safety, and model cache routing.
- Run `.github/workflows/mlx-upstream-sync.yml` monthly or manually to verify upstream reachability and Pine integration hooks.
- Keep one upstream-facing PR for the additive TurboQuant API so Pine can eventually return to upstream package releases.

## Remaining Native Work

- Move the current RNT56 fork branches under a Schtack GitHub organization if/when that organization is available to the authenticated account.
- Tune tiled decode thresholds after real A16/A17/A18/A19 profiling. Runtime probes now choose between portable, wide, sustained, and packed-fallback profiles, but checked-in defaults should remain conservative until device traces justify raising them.
- Re-run the KV-memory acceptance matrix on device. The supported `.metalPolarQJL` rotating path is raw-free; raw/packed fallback allocation is lazy and diagnostic-visible, but product `Verified`/`Certified` claims require imported real-device evidence, not simulator or desktop validation.
- Validate the acceptance matrix on real A16, A17 Pro, A18, A18 Pro, A19, A19 Pro thin, and A19 Pro sustained devices with full Xcode and Instruments.
