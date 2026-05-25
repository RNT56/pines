# Wave 3 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `08-worker-ownership.md`
- `06-quality-gates.md`
- `07-benchmark-evidence.md`

This file tracks Wave 3 evidence-loop implementation after the completed Wave 2 runtime-bridge handoff.

## 2026-05-25

### Start State

- Pines Wave 3 branch: `tq/wave3-evidence-loop`.
- Pines branch base: `f5a554a` from `tq/integration-runtime-bridge`.
- Wave 2 runtime bridge handoff is complete and pushed.
- `mlx-swift` branch head: `21002cb` (`codex/turboquant-core-completion`).
- `mlx-swift-lm` branch head: `6b15298` (`codex/turboquant-completion-hardening`).
- `compatibility-pair.json` remains `pending` because local full Xcode app validation is blocked.

### Wave 3 Scope

- W3: stable core benchmark JSON and hidden-copy audit in `mlx-swift`.
- W6: model profile v2 fail-closed validation and mismatch reasons in `mlx-swift-lm`.
- W10-full: `BenchmarkReport.v1` importer and `ProfileEvidenceStore` persistence in Pines.
- W22-full: quality gate computation and evidence-level activation rules.
- W23-full: memory calibration sample persistence and p95 multiplier aggregation.
- W12: compatibility UI states for Conservative, Unverified, Benchmark Required, Revoked, Degraded, Unsupported, and evidence-gated Verified.
- Real-device runner: export/import path for real-device acceptance evidence without fabricating a Verified tuple.

### Constraints

- No production pin promotion in Wave 3.
- No `Verified` product claim while `compatibility-pair.json` is `pending` or real-device evidence is absent.
- No edits to `MLXRuntimeBridge.swift` outside explicit Wave 2 follow-up ownership.
- No edits to `project.yml` or `Package.resolved` in Wave 3.
- Generated Xcode project changes are limited to pinned XcodeGen scheme normalization required by
  `run-xcode-validation.sh generate`.
- PinesCore stays MLX-free and consumes benchmark evidence through DTOs.

### Progress

- Created this Wave 3 progress log before implementation edits.
- Launched parallel Core and LM workers for W3/W6/W22 producer-side implementation.
- W3 `mlx-swift` worker completed on `tq/core-benchmark-json`:
  - added stable `TurboQuantCoreBenchmarkReport` DTOs;
  - added benchmark CLI flags and schemaVersion 1 JSON mode;
  - added hidden-copy audit status and report tests;
  - validation passed: `swift build --target TurboQuantBenchmark`, focused benchmark report tests,
    focused `swift run TurboQuantBenchmark --json ...`, `swift test --filter TurboQuant`, and
    `git diff --check`.
- W6/W22 `mlx-swift-lm` worker completed on `tq/lm-profile-v2-quality`:
  - profile selection fails closed on unsupported schema/layout versions;
  - stable mismatch DTOs are surfaced through profile validation diagnostics;
  - `TurboQuantModelBenchmark` emits aggregate and per-result QualityGate-shaped quality output;
  - validation passed: `swift build --target MLXLMCommon`, `swift build --target
    TurboQuantModelBenchmark`, `swift test --filter TurboQuantProfileTests`, and a focused
    benchmark JSON run.
- W10/W22/W23/W12 Pines implementation added:
  - `BenchmarkReport.v1` DTOs and importer policy;
  - evidence-level gating and revocation records;
  - quality gate threshold evaluator;
  - memory calibration aggregation and in-memory store helpers;
  - GRDB schema/methods for evidence, revocations, calibration samples, and aggregates;
  - compatibility UI state separation from catalog/preflight verification;
  - real-device acceptance export/import wrapper that records import failures instead of fabricating
    Verified evidence.
- Focused Pines validation passed:
  - `swift test --filter TurboQuantWave3EvidenceTests` passed 8 Swift Testing tests.
