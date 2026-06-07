# K8/Vx Real-Model Quality And Speed Baseline

Artifact run: `turboquant-k8vx-realmodel-20260601T144308Z`

Primary artifact:
`/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-k8vx-realmodel-20260601T144308Z/k8vx-quality-speed-summary.md`

Host:

| Field | Value |
| --- | --- |
| Hardware | `Mac14,10` |
| Memory | `17179869184` bytes |
| Model | `/Users/mt/.cache/huggingface/hub/models--mlx-community--Qwen3.5-2B-4bit/snapshots/674aaa7240b91e8012fcad5d791b7dfe5ba90207` |
| Tool | `TurboQuantInferenceParity` |
| Generate tokens | `8` |

## Speed Matrix

| Context | Config | Decode tok/s | Prefill tok/s | Ratio vs FP16 |
| ---: | --- | ---: | ---: | ---: |
| 32768 | `fp16` | 20.50 | 710.6 | 1.000 |
| 32768 | `affineK8V4` | 32.40 | 809.4 | 1.581 |
| 32768 | `affineK8V3` | 14.16 | 796.7 | 0.691 |
| 32768 | `affineK8V2` | 15.54 | 729.3 | 0.758 |
| 65536 | `fp16` | 43.06 | 684.9 | 1.000 |
| 65536 | `affineK8V4` | 21.54 | 616.2 | 0.500 |
| 65536 | `affineK8V3` | 21.39 | 700.1 | 0.497 |
| 65536 | `affineK8V2` | 21.36 | 710.6 | 0.496 |
| 131072 | `affineK8V4` | 15.72 | 448.5 | n/a |
| 131072 | `affineK8V3` | 13.24 | 543.7 | n/a |
| 131072 | `affineK8V2` | 8.54 | 502.9 | n/a |

128K FP16 was not run on this host. For the Qwen GQA4/HD256 shape with 32
layers, raw FP16 KV alone is roughly 16 GiB at 128K before model weights,
temporary tensors, command buffers, and runtime overhead.

128K rows required strict long-context scheduling:

```bash
TQ_PREFILL_SYNC_INTERVAL=1 TQ_DECODE_SYNC_INTERVAL=1
```

A combined 128K K8/V4 -> K8/V3 process still hit
`kIOGPUCommandBufferCallbackErrorImpactingInteractivity`; isolated strict-sync
V3 and V2 processes completed.

## Quality Matrix

32K and 64K compare compressed rows against FP16. 128K compares lower-V rows
against dense K8/V4 because FP16 is not practical on this host.

Current `real-model-inference-v1` thresholds for this gate:

| Metric | Threshold |
| --- | ---: |
| Top-1 match | `1.0` |
| Mean KL | `<= 0.10` |
| P95 max abs logit error | `<= 2.0` |

| Context | Candidate | Reference | Top-1 | KL | P95 max abs | Cosine | Result |
| ---: | --- | --- | ---: | ---: | ---: | ---: | --- |
| 32768 | `affineK8V4` | `fp16` | 1.000 | 0.000004 | 1.0625 | 0.9934 | pass |
| 32768 | `affineK8V3` | `fp16` | 1.000 | 0.000035 | 2.7656 | 0.9638 | fail |
| 32768 | `affineK8V2` | `fp16` | 1.000 | 0.000262 | 4.5586 | 0.8914 | fail |
| 65536 | `affineK8V4` | `fp16` | 1.000 | 0.000006 | 1.1328 | 0.9888 | pass |
| 65536 | `affineK8V3` | `fp16` | 1.000 | 0.000057 | 2.8828 | 0.9348 | fail |
| 65536 | `affineK8V2` | `fp16` | 1.000 | 0.000048 | 4.4004 | 0.8720 | fail |
| 131072 | `affineK8V3` | `affineK8V4` | 1.000 | 0.000121 | 2.9375 | 0.9656 | fail |
| 131072 | `affineK8V2` | `affineK8V4` | 1.000 | 0.000096 | 5.3984 | 0.8606 | fail |

## Current Verdict

Dense K8/V4 is the only K8/Vx row that passes the current FP16-referenced
real-model logit gate at 32K and 64K. K8/V3 and K8/V2 preserve top-1 in this
run, but they exceed the P95 max-logit-error threshold at every measured
context.

For 128K optimization work on this 16 GB Mac, dense K8/V4 is the correct
reference baseline. Lower-V rows and Sparse-V rows must be treated as guarded
experiments until they pass real-model speed, memory, fallback, and quality
gates.
