# Pines Developer README

This is the technical on-ramp for Pines. The main [README](README.md) is intentionally user-facing; this file keeps build steps, repository layout, implementation status, fork pins, and release mechanics in one place.

Pines is a source-available iOS 26 AI workbench built around MLX Swift inference, BYOK cloud routing, private vault context, MCP Streamable HTTP, and pinned Schtack-maintained MLX forks.

## Status

This repository is a working foundation, not a complete App Store-ready MLX client yet.

Implemented today:

- SwiftUI app shell with Chats, Models, Vault, Agents, and Settings surfaces.
- GRDB-backed local persistence and repository protocols.
- Core inference/provider/model contracts with typed stream events.
- Local/cloud routing modes: `localOnly`, `preferLocal`, `cloudAllowed`, and `cloudRequired`.
- Hugging Face model discovery, preflight classification, resumable install/delete support, and curated model manifests.
- MLX runtime bridge, model-family compatibility layers, and pinned MLX fork integration.
- TurboQuant runtime defaults, diagnostics, compressed vault embeddings, approximate vector search, and FP16 rerank.
- BYOK streaming adapters for OpenAI-compatible providers, OpenRouter, Anthropic, and Gemini.
- Chat attachments for images, HEIC/HEIF as staged JPEG, PDFs, and common text-like files.
- Vault import pipeline with chunking, OCR, embedding invocation, and local search.
- Agent/tool policy models, tool registry, calculator, Brave Search BYOK, and browser observe/action runtime.
- MCP Streamable HTTP support for tools, resources, prompts, sampling, subscriptions, bearer tokens, and OAuth PKCE.
- Optional CloudKit private database sync behind paid-team build settings and runtime guards.
- iOS runtime guardrails for memory pressure, thermal state, compact 6 GB devices, bounded vector scans, and batched embedding ingestion.
- Watch support, Live Activity model download support, diagnostics, audit events, and CI validation.

Still being finished:

- Real-device TurboQuant acceptance across the A16 through A19 Pro hardware matrix.
- Production UX hardening for regenerate flows, provider editing, CloudKit conflict handling, and model compatibility messaging.
- Final App Store privacy validation against the resolved package graph.
- Further semantic splits of the remaining large orchestration and settings/model presentation files.

For the full ledger, see [docs/STATUS.md](docs/STATUS.md).

## Build

Generate the Xcode project:

```sh
xcodegen generate
```

Use XcodeGen `2.45.4` or newer so generated project and scheme files match CI.

Run the local core checks:

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
```

Full iOS compilation requires a full Xcode install selected with `xcode-select`.

```sh
xcodebuild -project Pines.xcodeproj -scheme Pines -destination 'generic/platform=iOS' build
```

The generated app target is safe for personal Apple Developer accounts by default. `PINES_CODE_SIGN_ENTITLEMENTS` and `PINES_ICLOUD_SWIFT_FLAGS` are empty, so Xcode does not ask a personal team to provision iCloud.

Paid-team CloudKit builds must opt in to both the entitlement and the runtime flag:

```sh
xcodebuild \
  -project Pines.xcodeproj \
  -scheme Pines \
  PINES_CODE_SIGN_ENTITLEMENTS=Pines/Pines.entitlements \
  PINES_ICLOUD_SWIFT_FLAGS="-D PINES_CLOUDKIT_ENABLED" \
  build
```

## Repository Map

- `Pines/`: SwiftUI iOS app, design system, runtime bridge points, persistence adapters, CloudKit sync, MCP client, tools, watch orchestration, and feature views.
- `Sources/PinesCore/`: testable domain contracts for inference, routing, models, vault, tools, agents, persistence schema, cloud providers, security, and architecture ownership.
- `Sources/PinesCore/Architecture/`: module ownership and repository contracts for production feature boundaries.
- `Sources/PinesCoreTestRunner/`: framework-light smoke runner for constrained developer and CI environments.
- `PinesTests/` and `Tests/`: iOS-facing and core contract tests.
- `.github/workflows/`: CI, release validation, and MLX upstream reachability automation.
- `project.yml`: XcodeGen source of truth for the generated iOS project.
- `Package.resolved`: committed SwiftPM lockfile for package/test checks.
- `Pines.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: committed Xcode app lockfile for the deployed iOS graph.

