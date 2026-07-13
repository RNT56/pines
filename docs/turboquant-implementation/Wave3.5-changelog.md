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
    `21a897c5d1ae1930bd7c7a47bb3ed6c9fe8c8772`;
  - `mlx-swift-lm` `tq/wave7-lm-platform` at
    `6d2d791a12e60dc1bd7534d6c95454a2284edf8c`.
- `compatibility-pair.json` remained `pending` at Wave 3.5 start.
- The only connected physical device reported by `xcrun xctrace list devices`
  was a Mac-class device. The iPhone-class device was offline, so the required
  real-device verified tuple could not be produced in this workspace.
- Full local Xcode package/app validation was still blocked at Wave 3.5 start
  by the known `xcodebuild -resolvePackageDependencies` stall. The later
  production closeout resolved this local gate and passed
  `bash scripts/ci/run-xcode-validation.sh all` on the final pair.

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
  - `mlx-swift`: `21a897c5d1ae1930bd7c7a47bb3ed6c9fe8c8772`;
  - `mlx-swift-lm`: `6d2d791a12e60dc1bd7534d6c95454a2284edf8c`.
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

Wave 3.5 source wiring was complete at the initial handoff, but release-green
closeout happened in a later production pass:

- the stale `mlx-swift` Metal reduce JIT generated source was regenerated so
  full core tests pass;
- `mlx-swift-lm` was pinned to that release-green core commit;
- Pines production pins, generated Xcode references, package lockfile,
  `MLXRuntimeBridge.turboQuantCompatibilityPairID`, TurboQuant docs, and
  `compatibility-pair.json` were synchronized to the final pair;
- `bash scripts/ci/run-xcode-validation.sh all` passed, including locked
  package resolution, unsigned iOS build, build-for-testing, simulator unit
  smoke, simulator UI smoke, and final drift checks;
- `compatibility-pair.json` is now `green` for local release gates.

No online iPhone-class device was available to produce a real-device verified
tuple. `Verified` and `Certified` model/device/mode product claims remain
disabled until real-device evidence is imported for the exact tuple.
