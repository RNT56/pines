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
3. [Schema Registry](02-schema-registry.md)
4. [Failure Matrix](03-failure-matrix.md)
5. [Mode and Fallback Contract](04-mode-fallback-contract.md)
6. [Memory Admission and Calibration](05-memory-admission-calibration.md)
7. [Quality Gates](06-quality-gates.md)
8. [Benchmark Evidence](07-benchmark-evidence.md)
9. [Worker Ownership](08-worker-ownership.md)
10. [Runtime Bridge Integration](09-runtime-bridge-integration.md)
11. [Context Memory Planner](10-context-memory-planner.md)
12. [KV Snapshot Security](11-kv-snapshot-security.md)
13. [Validation and Release Gates](12-validation-and-release-gates.md)
14. [Complete Task Inventory](13-complete-task-inventory.md)

Machine-readable compatibility-pair files:

- [compatibility-pair.schema.json](compatibility-pair.schema.json)
- [compatibility-pair.json](compatibility-pair.json)

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

## Implementation principle

Implement the full scope, but activate nothing on hope.

The train is:

```text
Safety -> Contracts -> Admission -> Run Ledger -> Evidence -> Context Memory -> Snapshots -> Optimization -> Speculation -> Platform
```

The first visible product milestone is:

Pines can tell the user exactly which context length is safe for a local model on this phone, why that limit was chosen, whether it is verified, and then run without fatal, zeros, surprise cloud fallback, or unbudgeted KV duplication.
