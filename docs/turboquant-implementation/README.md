# TurboQuant Implementation Packet

This folder is the source-of-truth planning packet for the multi-repo TurboQuant implementation train.

The goal is to move from the current MLX fork integration state to a shippable, evidence-backed, mobile long-context Pines runtime. Implementations should branch from the repo branches that contain these docs, and every worker PR should reference the relevant document and release gate.

## North-star outcome

The finished system should behave like this:

1. User selects a local model.
2. Pines checks model evidence, device state, memory, thermal state, and user mode.
3. Pines shows safe admitted context per mode.
4. Pines refuses unsafe runs before generation.
5. Prefill remains exact.
6. KV cache is compressed and committed safely.
7. Decode runs compressed-domain where possible.
8. Fallbacks are budgeted and correct.
9. Every run records what happened.
10. Evidence updates model/device compatibility.
11. Sessions can later resume from valid encrypted snapshots.
12. No cloud fallback happens without explicit user-approved policy.

## Required reading order

1. [Current State](00-current-state.md)
2. [Release Train](01-release-train.md)
3. [Worker Launch Schedule](14-worker-launch-schedule.md)
4. [Schema Registry](02-schema-registry.md)
5. [Failure Matrix](03-failure-matrix.md)
6. [Mode and Fallback Contract](04-mode-fallback-contract.md)
7. [Memory Admission and Calibration](05-memory-admission-calibration.md)
8. [Quality Gates](06-quality-gates.md)
9. [Benchmark Evidence](07-benchmark-evidence.md)
10. [Worker Ownership](08-worker-ownership.md)
11. [Runtime Bridge Integration](09-runtime-bridge-integration.md)
12. [Context Memory Planner](10-context-memory-planner.md)
13. [KV Snapshot Security](11-kv-snapshot-security.md)
14. [Validation and Release Gates](12-validation-and-release-gates.md)
15. [Complete Task Inventory](13-complete-task-inventory.md)
16. [PR and Merge Plan](15-pr-merge-plan.md)
17. [Current Paths and Benchmark Matrix](16-current-paths-and-benchmarks.md)
18. [Lower-V and Sparse-V Optimization Plan](17-lower-v-sparse-v-optimization-plan.md)
19. [Multi-Worker Execution](18-multi-worker-execution.md)

## How to execute the packet

Use [Worker Launch Schedule](14-worker-launch-schedule.md) as the primary execution document. It restructures the complete worker set into waves:

- Wave 0: docs, contracts, and safety can start immediately.
- Wave 1: control-plane building blocks.
- Wave 2: serialized runtime integration.
- Wave 3: evidence activation and compatibility UI.
- Wave 3.5: production pin promotion.
- Wave 4: context and persistence.
- Wave 5: optimization.
- Wave 6: speculative decode and platform unlocks.
- Wave 7: W29+/MVP 6 platform-unlock contracts and fail-closed gates.

Use [Worker Ownership](08-worker-ownership.md) for file ownership and PR rules, and [Complete Task Inventory](13-complete-task-inventory.md) for the full backlog. The schedule is the launch order; the inventory is the scope catalogue.

Use [PR and Merge Plan](15-pr-merge-plan.md) for branch targets, worker PR sequencing, wave promotion, compatibility pin validation, and final default-branch merge gates.

Use [Multi-Worker Execution](18-multi-worker-execution.md) and its
machine-readable [manifest](18-multi-worker-execution-manifest.json) when
launching parallel agents or validating worker dispatch rules:

```bash
python3 scripts/diagnostics/turboquant-worker-plan.py --validate --compatibility
python3 scripts/diagnostics/turboquant-worker-plan.py --wave wave-3
```

Machine-readable compatibility-pair files:

- [compatibility-pair.schema.json](compatibility-pair.schema.json)
- [compatibility-pair.json](compatibility-pair.json)

Current status:

- The active compatibility pair is failed/non-green after the Wave 0 baseline `turboquant-wave0-20260531T024557Z`.
- Pines pins `mlx-swift` `609e8333671419ee1dbe928eeee7f48a24682631` and `mlx-swift-lm` `725add5dd15ef6c1c01073ce9f81412957fa5c6d`.
- Layout V4 is the production default for new TurboQuant attention layout requests; Layout V5/V6 remain supported for explicit experimental, benchmark, and compatibility runs.
- Current continuation evidence includes passing local TurboQuant gates and exact-pin physical-device app-host smoke on `iPhone16,2`, but that smoke is synthetic attention-shape evidence. Release comparisons now require `real-model-inference-v1`; native backend performance parity and the full release benchmark/quality/fallback matrix remain incomplete.
- The latest Mac real-model K8/Vx baseline is [20260601T144308Z](baselines/20260601T144308Z-k8vx-realmodel-quality-speed.md): dense K8/V4 passes the current 32K/64K FP16-referenced logit gates, while K8/V3 and K8/V2 preserve top-1 but fail P95 max-logit-error gates. Native Sparse-V threshold/top-k/cumulative/hybrid modes are implemented and reportable, but remain disabled by default until real-model and iOS evidence passes.
- Historical pass, smoke, simulator, and Mac proof evidence is retained for audit only and cannot make the current pair green.
- Real-device model/device/mode evidence is still required before any product surface may claim `Verified` or `Certified` compatibility.

