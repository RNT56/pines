# TurboQuant Integration

Pine requests TurboQuant as the default local KV-cache strategy and stores vault embeddings with a compressed TurboQuant-compatible code path. The app consumes additive APIs from the maintained MLX forks so the runtime can be rebased as MLX Swift evolves.

## Runtime Strategy

- Pine runtime profiles request `QuantizationAlgorithm.turboQuant` and use the bundled `mlx-swift-lm` TurboQuant profile registry where possible. Verified local generation defaults to `turbo4v2` for current-generation KV cache profiles, with `turbo3_5` retained as the conservative fallback.
- Runtime profiles are adapted from `hw.machine`, memory, thermal state, Low Power Mode, Metal architecture, MLX working-set size, and the MLX TurboQuant self-test. Device names are diagnostic hints; verified MLX capabilities decide whether compressed Metal attention is active.
- 6 GB A16-class devices use compact defaults. A17 Pro, A18, A18 Pro, A19, A19 Pro thin, A19 Pro sustained, and future verified devices get progressively larger prefill and context defaults, with conservative downshifts under thermal, Low Power Mode, or available-memory pressure.
- Low-memory constrained generation clamps completion tokens from measured generation-start headroom so optimized TurboQuant can finish before crossing the emergency memory floor.
- iOS memory warnings soft-recover through the runtime bridge while active generation still has emergency headroom; otherwise they stop the active local run and unload transient MLX containers.
- Pine pins `RNT56/mlx-swift` and `RNT56/mlx-swift-lm` to exact TurboQuant fork revisions in `project.yml` and the generated Xcode project. CI rejects drift back to the pre-fix revisions.
- Current pins:
  - `RNT56/mlx-swift`: `dfa7eeb6655facc4916381e95a1deb83a6d8728a`
  - `RNT56/mlx-swift-lm`: `9f29a48654b546615f4b33059b52d27af931753e`
  - Nested `mlx` inside `RNT56/mlx-swift`: `8f13e02fa85252f2a569a43c6759f07490b816a5`
  - Nested `mlx-c` inside `RNT56/mlx-swift`: `fff19671eed2e556bdf4552328a1791a8f37b651`
- `mlx-swift` exposes additive TurboQuant packed tensor APIs over MLX native packed quantization and quantized matmul, a deterministic PolarQuant/QJL reference codec, custom Metal encode/decode kernels, row-wise compressed-attention code blobs, direct compressed `QK^T`, direct compressed `AV`, a tiled online fused decode path for admitted 64/80/96/112/128/192/240/256 head dimensions, runtime device capabilities, selected kernel profiles, tiny latency probes, per-group QJL residual scaling, quality-gate metrics, and a runtime self-tested backend availability contract.
- `mlx-swift-lm` exposes `KVCacheStrategy.turboQuant`, `TurboQuantKVCache`, a raw-free physical-slot `RotatingTurboQuantKVCache` for supported `.metalPolarQJL` `maxKVSize` paths, a shared packed quantized-attention fallback before raw decode, prepared-prefix generation, prompt-cache serialization hooks, `TurboQuantCompressedKVCacheProtocol`, the bundled `TurboQuantProfileRegistry`, and `GenerateParameters` fields for cache strategy, preset, requested backend selection, value bits, device-adaptive optimization policy, model metadata, KV head dimensions, and compressed-attention diagnostics.
- Pines keeps a local prompt KV cache for text-only MLX turns. Cache entries are keyed by model/runtime/tokenizer and quantization shape, reused only on token-prefix match, trimmed after successful generation, and evicted before model unload under memory pressure or thermal downshift.
- Pines marks Qwen3.5/Qwen3.6 as Hybrid Full: standard attention KV caches use TurboQuant, while Qwen linear-attention native state caches remain exact MLX state. Gemma 3/3n/4 and text Llama are marked TurboQuant full when metadata matches the pinned profile registry. Llama 3.2 Vision stays unsupported until the pinned `mlx-swift-lm` fork exposes `mllama` VLM registration, preprocessing, cache construction, and profiles.
- The app-level runtime smoke tests link MLX/MLXLMCommon, assert those fixed pins are present, validate high-bit TurboQuant seed propagation, and run a tiny Metal codec round trip when the executing device exposes the TurboQuant Metal codec.
- `tools/update-mlx-pins.sh` advances the reproducible SHAs, regenerates `Pines.xcodeproj`, and can run the package plus iOS smoke-test checks. Renovate proposes these pin moves by PR instead of switching Pines to non-reproducible branch pins.
- Pine requests the paper-exact `metalPolarQJL` backend by default. Devices with Metal compressed-attention support report the direct compressed attention path; unsupported shapes or devices use the shared MLX packed quantized-attention fallback before raw decode.

