# TurboQuant Integration

Pine requests TurboQuant as the default local KV-cache strategy and stores vault embeddings with a compressed TurboQuant-compatible code path. The app consumes additive APIs from the maintained MLX forks so the runtime can be rebased as MLX Swift evolves.

## Runtime Strategy

- Pine runtime profiles request `QuantizationAlgorithm.turboQuant` and use the bundled `mlx-swift-lm` TurboQuant profile registry where possible. Verified local generation defaults to `turbo4v2` for current-generation KV cache profiles, with `turbo3_5` retained as the conservative fallback.
- Runtime profiles are adapted from `hw.machine`, memory, thermal state, Low Power Mode, Metal architecture, MLX working-set size, and the MLX TurboQuant self-test. Device names are diagnostic hints; verified MLX capabilities decide whether compressed Metal attention is active.
- 6 GB A16-class devices use compact defaults. A17 Pro, A18, A18 Pro, A19, A19 Pro thin, A19 Pro sustained, and future verified devices get progressively larger prefill and context defaults, with conservative downshifts under thermal, Low Power Mode, or available-memory pressure.
- iOS memory warnings stop the active local run and unload transient MLX containers through the runtime bridge.
- Pine pins `RNT56/mlx-swift` and `RNT56/mlx-swift-lm` to exact TurboQuant fork revisions in `project.yml` and the generated Xcode project. CI rejects drift back to the pre-fix revisions.
- Current pins:
  - `RNT56/mlx-swift`: `48375f1d8f0694dee2ce8aab7f46be50c5297aec`
  - `RNT56/mlx-swift-lm`: `bb5f6f837896503b1f660eaeed2850fb0f232a64`
  - Nested `mlx` inside `RNT56/mlx-swift`: `292c54b7bbf95a7061b3d70c05c1785dfb9b9a85`
  - Nested `mlx-c` inside `RNT56/mlx-swift`: `f53f40c7a5d0db5cb2a8661e67e29a18470d8863`
- `mlx-swift` exposes additive TurboQuant packed tensor APIs over MLX native packed quantization and quantized matmul, a deterministic PolarQuant/QJL reference codec, custom Metal encode/decode kernels, row-wise compressed-attention code blobs, direct compressed `QK^T`, direct compressed `AV`, a tiled online fused decode path, runtime device capabilities, selected kernel profiles, tiny latency probes, per-group QJL residual scaling, quality-gate metrics, and a runtime self-tested backend availability contract.
- `mlx-swift-lm` exposes `KVCacheStrategy.turboQuant`, `TurboQuantKVCache`, a raw-free physical-slot `RotatingTurboQuantKVCache` for supported `.metalPolarQJL` `maxKVSize` paths, prompt-cache serialization hooks, `TurboQuantCompressedKVCacheProtocol`, the bundled `TurboQuantProfileRegistry`, and `GenerateParameters` fields for cache strategy, preset, requested backend selection, value bits, device-adaptive optimization policy, and compressed-attention diagnostics.
- The app-level runtime smoke tests link MLX/MLXLMCommon, assert those fixed pins are present, validate high-bit TurboQuant seed propagation, and run a tiny Metal codec round trip when the executing device exposes the TurboQuant Metal codec.
- `tools/update-mlx-pins.sh` advances the reproducible SHAs, regenerates `Pines.xcodeproj`, and can run the package plus iOS smoke-test checks. Renovate proposes these pin moves by PR instead of switching Pines to non-reproducible branch pins.
- Pine requests the paper-exact `metalPolarQJL` backend by default. Devices with Metal compressed-attention support report the direct compressed attention path; unsupported shapes or devices use the existing MLX packed quantized-matmul fallback.

## Vault Retrieval

- Imported document chunks store an FP16 embedding for exact rerank and a compressed TurboQuant vector code for approximate candidate retrieval.
- Vault vector codes default to `turbo4v2`, matching the current MLX TurboQuant generation recommendation for new installs. Codes still carry their preset and seed in the blob, so explicit older `turbo3_5` rows remain decodable if developer or pre-release data exists.
- Embedding ingestion is batched according to the active device profile to avoid avoidable jetsam on compact iOS devices.
- Search uses compressed candidates first, filters by embedding model when available, bounds the scanned candidate set by device profile, reranks with the FP16 vector, and falls back to SQLite FTS when embeddings are unavailable.
- Embeddings and compressed vector codes remain local-only unless the user explicitly enables both private iCloud sync and embedding sync through settings.

## Diagnostics

- Models and Settings show the requested codec, requested/active backend, Metal codec availability, Metal compressed-attention availability, active attention path, selected kernel variant, MLX self-test status, performance class, optimization policy, raw fallback allocation state, active fallback, preset, context window, thermal downshift, thermal state, device identifier, Metal architecture, MLX working set, and memory counters exposed by the runtime monitor.
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
- Re-run the KV-memory acceptance matrix on device. The supported `.metalPolarQJL` rotating path is raw-free; raw/packed fallback allocation is lazy and diagnostic-visible, but final acceptance numbers still require real hardware measurement.
- Validate the acceptance matrix on real A16, A17 Pro, A18, A18 Pro, A19, A19 Pro thin, and A19 Pro sustained devices with full Xcode and Instruments.