- Broad Pines validation passed:
  - `swift build --disable-automatic-resolution`;
  - `swift test --disable-automatic-resolution` passed 150 Swift Testing tests;
  - `swift run --disable-automatic-resolution PinesCoreTestRunner`;
  - `xcrun swiftc -parse -I .build/debug/Modules Pines/Runtime/MLXRuntimeBridge.swift`;
  - `git diff --check`;
  - `bash scripts/ci/check-mlx-package-pins.sh`;
  - `compatibility-pair.json` JSON parse.
- Xcode project validation:
  - `bash scripts/ci/xcodegen.sh generate` completed;
  - the first `bash scripts/ci/run-xcode-validation.sh generate` surfaced generated scheme drift;
  - retained the pinned XcodeGen scheme normalization, then reran
    `run-xcode-validation.sh prepare/generate/finalize`, which passed.
- App-target syntax validation:
  - `xcrun swiftc -parse -I .build/arm64-apple-macosx/debug/Modules` passed for the changed
    Pines app presentation, persistence, and model-view component files.
- Xcode package/app build limitation:
  - `bash scripts/ci/run-xcode-validation.sh resolve` stalled inside
    `xcodebuild -resolvePackageDependencies` with no progress;
  - terminated PID 37060 and confirmed no `xcodebuild` / `XCBBuildService` processes remained;
  - app build/test phases were not run because they depend on the blocked Xcode package-resolution
    phase.
- `Tests/PinesCoreTests/CoreContractTests.swift` was updated from schema version 19 to 20 to match
  the Wave 3 evidence-loop database migration.

### Evidence Gate Status

- Wave 3 implementation is functionally complete, but production evidence activation is not green in
  this workspace.
- `compatibility-pair.json` remains `pending` because full Xcode app validation is still blocked by
  local `xcodebuild` behavior and no real-device evidence tuple was produced.
- No real-device benchmark tuple was produced in this environment.
- Verified/Certified product claims remain disabled by policy unless a caller supplies an accepted
  compatibility-pair ID, accepted fallback-contract hash, passing quality gate, no jetsam/memory
  warning violation, and `allowVerifiedEvidence: true`.

### Handoff Audit

- Re-ran deterministic handoff validation after the Wave 2 admission/fallback-policy bridge follow-up
  and the Wave 3 evidence-loop implementation were both present in this worktree.
- Pines validation passed:
  - `git diff --check`;
  - `swift build --disable-automatic-resolution`;
  - `swift test --disable-automatic-resolution` passed 150 Swift Testing tests;
  - `swift test --filter TurboQuantWave3EvidenceTests` passed 8 Swift Testing tests;
  - `swift run --disable-automatic-resolution PinesCoreTestRunner`;
  - `xcrun swiftc -parse -I .build/debug/Modules Pines/Runtime/MLXRuntimeBridge.swift`;
  - `bash scripts/ci/check-mlx-package-pins.sh`;
  - `compatibility-pair.json` JSON parse;
  - `bash scripts/ci/xcodegen.sh generate`;
  - `bash scripts/ci/run-xcode-validation.sh prepare/generate/finalize`.
- `mlx-swift` validation passed on `tq/core-benchmark-json`:
  - `git diff --check`;
  - `swift build`;
  - `swift build --product TurboQuantBenchmark`;
  - `swift test --filter TurboQuantBenchmarkReportTests`;
  - `swift test --filter 'TurboQuant(Contracts|Validation|AttentionRouter)Tests'`;
  - `swift run TurboQuantBenchmark --json --iterations 1 --warmup 0 --context 16 --head-dim 64 --query-length 1`.
- `mlx-swift-lm` validation passed on `tq/lm-profile-v2-quality`:
  - `git diff --check`;
  - `swift build --target MLXLMCommon`;
  - `swift build --product TurboQuantModelBenchmark`;
  - `swift test --filter TurboQuantProfileTests`;
  - `swift test --filter TurboQuantRuntimeFailureTests`;
  - `swift test --filter TurboQuantCacheRuntimeSnapshotTests`;
  - `swift run TurboQuantModelBenchmark --help`.
- Full Xcode package/app validation remains the only non-green local gate because
  `xcodebuild -resolvePackageDependencies` is the known local blocker.
- Confirmed no `xcodebuild` or `XCBBuildService` processes remained after validation.
