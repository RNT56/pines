# Release Train

This document owns the multi-repo release train. It prevents agents from landing incompatible contracts, moving pins without validation, or activating features before evidence exists.

## Release train artifacts

Required artifacts:

- `docs/turboquant-implementation/00-current-state.md`
- `docs/turboquant-implementation/01-release-train.md`
- `docs/turboquant-implementation/compatibility-pair.schema.json`
- `docs/turboquant-implementation/compatibility-pair.json`
- repo-local implementation docs in `mlx-swift` and `mlx-swift-lm`

## Compatibility-pair ownership

The compatibility pair is the validated triplet:

```text
Pines commit + MLXSwift commit + MLXSwiftLM commit
```

W0 owns the compatibility-pair files, but promotion to `green` requires sign-off from:

1. MLX core contracts owner;
2. LM typed-error owner;
3. Pines runtime bridge integration owner.

No single worker may unilaterally promote or production-pin a pair.

## Pin update split

Pin movement is split into two integrations:

### INT-2A: compatibility-branch MLX pin validation

Purpose:

- prove a candidate MLX pair compiles against Pines;
- run build/test validation;
- update `compatibility-pair.json` with result;
- do not treat this as production-pinned until evidence gates pass.

### INT-2B: production pin update

Purpose:

- update `project.yml`;
- update `Package.resolved`;
- regenerate `Pines.xcodeproj`;
- update existing status docs;
- commit only after compatibility branch and at least one real-device evidence tuple pass.

## Release ladder

### MVP 0 - Contract and safety freeze

Goal:

Remove unsafe behavior and create stable cross-repo contracts.

Exit gate:

- no product-facing zero output;
- no product-facing fatal;
- versioned schemas exist;
- failure matrix exists;
- core contracts exist;
- Pines shims build;
- no production pin update unless compatibility branch is green.

### MVP 1 - Control-plane long-context runtime

Goal:

Pines can admit or reject local long-context generation before running.

Exit gate:

- admission runs before generation;
- memory zones are recorded;
- mode-specific fallback policy exists;
- typed MLX errors map to typed Pines stream failures;
- RunDecision metadata is attached;
- basic compatibility UI exists;
- no silent cloud fallback.

### MVP 1.5 - Evidence and verification loop

Goal:

Support claims become measured, not optimistic.

Exit gate:

- benchmark JSON imports;
- QualityGate passes;
- memory estimate-vs-actual calibration exists;
- at least one model/device/mode tuple is verified on a real device;
- compatibility UI shows verified/unverified correctly.

### MVP 2 - Context virtualization v1

Goal:

Replace blunt truncation with segment-aware context assembly.

Exit gate:

- pinned, recent, retrieved, summarized, and dropped segments are recorded;
- user can see what was included or removed;
- warm KV pages are never treated as semantic retrieval chunks;
- vault context respects local/cloud boundaries.

### MVP 3 - Persistent private workspace

Goal:

Valid compressed KV snapshots enable instant resume.

Exit gate:

- snapshot export/import roundtrips;
- snapshots are encrypted;
- writes are atomic;
- invalid snapshots fail closed;
- model/tokenizer/profile/RoPE/prefix mismatch invalidates restore;
- deletion/export behavior is correct.

### MVP 4 - Kernel/storage optimization

Goal:

Improve actual bits/value and decode speed after measurement exists.

Exit gate:

- hidden-copy audit passes;
- kernel warmup exists;
- Layout V5 is gated;
- popcount offset path is benchmarked;
- fused specializations prove improvement;
- quality gates remain green.

### MVP 5 - Speculative TurboQuant

Goal:

Make local long-context decode feel interactive.

Exit gate:

- tentative cache append is rollback-safe;
- accepted tokens match target;
- poor acceptance disables speculation;
- Fast mode improves p50 decode speed.

### MVP 6 - Platform unlocks

Queued after the above:

- adaptive precision;
- semantic memory store;
- multimodal memory;
- agent working memory;
- open TurboQuant format;
- device mesh;
- personalization/adapters.

## Executable wave schedule

The release ladder defines product gates. The worker launch schedule defines executable order.

Use [Worker Launch Schedule](14-worker-launch-schedule.md) as the primary launch document:

