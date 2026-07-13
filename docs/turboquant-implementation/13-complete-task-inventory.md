# Complete Task Inventory

This file preserves the full backlog depth for the multi-worker implementation. It is intentionally detailed so workers can branch from this planning packet without reconstructing scope from chat history.

Use [Worker Launch Schedule](14-worker-launch-schedule.md) to decide execution order. This file is the complete scope catalogue.

## Executable wave index

| Wave | Launch condition | Workers/tasks |
| --- | --- | --- |
| Wave 0 | start immediately | W25, W0, W20, W21, W4, W1, W7, W24 |
| Wave 1 | W1/W4/W7/W24 usable | W2, W5, W8, W9, W10 skeleton, W22 skeleton, W23 skeleton |
| Wave 2 | W8/W9 ready and W4 safe | INT-1, INT-2A |
| Wave 3 | bridge integrated | W3, W6, W10 full, W22 full, W23 full, W12, real-device runner |
| Wave 3.5 | one verified tuple and green compatibility branch | INT-2B |
| Wave 4 | MVP 1.5 evidence gate passed | W11, W14A, W14B, W17, iOS lifecycle policy |
| Wave 5 | benchmark/quality/memory loop exists | W13, optimization evidence update |
| Wave 6 | rollback-safe compressed cache exists | W15A, W15B, platform backlog |
| Wave 7 | completed Wave 6 | W29-core, W29-lm, W29-pines platform contracts |

Inventory tables below retain the original task depth. If a task appears in a later queue, it can be implemented behind a disabled flag earlier only if it does not modify serialized files or product activation.

## P0 - Safety and contracts

| ID | Repo | Task |
| --- | --- | --- |
| W25 | all | Current-state reconciliation |
| W0 | all | Release train |
| W20 | all | Schema registry |
| W21 | all | Failure matrix |
| W4 | `mlx-swift-lm` | Remove zero/fatal |
| W1 | `mlx-swift` | Public contracts |
| W7 | `pines` | Local DTO shims |
| W24 | `pines` | Mode/fallback contract |
| W8 | `pines` | Admission service |
| W9 | `pines` | RunDecision |
| INT-1 | `pines` | Bridge integration |
| INT-2A | `pines` | Compatibility-branch pin validation |
| INT-2B | `pines` | Production pin update |

## Core MLX queue

| ID | Task |
| --- | --- |
| CORE-001 | Kernel capabilities |
| CORE-002 | Storage estimate |
| CORE-003 | Attention decision |
| CORE-004 | No-Metal defaults |
| CORE-005 | Contract tests |
| CORE-006 | Path router |
| CORE-007 | Rejected reasons |
| CORE-008 | dtype/mask/head gates |
| CORE-009 | Hidden-copy audit |
| CORE-010 | `ensure_row_contiguous` review |
| CORE-011 | Kernel warmup |
| CORE-012 | Cold/warm metrics |
| CORE-013 | Layout V5 |
| CORE-014 | Deterministic high mask |
| CORE-015 | Popcount offsets |
| CORE-016 | fp16 scales |
| CORE-017 | V4 compatibility |
| CORE-018 | Fused dim 64 |
| CORE-019 | Fused dim 80 |
| CORE-020 | Fused dim 96 |
| CORE-021 | Fused dim 128 |
| CORE-022 | Fused dim 192 |
| CORE-023 | Fused dim 256 |
| CORE-024 | bfloat gate |
| CORE-025 | Value decode tiling |
| CORE-026 | No full K/V hot path |
| CORE-027 | Benchmark JSON |
| CORE-028 | Quality A/B report |
| CORE-029 | TurboQuant linear remains gated |
| CORE-030 | Open-format prep |

## MLX-LM queue

