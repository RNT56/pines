# TurboQuant Integration

Pine requests TurboQuant as the default local KV-cache strategy and stores vault embeddings with a compressed TurboQuant-compatible code path. The app consumes additive APIs from the maintained MLX forks so the runtime can be rebased as MLX Swift evolves.

The current compatibility pair is green for local release gates. Pines can build, test, resolve the pinned MLX packages through Xcode, run simulator smoke tests, and enforce pin drift checks on:

- `RNT56/mlx-swift`: `776aaf9520ae4b506781d32b674b56f8a18dc165`
- `RNT56/mlx-swift-lm`: `fbaf2df6218acf2b6a21f69ae49d28ed87a301b6`

This does not promote any model/device/mode to `Verified` or `Certified`. Those labels still require imported real-device evidence for the exact model revision, tokenizer/profile/fallback hashes, device class, context length, quality gate, memory behavior, and active TurboQuant path.

The pinned pair makes Layout V6 the default TurboQuant attention layout for device testing. Layout V6 uses a fixed-tail split-magnitude key layout for lower-bit Qwen precision candidates, while Layout V4 and V5 remain supported for legacy and A/B comparison runs until real-device evidence decides the production promotion surface.

## Runtime Strategy

- Pine runtime profiles request `QuantizationAlgorithm.turboQuant` and use the bundled `mlx-swift-lm` TurboQuant profile registry where possible. Qwen3.5/Qwen3.6 production profiles use `turbo8` with exact initial prefill and block-parallel fused compressed decode for 8K/16K/32K extended contexts. Lower-bit `turbo4v2` and `turbo3_5` Qwen candidates remain guarded for product certification but now route through the same fused proof path; `turbo4v2` is 4-bit keys/4-bit values, while `turbo3_5` is mixed 3/4-bit keys with 4-bit values. Gemma and Llama quality-sensitive profiles still use `turbo8` with exact initial prefill and raw-free compressed decode.
- The app runs a local control plane before generation: it computes an admission plan, memory zones, a mode-specific fallback contract, selected context length, and a user-facing downgrade/rejection reason before creating the MLX cache.
- Every local run can attach a TurboQuant RunDecision with admission, context plan, active attention path, fallback state, cache lifecycle, measured compressed bytes, calibration sample, speculative telemetry when present, and explicit no-cloud-fallback metadata.
- Runtime profiles are adapted from `hw.machine`, memory, thermal state, Low Power Mode, Metal architecture, MLX working-set size, and the MLX TurboQuant self-test. Device names are diagnostic hints; verified MLX capabilities decide whether compressed Metal attention is active.
- 6 GB A16-class devices use compact defaults. A17 Pro, A18, A18 Pro, A19, A19 Pro thin, A19 Pro sustained, and future verified devices get progressively larger prefill and context defaults, with conservative downshifts under thermal, Low Power Mode, or available-memory pressure.
- Low-memory constrained generation clamps completion tokens from measured generation-start headroom so optimized TurboQuant can finish before crossing the emergency memory floor.
- iOS memory warnings soft-recover through the runtime bridge while active generation still has emergency headroom; otherwise they stop the active local run and unload transient MLX containers.
- Pine pins `RNT56/mlx-swift` and `RNT56/mlx-swift-lm` to exact TurboQuant fork revisions in `project.yml` and the generated Xcode project. CI rejects drift back to the pre-fix revisions.
- Current pins:
  - `RNT56/mlx-swift`: `776aaf9520ae4b506781d32b674b56f8a18dc165`
  - `RNT56/mlx-swift-lm`: `fbaf2df6218acf2b6a21f69ae49d28ed87a301b6`
  - Nested `mlx` inside `RNT56/mlx-swift`: `75b756717154890033209aaba4ffc89b113c5998`
  - Nested `mlx-c` inside `RNT56/mlx-swift`: `2abc34daff6ded246054d9e15b98870b5cd08b97`
