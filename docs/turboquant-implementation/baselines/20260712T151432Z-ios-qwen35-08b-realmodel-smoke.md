# 2026-07-12 Qwen 3.5 0.8B iOS real-model smoke

This baseline records a small physical-device `real-model-inference-v1` comparison on the exact current Pines MLX pair. The harness loaded the model already installed in the Pines container and ran actual token generation through FP16 and affine K8/V4 cache configurations.

## Reproducibility tuple

- Run: `device-rm-08b-current-20260712T151100Z`
- Model: `mlx-community/Qwen3.5-0.8B-MLX-4bit`
- Context: `4,096`
- Generated tokens: `8`
- Throughput repeats: `2`, randomized arm order
- Bootstrap resamples: `200`
- Device: `iPhone16,2` / iPhone 15 Pro Max, iOS 26.5 (`23F77`)
- Device identifier: `7BFB7B72-C40C-58A7-B2C6-F075BDE21116`
- `mlx-swift`: `d378d85c114b38c0919d5f6f7a489528427cb23d`
- `mlx-swift-lm`: `1ab388ff78eaa572b2eb9de2b330d218818b3920`
- Compatibility pair: `mlx-swift-d378d85c114b38c0919d5f6f7a489528427cb23d+mlx-swift-lm-1ab388ff78eaa572b2eb9de2b330d218818b3920`

## Result

| Arm | Samples (tok/s) | Median | Bootstrap 95% CI | Peak active memory |
| --- | --- | ---: | --- | ---: |
| FP16 | 24.47, 38.97 | 31.72 | 24.47–38.97 | 905,391,172 bytes |
| Affine K8/V4 | 38.86, 39.28 | 39.07 | 38.86–39.28 | 905,391,172 bytes |

- Compressed/FP16 median ratio: `1.2318×`
- Ratio bootstrap 95% CI: `0.9972–1.6053×`
- Deterministic top-1 match rate: `1.0`
- Attention-output cosine mean: `1.0`
- Logit KL-divergence mean: `0.0`
- Logit max-absolute-error P95: `0.0`
- Quality gate: passed
- Raw fallback allocated: false
- Row status: `ok`

The small run demonstrates coherent exact-pair real-model execution and a passing focused quality comparison. It is not sufficient to establish stable throughput superiority: only two repeats were requested, the ratio confidence interval is wide and includes approximately `1.0`, and the selected-attention-path diagnostic array was empty. Native backend engagement therefore remains unproven by this artifact alone.

Raw local artifacts are retained under `artifacts/ios-realmodel-tq-device-rm-08b-current-20260712T151100Z` and remain ignored by Git because copied device containers include unrelated historical diagnostics.

## Release interpretation

This closes a focused exact-pair real-model smoke gap for one model, one device, and one small context. Release readiness remains non-green until the required context/device/model matrix, stable throughput confidence, native-path diagnostics, memory behavior, fallback behavior, and task/quality gates pass and an accepted tuple is imported into the product evidence store.
