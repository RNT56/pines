# Worker Launch Schedule

This is the primary execution order for the TurboQuant implementation train. The detailed worker cards and task inventory remain authoritative for scope, but agents should use this schedule first to decide what can start, what is blocked, what can run in parallel, and what must be serialized.

## Execution model

The implementation is organized by waves.

Each wave defines:

- workers that can run in parallel;
- workers that are serialized;
- prerequisites;
- outputs;
- activation status;
- merge criteria;
- blockers for the next wave.

Feature implementation may happen behind disabled flags before product activation, but product activation must respect the release gates in [Validation and Release Gates](12-validation-and-release-gates.md).

## Global serialization rules

Some areas are intentionally serialized even if their surrounding wave is parallel:

| Area | Single owner |
| --- | --- |
| `pines/project.yml`, `Package.resolved`, generated Xcode project | INT-2A / INT-2B |
| `Pines/Runtime/MLXRuntimeBridge.swift` main generation flow | INT-1 |
| TurboQuant kernel source/layout implementation | W13 |
| LM product attention error behavior | W4 |
| release train and compatibility-pair state | W0 |

No other worker should edit these areas unless the release-train owner explicitly reassigns ownership.

## Wave 0 - Docs, contracts, and safety can start immediately

Purpose:

Set the rails so later work can proceed in parallel without contract drift.

Workers in this wave can start in parallel:

| Worker | Repo | Branch | Primary doc | Output |
| --- | --- | --- | --- | --- |
| W25 | all | `tq/current-state-reconciliation` | [Current State](00-current-state.md) | reconciled current repo heads, pins, blockers |
| W0 | all | `tq/release-train` | [Release Train](01-release-train.md) | compatibility-pair ownership, sign-off state |
| W20 | all | `tq/schema-registry` | [Schema Registry](02-schema-registry.md) | schema constants, envelope rules, migration stubs |
| W21 | all | `tq/failure-matrix` | [Failure Matrix](03-failure-matrix.md) | typed failure matrix and behavior map |
| W4 | `mlx-swift-lm` | `tq/lm-typed-errors-no-zero` | LM [Runtime Failures](/Users/mt/Programming/Schtack/mlx-forks/mlx-swift-lm/docs/turboquant-implementation/runtime-failures.md) | no product zero/fatal, typed failures |
| W1 | `mlx-swift` | `tq/core-contracts` | Core [Contracts](/Users/mt/Programming/Schtack/mlx-forks/mlx-swift/docs/turboquant-implementation/core-contracts.md) | capabilities, storage estimate, attention decision |
| W7 | `pines` | `tq/pines-contract-shims` | [Worker Ownership](08-worker-ownership.md) | Pines MLX-independent DTO shims |
| W24 | `pines` | `tq/mode-fallback-contract` | [Mode and Fallback Contract](04-mode-fallback-contract.md) | user modes and fallback contract |

Parallelization notes:

- W4 and W1 are independent and should start immediately.
- W7 can start before W1 merges because Pines uses local DTO shims.
- W24 can start independently of MLX contracts.
- W20 and W21 should coordinate names with W7/W24 but do not block initial code.

Wave 0 exit criteria:

- product-path fatal/zero behavior is removed or impossible from Pines-facing paths;
- core contracts compile and test without Metal;
- Pines DTO shims build without importing MLX;
- mode/fallback contract tests pass;
- schema registry and failure matrix exist;
- compatibility-pair manifest exists and remains pending or green.

Blocks:

- W8 admission should not merge until W24 mode/fallback contract is usable.
- INT-1 should not start until W4, W7, W8, and W9 are usable.
- INT-2B production pinning must not happen in this wave.

## Wave 1 - Control-plane building blocks

Purpose:

Build the pieces that admission and RunDecision need before central bridge integration.

Workers that can run in parallel after the named prerequisites:

| Worker | Repo | Branch | Prerequisites | Output |
| --- | --- | --- | --- | --- |
| W2 | `mlx-swift` | `tq/core-validation-router` | W1 | validators and path router |
| W5 | `mlx-swift-lm` | `tq/lm-cache-lifecycle` | W4 partially usable | cache lifecycle and runtime snapshot |
| W8 | `pines` | `tq/pines-admission` | W7, W24 | admission service and memory zones |
| W9 | `pines` | `tq/pines-run-decision` | W7, W8 types | RunDecision ledger |
| W10-skeleton | `pines` | `tq/pines-evidence-store` | W20, W7 | evidence store schema skeleton |
| W22-skeleton | `mlx-swift-lm`, `pines` | `tq/quality-gates` | W20 | QualityGate type and suite IDs |
| W23-skeleton | `pines` | `tq/memory-calibration` | W8 memory zones | calibration sample schema |

