# Current State

This document records the observed local repository state at the start of the implementation-doc pass. It is intentionally factual and was used by W25 before implementation branches began.

## Current release-green status

After the Wave 7 and production pin closeout, the active local compatibility pair is green:

| Repo | Branch | Release-green commit |
| --- | --- | --- |
| `pines` | `tq/integration-pin-mlx-production` | `4d9d89eb801de2e5bb2635d8b81e81b27cd39b83` |
| `mlx-swift` | `tq/wave7-core-platform` | `21a897c5d1ae1930bd7c7a47bb3ed6c9fe8c8772` |
| `mlx-swift-lm` | `tq/wave7-lm-platform` | `6d2d791a12e60dc1bd7534d6c95454a2284edf8c` |

Pines pins `MLXSwift` to `21a897c5d1ae1930bd7c7a47bb3ed6c9fe8c8772` and `MLXSwiftLM` to `6d2d791a12e60dc1bd7534d6c95454a2284edf8c` across `project.yml`, the generated Xcode project, the Xcode package lockfile, `docs/TURBOQUANT.md`, `MLXRuntimeBridge.turboQuantCompatibilityPairID`, and `compatibility-pair.json`.

Local release gates are green, including full SwiftPM validation and `bash scripts/ci/run-xcode-validation.sh all`. Real-device model/device/mode evidence remains pending and is still required before any `Verified` or `Certified` product claim.

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

Updated during W25 Wave 0 reconciliation on 2026-05-25.

| Repo | Branch | Observed HEAD | Dirty state |
| --- | --- | --- | --- |
| `pines` | `codex/local-runtime-hardening` | `2956939fdcf584f4988dd7dc3bd67f8e5bc0cddf` | clean before this blocker-resolution doc update |
| `mlx-swift` | `codex/turboquant-core-completion` | `f3fe58109faf2b0a74405df321a8474df8803da8` | pushed to origin |
| `mlx-swift-lm` | `codex/turboquant-completion-hardening` | `a1628c8a64b3258b122fa05fd4007e6dfd54cc3d` | pushed to origin |

## Historical Wave 0 Pines pins

At Wave 0, `pines/project.yml` pinned:

| Package | Revision |
| --- | --- |
| `MLXSwift` | `cbea339ac81d701ea24df1bdc8b3008bcb99945a` |
| `MLXSwiftLM` | `86b5d6bb1c0192f3b229a8b2c08fab59a918957b` |

The generated Xcode package resolution at
`Pines.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
lists the same `MLXSwift` and `MLXSwiftLM` revisions as `project.yml`.

At Wave 0, `pines/docs/TURBOQUANT.md` listed a different older pair:

| Package | Revision listed in `docs/TURBOQUANT.md` |
| --- | --- |
| `MLXSwift` | `a90b1097df45e4e70b6e0bb367624f8f5857970b` |
| `MLXSwiftLM` | `af28d8a0e28a5f7d8a012ed66a1470ac00c6f20c` |

This is documentation drift only in Wave 0. W25 records it; W0/INT-2A/INT-2B own any
compatibility-pair or pin-state promotion, and production pin movement must wait for
the later compatibility validation gates.

## Resolved Wave 0 blocker state

The Wave 0 blocker pass resolved the four pre-Wave-1 ambiguity points:

1. `mlx-swift` now has explicit storage-estimate symbols in `Source/MLX/TurboQuantStorageEstimate.swift`.
2. `mlx-swift` now has the public contract surface in `Source/MLX/TurboQuantContracts.swift`, with compatibility aliases for `RejectedTurboQuantPath` and the path-specific capability names used by Wave 1 docs.
3. `mlx-swift-lm` now has `TurboQuantRuntimeFailure.swift` and a regression proving TurboQuant generation rejects non-throwing models before `prepare`, `newCache`, or runtime attention can run.
4. Pines reuses the existing `TurboQuantUserMode`, `TurboQuantAttentionPath`, `RuntimeQuantizationDiagnostics`, and `RuntimeTypes.swift` DTOs rather than introducing duplicate `Local*` packet types.
5. Pines has `TurboQuantFallbackContract` with canonical SHA-256 `contractHash` and `policyHash`.

`mlx-swift-lm/Libraries/MLXLMCommon/AttentionUtils.swift` still retains deprecated non-throwing compatibility wrappers. Those wrappers are not the TurboQuant product-generation path. The production gate is:

1. `GenerateParameters.kvCacheStrategy == .turboQuant` requires `ThrowingLanguageModel`.
2. Non-throwing models fail with `TurboQuantGenerationError.modelRequiresThrowingAttention`.
3. Typed throwing model paths propagate `TurboQuantRuntimeFailure`.
4. No product path returns zero or guessed tensors as a substitute for failed TurboQuant attention.

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

## Historical Wave 0 incomplete product gates

At Wave 0, the following were not complete and were release blockers for the
long-context target:

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

After the Wave 7 production closeout, the local runtime-pair gates listed above
are complete except for real-device model/device/mode evidence and signed App
Store distribution. Runtime admission, memory zones, memory calibration records,
typed failure mapping, RunDecision metadata, compatibility UI states, privacy
manifest validation against the local resolved graph, and encrypted snapshot
storage are implemented. `Verified` and `Certified` product labels still require
matching imported real-device evidence.

## Immediate implementation blockers

Closed Wave 0 blockers:

1. Product-path fatal avoidance in `mlx-swift-lm`.
2. Explicit `TurboQuantStorageEstimate` in `mlx-swift`.
3. Explicit `TurboQuantContracts.swift` in `mlx-swift`.
4. Pines type-family decision: reuse existing `TurboQuant*` DTOs.
5. Mode/fallback contract hashing in Pines.

Wave 1+ implementation work is now closed through the production pin closeout:

1. Admission service.
2. RunDecision ledger integration.
3. Runtime bridge integration.
4. Full compatibility-pair validation and pin/document synchronization.
5. Evidence, context planning, snapshots, optimization, speculative contracts,
   and disabled-by-default platform-unlock contracts.

## Current-state update procedure

Before a future compatibility branch begins:

1. Run `git status --short` in all three repos.
2. Record HEAD SHAs.
3. Record package pins.
4. Record whether `docs/TURBOQUANT.md`, `project.yml`, and `Package.resolved` agree.
5. Record whether product-path fatal and zero-output blockers still exist.
6. Update `compatibility-pair.json` to `pending` only when starting a new
   unvalidated pair.
7. Do not promote any pair to `green` until the validation commands in [Validation and Release Gates](12-validation-and-release-gates.md) pass.
