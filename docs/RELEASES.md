# Release Process

`pines` uses GitHub Actions for CI and GitHub Releases for source/developer-preview releases.

## CI

CI runs on pull requests, pushes to `main`, and manual dispatch.

Jobs:

- `swift-core`: public-repo hygiene, Swift package build, and `PinesCoreTestRunner`.
- `xcode-project`: XcodeGen project generation, generated-project drift check, package resolution, and unsigned generic iOS build.

The iOS job uses the `macos-26` GitHub-hosted runner so Xcode 26 and iOS 26 SDKs are available.

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

## Manual Release

The release workflow also supports manual dispatch with a `tag` input. Use this only when the tag already exists or when the workflow should create/update assets for that tag.

## Current Artifact Policy

Until signing and App Store Connect automation are configured, releases publish source/developer-preview artifacts only:

- `pines-<tag>-source.tar.gz`
- `pines-<tag>-source.tar.gz.sha256`
- validation logs as workflow artifacts

Do not publish an unsigned `.ipa`.

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
