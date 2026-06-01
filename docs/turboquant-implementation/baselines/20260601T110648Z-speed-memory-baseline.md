# TurboQuant Speed And Memory Baseline

Created UTC: `2026-06-01T11:06:48Z`  
Created local: `2026-06-01 13:06:48 CEST`

This baseline records the current real-model speed evidence and KV-cache memory estimates for comparing later TurboQuant, K8/V4, and hybrid-attention changes.

## Repo Heads

| Surface | Branch | Commit |
|---|---|---|
| `mlx` | `codex/mlx-core-distributed-autodiff-backends` | `2b37f4ec24d9653ee1efc29256d5b8cc2bda565e` |
| `mlx-c` | `codex/mlx-c-quantized-sdpa-parity` | `c270c9ef3b8cae2b92861aa8fca9345484d29c26` |
| `mlx-swift` | `tq/layout-v5-default-device-tests` | `609e8333671419ee1dbe928eeee7f48a24682631` |
| `mlx-swift-lm` | `tq/lm-layout-v5-default-device-tests` | `725add5dd15ef6c1c01073ce9f81412957fa5c6d` |
| `pines` | `tq/real-device-evidence-acceptance` | `e7125308e3253d46447d2b61b46a194b4096605f` |

## Speed Baseline

Model:
`/Users/mt/.cache/huggingface/hub/models--mlx-community--Qwen3.5-2B-4bit/snapshots/674aaa7240b91e8012fcad5d791b7dfe5ba90207`

Hardware:
Mac local run, real model inference, idle runs only.

Source logs:
- `/Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm/artifacts/real-model-k8v4-idle-32k-20260601T101644Z/qwen35-2b-real-model-32k.log`
- `/Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm/artifacts/real-model-k8v4-idle-64k-20260601T102000Z/qwen35-2b-real-model-64k.log`

| Context | Config | Decode tok/s | Prefill tok/s | Generated Tokens | Ratio vs FP16 |
|---:|---|---:|---:|---:|---:|
| 32K | FP16 raw KV | 42.74 | 716.1 | 32 | 1.000 |
| 32K | affine K8/V4 | 33.20 | 738.2 | 32 | 0.777 |
| 32K | MLX affine q8 | 18.01 | 733.1 | 32 | 0.421 |
| 32K | affine int4 | 24.42 | 747.9 | 32 | 0.571 |
| 64K | FP16 raw KV | 32.31 | 615.2 | 16 | 1.000 |
| 64K | affine K8/V4 | 17.57 | 610.4 | 16 | 0.544 |

Current interpretation:
- FP16 remains the speed baseline when memory fits.
- affine K8/V4 is the current best production compressed speed route.
- affine K8/V4 is not yet performance-parity with FP16 at equal dense context.
- Turbo4V2 is treated as a capacity route unless later real-model benchmarks prove otherwise.

## KV Memory Baseline

Assumed Qwen GQA4 HD256 KV shape:
- layers: `32`
- KV heads: `4`
- head dim: `256`
- tensors: key plus value
- FP16 raw KV: `2 bytes` per scalar
- affine K8/V4: K uses 8-bit affine groups of 64, V uses 4-bit affine groups of 32, with fp16 scale/bias metadata
- Turbo4V2 estimate is based on the current planning ratio of approximately `2.63 GiB` at 64K

| Context | FP16 Raw KV | affine K8/V4 KV | Turbo4V2 KV |
|---:|---:|---:|---:|
| 16K | 2.00 GiB | 0.84 GiB | 0.66 GiB |
| 32K | 4.00 GiB | 1.69 GiB | 1.32 GiB |
| 64K | 8.00 GiB | 3.38 GiB | 2.63 GiB |
| 128K | 16.00 GiB | 6.75 GiB | 5.26 GiB |

| Mode | Approx KV Size vs FP16 | Approx Reduction |
|---|---:|---:|
| FP16 raw KV | 100.0% | baseline |
| affine K8/V4 | 42.2% | 2.37x smaller |
| Turbo4V2 | 32.9% | 3.04x smaller |

## Comparison Notes

Use this baseline to compare future runs against:
- decode tok/s at the same model, context, and generated-token count,
- prefill tok/s separately from decode,
- ratio vs FP16 at the same context,
- KV-only memory estimates separately from total process memory,
- real-model inference only for release-quality claims.

Do not use synthetic attention-shape smoke tests as performance parity evidence.