| ID | Task |
| --- | --- |
| LM-001 | Typed errors |
| LM-002 | Throwing product path |
| LM-003 | Forced-failure tests |
| LM-004 | Cache lifecycle |
| LM-005 | Runtime snapshot |
| LM-006 | Budgeted fallback |
| LM-007 | Layer-local fallback |
| LM-008 | Exact prefill invariant |
| LM-009 | Profile schema v2 |
| LM-010 | Profile mismatch reasons |
| LM-011 | Model benchmark JSON |
| LM-012 | Quality gate outputs |
| LM-013 | Cache expansion tests |
| LM-014 | Ring offset tests |
| LM-015 | Pinned prefix tests |
| LM-016 | GQA/MQA tests |
| LM-017 | Unsupported mask tests |
| LM-018 | Snapshot export |
| LM-019 | Snapshot import |
| LM-020 | Snapshot roundtrip logits |
| LM-021 | Speculative verifier |
| LM-022 | Rollback append |
| LM-023 | Acceptance metrics |

## Pines MVP queue

| ID | Task |
| --- | --- |
| PINES-001 | Local TurboQuant DTOs |
| PINES-002 | MLX adapter shell |
| PINES-003 | Typed failures |
| PINES-004 | No silent cloud check |
| PINES-005 | Admission service |
| PINES-006 | Memory zones |
| PINES-007 | Available memory |
| PINES-008 | Model bytes estimate |
| PINES-009 | Raw KV estimate |
| PINES-010 | Compressed KV estimate |
| PINES-011 | Fallback reserve |
| PINES-012 | Metal scratch reserve |
| PINES-013 | Vault reserve |
| PINES-014 | Prompt buffer reserve |
| PINES-015 | Safety reserve |
| PINES-016 | Correct downgrade |
| PINES-017 | User-facing admission copy |
| PINES-018 | Stream error mapping |
| PINES-019 | RunDecision |
| PINES-020 | Provider metadata |
| PINES-021 | OSLog decision |
| PINES-022 | Compatibility UI |
| PINES-023 | Support export |
| PINES-024 | Settings mode picker |
| PINES-025 | Per-model mode override |

## Evidence queue

| ID | Task |
| --- | --- |
| EVID-001 | Benchmark schema |
| EVID-002 | Benchmark importer |
| EVID-003 | ProfileEvidenceStore |
| EVID-004 | Evidence lookup |
| EVID-005 | Evidence levels |
| EVID-006 | Evidence invalidation |
| EVID-007 | QualityGate |
| EVID-008 | Top-1 match |
| EVID-009 | KL divergence |
| EVID-010 | Max logit error |
| EVID-011 | Perplexity delta |
| EVID-012 | Task eval delta |
| EVID-013 | Needle smoke |
| EVID-014 | Fallback equivalence |
| EVID-015 | p50/p95 decode |
| EVID-016 | first-token latency |
| EVID-017 | peak memory |
| EVID-018 | no-jetsam record |
| EVID-019 | device class |
| EVID-020 | OS build |
| EVID-021 | model revision |
| EVID-022 | tokenizer hash |
| EVID-023 | profile hash |
| EVID-024 | layout version |

## Memory calibration queue

| ID | Task |
| --- | --- |
| MEM-001 | Estimate-vs-actual |
| MEM-002 | Peak memory sample |
| MEM-003 | Memory warning sample |
| MEM-004 | Prefill memory checkpoint |
| MEM-005 | Decode memory checkpoint |
| MEM-006 | Calibration table |
| MEM-007 | p95 multiplier |
| MEM-008 | scratch multiplier |
| MEM-009 | fallback multiplier |
| MEM-010 | safety reserve tuning |
| MEM-011 | stale calibration |
| MEM-012 | device-class policy |
| MEM-013 | jetsam QA hook |
| MEM-014 | MetricKit correlation |

## Context queue

| ID | Task |
| --- | --- |
| CTX-001 | ContextSegment |
| CTX-002 | ContextAssemblyPlan |
| CTX-003 | pinned prompt |
| CTX-004 | live recent |
| CTX-005 | retrieved vault |
| CTX-006 | summary segment |
| CTX-007 | dropped segment |
| CTX-008 | segment scoring |
| CTX-009 | retrieval budget |
| CTX-010 | summary budget |
| CTX-011 | citation budget |
| CTX-012 | source provenance |
| CTX-013 | semantic vs KV distinction |
| CTX-014 | cloud approval |
| CTX-015 | context UI |
| CTX-016 | context support export |

