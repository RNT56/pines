# Wave 2 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `08-worker-ownership.md`
- `09-runtime-bridge-integration.md`

This file tracks Wave 2 implementation progress after the completed Wave 1 handoff.

## 2026-05-25

### Start State

- Pines Wave 2 worker branch: `tq/integration-runtime-bridge`.
- Pines target integration branch: `codex/local-runtime-hardening`.
- Pines branch base: `ec2e1b8`.
- `mlx-swift` branch head: `21002cb` (`codex/turboquant-core-completion`).
- `mlx-swift-lm` branch head: `6b15298` (`codex/turboquant-completion-hardening`).
- Wave 1 changelog reports W2/W5/W8/W9/W10/W22/W23 complete and validated.
- `compatibility-pair.json` remains `pending`; Wave 2 INT-2A may validate a compatibility branch, but production pin promotion remains Wave 3.5.

### Wave 2 Scope

- INT-1: integrate admission, fallback policy, typed failure mapping, RunDecision metadata, memory calibration, and minimal context assembly metadata into the real local MLX generation path.
- INT-2A: validate exact `mlx-swift` and `mlx-swift-lm` commits on a compatibility branch and update `compatibility-pair.json`.

### Constraints

- `MLXRuntimeBridge.swift` is INT-1-owned while runtime bridge integration is active.
- `project.yml`, `Package.resolved`, and generated Xcode project files are INT-2A-owned during compatibility validation.
- No Verified compatibility UI activation in Wave 2.
- No production pin promotion in Wave 2.
- No silent cloud retry after local TurboQuant failure.

### Progress

- Created this Wave 2 progress log before bridge edits.
- Launched sidecar validation workers for Wave 1 core/LM prerequisite checks and Pines bridge gap scouting.
- Core/LM sidecar validation passed:
  - `mlx-swift`: `TurboQuantContractsTests`, `TurboQuantValidationTests`, and
    `TurboQuantAttentionRouterTests`.
  - `mlx-swift-lm`: `TurboQuantRuntimeFailureTests`,
    `TurboQuantCacheRuntimeSnapshotTests`, and `TurboQuantAdmissionPlannerTests`.
- Added minimal `ContextAssemblyPlan.v1` in PinesCore.
- Extended `InferenceStreamFailure` so typed stream failures can carry Wave 2 provider metadata.
- Began INT-1 bridge wiring for request-scoped admission, context assembly plan metadata,
  RunDecision metadata, memory calibration samples, typed failure events, and explicit no-cloud
  fallback metadata.
- Completed INT-1 bridge wiring in `Pines/Runtime/MLXRuntimeBridge.swift`:
  - request-scoped `LocalRuntimeAdmissionService` plan is built after exact token preflight and
    before cache creation/generation;
  - generation uses the admitted context window for `GenerateParameters.maxKVSize`;
  - rejected local runs emit typed failure events before generation;
  - successful finishes attach `TurboQuantRunDecision`, `RuntimeMemoryCalibrationSample`, admission,
    and minimal context assembly metadata;
  - runtime failures emit typed `LocalInferenceFailureKind` codes plus partial RunDecision/failure
    metadata;
  - cloud retry is explicitly marked disallowed in metadata unless a future route policy enables it.
- Added failure provider metadata propagation through `InferenceStreamFailure` and the main chat
  failure flush path.
- Completed INT-2A pin update to:
  - `mlx-swift` `21002cb84fe37204b7cab3fbb363ecbc260bf6a4`;
  - `mlx-swift-lm` `6b15298efa1fe3db8cb78e15cd2b6bdb95b29075`.
- Regenerated `Pines.xcodeproj` and synchronized the Xcode SwiftPM `Package.resolved` and
  `docs/TURBOQUANT.md` pin documentation.
- Updated `compatibility-pair.json` with the Wave 2 validation results. It remains `pending`
  because full local Xcode app validation could not complete in this environment.

### Validation

- `swift test --filter TurboQuantWave1ControlPlaneTests` passed 6 Swift Testing tests after the
  Core metadata additions.
- `swift build --disable-automatic-resolution` passed.
- `swift test --disable-automatic-resolution` passed 142 Swift Testing tests.
- `swift run --disable-automatic-resolution PinesCoreTestRunner` passed.
- `xcrun swiftc -parse -I .build/debug/Modules Pines/Runtime/MLXRuntimeBridge.swift` passed.
- `bash scripts/ci/xcodegen.sh generate` passed.
- `bash scripts/ci/run-xcode-validation.sh prepare`, `generate`, and `finalize` passed.
- `bash scripts/ci/check-mlx-package-pins.sh` passed.
- `mlx-swift`: `swift build` passed; focused Wave 1 prerequisite tests passed.
- `mlx-swift-lm`: `swift build --target MLXLMCommon` passed; focused Wave 1 prerequisite tests
  passed.
- Final closeout checks passed:
  - `git diff --check`;
  - `compatibility-pair.json` JSON parse validation.

### Validation Blocker

- `xcodebuild -resolvePackageDependencies`, `xcodebuild build`, and even `xcodebuild -list` idled
  locally with a single `xcodebuild` process, no compiler/fetch child process, and no output. The
  hung processes were terminated. This prevents marking the compatibility pair `green` from this
  workspace even though SwiftPM, XcodeGen drift checks, pin checks, and bridge syntax parse passed.

### Handoff Audit

- Re-ran the deterministic Wave 2 validation gates during handoff:
  - `git diff --check`;
  - `swift test --filter TurboQuantWave1ControlPlaneTests`;
  - `swift build --disable-automatic-resolution`;
  - `swift test --disable-automatic-resolution`;
  - `swift run --disable-automatic-resolution PinesCoreTestRunner`;
  - `bash scripts/ci/xcodegen.sh generate`;
  - `bash scripts/ci/run-xcode-validation.sh prepare`;
  - `bash scripts/ci/run-xcode-validation.sh generate`;
  - `bash scripts/ci/run-xcode-validation.sh finalize`;
  - `bash scripts/ci/check-mlx-package-pins.sh`;
  - `compatibility-pair.json` JSON parse;
  - `xcrun swiftc -parse -I .build/debug/Modules Pines/Runtime/MLXRuntimeBridge.swift`.
- All deterministic handoff gates passed.
- Committed the Wave 2 implementation as
  `a1cdcb4798047c9847a4532730b4b7f59c16fe86`.
- Updated `compatibility-pair.json` to point at the committed Wave 2 integration while preserving
  `status: pending` because full local Xcode app validation is still blocked.
