<p align="center">
  <img src="Pines/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" alt="pines logo" width="144" height="144">
</p>

<h1 align="center">pines</h1>

<p align="center">
  <a href="https://github.com/RNT56/pines/actions/workflows/ci.yml"><img src="https://github.com/RNT56/pines/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-informational" alt="License: PolyForm Noncommercial 1.0.0"></a>
</p>

`pines` is an iOS 26-only, local-first AI workbench scaffolded for MLX Swift inference.

The repository contains:

- `Pines/`: SwiftUI iOS application shell, design system, app icon assets, and runtime bridge points.
- `Sources/PinesCore/`: testable core domain, routing, model catalog, tools, vault, persistence schema, and cloud/BYOK abstractions.
- `Sources/PinesCore/Architecture/`: module ownership and repository contracts for production feature boundaries.
- `Sources/PinesCoreTestRunner/`: framework-free checks for the non-UI production contracts.
- `.github/workflows/`: CI and GitHub Release automation.
- `project.yml`: XcodeGen configuration for the iOS project.

## Architecture

The app is split into production seams:

- `PinesAppServices` is the composition root for secrets, model catalog, preflight, execution routing, tool policy, redaction, and MLX bridge services.
- `PinesArchitecture.modules` documents feature ownership for Chats, Models, Vault, Agents, and Settings, including database tables and dependencies.
- Repository protocols in `PinesCore` isolate persistence from SwiftUI and let GRDB/CloudKit implementations replace seed data without changing views.
- Agent/cloud routing remains explicit: cloud execution is opt-in through `AgentPolicy` and is never a silent fallback.
- TurboQuant is the requested default local KV-cache strategy. Pine requests the paper-exact Metal backend, reports native Metal codec and compressed-attention availability, falls back to MLX packed attention when needed, and stores compressed vault embeddings locally for approximate search plus FP16 rerank. Runtime defaults adapt to iOS memory/thermal state, including compact 6 GB device guardrails. See `docs/TURBOQUANT.md`.

## Design System

`PinesDesignSystem.swift` defines the complete app style surface:

- User-selectable templates: Evergreen, Graphite, Aurora, and Paper.
- Interface modes: System, Light, and Dark.
- Semantic colors, typography, spacing, radii, strokes, shadows, materials, and motion curves.
- Environment injection through `\.pinesTheme`, so every screen inherits the selected template.
- Settings includes live template previews and mode selection.

Generate the Xcode project:

```sh
xcodegen generate
```

Run available local core checks:

```sh
swift run PinesCoreTestRunner
```

The active Command Line Tools install on this machine does not expose XCTest or Swift Testing, so the repository includes a framework-free executable test runner. Full iOS compilation requires a full Xcode install selected via `xcode-select`; this machine currently exposes Command Line Tools only.

## CI And Releases

CI runs on pull requests, pushes to `main`, and manual dispatch. It performs public-repo hygiene checks, builds the Swift package, runs `PinesCoreTestRunner`, regenerates the Xcode project, and builds the iOS app without signing on the `macos-26` runner.

GitHub Releases are tag-driven. Push a semantic tag such as `v0.1.0` to run release validation and publish a source/developer-preview release with checksums:

```sh
git tag v0.1.0
git push origin v0.1.0
```

See:

- `docs/ARCHITECTURE.md`
- `docs/DESIGN_SYSTEM.md`
- `docs/SECURITY.md`
- `docs/STATUS.md`
- `docs/RELEASES.md`

## License

Pines is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`). You may use, modify, and redistribute this repository only for permitted noncommercial purposes under that license. Commercial use requires a separate written license from Schtack.

Redistributions must preserve the required notices in [NOTICE](NOTICE). Third-party dependencies keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