| Wave | Can run in parallel | Serialized pieces | Gate produced |
| --- | --- | --- | --- |
| Wave 0 | W25, W0, W20, W21, W4, W1, W7, W24 | compatibility-pair promotion remains W0-owned | MVP 0 rails |
| Wave 1 | W2, W5, W8, W9, W10 skeleton, W22 skeleton, W23 skeleton | none except file ownership rules | control-plane building blocks |
| Wave 2 | none | INT-1, then INT-2A | bridge integration and branch validation |
| Wave 3 | W3, W6, W10 full, W22 full, W23 full, W12, real-device runner | Verified UI activation waits for evidence | MVP 1.5 evidence |
| Wave 3.5 | none | INT-2B | production pin promotion |
| Wave 4 | W11, W14A, W14B, W17, iOS lifecycle work | snapshot restore activation waits for W14A/W17 | context and persistence |
| Wave 5 | W13 plus evidence update | Layout V5 activation waits for benchmark/quality | optimization |
| Wave 6 | W15A, W15B, W29+ | speculative activation waits for rollback proof | speed and platform |

Rules:

- A later-wave feature may be implemented behind a disabled flag, but it may not become product-active until its prerequisite wave gate passes.
- Central bridge and pin-update work remain serialized even when surrounding worker lanes run in parallel.
- The complete backlog remains in [Complete Task Inventory](13-complete-task-inventory.md); wave order decides launch timing.

## Strict integration sequence

1. W4 removes zero/fatal.
2. W1 publishes core contracts.
3. W7 adds Pines shims.
4. W24 fixes mode/fallback semantics.
5. W8 adds admission.
6. W9 adds RunDecision.
7. INT-1 wires runtime bridge.
8. W3/W10/W22/W23 add evidence loop.
9. INT-2A validates compatible MLX pair on a branch.
10. One real-device tuple is verified.
11. INT-2B updates production pins.
12. MVP 2+ begins activation.

Implementation of later features behind disabled flags is allowed, but activation must not bypass this order.

## Branch naming

Use short-lived branches:

| Branch | Repo | Purpose |
| --- | --- | --- |
| `tq/current-state-reconciliation` | all | record observed state |
| `tq/release-train` | all | release train docs |
| `tq/schema-registry` | all | versioned schema contracts |
| `tq/failure-matrix` | all | failure matrix and typed failures |
| `tq/core-contracts` | `mlx-swift` | public core contracts |
| `tq/core-validation-router` | `mlx-swift` | validators and path router |
| `tq/core-benchmark-json` | `mlx-swift` | benchmark output and hidden-copy audit |
| `tq/lm-typed-errors-no-zero` | `mlx-swift-lm` | app-safe failures |
| `tq/lm-cache-lifecycle` | `mlx-swift-lm` | lifecycle and runtime snapshot |
| `tq/lm-profile-v2` | `mlx-swift-lm` | model profile validator |
| `tq/pines-contract-shims` | `pines` | MLX-independent DTOs |
| `tq/mode-fallback-contract` | `pines` | modes and fallback contracts |
| `tq/pines-admission` | `pines` | admission service |
| `tq/pines-run-decision` | `pines` | run ledger |
| `tq/pines-evidence-store` | `pines` | evidence persistence |
| `tq/quality-gates` | `mlx-swift-lm`, `pines` | correctness gates |
| `tq/memory-calibration` | `pines` | calibration samples |
| `tq/pines-compatibility-ui` | `pines` | UI states |
| `tq/integration-runtime-bridge` | `pines` | bridge integration |
| `tq/integration-pin-mlx-validation` | `pines` | INT-2A |
| `tq/integration-pin-mlx-production` | `pines` | INT-2B |

## Worker PR checklist

Every worker PR must include:

```text
Scope:
Owned files:
Files intentionally not touched:
Contracts used:
Schemas changed:
Feature flags:
Tests added:
Manual validation:
Known follow-up:
Activation status: disabled / debug / conservative / verified
Compatibility-pair impact:
```

## Activation states

| State | Meaning |
| --- | --- |
| `disabled` | implementation may exist but cannot be used in product |
| `debug` | manually testable only in debug/developer surfaces |
| `conservative` | allowed with reduced claims and safe defaults |
| `verified` | evidence-backed for model/device/mode tuple |
| `certified` | broader release-grade evidence and regression monitoring |
| `revoked` | previously valid evidence invalidated by regression or incompatibility |

Only `verified` and `certified` can support product compatibility claims.
