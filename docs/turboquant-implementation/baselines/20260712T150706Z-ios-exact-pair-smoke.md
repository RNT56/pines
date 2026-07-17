# 2026-07-12 exact-pair iOS app-host smoke

This baseline records a physical-device synthetic attention-shape smoke for the current Pines MLX dependency pair. It proves the signed app-host installation, launch, native compressed-attention route, and diagnostics export on the paired device. It is not real-model inference and cannot promote the pair to `Verified` or `Certified`.

## Reproducibility tuple

- Run: `turboquant-bench-20260712T150706Z`
- Device: `iPhone16,2` / iPhone 15 Pro Max, iOS 26.5 (`23F77`)
- Device identifier: `7BFB7B72-C40C-58A7-B2C6-F075BDE21116`
- App host: Pines Debug app, hidden `--pines-turboquant-bench` launch mode
- Pines validation base: `ebc1d80aba9466da5e72690b26d9155aec72836d` with the reviewed worktree changes
- `mlx-swift`: `d378d85c114b38c0919d5f6f7a489528427cb23d`
- `mlx-swift-lm`: `1ab388ff78eaa572b2eb9de2b330d218818b3920`
- Compatibility pair: `mlx-swift-d378d85c114b38c0919d5f6f7a489528427cb23d+mlx-swift-lm-1ab388ff78eaa572b2eb9de2b330d218818b3920`

## Result

| Context | Scheme | Selected path | Compressed tok/s | Plain tok/s | Ratio | Native/Swift Metal | Cosine | KV memory reduction |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8,192 | `turbo4v2` | `nativeMLXCompressed` | 184.43 | 645.58 | 0.286× | 1.150× | 0.999992 | 2.286× |

The benchmark completed with one passing result and no failed or skipped rows. The native MLX compressed path was active, but compressed throughput remained below plain SDPA at equal context. The result declares `synthetic: true`, `realModel: false`, `productClaimLevel: unverified`, `nativeBackendPerformanceEvidence: not-proven`, and `performanceParityEvidence: not-proven`.

Raw local artifacts are retained under `artifacts/ios-turboquant-bench-20260712T150706Z` and remain ignored by Git because device containers may include unrelated historical diagnostics. The authoritative current-run result is `pines-turboquant-bench-turboquant-bench-20260712T150706Z.json` inside that capture.

## Release interpretation

This closes the exact-pair physical app-host smoke gap only. Release readiness remains non-green until real-model inference, broader device/context coverage, quality, memory, throughput, fallback, and benchmark-matrix gates pass for the exact tuple.
