# Current Paths And Benchmark Matrix

This is the cross-repo checklist for what is currently implemented and how each
surface must be tested before Pines can make product claims.

## Implemented Paths

| Surface | Path | Config label / strategy | Status |
| --- | --- | --- | --- |
| Raw attention | FP16 MLX SDPA | `fp16`, `KVCacheStrategy.none` | Production baseline when memory fits. |
| Legacy compressed KV | Polar/QJL TurboQuant | `turbo8`, `turbo4v2`, `turbo3_5`, `.turboQuant` | Capacity route; not a speed-parity claim. |
| Adaptive compressed KV | Raw-first TurboQuant | `.adaptiveTurboQuant` | Compatibility route for raw short context plus compressed long context. |
| Hybrid cache/selector | Hot raw tail plus cold block selector | `.hybridTurboQuant` | Selector/cache diagnostics are implemented; product promotion still requires real fused selected-block evidence. |
| MLX affine Q8 | Native affine quantized KV | `mlxAffine-q8`, `.mlxAffine` | Community-comparable benchmark/reference route. |
| K8/V4 speed candidate | K affine 8-bit, V affine 4-bit | `affineK8V4`, `.affineK8V4` | Wired end to end and currently the main quality-preserving compressed speed candidate. |
| K8/V3 experiment | K affine 8-bit, V 3-bit | `affineK8V3`, `.affineK8Vx`, `turboQuantValueBits = 3` | Guarded lower-V experiment with correct labels and quality gates. |
| K8/V2 experiment | K affine 8-bit, V 2-bit | `affineK8V2`, `.affineK8Vx`, `turboQuantValueBits = 2` | Guarded lower-V experiment with correct labels and quality gates. |
| Affine int4 | Affine 4-bit KV | `affineInt4`, `.affineInt4` | Fast comparison route; quality must pass per model. |
| Sparse-V | Value-token skip diagnostics | threshold, top-k, cumulative mass, hybrid cumulative-plus-top-k | Native modes are wired and report diagnostics, but remain disabled by default until real-model quality and throughput gates pass. |

## Implemented Optimizations To Test

- exact prefill followed by cache conversion;
- quantized start threshold, default `16K`, so short caches avoid compression cost;
- K8/lower-V mixed precision;
- protected boundary layers and per-layer mixed KV policy;
- long-context prefill/decode synchronization and split-block scheduling;
- Qwen GQA4/HD256 decode shape;
- Sparse-V threshold, top-k, cumulative-mass, and hybrid diagnostics based on
  normalized softmax weights;
- p50/p95 latency, speed ratio, memory ratio, fallback reason, and quality gate
  reporting.

## Latest Real-Model K8/Vx Baseline

Current documented baseline:
[20260601T144308Z K8/Vx real-model quality and speed](baselines/20260601T144308Z-k8vx-realmodel-quality-speed.md).

Artifact:
`/Users/mt/Programming/Schtack/mlx-forks/artifacts/turboquant-k8vx-realmodel-20260601T144308Z/k8vx-quality-speed-summary.md`.

Speed rows from `TurboQuantInferenceParity` on `Mac14,10`,
`mlx-community/Qwen3.5-2B-4bit`, `generateTokens=8`:

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

Quality-gate verdict:

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

Current conclusion: dense K8/V4 is the only K8/Vx row that passes the active
real-model logit gate at 32K and 64K. K8/V3 and K8/V2 are correctly wired and
useful experiments, but they are not promotable under the current P95 max-logit
error gate. At 128K, dense K8/V4 is the comparison baseline on this 16 GB Mac
because raw FP16 KV alone is roughly 16 GiB before model/runtime overhead.

The lower-V and Sparse-V follow-up plan is tracked in
[Lower-V and Sparse-V Optimization Plan](17-lower-v-sparse-v-optimization-plan.md).

## Required Benchmark Surfaces

### Core operator JSON

Run in `/Users/mt/Programming/Schtack/mlx-forks/mlx-swift`:

