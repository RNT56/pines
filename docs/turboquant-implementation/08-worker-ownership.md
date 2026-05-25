# Worker Ownership

This document assigns repo lanes, worker cards, file ownership, merge dependencies, and PR requirements. It is designed to allow parallel work without agents fighting over central files.

Use [Worker Launch Schedule](14-worker-launch-schedule.md) for executable order. This file is the ownership and dependency reference that keeps each wave safe.

Use [PR and Merge Plan](15-pr-merge-plan.md) for target branches, worker PR order, wave promotion, and final default-branch merge gates.

## Primary executable structure

| Wave | Workers | Parallelism |
| --- | --- | --- |
| Wave 0 | W25, W0, W20, W21, W4, W1, W7, W24 | start immediately in parallel, except compatibility-pair promotion is W0-owned |
| Wave 1 | W2, W5, W8, W9, W10 skeleton, W22 skeleton, W23 skeleton | parallel after W1/W4/W7/W24 are usable |
| Wave 2 | INT-1, INT-2A | serialized integration |
| Wave 3 | W3, W6, W10 full, W22 full, W23 full, W12, real-device runner | parallel evidence activation after bridge integration |
| Wave 3.5 | INT-2B | serialized production pin promotion |
| Wave 4 | W11, W14A, W14B, W17, iOS lifecycle policy | parallel after evidence gate |
| Wave 5 | W13, optimization evidence update | gated optimization after measurement exists |
| Wave 6 | W15A, W15B, W29+ | speculative and platform work after rollback/cache proof |
| Wave 7 | W29-core, W29-lm, W29-pines | platform-unlock contracts after Wave 6 |

The tables below preserve worker ownership and scope. They are grouped by earliest legal launch window.

## Lanes

- Coordination lane
- Core MLX lane
- LM cache/model lane
- Pines control-plane lane
- Evidence lane
- UX lane
- Persistence lane
- Optimization lane
- Platform lane

## Wave 0 - immediate start workers

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| W25 | all | MVP 0 | P0 | `tq/current-state-reconciliation` | current-state reconciliation |
| W0 | all | MVP 0 | P0 | `tq/release-train` | release train and compatibility pair |
| W20 | all | MVP 0 | P0 | `tq/schema-registry` | schema registry |
| W21 | all | MVP 0/1 | P0 | `tq/failure-matrix` | failure matrix |
| W4 | `mlx-swift-lm` | MVP 0 | P0 | `tq/lm-typed-errors-no-zero` | remove zero/fatal, typed errors |
| W1 | `mlx-swift` | MVP 0 | P0 | `tq/core-contracts` | core public contracts |
| W7 | `pines` | MVP 0 | P0 | `tq/pines-contract-shims` | local DTO shims |
| W24 | `pines` | MVP 0/1 | P0 | `tq/mode-fallback-contract` | mode/fallback contract |

## Wave 1 - control-plane building blocks

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| W2 | `mlx-swift` | MVP 1 | P1 | `tq/core-validation-router` | validation/router |
| W5 | `mlx-swift-lm` | MVP 1 | P1 | `tq/lm-cache-lifecycle` | cache lifecycle/runtime snapshot |
| W8 | `pines` | MVP 1 | P0 | `tq/pines-admission` | admission service |
| W9 | `pines` | MVP 1 | P0 | `tq/pines-run-decision` | RunDecision ledger |
| W10-skeleton | `pines` | MVP 1.5 | P1 | `tq/pines-evidence-store` | ProfileEvidenceStore schema skeleton |
| W22-skeleton | `mlx-swift-lm`, `pines` | MVP 1.5 | P1 | `tq/quality-gates` | QualityGate type and suite IDs |
| W23-skeleton | `pines` | MVP 1.5 | P1 | `tq/memory-calibration` | calibration sample schema |

## Wave 2 - serialized integration

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| INT-1 | `pines` | MVP 1 | P0 | `tq/integration-runtime-bridge` | runtime bridge integration |
| INT-2A | `pines` | MVP 1 | P0 | `tq/integration-pin-mlx-validation` | compatibility-branch pin validation |

These workers are intentionally serialized. They should not run concurrently with unrelated bridge/pin edits.

## Wave 3 - evidence activation

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| W3 | `mlx-swift` | MVP 1.5 | P1 | `tq/core-benchmark-json` | benchmark JSON and hidden-copy audit |
| W6 | `mlx-swift-lm` | MVP 1.5 | P1 | `tq/lm-profile-v2` | profile schema v2 |
| W10-full | `pines` | MVP 1.5 | P1 | `tq/pines-evidence-store` | full ProfileEvidenceStore importer |
| W22-full | `mlx-swift-lm`, `pines` | MVP 1.5 | P1 | `tq/quality-gates` | full quality gates and evidence levels |
| W23-full | `pines` | MVP 1.5 | P1 | `tq/memory-calibration` | full memory calibration and p95 multiplier |
| W12 | `pines` | MVP 1/1.5 | P1 | `tq/pines-compatibility-ui` | compatibility UI |
| Real-device runner | `pines` | MVP 1.5 | P1 | `tq/pines-device-acceptance-runner` | one verified tuple |

