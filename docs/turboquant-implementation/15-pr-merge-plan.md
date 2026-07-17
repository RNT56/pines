# PR and Merge Plan

This document defines how worker branches become reviewed PRs, how waves are promoted, and how the three repos are finally synchronized. The goal is to avoid one giant cross-repo PR while still preserving a single compatibility truth.

## Target integration branches

Worker branches target the current implementation branches, not default branches directly:

| Repo | Worker PR target | Purpose |
| --- | --- | --- |
| `pines` | `codex/local-runtime-hardening` | mobile control plane and compatibility integration |
| `mlx-swift` | `codex/turboquant-core-completion` | primitive/kernel/runtime contracts |
| `mlx-swift-lm` | `codex/turboquant-completion-hardening` | model/cache integration |

These branches are the cross-repo integration surfaces. Final merge to each repo's default branch happens only after release gates pass.

## Branch and PR types

### Worker PR

Small PR from one worker branch into the repo integration branch.

Examples:

- `tq/lm-typed-errors-no-zero` -> `codex/turboquant-completion-hardening`
- `tq/core-contracts` -> `codex/turboquant-core-completion`
- `tq/pines-admission` -> `codex/local-runtime-hardening`

Rules:

- touches owned files only unless explicitly declared;
- includes tests for its scope;
- updates docs when contracts change;
- leaves product activation disabled unless its wave gate permits activation.

### Wave promotion

Wave promotion is not always a separate PR. It is the review point after all worker PRs in a wave merge.

Wave promotion updates:

- release train status;
- compatibility-pair status when applicable;
- schema registry if new schemas landed;
- failure matrix if failure behavior changed;
- validation notes.

### Cross-repo compatibility PR

Pines-only integration PR that validates exact MLX fork commits.

Two phases:

- INT-2A: compatibility-branch pin validation;
- INT-2B: production pin promotion.

### Final repo PR

After the cross-repo gates pass, each integration branch can be merged into its repo default branch through the repo's normal PR flow.

## PR checklist

Every worker PR must include:

