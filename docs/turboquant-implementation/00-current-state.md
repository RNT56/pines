# Current State

This document records the observed local repository state at the start of the implementation-doc pass. It is intentionally factual and should be updated by W25 before implementation branches begin.

## Observed workspace

Root workspace:

```text
/Users/mt/Programming/Schtack/mlx-forks
```

Related Pines repo:

```text
/Users/mt/Programming/Schtack/pines
```

## Observed branches and commits

| Repo | Branch | Observed HEAD | Dirty state |
| --- | --- | --- | --- |
| `pines` | `codex/local-runtime-hardening` | `3c21a2d2ae9d2062881990f9529a916bbfa85571` | unrelated artifact workspace files are modified locally and were not included in this pin promotion |
| `mlx-swift` | `codex/turboquant-core-completion` | `a90b1097df45e4e70b6e0bb367624f8f5857970b` | nested `Source/Cmlx/mlx`, `Source/Cmlx/mlx-c` modified before this doc pass |
| `mlx-swift-lm` | `codex/turboquant-completion-hardening` | `af28d8a0e28a5f7d8a012ed66a1470ac00c6f20c` | clean before this doc pass |

## Observed Pines pins

`pines/project.yml` currently pins:

| Package | Revision |
| --- | --- |
| `MLXSwift` | `a90b1097df45e4e70b6e0bb367624f8f5857970b` |
| `MLXSwiftLM` | `af28d8a0e28a5f7d8a012ed66a1470ac00c6f20c` |

`pines/docs/TURBOQUANT.md` now lists the same current-pin pair:

| Package | Revision listed in `docs/TURBOQUANT.md` |
| --- | --- |
| `MLXSwift` | `a90b1097df45e4e70b6e0bb367624f8f5857970b` |
| `MLXSwiftLM` | `af28d8a0e28a5f7d8a012ed66a1470ac00c6f20c` |

Keeping `docs/TURBOQUANT.md`, `project.yml`, and the generated Xcode project synchronized is part of the release-train gate whenever the compatibility pair changes.

## Observed LM attention safety state

`mlx-swift-lm/Libraries/MLXLMCommon/AttentionUtils.swift` currently has:

- a throwing attention path;
- typed-ish TurboQuant attention errors;
- no obvious all-zero fallback in the inspected path;
- deprecated non-throwing wrappers that still call `fatalError` when failures cannot be represented semantically.

The P0 safety target remains:

1. no Pines-facing product call site uses non-throwing wrappers;
2. no product path can fatal on TurboQuant failure;
3. failure maps to typed runtime errors;
4. no product path returns zero or guessed tensors.

## Implemented Pines foundation

Pines already has a substantial local-first foundation:

- SwiftUI app shell;
- typed stream events;
- local/cloud execution routing rules;
- model catalog and preflight;
- persistence schema;
- vault chunking and vector index;
- local attachments and file staging;
- MLX runtime bridge;
- exact app-level pins to MLX forks;
- TurboQuant runtime diagnostics;
- memory/thermal adaptive profiles;
- memory-warning unload;
- foreground-only MLX execution;
- OSLog and MetricKit hooks;
- CI validation scripts;
- local-first security boundary with opt-in cloud and sync behavior.

## Known incomplete product gates

The following are not complete and remain release blockers for the long-context target:

- real-device TurboQuant acceptance on the A16-through-A19 Pro matrix;
- evidence-backed model/device/mode compatibility claims;
- detailed model compatibility UI;
- runtime admission before local generation;
- full memory-zone accounting;
- planned-vs-actual memory calibration;
- typed app-level TurboQuant failure mapping;
- complete run decision ledger;
- final privacy-manifest validation against the resolved package graph;
- encrypted KV snapshot persistence and restore.

## Immediate implementation blockers

P0 blockers:

1. Product-path fatal removal or product-path avoidance in `mlx-swift-lm`.
2. Cross-repo contracts and Pines shims.
3. Mode/fallback contract.
4. Admission service.
5. RunDecision ledger.
6. Runtime bridge integration.
7. Compatibility-pair validation.

## Current-state update procedure

Before any implementation branch begins:

1. Run `git status --short` in all three repos.
2. Record HEAD SHAs.
3. Record package pins.
4. Record whether `docs/TURBOQUANT.md`, `project.yml`, and `Package.resolved` agree.
5. Record whether product-path fatal and zero-output blockers still exist.
6. Update `compatibility-pair.json` to `pending`.
7. Do not promote any pair to `green` until the validation commands in [Validation and Release Gates](12-validation-and-release-gates.md) pass.