## Vault Retrieval

- Imported document chunks store an FP16 embedding for exact rerank and a compressed TurboQuant vector code for approximate candidate retrieval.
- Vault vector codes default to `turbo4v2`, matching the current MLX TurboQuant generation recommendation for new installs. Codes still carry their preset and seed in the blob, so explicit older `turbo3_5` rows remain decodable if developer or pre-release data exists.
- Embedding ingestion is batched according to the active device profile to avoid avoidable jetsam on compact iOS devices.
- Search uses compressed candidates first, filters by embedding model when available, bounds the scanned candidate set by device profile, reranks with the FP16 vector, and falls back to SQLite FTS when embeddings are unavailable.
- Embeddings and compressed vector codes remain local-only unless the user explicitly enables both private iCloud sync and embedding sync through settings.

## Diagnostics

- Models and Settings show the requested codec, requested/active backend, Metal codec availability, Metal compressed-attention availability, active attention path, selected kernel variant, MLX self-test status, performance class, optimization policy, raw fallback allocation state, active fallback, preset, profile ID/source, profile diagnostics, cache topology, family support level, context window, thermal downshift, thermal state, device identifier, Metal architecture, MLX working set, and memory counters exposed by the runtime monitor.
- Runtime throughput, vault retrieval latency, memory-pressure events, and MetricKit payload availability are logged through `PinesRuntimeMetrics`.

## Fork Maintenance

- Do not edit Xcode DerivedData package checkouts.
- Maintain the Schtack/RNT56 forks of `mlx-swift` and `mlx-swift-lm`; Pine is pinned to known-good fork commits.
- Keep `project.yml`, `Pines.xcodeproj`, and this document synchronized whenever a fork revision changes.
- Current fork PRs:
  - `RNT56/mlx-swift#1`: TurboQuant packed tensor API, Polar/QJL reference backend contract, Metal codec and compressed-attention kernels, and deterministic quality gates.
  - `RNT56/mlx-swift-lm#1`: TurboQuant KV cache strategy, compressed attention routing, backend diagnostics, and Metal availability.
- Run `.github/workflows/mlx-upstream-sync.yml` monthly or manually to verify upstream reachability and Pine integration hooks.
- Keep one upstream-facing PR for the additive TurboQuant API so Pine can eventually return to upstream package releases.

## Remaining Native Work

- Move the current RNT56 fork branches under a Schtack GitHub organization if/when that organization is available to the authenticated account.
- Tune tiled decode thresholds after real A16/A17/A18/A19 profiling. Runtime probes now choose between portable, wide, sustained, and packed-fallback profiles, but checked-in defaults should remain conservative until device traces justify raising them.
- Re-run the KV-memory acceptance matrix on device. The supported `.metalPolarQJL` rotating path is raw-free; raw/packed fallback allocation is lazy and diagnostic-visible, and A17 Pro Qwen3.5 2B optimized inference has completed under low-memory pressure with the adaptive completion cap, but broader acceptance numbers still require real hardware measurement.
- Validate the acceptance matrix on real A16, A17 Pro, A18, A18 Pro, A19, A19 Pro thin, and A19 Pro sustained devices with full Xcode and Instruments.