Wave handoff logs:

- [Wave 1 Changelog](Wave1-changelog.md)
- [Wave 2 Changelog](Wave2-changelog.md)
- [Wave 3 Changelog](Wave3-changelog.md)
- [Wave 3.5 Changelog](Wave3.5-changelog.md)
- [Wave 4 Changelog](Wave4-changelog.md)
- [Wave 5 Changelog](Wave5-changelog.md)
- [Wave 6 Changelog](Wave6-changelog.md)
- [Wave 7 Changelog](Wave7-changelog.md)

## Non-negotiable rules

These apply to all repos and all branches.

1. No silent wrong output. Never return zero tensors, stale tensors, partially compressed tensors, guessed tensors, or unvalidated decoded cache results.
2. No product-path `fatalError`. Debug fatal flags are allowed only in explicitly test/debug code. Pines-facing runtime paths must throw typed errors or downgrade.
3. No unapproved cloud escape. Local failure must not silently route to cloud. Cloud retry is allowed only if the user policy and route decision explicitly permit it.
4. No unbounded duplicate KV. Long-context mode cannot keep raw KV, packed fallback KV, decoded fallback KV, and compressed KV resident unless the admission plan budgets them.
5. No verified label without evidence. Verified requires a versioned benchmark/evidence record with memory, speed, correctness, and quality gates.
6. No blind MLX pin update. Pines pins a new MLX pair only after a compatibility branch proves the public contracts compile and Pines passes validation.
7. No hidden long-cache copies. Long-KV Metal paths must audit and avoid accidental full-cache row-contiguous copies.
8. Future work may be implemented behind disabled flags before gates pass, but activation waits for gate evidence.

## Release ladder

| Gate | Goal | Exit criteria |
| --- | --- | --- |
| MVP 0 | Contract and safety freeze | no product-facing zero output, no product-facing fatal, versioned schemas exist, failure matrix exists, core contracts exist, Pines shims build |
| MVP 1 | Control-plane long-context runtime | admission runs before generation, memory zones are recorded, mode-specific fallback policy exists, typed MLX errors map to typed Pines stream failures, RunDecision metadata is attached, no silent cloud fallback |
| MVP 1.5 | Evidence and verification loop | benchmark JSON imports, QualityGate passes, memory estimate-vs-actual calibration exists, at least one model/device/mode tuple is verified on a real device |
| MVP 2 | Context virtualization v1 | pinned, recent, retrieved, summarized, and dropped segments are recorded; user can inspect what was included or removed; warm KV pages are not treated as semantic retrieval chunks |
| MVP 3 | Persistent private workspace | snapshot export/import roundtrips; snapshots are encrypted, atomic, local by default, and fail closed on identity mismatch |
| MVP 4 | Kernel/storage optimization | hidden-copy audit passes; kernel warmup exists; Layout V5 is gated; popcount offset path and fused specializations are benchmarked; quality gates remain green |
| MVP 5 | Speculative TurboQuant | tentative cache append is rollback-safe; accepted tokens match target; poor acceptance disables speculation; Fast mode improves p50 decode speed |
| MVP 6 | Platform unlocks | adaptive precision, semantic memory, multimodal memory, agents, open format, device mesh, and personalization/adapters |

Wave 7 implements W29+/MVP 6 platform contracts end to end while keeping every
platform feature disabled by default, kill-switched, and evidence-required.

Compatibility-pair `green` closes the local runtime-pair validation gate only. Exact pins alone establish an unverified compatibility identity; evidence-backed model claims still require real hardware benchmark import through the evidence pipeline.

## Implementation principle

Implement the full scope, but activate nothing on hope.

The train is:

```text
Safety -> Contracts -> Admission -> Run Ledger -> Evidence -> Context Memory -> Snapshots -> Optimization -> Speculation -> Platform
```

The first visible product milestone is:

Pines can tell the user exactly which context length is safe for a local model on this phone, why that limit was chosen, whether it is verified, and then run without fatal, zeros, surprise cloud fallback, or unbudgeted KV duplication.
