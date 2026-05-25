# Wave 1 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `08-worker-ownership.md`

This file tracks Wave 1 implementation progress after the resolved Wave 0 handoff.

## 2026-05-25

### Start State

- Pines implementation branch is checked out in linked worktree:
  `/Users/mt/Programming/Schtack/wave0-worktrees/pines-wave0-integration`.
- Pines branch head: `afe8c1e` (`codex/local-runtime-hardening`).
- `mlx-swift` branch head: `f3fe581` (`codex/turboquant-core-completion`).
- `mlx-swift-lm` branch head: `a1628c8` (`codex/turboquant-completion-hardening`).
- All three branches were clean and up to date with origin before Wave 1 edits.
- `compatibility-pair.json` remains `pending`; Wave 1 does not promote production pins or Verified evidence.

### Wave 1 Scope

- W2: core validation and attention router.
- W5: LM cache lifecycle runtime snapshot.
- W8: Pines admission service and memory zones.
- W9: Pines RunDecision ledger.
- W10 skeleton: evidence store schema shell only.
- W22 skeleton: QualityGate type and suite IDs only.
- W23 skeleton: memory calibration sample schema only.

### Constraints

- Do not edit `Pines/Runtime/MLXRuntimeBridge.swift`; INT-1 owns bridge integration in Wave 2.
- Do not edit `project.yml`, `Package.resolved`, or generated Xcode project files; INT-2A/INT-2B own pins.
- Do not activate Verified compatibility claims in Wave 1.
- Keep Pines control-plane types MLX-independent.

### Parallel Worker Launch

- W2 core validation/router worker launched for `mlx-swift`.
- W5 cache lifecycle snapshot worker launched for `mlx-swift-lm`.
- Pines W8/W9/W10/W22/W23 worker launched for PinesCore control-plane and skeleton schemas.

Workers were assigned disjoint write scopes. Shared central bridge and pin files remain locked for later integration waves.

### Implemented

- W2 Core:
  - Added `Source/MLX/TurboQuantValidation.swift`.
  - Added `Source/MLX/TurboQuantAttentionRouter.swift`.
  - Added validation/router tests.
  - Public APIs now include `validateTurboQuantAttentionCode(...)` and
    `selectTurboQuantAttentionPath(...)`.
- W5 LM:
  - Added `TurboQuantCacheRuntimeSnapshot`.
  - Added `runtimeSnapshot()` to TurboQuant compressed cache protocol and concrete cache types.
  - Added snapshot tests covering empty, failure, fallback, and rotating-cache metadata.
- Pines W8/W9/W10/W22/W23:
  - Added `RuntimeMemoryZones`.
  - Added `LocalRuntimeAdmissionRequest`, `LocalRuntimeAdmissionPlan`, and
    `LocalRuntimeAdmissionService`.
  - Added `TurboQuantRunDecision`.
  - Added `RuntimeProfileEvidence`, `RuntimeEvidenceLevel`, and in-memory `ProfileEvidenceStore`
    skeleton.
  - Added `TurboQuantQualityGate` and benchmark suite IDs.
  - Added `RuntimeMemoryCalibration` sample, aggregate, and summary types.
  - Added Wave 1 control-plane tests.

### Validation

- `mlx-swift`: `swift test --filter 'TurboQuant(Contracts|Validation|AttentionRouter)Tests'`
  passed 13 tests.
- `mlx-swift`: `swift build` passed.
- `mlx-swift-lm`: `swift test --filter 'TurboQuant(CacheRuntimeSnapshot|RuntimeFailure)Tests|KVCacheTests'`
  passed 48 Swift Testing tests.
- `mlx-swift-lm`: `swift build --target MLXLMCommon` passed.
- Pines: `swift test --filter 'TurboQuant(Wave1ControlPlane|FallbackContract)Tests|versionedEnvelope|turboQuant'`
  passed 15 Swift Testing tests.
- Pines: `swift build --disable-automatic-resolution` passed.
- Pines: `swift run --disable-automatic-resolution PinesCoreTestRunner` passed.
- `git diff --check` passed in all three repos.

### Handoff Audit

- Rerun validation initially caught one LM snapshot issue: empty rotating TurboQuant caches reported
  `rawShadowAllocated == true` because the snapshot checked helper-cache object presence rather than
  resident raw-shadow arrays.
- Fixed the LM snapshot implementation to report raw and packed fallback allocation from resident
  array bytes. This keeps `TurboQuantCacheRuntimeSnapshot` aligned with the memory accounting contract
  Pines will consume in INT-1.
- Re-ran the Wave 1 validation commands after the fix; the `mlx-swift`, `mlx-swift-lm`, and Pines
  suites listed above passed.

### Remaining Wave 1 Boundaries

- `MLXRuntimeBridge.swift` remains untouched for INT-1.
- Pin files remain untouched for INT-2A/INT-2B.
- Evidence store is a schema/storage skeleton only; importer and Verified activation remain Wave 3.
- Compatibility pair remains pending until integration and validation gates run.