## Snapshot queue

| ID | Task |
| --- | --- |
| SNAP-001 | Manifest schema |
| SNAP-002 | LM export |
| SNAP-003 | LM import |
| SNAP-004 | layout validation |
| SNAP-005 | next-token roundtrip |
| SNAP-006 | Pines manifest table |
| SNAP-007 | blob store |
| SNAP-008 | encryption |
| SNAP-009 | Keychain key |
| SNAP-010 | key rotation |
| SNAP-011 | atomic writes |
| SNAP-012 | partial recovery |
| SNAP-013 | quarantine |
| SNAP-014 | quota |
| SNAP-015 | eviction |
| SNAP-016 | model deletion |
| SNAP-017 | data erasure |
| SNAP-018 | CloudKit exclusion |
| SNAP-019 | prefix hash |
| SNAP-020 | tokenizer hash |
| SNAP-021 | RoPE hash |
| SNAP-022 | profile hash |
| SNAP-023 | restore UI |
| SNAP-024 | invalidation UI |

## iOS lifecycle queue

| ID | Task |
| --- | --- |
| IOS-001 | memory warning |
| IOS-002 | thermal downgrade |
| IOS-003 | Low Power Mode |
| IOS-004 | background policy |
| IOS-005 | suspend/resume |
| IOS-006 | cancellation |
| IOS-007 | model unload |
| IOS-008 | download/inference concurrency |
| IOS-009 | foreground-only MLX |
| IOS-010 | support export |
| IOS-011 | privacy manifest |
| IOS-012 | App Store validation |

## Speculative queue

| ID | Task |
| --- | --- |
| SPEC-001 | target verifier |
| SPEC-002 | tentative append |
| SPEC-003 | rollback |
| SPEC-004 | tokenizer compatibility |
| SPEC-005 | draft pairing |
| SPEC-006 | acceptance rate |
| SPEC-007 | Fast mode UX |
| SPEC-008 | auto-disable |
| SPEC-009 | evidence update |

## Platform backlog

| ID | Task |
| --- | --- |
| PLAT-001 | adaptive precision |
| PLAT-002 | segment precision |
| PLAT-003 | layer sensitivity |
| PLAT-004 | head sensitivity |
| PLAT-005 | semantic memory |
| PLAT-006 | user fact store |
| PLAT-007 | multimodal memory |
| PLAT-008 | audio transcript memory |
| PLAT-009 | image memory |
| PLAT-010 | local agent memory |
| PLAT-011 | tool-state pinning |
| PLAT-012 | open KV format |
| PLAT-013 | safetensors layout |
| PLAT-014 | external converter |
| PLAT-015 | device mesh |
| PLAT-016 | encrypted LAN sync |
| PLAT-017 | personalization |
| PLAT-018 | local adapters |

## Release/kill-switch queue

| ID | Task |
| --- | --- |
| REL-001 | `TURBOQUANT_DISABLE` |
| REL-002 | force baseline |
| REL-003 | force packed |
| REL-004 | disable snapshots |
| REL-005 | disable adaptive precision |
| REL-006 | disable speculative |
| REL-007 | disable fused |
| REL-008 | disable bfloat |
| REL-009 | release checklist |
| REL-010 | support export redaction |
| REL-011 | benchmark regression revoke |
| REL-012 | schema compatibility audit |

## Integration sequence

1. W4 removes zero/fatal.
2. W1 publishes core contracts.
3. W7 adds Pines shims.
4. W24 fixes mode/fallback semantics.
5. W8 adds admission.
6. W9 adds RunDecision.
7. INT-1 wires runtime bridge.
8. W3/W10/W22/W23 add evidence loop.
9. INT-2A validates compatible MLX pair on branch.
10. One real-device tuple is verified.
11. INT-2B updates production pins.
12. MVP 2+ begins activation.