## Architecture Notes

`PinesAppServices` is the composition root for secrets, model catalog, preflight, execution routing, tool policy, redaction, MLX bridge services, and the GRDB-backed repository set. The default SwiftUI environment uses a no-store preview instance; live services are created after the boot mark is visible.

`PinesArchitecture.modules` documents feature ownership for Chats, Models, Vault, Agents, and Settings, including database tables and dependencies.

Repository protocols in `PinesCore` isolate persistence from SwiftUI and let GRDB/CloudKit implementations replace seed data without changing views.

Normal chat routing remains explicit. Local models are preferred by default, selected BYOK providers can be used when configured, and private vault/MCP context requires per-turn approval before it is sent to cloud. Agent and MCP sampling flows keep their own policy gates.

Chat supports local attachments for common image, PDF, and text-like files. HEIC/HEIF imports are staged as JPEG chat attachments, attachment-only messages get explicit analysis prompts, and message rows expose copy, edit, and add-attachments-to-Vault actions.

App-level implementation files are split by concern:

- `PinesAppModelTypes.swift`: app model DTOs.
- `GRDBPinesStore+CloudKit.swift`: CloudKit persistence merge logic.
- `PinesDesignComponents.swift`: reusable design components.
- `MCPStreamableHTTPPayloads.swift`: MCP wire payloads.
- `ModelDownloadSupport.swift`: model download support.
- `MLXCompatibleModels+Llama4.swift` and `MLXCompatibleModels+DeepseekV4.swift`: model-family compatibility.

TurboQuant is the requested default local KV-cache strategy. Pines requests the paper-exact Metal backend, reports native Metal codec and compressed-attention availability, falls back to MLX packed attention when needed, and stores compressed vault embeddings locally for approximate search plus FP16 rerank. Runtime defaults adapt to iOS memory and thermal state, including compact 6 GB device guardrails. See [docs/TURBOQUANT.md](docs/TURBOQUANT.md).

## MLX Fork Pins

The iOS app links maintained MLX forks through `project.yml` and the generated Xcode project:

- `MLXSwift`: `https://github.com/RNT56/mlx-swift` at `5db40d34a96a9c6889b6583d6cc09f8b8f05ea5e`
- `MLXSwiftLM`: `https://github.com/RNT56/mlx-swift-lm` at `e39787395c977549e1ba112ee2fd7eb509d57f30`
- Nested `mlx` inside `MLXSwift`: `d999c27ecd549e65f8f689bdd5c83648da977b81`

These pins are intentional because the app consumes additive TurboQuant and compatibility APIs that are not assumed to exist in upstream package releases yet.

Use `tools/update-mlx-pins.sh` to move the reproducible SHAs and regenerate `Pines.xcodeproj`. CI checks that `project.yml` and the generated project agree, that pins do not fall below known-good minimums, and that the nested `mlx` submodule is the expected revision. Renovate is configured to propose pin updates by PR instead of moving app builds to branch references.

## CI And Releases

CI runs on pull requests, pushes to `main`, and manual dispatch. It performs public-repo hygiene checks, including privacy-manifest linting, package builds with automatic resolution disabled, `swift test`, `PinesCoreTestRunner`, XcodeGen regeneration, generated-project drift checks, lockfile drift checks, unsigned iOS builds, simulator build-for-testing, and simulator smoke tests when an iPhone simulator is available on the runner.

GitHub Releases are tag-driven. Push a semantic tag such as `v0.1.0` to run release validation and publish a source/developer-preview release with checksums:

```sh
git tag v0.1.0
git push origin v0.1.0
```

See [docs/RELEASES.md](docs/RELEASES.md) for the full release process.

## Technical Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Design System](docs/DESIGN_SYSTEM.md)
- [Security And Privacy](docs/SECURITY.md)
- [MCP Support](docs/MCP.md)
- [TurboQuant](docs/TURBOQUANT.md)
- [Release Process](docs/RELEASES.md)
- [Implementation Status](docs/STATUS.md)

## License

Pines is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`). You may use, modify, and redistribute this repository only for permitted noncommercial purposes under that license. Commercial use requires a separate written license from Schtack.

Redistributions must preserve the required notices in [NOTICE](NOTICE). Third-party dependencies keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