```text
Scope:
Wave:
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

## Wave 0 PR plan

Purpose:

Safety, contracts, and app shims.

Parallel worker PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| all | `tq/current-state-reconciliation` | current repo integration branch | current-state doc updated |
| all | `tq/release-train` | current repo integration branch | compatibility-pair doc present |
| all | `tq/schema-registry` | current repo integration branch | schema registry tests/stubs |
| all | `tq/failure-matrix` | current repo integration branch | failure kinds mapped |
| `mlx-swift-lm` | `tq/lm-typed-errors-no-zero` | `codex/turboquant-completion-hardening` | no product zero/fatal path |
| `mlx-swift` | `tq/core-contracts` | `codex/turboquant-core-completion` | public contracts compile and test |
| `pines` | `tq/pines-contract-shims` | `codex/local-runtime-hardening` | PinesCore MLX-free shims compile |
| `pines` | `tq/mode-fallback-contract` | `codex/local-runtime-hardening` | downgrade/fallback tests pass |

Recommended merge order:

1. docs/release/schema/failure PRs where needed;
2. `mlx-swift-lm` W4;
3. `mlx-swift` W1;
4. Pines W7;
5. Pines W24.

Wave 0 promotion gate:

- no product-facing zero output;
- no product-facing fatal path;
- core contracts exist;
- Pines shims build;
- mode/fallback contract exists;
- compatibility pair remains pending or green.

## Wave 1 PR plan

Purpose:

Build control-plane blocks before central bridge integration.

Parallel worker PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `mlx-swift` | `tq/core-validation-router` | `codex/turboquant-core-completion` | invalid layout fails before Metal |
| `mlx-swift-lm` | `tq/lm-cache-lifecycle` | `codex/turboquant-completion-hardening` | runtime snapshot queryable |
| `pines` | `tq/pines-admission` | `codex/local-runtime-hardening` | unsafe contexts reject before run |
| `pines` | `tq/pines-run-decision` | `codex/local-runtime-hardening` | RunDecision encodes successfully |
| `pines` | `tq/pines-evidence-store` skeleton | `codex/local-runtime-hardening` | schema/storage skeleton |
| `mlx-swift-lm` + `pines` | `tq/quality-gates` skeleton | repo integration branches | QualityGate type/suite IDs |
| `pines` | `tq/memory-calibration` skeleton | `codex/local-runtime-hardening` | calibration sample schema |

Recommended merge order:

1. `mlx-swift` W2;
2. `mlx-swift-lm` W5;
3. Pines W8;
4. Pines W9;
5. evidence/quality/calibration skeletons.

Wave 1 promotion gate:

- validators and router exist;
- cache lifecycle exists;
- admission can produce deterministic plan;
- memory zones are recorded;
- RunDecision is serializable;
- evidence/quality/calibration skeletons compile.

## Wave 2 PR plan

Purpose:

Serialized runtime integration.

Serialized PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `pines` | `tq/integration-runtime-bridge` | `codex/local-runtime-hardening` | admission before generation, typed failures, RunDecision metadata |
| `pines` | `tq/integration-pin-mlx-validation` | `codex/local-runtime-hardening` | exact candidate MLX pair validates on branch |

Merge order:

1. INT-1 runtime bridge integration.
2. INT-2A compatibility-branch pin validation.

Rules:

- no other PR edits `MLXRuntimeBridge.swift` while INT-1 is active;
- no other PR edits `project.yml`, `Package.resolved`, or generated Xcode project while INT-2A is active;
- INT-2A does not count as production pin promotion.

Wave 2 promotion gate:

- local run can reject before generation;
- typed failures reach stream/UI;
- successful local run emits RunDecision;
- local failure never silently routes to cloud;
- compatibility-pair JSON updated with validation result.

## Wave 3 PR plan

Purpose:

Evidence activation and compatibility UI.

Parallel worker PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `mlx-swift` | `tq/core-benchmark-json` | `codex/turboquant-core-completion` | stable JSON and hidden-copy audit |
| `mlx-swift-lm` | `tq/lm-profile-v2` | `codex/turboquant-completion-hardening` | profile mismatch fails closed |
| `pines` | `tq/pines-evidence-store` full | `codex/local-runtime-hardening` | benchmark importer and evidence lookup |
| `mlx-swift-lm` + `pines` | `tq/quality-gates` full | repo integration branches | quality metrics and evidence levels |
| `pines` | `tq/memory-calibration` full | `codex/local-runtime-hardening` | planned-vs-actual samples and p95 multiplier |
| `pines` | `tq/pines-compatibility-ui` | `codex/local-runtime-hardening` | conservative/unverified/verified UI states |
| `pines` | `tq/pines-device-acceptance-runner` | `codex/local-runtime-hardening` | real-device evidence export/import |

Recommended merge order:

1. `mlx-swift` W3;
2. `mlx-swift-lm` W6;
3. Pines W10 full importer;
4. W22 quality gates;
5. W23 memory calibration;
6. W12 compatibility UI;
7. real-device runner.

Wave 3 promotion gate:

- benchmark JSON imports;
- QualityGate passes for Verified;
- evidence includes compatibility-pair ID and fallback-contract hash;
- memory calibration sample exists;
- compatibility UI cannot show Verified without evidence;
- at least one real-device tuple is verified.

## Wave 3.5 PR plan

Purpose:

Production pin promotion.

Serialized PR:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `pines` | `tq/integration-pin-mlx-production` | `codex/local-runtime-hardening` | production pins match green compatibility pair |

Merge gate:

- INT-2A green;
- Wave 3 evidence tuple verified;
- `project.yml`, `Package.resolved`, generated Xcode project, existing status docs synchronized;
- validation commands pass.

## Wave 4 PR plan

Purpose:

Context virtualization and persistent workspace.

Parallel worker PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `pines` | `tq/context-memory-v1` | `codex/local-runtime-hardening` | pinned/recent/retrieved/summary/dropped segments |
| `mlx-swift-lm` | `tq/lm-kv-snapshots` | `codex/turboquant-completion-hardening` | export/import roundtrip |
| `pines` | `tq/pines-kv-snapshots` | `codex/local-runtime-hardening` | encrypted local snapshot store |
| `pines` | `tq/snapshot-security` | `codex/local-runtime-hardening` | key rotation, atomic writes, quarantine, quota |
| `pines` | iOS lifecycle branches | `codex/local-runtime-hardening` | memory/thermal/suspend/resume policy |

Recommended merge order:

1. W11 context planner;
2. W14A LM snapshot export/import;
3. W14B Pines snapshot store;
4. W17 snapshot security;
5. iOS lifecycle policy.

Wave 4 promotion gate:

- context plan is inspectable;
- semantic memory and KV pages remain distinct;
- snapshot restore fails closed;
- snapshots are encrypted and local by default;
- data deletion removes snapshots.

## Wave 5 PR plan

Purpose:

Optimization after measurement exists.

Worker PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `mlx-swift` | `tq/layout-v5-kernels` | `codex/turboquant-core-completion` | gated V5 improves speed or bytes |
| all relevant | optimization evidence update branches | repo integration branches | before/after benchmark evidence |

Merge gate:

- hidden-copy audit passes;
- Layout V5 disabled by default until evidence;
- V4 compatibility remains;
- QualityGate remains green;
- unsupported dims fall back safely.

## Wave 6 PR plan

Purpose:

Speculative decode and platform unlocks.

Worker PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `mlx-swift-lm` | `tq/lm-speculative` | `codex/turboquant-completion-hardening` | rollback-safe target verifier |
| `pines` | `tq/pines-speculative` | `codex/local-runtime-hardening` | Fast mode UX, acceptance telemetry |
| all | platform branches | repo integration branches | adaptive precision, memory, agents, open format, mesh |

Merge gate:

- accepted speculative tokens match target;
- rejected tokens do not corrupt cache;
- poor acceptance disables speculation;
- Fast mode improvement is evidence-backed.

## Wave 7 PR plan

Purpose:

Finish W29+/MVP 6 platform-unlock contracts without activating product claims.

Worker PRs:

| Repo | Branch | Target | Merge gate |
| --- | --- | --- | --- |
| `mlx-swift` | `tq/wave7-core-platform` | `codex/turboquant-core-completion` | adaptive/open-KV capability contracts compile and fail closed |
| `mlx-swift-lm` | `tq/wave7-lm-platform` | `codex/turboquant-completion-hardening` | LM platform policy/open-KV identity contracts compile and fail closed |
| `pines` | `tq/wave7-platform-unlocks` | `codex/local-runtime-hardening` | platform gates, admission reserves, evidence dimensions, persistence, and tests |

Merge gate:

- all Wave 7 contracts are Codable/Sendable and disabled by default;
- active platform states require evidence and clear kill switches;
- Pines evidence tuple matching includes platform dimensions;
- no production pin update or generated-project ownership change;
- compatibility-pair remains pending unless a separate release-train owner
  validates and promotes it.

## Hard merge gates

No worker PR merges unless:

- it touches owned files only, or declares integration ownership;
- relevant tests pass;
- schema/version changes update the schema registry;
- failure behavior maps to the failure matrix;
- product activation is behind flags unless evidence exists.

No Pines pin PR merges unless:

- MLX Swift target branch is green;
- MLX Swift LM target branch is green;
- Pines builds against the exact pair;
- `compatibility-pair.json` is updated;
- required sign-offs are recorded.

No final production merge unless:

- Wave 0 through Wave 3.5 gates pass;
- at least one real-device tuple is verified;
- no silent cloud fallback exists;
- no product fatal/zero path exists;
- admission and RunDecision are active;
- evidence-backed compatibility UI works.

## Final default-branch merge plan

After Wave 3.5:

1. Merge `mlx-swift` integration branch into its default branch.
2. Merge `mlx-swift-lm` integration branch into its default branch after it points at compatible MLX Swift behavior.
3. Merge `pines` integration branch after production pins point at the validated MLX commits.

If default-branch merge order is constrained by repo policy, keep Pines pinned to exact validated commits and update `compatibility-pair.json` with the final commit IDs after merge.

## Rollback plan

If a wave breaks after merge:

1. stop activation through feature flags;
2. revoke evidence if compatibility was affected;
3. update failure matrix or release-train notes;
4. revert only the offending worker PR if needed;
5. do not move production pins until validation is green again.

Kill switches:

- `TURBOQUANT_DISABLE`;
- force baseline;
- force packed;
- disable snapshots;
- disable adaptive precision;
- disable speculative;
- disable fused;
- disable bfloat.
