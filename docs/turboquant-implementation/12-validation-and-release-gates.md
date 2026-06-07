# Validation and Release Gates

This document lists validation commands, release-gate checks, and definition of done for each release milestone.

Use [Worker Launch Schedule](14-worker-launch-schedule.md) for the executable order that feeds these gates. A wave may produce implementation artifacts before a gate is fully product-active, but each gate must pass before the corresponding capability is exposed as supported or verified.

## Validation commands

Pines:

```bash
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
bash scripts/ci/xcodegen.sh generate
bash scripts/ci/run-xcode-validation.sh
```

MLX forks:

```bash
swift build
swift test
```

Benchmarks:

```bash
swift run TurboQuantBenchmark --json
swift run TurboQuantModelBenchmark --json
```

Current TurboQuant benchmark matrix:

```bash
cd /Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm
TQ_MODEL_DIR=/path/to/mlx-model scripts/run-turboquant-current-benchmarks.sh
```

Focused real-model quality gate:

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

Long-context lower-V comparison when FP16 does not fit:

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

Full iOS verification:

```bash
xcodebuild -project Pines.xcodeproj -scheme Pines -destination 'generic/platform=iOS' build
```

## Compatibility-pair green gate

`docs/turboquant-implementation/compatibility-pair.json` is the machine-readable source for pair status. A pair must stay `failed` or `pending` unless `releaseReadiness.greenAllowed` is true and current evidence passes all of these gates:

- native backend performance evidence for the production compressed-attention backend;
- compressed-vs-plain performance parity evidence from real model inference on the current pair;
- `real-model-inference-v1` quality evidence from actual model generation/inference comparisons;
- physical-device app-host evidence with hybrid/native cache diagnostics;
- benchmark matrix coverage for release contexts;
- quality, memory, and fallback gates for the exact model/device/mode tuple;
- lower-V and Sparse-V evidence when those paths are exposed, including mode,
  skipped/considered tokens, retained mass, dense-reference quality, and
  fallback count.

API contract tests, package-pin checks, simulator or generic iOS builds, and historical/superseded proofs do not make a pair green by themselves.

## MVP 0 gate

Required:

- W25 current-state doc updated;
- W0 release train doc updated;
- W20 schema registry exists;
- W21 failure matrix exists;
- W4 removes or isolates product fatal/zero behavior;
- W1 core public contracts exist;
- W7 Pines local shims build;
- W24 mode/fallback contract exists;
- compatibility-pair JSON is present and honestly `pending` or `failed` unless all green gates pass.

Validation:

- MLX Swift build/test for contracts;
- MLX LM build/test for typed errors;
- PinesCore build/test for shims.

Exit:

- no product-facing zero output;
- no product-facing fatal path;
- schemas and failure matrix are reviewable;
- no production pin update unless green.

## MVP 1 gate

Required:

- admission service;
- memory zones;
- mode fallback policy;
- typed failure mapping;
- RunDecision metadata;
- bridge integration;
- compatibility UI basic states;
- no silent cloud fallback.

Validation:

- unsafe context rejects before generation;
- typed MLX failure reaches stream failure;
- successful local run emits RunDecision;
- failure local run emits partial RunDecision;
- route policy test proves local failure does not silently cloud fallback.

Exit:

- Pines can show admitted context before generation;
- local generation uses admitted context;
- fallback policy is mode-specific;
- memory zones are recorded.

## MVP 1.5 gate

Required:

- BenchmarkReport.v1 import;
- ProfileEvidenceStore;
- QualityGate;
- MemoryCalibration;
- compatibility UI uses evidence levels;
- INT-2A green compatibility pair;
- at least one real-device tuple verified.

Validation:

- benchmark JSON imports;
- failed quality does not verify;
- memory calibration sample persists;
- verified evidence includes fallback contract hash;
- evidence revocation prevents product claim.

Exit:

- one real iPhone model/device/mode tuple is verified;
- UI shows evidence date and mode-specific context;
- no jetsam in admitted run.

## MVP 2 gate

Required:

- ContextAssemblyPlan.v1 full planner;
- pinned/recent/retrieved/summary/dropped segments;
- vault retrieval budget;
- context provenance UI;
- semantic vs KV distinction enforced.

Validation:

- pinned prompt cannot be dropped;
- cloud route excludes vault content without approval;
- compressed KV pages require exact prefix validity;
- deterministic plan for same inputs.

Exit:

- user can inspect what was included, summarized, and dropped.

## MVP 3 gate

Required:

- LM snapshot export/import;
- Pines encrypted snapshot store;
- snapshot security policy;
- restore flow;
- invalidation flow.

Validation:

- app restart restore works;
- invalid snapshot fails closed;
- partial writes quarantine;
- data erasure deletes snapshots;
- model deletion deletes snapshots.

Exit:

- close app -> reopen -> continue from valid local snapshot.

## MVP 4 gate

Required:

- hidden-copy audit passes;
- kernel warmup registry;
- Layout V5 behind flag;
- popcount offset path;
- fused dim specializations;
- benchmark before/after;
- quality gates remain green.

Validation:

- no hidden full-cache copy in hot path;
- V4 compatibility;
- V5 improves bytes or speed;
- unsupported dims fallback safely.

Exit:

- optimization release is evidence-backed.

## MVP 5 gate

Required:

- LM speculative verifier;
- tentative append;
- rollback rejected tokens;
- Pines draft pairing;
- acceptance telemetry;
- auto-disable poor speculation.

Validation:

- accepted sequence matches target;
- rejected tokens do not corrupt cache;
- Fast mode improves p50 decode when acceptance is high;
- poor acceptance degrades cleanly.

## Final release definition of done

First shippable control-plane milestone:

- admitted context shown before generation;
- unsafe contexts rejected before generation;
- no MLX-LM product zero/fatal path;
- TurboQuant failures are typed;
- memory zones recorded;
- fallback policy mode-specific;
- RunDecision attached;
- compatibility UI shows conservative/unverified/verified states;
- compatibility pair proven;
- no silent cloud fallback.

First evidence-backed release:

- one real iPhone model/device/mode tuple verified;
- benchmark JSON imports into Pines;
- QualityGate passes;
- memory calibration sample exists;
- estimated-vs-actual memory recorded;
- no jetsam in admitted run;
- UI shows evidence date and mode-specific context.

First persistent-workspace release:

- KV snapshots export/import;
- snapshots encrypted and local;
- invalid restore fails closed;
- close app -> reopen -> continue;
- data deletion removes snapshots.

First optimization release:

- hidden-copy audit passes;
- kernel warmup reduces cold start;
- Layout V5 improves bytes or speed;
- fused specializations improve decode;
- QualityGate remains green.