Parallelization notes:

- W2 and W5 are independent after W1/W4.
- W8 and W9 can run in parallel once W7/W24 define local types, but W9 should allow `admission: nil` until W8 lands.
- W10/W22/W23 can create schemas and storage shells early; full evidence activation waits for Wave 3.

Wave 1 exit criteria:

- bad compressed layout fails before Metal dispatch;
- LM cache lifecycle snapshot is queryable;
- admission produces deterministic admitted/rejected plans;
- memory zones are included in admission;
- RunDecision encodes selected path, fallback, lifecycle, and bytes fields;
- evidence/quality/calibration skeletons compile.

Blocks:

- INT-1 cannot merge without W8 and W9.
- W3 benchmark import activation waits for W10/W22 schema stability.

## Wave 2 - Serialized runtime integration

Purpose:

Wire the new control plane into the real local generation path. This is serialized to avoid competing edits in `MLXRuntimeBridge`.

Serialized workers:

| Worker | Repo | Branch | Prerequisites | Output |
| --- | --- | --- | --- | --- |
| INT-1 | `pines` | `tq/integration-runtime-bridge` | W4, W7, W8, W9; W5 if lifecycle is ready | admission before generation, typed error mapping, RunDecision metadata |
| INT-2A | `pines` | `tq/integration-pin-mlx-validation` | INT-1, W1, W4; candidate MLX commits | compatibility-branch pin validation |

INT-1 required flow:

```text
route policy
  -> minimal ContextAssemblyPlan.v1
  -> device/memory probe
  -> mode/fallback contract
  -> admission
  -> reject/downgrade or run
  -> exact prefill
  -> compressed commit
  -> compressed-domain decode
  -> budgeted fallback only
  -> RunDecision + calibration sample
  -> finish or typed failure
```

INT-2A required behavior:

- update pins only on a compatibility branch;
- run validation commands;
- update `compatibility-pair.json`;
- do not promote production pins unless evidence gates pass.

Wave 2 exit criteria:

- unsafe local run rejects before generation;
- successful local run emits RunDecision;
- local failure emits typed stream failure and partial RunDecision when possible;
- cloud route is never used without explicit route policy;
- compatibility pair can be validated on branch.

Blocks:

- evidence UI must not show Verified until Wave 3 passes.
- production pin update INT-2B waits for real-device evidence.

## Wave 3 - Evidence activation and compatibility UI

Purpose:

Turn runtime facts into measured support claims.

Workers can run in parallel after Wave 2 bridge integration exists:

| Worker | Repo | Branch | Prerequisites | Output |
| --- | --- | --- | --- | --- |
| W3 | `mlx-swift` | `tq/core-benchmark-json` | W1, W2 | core benchmark JSON and hidden-copy audit |
| W6 | `mlx-swift-lm` | `tq/lm-profile-v2` | W4; W1 if profile paths reference core enums | model profile v2 and mismatch reasons |
| W10-full | `pines` | `tq/pines-evidence-store` | W10 skeleton, W3 schema | benchmark importer and evidence lookup |
| W22-full | `mlx-swift-lm`, `pines` | `tq/quality-gates` | W22 skeleton, benchmark output | QualityGate metrics and evidence levels |
| W23-full | `pines` | `tq/memory-calibration` | INT-1, W23 skeleton | planned-vs-actual calibration and p95 multiplier |
| W12 | `pines` | `tq/pines-compatibility-ui` | W8, W9, W10 skeleton | compatibility UI states and technical drawer |
| Real-device runner | `pines` | `tq/pines-device-acceptance-runner` | INT-1, W10, W22, W23 | one verified tuple |

Parallelization notes:

- W3 can proceed while W6 works on profile validation.
- W10 can implement importer against schema before all benchmark producers are final.
- W12 can show Conservative/Unverified first, but Verified remains disabled until evidence passes.

Wave 3 exit criteria:

- benchmark JSON imports;
- QualityGate must pass for Verified;
- memory calibration sample exists;
- evidence includes fallback contract hash and compatibility-pair ID;
- at least one real-device tuple is verified;
- hidden-copy audit exists;
- compatibility UI uses evidence levels correctly.

