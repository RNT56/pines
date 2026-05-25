# Wave 3.5 Changelog

Read this alongside:

- `14-worker-launch-schedule.md`
- `15-pr-merge-plan.md`
- `12-validation-and-release-gates.md`
- `compatibility-pair.json`

Wave 3.5 is the serialized production pin-promotion lane. It does not add a
new TurboQuant runtime feature. Its job is to make Pines consume a validated MLX
compatibility pair through production pin surfaces after the Wave 3 evidence
loop.

## 2026-05-25

### Start State

- Pines branch before promotion: `tq/wave7-platform-unlocks` at
  `b410ae901ad92e969f46d482a01f12d1f9058851`.
- Production pins still referenced the older Wave 0/2 pair:
  - `mlx-swift`: `21002cb84fe37204b7cab3fbb363ecbc260bf6a4`;
  - `mlx-swift-lm`: `6b15298efa1fe3db8cb78e15cd2b6bdb95b29075`.
- Final local MLX Wave 7 branches were committed but not reachable remotely:
  - `mlx-swift` `tq/wave7-core-platform` at
    `d8725e195fd4e0d0cedb3acdca5d1a8327377c19`;
  - `mlx-swift-lm` `tq/wave7-lm-platform` at
    `beca69f07458b3c04075f0adaf31ef3908629d66`.
- `compatibility-pair.json` remained `pending`.
- The only connected physical device reported by `xcrun xctrace list devices`
  was a Mac-class device. The iPhone-class device was offline, so the required
  real-device verified tuple could not be produced in this workspace.
- Full local Xcode package/app validation remained blocked by the known
  `xcodebuild -resolvePackageDependencies` stall.

### Scope

Wave 3.5 production pin promotion updates only the serialized pin surfaces and
their validation rails:

- `project.yml`;
- `Pines.xcodeproj/project.pbxproj`;
- `Pines.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`;
- runtime compatibility pair ID;
- `docs/TURBOQUANT.md`;
- `docs/turboquant-implementation/compatibility-pair.json`;
- pin-alignment CI checks.

It must not fabricate real-device evidence, mark the compatibility pair green,
or promote Verified/Certified product claims while release gates remain open.

### Completed Implementation

- Pushed the final MLX Wave 7 branches so the pinned revisions are reachable by
  SwiftPM:
  - `RNT56/mlx-swift` branch `tq/wave7-core-platform`;
  - `RNT56/mlx-swift-lm` branch `tq/wave7-lm-platform`.
- Created Pines branch `tq/integration-pin-mlx-production`.
- Promoted Pines production pins to the final Wave 7 pair:
  - `mlx-swift`: `d8725e195fd4e0d0cedb3acdca5d1a8327377c19`;
  - `mlx-swift-lm`: `beca69f07458b3c04075f0adaf31ef3908629d66`.
- Regenerated the Xcode project with `scripts/ci/xcodegen.sh generate`.
- Updated the Xcode package lockfile to the same pair.
- Updated `MLXRuntimeBridge.turboQuantCompatibilityPairID` so run decisions,
  benchmark evidence, and product compatibility matching use the promoted pair.
- Updated `docs/TURBOQUANT.md`.
- Updated `compatibility-pair.json` to record the promoted pair and explicitly
  keep release status pending.
- Hardened `scripts/ci/check-mlx-package-pins.sh` so future drift checks cover:
  - `project.yml`;
  - generated Xcode project package references;
  - Xcode `Package.resolved`;
  - runtime compatibility pair ID;
  - TurboQuant docs;
  - compatibility-pair metadata.

### Validation

The following gates were run after promotion:

- `swift build --disable-automatic-resolution`;
- `swift test --disable-automatic-resolution`;
- `swift run --disable-automatic-resolution PinesCoreTestRunner`;
- `bash scripts/ci/check-mlx-package-pins.sh`;
- `python3 -m json.tool docs/turboquant-implementation/compatibility-pair.json`;
- `bash scripts/ci/xcodegen.sh generate`;
- `bash scripts/ci/run-xcode-validation.sh prepare`;
- `bash scripts/ci/run-xcode-validation.sh generate`;
- `bash scripts/ci/run-xcode-validation.sh finalize`;
- `git diff --check`.

### Remaining Release Gates

Wave 3.5 source wiring is complete, but the release gate is not green:

- no online iPhone-class device was available to produce the required
  real-device verified tuple;
- `compatibility-pair.json` must remain `pending`;
- full local Xcode package/app validation is still blocked by the existing
  `xcodebuild -resolvePackageDependencies` stall;
- Verified/Certified product claims remain disabled until a real-device tuple
  and full validation close these gates.
