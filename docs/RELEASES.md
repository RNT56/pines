# Release Process

`pines` uses GitHub Actions for CI and GitHub Releases for source/developer-preview releases.

## CI

CI runs on pull requests, pushes to `main`, and manual dispatch.

Jobs:

- `workflow-lint`: pinned `actionlint` validation for all GitHub Actions workflows.
- `shell-static-analysis`: pinned ShellCheck validation for CI scripts.
- `secret-scan`: pinned gitleaks source scan with explicit allowlists for synthetic test fixtures and ignored build outputs.
- `dependency-review`: GitHub dependency review on pull requests, failing on high-severity dependency changes.
- `repo-hygiene`: shell-script syntax validation, public-repo hygiene, license and notice checks, privacy manifest linting, MLX package-pin checks, tracked-artifact checks, secret-pattern scanning, and high-assurance security-boundary checks.
- `site`: Netlify/Astro site dependency install, build, and `site/dist/index.html` artifact verification.
- `swift-package-build`: Swift package build with automatic resolution disabled.
- `swift-package-tests`: Swift package tests with automatic resolution disabled.
- `core-verification`: `PinesCoreTestRunner` with automatic resolution disabled.
- `xcode-project`: XcodeGen project snapshotting, generated-project drift check, locked package resolution from `Pines.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, unsigned generic iOS build, simulator build-for-testing, simulator runtime smoke tests, generated-project restoration, and final package lockfile drift checks.

The Xcode job uses the `macos-26` GitHub-hosted runner and verifies the full iOS and watchOS build destinations needed by the `Pines` and `PinesWatch` schemes before running project validation. SDK visibility from `xcodebuild -showsdks` is not sufficient for the generic device builds on hosted runners, so the workflow installs missing platform payloads only when the actual scheme destinations are unavailable. CI requires an available iPhone simulator for runtime smoke tests; local runs can still skip simulator execution with `PINES_SKIP_SIMULATOR_TEST_RUN=1`. Regenerate `Pines.xcodeproj` with `bash scripts/ci/xcodegen.sh generate`; the wrapper pins XcodeGen `2.45.4` and verifies the release checksum so local and CI scheme output stay aligned.

The CodeQL workflow runs separately from the main CI gate on pull requests, pushes to `main`, a weekly schedule, and manual dispatch. Swift analysis uses a manual Xcode build so the database is built from the app target, while JavaScript/TypeScript analysis covers the Netlify/Astro site.

The release workflow uses the same Xcode validation phases as CI, verifies the iOS and watchOS scheme destinations before installing missing platforms, runs SwiftPM and Xcode with automatic package resolution disabled, validates the site build, builds an unsigned iOS archive from the committed deployment graph, and packages source artifacts. Keep both package lockfiles, `scripts/ci/select-xcode.sh`, `scripts/ci/run-xcode-validation.sh`, `scripts/ci/ensure-xcode-platforms.sh`, `ci.yml`, `codeql.yml`, and `release.yml` aligned when adding required checks.

Release artifacts include a CycloneDX SBOM generated from SwiftPM and npm lockfiles. The release workflow also creates GitHub artifact attestations for the source bundle, checksum, and SBOM.

## Release Tags

Release tags must use semantic version format:

```sh
v0.1.0
v0.2.0
v1.0.0
```

Create and push a release tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow validates the app, creates a source bundle, writes a SHA-256 checksum, and publishes a GitHub prerelease with generated release notes.

Release bundles must include the repository `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md` files. Pines is source-available under the PolyForm Noncommercial License 1.0.0 (`PolyForm-Noncommercial-1.0.0`), and commercial use requires a separate written license from RNT56. Third-party dependencies keep their own licenses.

## Manual Release

The release workflow also supports manual dispatch with a `tag` input. Use this only when the tag already exists or when the workflow should create/update assets for that tag.

## Current Artifact Policy

Until signing and App Store Connect automation are configured, releases publish source/developer-preview artifacts only:

- `pines-<tag>-source.tar.gz`
- `pines-<tag>-source.tar.gz.sha256`
- `pines-<tag>-sbom.cdx.json`
- validation logs as workflow artifacts

Do not publish an unsigned `.ipa`.

Production distribution remains blocked until signed archive export, TestFlight/App Store upload, real-device TurboQuant acceptance, and final App Store privacy review are configured and passed. The current TurboQuant compatibility pair is non-green: focused local gates and exact-pin physical-device smoke pass, but that smoke is synthetic attention-shape evidence. The latest Mac real-model baseline keeps dense K8/V4 as the compressed reference; K8/V3, K8/V2, and Sparse-V remain non-promoted until real-model benchmark/quality/fallback evidence and iOS evidence pass.

## v0.1.0 Preview Readiness

`v0.1.0` is ready to cut as a source/developer-preview release once CI for the target commit is complete. The app and extension marketing versions are already `0.1.0`, release packaging emits only source artifacts plus SHA-256 checksums, and the release workflow keeps unsigned archive validation separate from production distribution. The release validation job has a two-hour timeout because hosted macOS platform setup, simulator validation, and archive builds can exceed one hour.

Before pushing the tag, verify:

- `git status --short` is clean.
- `git tag --list v0.1.0` is empty.
- CI is complete and green for the commit to be tagged.
- `bash scripts/ci/check-public-hygiene.sh`
- `swift test --disable-automatic-resolution`
- `swift run --disable-automatic-resolution PinesCoreTestRunner`
- `npm --prefix site ci && npm --prefix site run build`
- `bash scripts/ci/run-xcode-validation.sh all`
- `bash scripts/ci/package-release.sh v0.1.0`

For TurboQuant-related release candidates, also verify that `docs/turboquant-implementation/compatibility-pair.json` is synchronized with `project.yml`, `Pines.xcodeproj`, the Xcode `Package.resolved`, and `MLXRuntimeBridge.turboQuantCompatibilityPairID`. A green compatibility pair requires native backend performance, real-model-inference performance parity or explicitly scoped capacity-mode status, current real-device app-host evidence, benchmark matrix coverage, lower-V/Sparse-V fallback evidence, and quality/memory/fallback gates; real-device profile evidence is still required before product compatibility labels can become `Verified` or `Certified`.

## Future TestFlight Pipeline

When Apple signing is ready, add repository or environment secrets:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_P8`
- signing certificate and provisioning profile material, or a managed signing service

Then extend `release.yml` to:

- build a signed archive
- export an `.ipa`
- upload to TestFlight
- attach final metadata to the GitHub Release