## Wave 3.5 - production pin promotion

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| INT-2B | `pines` | MVP 1.5 | P0 | `tq/integration-pin-mlx-production` | production pin update |

## Wave 4 - after MVP 1.5

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| W11 | `pines` | MVP 2 | P2 | `tq/context-memory-v1` | context planner v1 |
| W14A | `mlx-swift-lm` | MVP 3 | P2 | `tq/lm-kv-snapshots` | KV snapshot export/import |
| W14B | `pines` | MVP 3 | P2 | `tq/pines-kv-snapshots` | encrypted snapshot store |
| W17 | `pines` | MVP 3 | P2 | `tq/snapshot-security` | snapshot security |
| iOS lifecycle workers | `pines` | MVP 2/3 | P2 | varied | memory warning, thermal, suspend/resume, cancellation policy |

## Wave 5 - optimization

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| W13 | `mlx-swift` | MVP 4 | P2 | `tq/layout-v5-kernels` | layout V5/kernels |
| Optimization evidence update | all | MVP 4 | P2 | varied | before/after benchmark evidence |

## Wave 6 - later workers

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| W15A | `mlx-swift-lm` | MVP 5 | P3 | `tq/lm-speculative` | speculative verifier |
| W15B | `pines` | MVP 5 | P3 | `tq/pines-speculative` | speculative UX |
| W29+ | all | MVP 6 | P3 | varied | adaptive precision, memory, agents, open format, mesh |

## Wave 7 - platform unlock contracts

| Worker | Repo | Phase | Priority | Branch | Task |
| --- | --- | --- | --- | --- | --- |
| W29-core | `mlx-swift` | MVP 6 | P3 | `tq/wave7-core-platform` | adaptive precision/open-KV capability contracts |
| W29-lm | `mlx-swift-lm` | MVP 6 | P3 | `tq/wave7-lm-platform` | LM platform policy/open-KV identity contracts |
| W29-pines | `pines` | MVP 6 | P3 | `tq/wave7-platform-unlocks` | platform gates, admission reserves, evidence dimensions |

## File ownership map

| File/area | Owner |
| --- | --- |
| `project.yml` | W0 / INT-2A / INT-2B only |
| `Package.resolved` | W0 / INT-2A / INT-2B only |
| `Pines.xcodeproj` | INT-2A / INT-2B only |
| release train docs | W0 |
| schema registry docs/types | W20 |
| failure matrix docs/types | W21 |
| `Source/MLX/TurboQuantContracts.swift` | W1 |
| `Source/MLX/TurboQuantValidation.swift` | W2 |
| `Source/MLX/TurboQuantAttentionRouter.swift` | W2 |
| MLX benchmark report files | W3 |
| MLX hidden-copy audit docs | W3 / W13 |
| `Libraries/MLXLMCommon/AttentionUtils.swift` | W4 |
| `Libraries/MLXLMCommon/TurboQuantKVCache.swift` | W5 / W14A |
| LM profile JSON | W6 |
| existing `RuntimeTypes.swift` TurboQuant DTOs | W7 |
| existing `RuntimeTypes.swift` `TurboQuantUserMode` | W24 |
| `TurboQuantFallbackContract.swift` | W24 |
| `LocalRuntimeAdmissionService.swift` | W8 |
| `RuntimeMemoryZones.swift` | W8 |
| `TurboQuantRunDecision.swift` | W9 |
| Profile evidence persistence | W10 |
| Quality gate harness | W22 |
| Memory calibration persistence | W23 |
| compatibility UI | W12 |
| `MLXRuntimeBridge.swift` | INT-1 only |
| Context memory planner | W11 |
| KV snapshot store | W14B/W17 |
| TurboQuant kernels/Layout V5 | W13 only |
| W29+ platform contracts | W29-core / W29-lm / W29-pines by repo |

## Merge dependency graph

```text
W4 LM typed errors
  -> INT-1 bridge error mapping

W1 core contracts
  -> W2 validation/router
  -> W3 benchmark JSON
  -> INT-2A compatibility validation

W7 Pines shims
  -> W8 admission
  -> W9 RunDecision
  -> W10 evidence
  -> W12 UI

W24 mode/fallback
  -> W8 admission
  -> W10 evidence fallback hash

W8 admission + W9 RunDecision
  -> INT-1 bridge

W3 benchmark JSON + W10 evidence + W22 quality + W23 memory calibration
  -> MVP 1.5 evidence gate

W5 cache lifecycle
  -> INT-1 RunDecision snapshot
  -> W14A snapshots

MVP 1.5 evidence gate
  -> W11 context planner activation
  -> W13 layout V5 activation
  -> W14 snapshots activation

W14 snapshots
  -> W15 speculative decode
```

## PR rules

Every PR must include:

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

## Worker constraints

- Add new files before editing central files.
- PinesCore must remain MLX-free.
- Use adapter/shim types in Pines before MLX pins are promoted.
- Do not edit `MLXRuntimeBridge.swift` outside INT-1.
- Do not edit `project.yml` or generated project files outside INT-2A/INT-2B.
- Do not start layout V5 activation before benchmark JSON and quality gates exist.
- Do not start snapshot activation before lifecycle/runtime snapshot exists.
- Do not start speculative activation before rollback-safe cache append is proven.
