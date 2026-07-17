# Current State

This document records the observed local repository state at the start of the implementation-doc pass. It is intentionally factual and was used by W25 before implementation branches began.

## Current failed status

After the Wave 0 baseline capture on 2026-05-31, the active local compatibility pair is failed/non-green:

| Repo | Branch | Validation commit/pin |
| --- | --- | --- |
| `pines` | `tq/real-device-evidence-acceptance` | `ebc1d80aba9466da5e72690b26d9155aec72836d` dirty validation base before this evidence update |
| `mlx-swift` | `tq/layout-v5-default-device-tests` | `bcf93af23f11428f6f01efb0bb4b9020cd2eb383` pushed SwiftPM 6.2-compatible platform-aware Metal and Apple-mobile JIT compatibility pin |
| `mlx-swift-lm` | `tq/lm-layout-v5-default-device-tests` | `aeaa8e3024a82b25969741b53c749b28ddc64d1a` pushed exact-core integration pin |

Pines pins `MLXSwift` to `bcf93af23f11428f6f01efb0bb4b9020cd2eb383` and `MLXSwiftLM` to `aeaa8e3024a82b25969741b53c749b28ddc64d1a` across `project.yml`, the generated Xcode project, the Xcode package lockfile, `docs/TURBOQUANT.md`, `MLXRuntimeBridge.turboQuantCompatibilityPairID`, and `compatibility-pair.json`.

Wave 0 evidence recorded passing Pines pin/build gates and Mac benchmark artifacts, while `mlx-swift swift test --filter TurboQuant` failed lower-bit QK reference checks and the Wave 0 app-hosted iOS smoke ended `failed_environmental` before install/launch. The continuation pass resolves the local TurboQuant test blocker and wires native affine K8/V4 mixed quantized SDPA through the MLX Swift LM cache path. Physical-device app-host smoke on `iPhone16,2` is recorded in `20260712T150706Z-ios-exact-pair-smoke.md`, and a focused Qwen 3.5 0.8B `real-model-inference-v1` comparison passed at 4K in `20260712T151432Z-ios-qwen35-08b-realmodel-smoke.md`. Those runs belong to the immediately prior immutable pair: the current core revision changes only the SwiftPM tools-version manifest and the LM revision only repins that core, but exact pair identity still changed. The runs are therefore historical, and their two-repeat throughput interval is wide with selected-path diagnostics absent. Mac real-model inference evidence exists for Qwen3.5-2B at 32K and 64K, but it also belongs to an earlier tuple. Historical pass, smoke, simulator, and Mac proof evidence is retained for audit only; it does not override the current failed status. Layout V4 is the production default for new MLX attention layout requests; Layout V5/V6 remain supported for explicit experimental, benchmark, and compatibility runs only. The current exact pins remain unverified and a complete imported real-device model/device/mode evidence tuple remains required before any `Verified` or `Certified` product claim.

### Adopted N2 self-speculation (lever ①) + N4 codec surface

`mlx-swift-lm` `aeaa8e3024a82b25969741b53c749b28ddc64d1a` exposes
draft-model-free self-speculation as a product API: `GenerateParameters.selfSpeculationMode`
(`.off` default | `.promptLookup`) routed via `makeGenerationIterator(...)`, bit-exact for
greedy/no-processor and falling back to exact decode otherwise (incl. non-trimmable hybrid
caches). It pairs with the validated N7 async-prefetch path (16K long-doc 1.43→1.76×). `mlx-swift`
also adds the data-free Gaussian Lloyd-Max payload codec format
(`TurboQuantReferenceFormat.gaussianLloydMax`, 3.2× at equal quality), pending a Metal decode kernel.

The integration pair now pins mlx-swift `bcf93af23f11428f6f01efb0bb4b9020cd2eb383`
plus mlx-swift-lm `aeaa8e3024a82b25969741b53c749b28ddc64d1a`, and Pines wires
`selfSpeculationMode` into `MLXRuntimeBridge.GenerateParameters`. The pair remains
`failed`/`unverified` until exact-pair A-series evidence and the remaining release gates land.
Self-speculation ships default-off, so it is inert until explicitly enabled and device-validated.

Current continuation work adds explicit benchmark coverage and labels for
`affineK8V4`, `affineK8V3`, `affineK8V2`, `mlxAffine-q8`, `affineInt4`,
`turbo4v2`, `turbo3_5`, and `turbo8`; long-context scheduling/chunking fixes for
128K K8/Vx runs; native Sparse-V threshold, top-k, cumulative-mass, and hybrid
diagnostics; and `real-model-inference-v1` quality gates in
`TurboQuantInferenceParity`. The latest Mac artifact
`turboquant-k8vx-realmodel-20260601T144308Z` shows dense K8/V4 passing current
32K/64K FP16-referenced logit gates, while K8/V3 and K8/V2 preserve top-1 but
fail P95 max-logit-error gates. This is useful evidence, but it is still Mac
evidence and does not change the non-green compatibility status without the
required iOS real-model tuple.

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

After the Wave 7 production closeout, runtime admission, memory zones, memory
calibration records, typed failure mapping, RunDecision metadata, compatibility
UI states, privacy manifest validation against the local resolved graph, and
encrypted snapshot storage are implemented. The current Wave 0 pair remains
failed/non-green until all required gates have current evidence. `Verified` and
`Certified` product labels still require matching imported real-device evidence.

## Immediate implementation blockers

Closed Wave 0 blockers:

1. Product-path fatal avoidance in `mlx-swift-lm`.
2. Explicit `TurboQuantStorageEstimate` in `mlx-swift`.
3. Explicit `TurboQuantContracts.swift` in `mlx-swift`.
4. Pines type-family decision: reuse existing `TurboQuant*` DTOs.
5. Mode/fallback contract hashing in Pines.

Wave 1+ implementation work is implemented through the production pin closeout,
but release status remains failed/non-green for the current pair:

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