```bash
swift build --product TurboQuantBenchmark -c release
.build/release/TurboQuantBenchmark \
  --json --include-timestamp \
  --iterations 12 --warmup 3 \
  --context 32768 \
  --preset turbo4v2 \
  --path affine-k8v4-native \
  --head-dim 256 --query-heads 16 --kv-heads 4 --query-length 1
```

Core rows are kernel smoke/regression evidence only. They do not certify a Pines
model/device/mode tuple.

### Real-model inference parity

Run in `/Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm`:

```bash
swift build --product TurboQuantInferenceParity -c release
.build/release/TurboQuantInferenceParity \
  --model-dir /path/to/mlx-model \
  --contexts 32768,65536 \
  --generate-tokens 16 \
  --configs fp16,affineK8V4,affineK8V3,affineK8V2,mlxAffine-q8,affineInt4,turbo4v2,turbo3_5,turbo8 \
  --quality-gates \
  --quality-contexts 32768
```

This is the primary Mac evidence surface because it runs the real model and
reports full decode-loop throughput plus logit quality gates.

For contexts where FP16 raw KV does not fit, the same tool can compare lower-V
or Sparse-V candidates against dense K8/V4:

```bash
.build/release/TurboQuantInferenceParity \
  --model-dir /path/to/mlx-model \
  --contexts 131072 \
  --generate-tokens 8 \
  --configs affineK8V4,affineK8V3,affineK8V2 \
  --quality-gates \
  --quality-contexts 131072 \
  --quality-reference-config affineK8V4
```

### Current full local matrix runner

Run in `/Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm`:

```bash
TQ_MODEL_DIR=/path/to/mlx-model \
scripts/run-turboquant-current-benchmarks.sh
```

The script builds `TurboQuantBenchmark` and `TurboQuantInferenceParity`, loops
the current core path/preset/context matrix, optionally runs real-model quality
gates, and writes a timestamped artifact directory.

### App-hosted iOS evidence

Pines still needs physical-device evidence for product claims. Synthetic
attention smoke is useful but insufficient. Real promotion requires imported
`real-model-inference-v1` evidence with:

- model revision, tokenizer hash, profile hash, compatibility pair ID;
- device model, iOS version, thermal and Low Power Mode state;
- active path/config, admitted context, fallback contract hash;
- speed, memory, fallback count, and quality gate output.

### Sparse-V proof/profiling commands

Sparse-V threshold, top-k, cumulative-mass, and hybrid modes are exposed through
`TurboQuantQwenProof` for diagnostics. These are proof/profiling rows until the
real-model gates pass.

```bash
cd /Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm
swift build --product TurboQuantQwenProof -c release

.build/release/TurboQuantQwenProof \
  --profiles qwen3.5-2b \
  --schemes turbo4v2 \
  --contexts 32768 \
  --query-lengths 1 \
  --iterations 3 \
  --warmup 1 \
  --sparse-v-mode top-k \
  --sparse-v-top-k 256

.build/release/TurboQuantQwenProof \
  --profiles qwen3.5-2b \
  --schemes turbo4v2 \
  --contexts 32768 \
  --query-lengths 1 \
  --iterations 3 \
  --warmup 1 \
  --sparse-v-mode cumulative-mass \
  --sparse-v-cumulative-mass 99.5

.build/release/TurboQuantQwenProof \
  --profiles qwen3.5-2b \
  --schemes turbo4v2 \
  --contexts 32768 \
  --query-lengths 1 \
  --iterations 3 \
  --warmup 1 \
  --sparse-v-mode hybrid \
  --sparse-v-hybrid-mass 99.5 \
  --sparse-v-max-top-k 256
```

## Promotion Rules

Pines may keep a pair `failed`, `pending`, or `smoke-tested` while these surfaces
are being exercised. It must not mark a pair or model tuple `green`, `Verified`,
or `Certified` unless the exact current artifacts show:

- real-model quality gates passed;
- no hidden full-cache decompression or unbudgeted fallback allocation;
- dense full scan used only when explicitly requested or guard-triggered;
- physical iOS app-host evidence exists for iPhone claims;
- compressed/hybrid performance claims are backed by equal-context measured
  throughput, not synthetic attention-only numbers.