Blocks:

- INT-2B production pin update waits for this wave.
- MVP 2+ product activation waits for this wave.

## Wave 3.5 - Production pin promotion

Purpose:

Promote the validated compatibility pair to production pins after evidence.

Serialized worker:

| Worker | Repo | Branch | Prerequisites | Output |
| --- | --- | --- | --- | --- |
| INT-2B | `pines` | `tq/integration-pin-mlx-production` | INT-2A green, Wave 3 evidence tuple | production `project.yml`, `Package.resolved`, generated project, status docs |

Exit criteria:

- `compatibility-pair.json` status is green;
- production pins match the validated pair;
- existing docs/status files are synchronized;
- validation commands pass.

## Wave 4 - Context and persistence

Purpose:

Build the memory layer after the control plane and evidence loop are trustworthy.

Workers can run in parallel after Wave 3:

| Worker | Repo | Branch | Prerequisites | Output |
| --- | --- | --- | --- | --- |
| W11 | `pines` | `tq/context-memory-v1` | INT-1, W8 | full ContextAssemblyPlan.v1 |
| W14A | `mlx-swift-lm` | `tq/lm-kv-snapshots` | W5 | snapshot export/import |
| W14B | `pines` | `tq/pines-kv-snapshots` | W14A contract, W10, W11 minimal | encrypted snapshot store |
| W17 | `pines` | `tq/snapshot-security` | W14B | key rotation, atomic writes, quarantine, quota |
| iOS lifecycle workers | `pines` | varied | INT-1 | memory warning, thermal, suspend/resume, cancellation policy |

Parallelization notes:

- W11 does not need snapshot export/import to start.
- W14B can build manifest/store before W14A export is fully wired, but restore activation waits for W14A.
- W17 can implement policy/storage hardening after the store shape exists.

Wave 4 exit criteria:

- context plan records pinned/recent/retrieved/summary/dropped segments;
- semantic memory and KV pages are distinct;
- vault cloud-boundary approvals are enforced;
- snapshot export/import roundtrips;
- snapshots are encrypted and atomic;
- invalid snapshots fail closed.

## Wave 5 - Optimization

Purpose:

Optimize only after the measurement loop can prove improvement and catch regressions.

Workers:

| Worker | Repo | Branch | Prerequisites | Output |
| --- | --- | --- | --- | --- |
| W13 | `mlx-swift` | `tq/layout-v5-kernels` | W3, W22, W23 | Layout V5, kernel warmup, fused specializations |
| Optimization evidence update | all | varied | W13 | before/after benchmark evidence |

Wave 5 exit criteria:

- hidden-copy audit passes;
- Layout V5 remains feature-gated;
- V4 compatibility remains;
- V5 improves speed or actual bits/value;
- QualityGate remains green;
- unsupported dims fall back safely.

## Wave 6 - Speculative decode and platform unlocks

Purpose:

Add speed and platform capabilities after compressed cache rollback and evidence are reliable.

Workers:

| Worker | Repo | Branch | Prerequisites | Output |
| --- | --- | --- | --- | --- |
| W15A | `mlx-swift-lm` | `tq/lm-speculative` | W14A, W5 | target verifier and rollback-safe append |
| W15B | `pines` | `tq/pines-speculative` | W15A, W12 | Fast mode UX and acceptance telemetry |
| W29+ | all | varied | Wave 5/6 gates | adaptive precision, semantic/multimodal memory, agents, open format, mesh |

Wave 6 exit criteria:

- accepted speculative tokens match target;
- rejected tokens do not corrupt cache;
- poor acceptance disables speculation;
- Fast mode improvement is evidence-backed.

## Quick start recommendation

If starting implementation now, launch these in parallel:

1. W4 in `mlx-swift-lm`.
2. W1 in `mlx-swift`.
3. W7 in `pines`.
4. W24 in `pines`.
5. W20/W21 if schema/failure code is not already present.

Then launch:

1. W8 admission.
2. W9 RunDecision.
3. W2 validation/router.
4. W5 lifecycle.

Then serialize:

1. INT-1 runtime bridge.
2. INT-2A compatibility validation.

## What not to start as active product work yet

Do not activate:

- Layout V5;
- adaptive precision;
- KV snapshots;
- speculative decode;
- agent memory;
- open format;
- device mesh;

until their prerequisite waves pass. Implementation behind disabled flags is allowed if it does not create integration drift.
