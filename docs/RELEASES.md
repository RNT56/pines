# Release Process

`pines` uses GitHub Actions for CI and GitHub Releases for source/developer-preview releases.

## CI

CI runs on pull requests, pushes to `main`, and manual dispatch.

Jobs:

- `swift-core`: public-repo hygiene, Swift package build, `swift test`, and `PinesCoreTestRunner`. SwiftPM commands run with automatic resolution disabled so CI honors the committed `Package.resolved` graph.
- `xcode-project`: XcodeGen project generation, generated-project drift check, package resolution, unsigned generic iOS build, simulator build-for-testing, and simulator runtime smoke tests when an iPhone simulator is available.

The iOS job uses the `macos-26` GitHub-hosted runner so Xcode 26 and iOS 26 SDKs are available. Keep local XcodeGen at `2.45.4` or newer before regenerating `Pines.xcodeproj`.

The release workflow uses the same Xcode validation script as CI, runs SwiftPM with automatic package resolution disabled, builds an unsigned iOS archive, and packages source artifacts. Keep `scripts/ci/run-xcode-validation.sh`, `ci.yml`, and `release.yml` aligned when adding required checks.

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

The release workflow validates the app, creates a source bundle, writes a SHA-256 checksum, and publishes a GitHub Release with generated release notes.

Release bundles must include the repository `LICENSE`, `NOTICE`, and `THIRD_PARTY_NOTICES.md` files. Pines is source-available under the PolyForm Noncommercial License 1.0.0 (`PolyForm-Noncommercial-1.0.0`), and commercial use requires a separate written license from Schtack. Third-party dependencies keep their own licenses.

## Manual Release

The release workflow also supports manual dispatch with a `tag` input. Use this only when the tag already exists or when the workflow should create/update assets for that tag.

## Current Artifact Policy

Until signing and App Store Connect automation are configured, releases publish source/developer-preview artifacts only:

- `pines-<tag>-source.tar.gz`
- `pines-<tag>-source.tar.gz.sha256`
- validation logs as workflow artifacts

Do not publish an unsigned `.ipa`.

Production distribution remains blocked until signed archive export, TestFlight/App Store upload, real-device TurboQuant acceptance, and final App Store privacy review are configured and passed.

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