- `mlx-swift` exposes additive TurboQuant packed tensor APIs over MLX native packed quantization and quantized matmul, a deterministic PolarQuant/QJL reference codec, custom Metal encode/decode kernels, row-wise compressed-attention code blobs, runtime-layout direct compressed `QK^T`, runtime-layout direct compressed `AV`, runtime-layout compressed decode, `turbo8` high-precision KV-cache mode, device-profile-gated online fused decode, block-parallel fused partial/reduce kernels for long-context decode, a Mac Apple silicon kernel profile, Mac-gated grouped-query block fused decode for Qwen-style GQA, grouped GQA softmax reductions, four-repeat Qwen GQA key reuse, fixed-tail split-magnitude Turbo3.5/Turbo2.5 key reads without prefix scans, compact derived high-lane masks, aligned affine value reads, active-block dispatch for reserved larger caches, reduce-width tuning for block-parallel reductions, Qwen-shaped benchmark head-count and block-token controls, p50/p95 benchmark reporting, word-level packed bit read/write helpers for fixed and mixed TurboQuant schemes, runtime device capabilities, selected kernel profiles, tiny latency probes, opt-in long-context fused warmup, per-group QJL residual scaling, quality-gate metrics, and a runtime self-tested backend availability contract.
- `mlx-swift-lm` exposes `KVCacheStrategy.turboQuant`, `TurboQuantKVCache`, a physical-slot `RotatingTurboQuantKVCache` for supported `.metalPolarQJL` `maxKVSize` paths, a shared packed quantized-attention fallback before raw decode, typed throwing TurboQuant generation paths and an exported runtime capability registry for the profile-backed Llama, Gemma, Qwen, Mistral, Phi, Granite, Exaone4, SmolLM3, LFM2, and GLM4 MoE Lite families, prepared-prefix generation, prompt-cache serialization hooks, `TurboQuantCompressedKVCacheProtocol`, the bundled `TurboQuantProfileRegistry`, corrected profile/exported JSON bit metadata, direct initial compressed-cache commits, lightweight compressed update checkpoints, compact v6 state restore/snapshot validation, guarded throughput routing for lower-bit `turbo4v2` and `turbo3_5` profiles, Qwen3.5/Qwen3.6 exact-prefill grouped-query fused compressed decode policies, duplicate decode-copy/validation trimming, Qwen production and large-context experiment p50/p95 proof modes, reserved-capacity and block-size proof reporting, and `GenerateParameters` fields for cache strategy, preset, requested backend selection, value bits, fallback policy, device-adaptive optimization policy, model metadata, KV head dimensions, and compressed-attention diagnostics.
- Pines keeps a local prompt KV cache for text-only MLX turns. Cache entries are keyed by model/runtime/tokenizer and quantization shape, reused only on token-prefix match, trimmed after successful generation, and evicted before model unload under memory pressure or thermal downshift.
- Pines marks Qwen3.5/Qwen3.6 and LFM2 hybrid models as Hybrid Full: standard attention KV caches use TurboQuant, while linear/conv/native state caches remain exact MLX state. Gemma 3/3n/4, text Llama, Mistral/Ministral, Qwen2/Qwen3, Phi/Phi3, Granite, Exaone, SmolLM3, and GLM4 MoE Lite are marked TurboQuant full when metadata matches the pinned profile registry. Llama 3.2 Vision, Pixtral, and draft-only Gemma4 assistant paths stay gated until the pinned runtime exposes complete VLM or dual-model orchestration coverage.
- The app-level runtime smoke tests link MLX/MLXLMCommon, assert those fixed pins are present, validate high-bit TurboQuant seed propagation, and run a tiny Metal codec round trip when the executing device exposes the TurboQuant Metal codec.
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

## Physical Device Evidence

Most recent imported real-device smoke validation ran on `iPhone16,2` / A17 Pro (`7BFB7B72-C40C-58A7-B2C6-F075BDE21116`) on 2026-05-26 before the block-parallel fused pair was promoted. These runs are retained as raw-shadow recovery evidence for the exact local artifact tuple only; they do not certify the current fused path or lower-bit compressed attention paths.

| Model | Artifact | Result | Active profile/path | Observed result |
| --- | --- | --- | --- | --- |
| `mlx-community/Qwen3.5-2B-OptiQ-4bit` | `ios-freeze-stress-20260526T110210Z` | Completed | `turbo8`, exact raw shadow, baseline attention | Coherent output, no repeated bigram/trigram issue, `3.27 tok/s`, first token `1.66s`, stopped at the 192-token guard. |
| `mlx-community/gemma-3-1b-it-4bit` | `ios-freeze-stress-20260526T110605Z` | Failed stress gate | `turbo8`, exact raw shadow configured | Runtime loaded and emitted 14 tokens, but only `0.71 tok/s`; the stress harness still saw the assistant in `streaming`. |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | `ios-freeze-stress-20260526T110703Z` | Completed | `turbo8`, exact raw shadow, baseline attention | Coherent stop, no repeated bigram/trigram issue, `0.90 tok/s`; active KV window fell to 2048 under low-memory/thermal pressure. |
| `mlx-community/Qwen3.5-0.8B-MLX-4bit` | `ios-freeze-stress-20260526T110824Z` | Completed | `turbo8`, exact raw shadow, baseline attention | Coherent stop, no repeated bigram/trigram issue, `2.62 tok/s`, first token `1.32s`; context was thermally constrained to 4096. |

Current conclusion: the exact raw-shadow baseline preserved correctness but caused unacceptable throughput. The active LM pin keeps exact initial prefill for Qwen3.5/Qwen3.6 and routes decode through the grouped-query fused compressed path. On Mac, the strict Qwen proof with `float16`, 16 query heads, 4 KV heads, query length 1, 32K production context, 128K reserved compressed-cache capacity, and Turbo8/Turbo4V2/Turbo3.5 passed 9/9 production gates across Qwen3.5 2B, Qwen3.6 27B, and Qwen3.6 35B-A3B representative profiles. The latest reserved-capacity p95 rates at 32K were Turbo8 `43.53-44.61 tok/s`, Turbo4V2 `46.97-47.41 tok/s`, and Turbo3.5 `46.87-47.31 tok/s`. At 64K, all nine rows cleared the 20 tok/s p95 floor as experiment rows (`25.25-28.01 tok/s` p95). All 128K rows ran with valid quality and online fused attention but remain below the 20 tok/s production floor on this Mac (`13.55-15.04 tok/s` p95). Lower-bit `turbo4v2`, `turbo4`, `turbo3_5`, and `turbo2_5` remain guarded for product `Verified` or `Certified` claims until real-device compressed attention passes repetition, stop, memory, and throughput gates for the exact model/device/profile tuple.

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
