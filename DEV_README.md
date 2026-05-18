# Pines Developer README

This is the technical handbook for Pines. The main [README](README.md) is user-facing; this file is for people building, auditing, extending, or performance-tuning the app.

Pines is a source-available iOS 26 AI workbench built around local MLX Swift inference, BYOK cloud routing, private vault context, MCP Streamable HTTP, policy-gated tools, GRDB persistence, optional CloudKit sync, Watch support, and pinned Schtack-maintained MLX forks.

## Fast Path

Use the checked-in scripts and lockfiles. The project is intentionally reproducible and CI rejects drift.

```sh
bash scripts/ci/xcodegen.sh generate
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
```

Full iOS validation requires a full Xcode install selected with `xcode-select`:

```sh
bash scripts/ci/run-xcode-validation.sh
```

For a direct generic iOS build:

```sh
xcodebuild -project Pines.xcodeproj -scheme Pines -destination 'generic/platform=iOS' build
```

Project generation is pinned through `scripts/ci/xcodegen.sh` to XcodeGen `2.45.4`. Use that wrapper, not a globally installed generator, when committing project changes.

## Platform And Toolchain

- App deployment target: iOS `26.0`.
- Watch target deployment: watchOS `26.0`.
- Xcode project source of truth: `project.yml`.
- Generated project: `Pines.xcodeproj`, committed and drift-checked.
- Swift package tools version: Swift `6.2`.
- XcodeGen Swift setting: Swift `6.0`.
- Package lockfiles:
  - `Package.resolved` for package/test checks.
  - `Pines.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` for the iOS app graph.

SwiftPM package products:

- `PinesCore`: platform-light contracts and domain logic.
- `PinesHubXetSupport`: Hugging Face/Xet support.
- `PinesWatchSupport`: shared phone/watch protocol types.
- `PinesCoreTestRunner`: framework-light verification runner.

Xcode targets:

- `Pines`: iOS app.
- `PinesLiveActivities`: model download Live Activity extension.
- `PinesWatch`: watchOS companion app.
- `PinesTests`: iOS-facing unit and runtime smoke tests.

## Repository Structure

- `Pines/App/`: app entry point, root view, presentation model, service composition, SwiftUI environment wiring.
- `Pines/Views/`: feature surfaces for Chats, Models, Vault, Settings, and shared app views.
- `Pines/Design/`: token-driven design system and reusable SwiftUI components.
- `Pines/Runtime/`: MLX runtime bridge, model lifecycle/downloads, Hugging Face credentials, runtime metrics, device monitor, compatibility shims.
- `Pines/Persistence/`: GRDB store, mapping, and CloudKit merge/apply support.
- `Pines/Cloud/`: BYOK cloud provider service, payloads, streaming adapters, CloudKit sync service.
- `Pines/MCP/`: Streamable HTTP client, wire payloads, OAuth, configured server service.
- `Pines/Agents/`: default tool-calling agent runtime.
- `Pines/Vault/`: document import, chunking, OCR/embedding orchestration, retrieval context.
- `Pines/Tools/`: Brave Search and WKWebView browser runtime implementations.
- `Pines/Watch/`: phone/watch session orchestration.
- `Pines/Feedback/`: haptics and interaction feedback.
- `Sources/PinesCore/`: testable contracts for inference, routing, model hub, tools, agents, vault, persistence schema, security, and architecture ownership.
- `Sources/PinesWatchSupport/`: shared watch protocol.
- `Sources/PinesHubXetSupport/`: Hugging Face/Xet package integration.
- `Tests/` and `PinesTests/`: Swift package tests and iOS target tests.
- `scripts/ci/`: reproducibility, hygiene, Xcode validation, release packaging, and MLX pin checks.
- `tools/`: local maintenance helpers such as MLX pin updates.
- `docs/`: deeper references for architecture, security, MCP, TurboQuant, releases, design, status, and App Store privacy.

## Architecture

Pines is split into a SwiftUI app layer and a platform-light core.

`PinesAppServices` is the composition root. It creates secrets, model catalog, preflight, execution routing, tool policy, redaction, MLX bridge services, runtime metrics, GRDB repositories, model lifecycle, vault ingestion, cloud providers, CloudKit sync, and MCP server services. SwiftUI views receive these through environment values and should not construct persistence, cloud, or inference services directly.

`PinesRootView` creates live services only after the boot mark reaches the first frame. Keep startup work lazy and measured; do not move expensive service construction into static environment defaults or preview paths.

`PinesArchitecture.modules` documents production ownership:

- Chats own conversations, messages, message FTS, attachments, message editing, and chat attachment staging.
- Models own model installs, downloads, lifecycle state, and compatibility presentation.
- Vault owns documents, chunks, vault FTS, source attachments, embeddings, retrieval events, and embedding jobs.
- Agents own runtime/tool policy, approvals, audit events, MCP tables, and opt-in cloud permissions.
- Settings own user preferences, provider configuration, theme selection, sync toggles, and service configuration.

Repository protocols live in `Sources/PinesCore/Architecture/AppArchitecture.swift`. GRDB/CloudKit implementations live behind those protocols so SwiftUI and orchestration code depend on contracts, not concrete storage.

Important repository contracts include:

- `ConversationRepository`
- `ModelInstallRepository`
- `VaultRepository`
- `SettingsRepository`
- `CloudProviderRepository`
- `MCPServerRepository`
- `ModelDownloadRepository`
- `AuditEventRepository`

## Persistence And Sync

The local store is GRDB/SQLite. Schema source of truth is `Sources/PinesCore/Persistence/DatabaseSchema.swift`; the current schema version is `12`.

When changing persistence:

- Add migrations only through `PinesDatabaseSchema.migrations`.
- Increment `currentVersion` when adding a migration.
- Keep table ownership reflected in `PinesArchitecture.modules`.
- Add or update repository protocol methods in `PinesCore` before wiring app code.
- Implement GRDB operations in `Pines/Persistence/GRDBPinesStore.swift` or a concern-specific extension.
- Keep CloudKit merge/apply/delete code in `GRDBPinesStore+CloudKit.swift`.
- Add indexes for list, sync, search, and vector-scan paths before the UI depends on them.
- Update core tests or `PinesCoreTestRunner` for schema contract changes.

CloudKit is optional and private-database scoped. Do not sync API keys, model binaries, prompt caches, generated embeddings/vector codes by default, transient browser/tool state, or local chat attachment files. Generated embeddings and compressed vector codes sync only when private iCloud sync and the separate embedding sync toggle are both enabled.

Personal Apple Developer accounts are safe by default. `PINES_CODE_SIGN_ENTITLEMENTS` and `PINES_ICLOUD_SWIFT_FLAGS` are empty in `project.yml`, so Xcode does not request iCloud provisioning. Paid-team CloudKit builds must override both:

```sh
xcodebuild \
  -project Pines.xcodeproj \
  -scheme Pines \
  PINES_CODE_SIGN_ENTITLEMENTS=Pines/Pines.entitlements \
  PINES_ICLOUD_SWIFT_FLAGS="-D PINES_CLOUDKIT_ENABLED" \
  build
```

The entitlement alone is not enough. `PINES_CLOUDKIT_ENABLED` is the runtime guard that lets `CloudKitSyncService.hasRequiredEntitlements()` return true.

## Security And Privacy Requirements

Pines is local-first by default. Chats, model state, vault documents, embeddings, attachments, and normal inference stay on device unless the user configures a BYOK provider and chooses a cloud route.

Hard requirements:

- Store API keys, MCP bearer tokens, and OAuth access/refresh tokens in Keychain through `SecretStore`.
- Never store secrets in SQLite, UserDefaults, CloudKit, logs, audit payloads, examples, screenshots, or test fixtures.
- Run diagnostic payloads through `Redactor` when they may contain user/provider data.
- Cloud execution must be BYOK-only.
- The router must never silently fall back from local inference to cloud.
- Local vault and MCP resource context must require per-turn approval before entering a cloud request.
- Browser, web, and MCP outputs are untrusted model context.
- Browser automation must require visible approval for login, checkout, posting, upload, credential-adjacent, and remote-state-changing actions.
- Tool execution is deny-by-default and must pass `ToolPolicyGate`.

Allowed execution modes:

- `localOnly`
- `preferLocal`
- `cloudAllowed`
- `cloudRequired`

If cloud is required but not configured, fail into a consent/configuration path rather than selecting a provider implicitly.

## Runtime And Performance Requirements

Performance-sensitive work must respect iOS memory pressure, thermal state, Low Power Mode, and the device profile returned by `DeviceRuntimeMonitor`.

TurboQuant is the requested default local KV-cache strategy. Pines requests the `metalPolarQJL` backend by default, reports requested/active backend and attention path diagnostics, and falls back to MLX packed attention when required by device capability or shape.

Device profile defaults from `DeviceProfile`:

| Profile | Max model bytes | Context | Small-model context | Prefill | Embedding batch | Vector scan | Vision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| A16 compact | 2.7 GB | 8,192 | 16,384 | 256 | 8 | 2,048 | no |
| A17 Pro balanced | 3.5 GB | 16,384 | 24,576 | 512 | 12 | 4,096 | yes |
| A18 standard | 3.8 GB | 16,384 | 24,576 | 512 | 12 | 4,096 | yes |
| A18 Pro | 5.0 GB | 16,384 | 32,768 | 768 | 16 | 8,192 | yes |
| A19 standard/thin | 5.5 GB | 16,384 | 32,768 | 1,024 | 16 | 8,192 | yes |
| A19 Pro sustained | 7.0 GB | 32,768 | 65,536 | 1,024 | 24 | 16,384 | yes |
| Future verified/max | 8.0 GB | 32,768 | 65,536 | 1,024 | 32 | 16,384 | yes |

Downshift rules:

- Serious/critical thermal state or Low Power Mode caps context and small-model context at `4,096`, prefill at `256`, embedding batch at `4`, vector scan at `1,024`, disables vision defaults, and uses conservative TurboQuant policy.
- Available memory below `750 MB` applies the same caps and prefers memory.
- A19 Pro thin devices downshift under fair thermal state to at most `16,384` context and `512` prefill.
- iOS memory warnings must stop the active local run and unload transient MLX containers.

Runtime development rules:

- Do not add unbounded vector scans, attachment reads, provider buffers, or prompt assembly.
- Use streaming APIs and incremental persistence for long responses.
- Keep vault embedding ingestion batched by the active device profile.
- Preserve compressed-candidate retrieval plus FP16 rerank before falling back to SQLite FTS.
- Keep runtime diagnostics read-only and visible in Models/Settings where relevant.
- Log startup phases, generation throughput, vault retrieval latency, memory-pressure events, and MetricKit availability through `PinesRuntimeMetrics`.
- Treat device model names as hints; verified MLX capabilities decide whether compressed Metal attention is active.

Current app-level limits and defaults:

- Default local max completion tokens: `1,024`.
- Default cloud max completion tokens: `16,384`.
- Completion token clamp: `128...128,000`.
- Local context clamp: `1,024...262,144`.
- Chat attachments are capped at eight files per draft.
- MCP decoded blob previews are capped at `10 MB`.
- MCP text output passed back to model context is capped in service code.
- Default agent policy: `8` steps, `6` tool calls, `120` seconds wall time.
- Normal chat does not advertise every registered tool; Agent mode and MCP sampling have separate policy gates.

## MLX Fork Pins

The iOS app links exact maintained MLX fork revisions through `project.yml` and the generated Xcode project:

- `MLXSwift`: `https://github.com/RNT56/mlx-swift` at `48375f1d8f0694dee2ce8aab7f46be50c5297aec`
- `MLXSwiftLM`: `https://github.com/RNT56/mlx-swift-lm` at `fbae29300f38e9988a010997828e2aa08a32c338`
- Nested `mlx` inside `MLXSwift`: `292c54b7bbf95a7061b3d70c05c1785dfb9b9a85`
- Nested `mlx-c` inside `MLXSwift`: `f53f40c7a5d0db5cb2a8661e67e29a18470d8863`

These pins are intentional because Pines consumes additive TurboQuant and compatibility APIs not assumed to exist in upstream package releases yet.

Use the helper to move pins:

```sh
tools/update-mlx-pins.sh
```

CI checks that `project.yml` and `Pines.xcodeproj` agree, that pins are not below known-good minimums, that obsolete revisions are absent, and that nested `mlx`/`mlx-c` revisions match expectations. Do not edit Xcode DerivedData package checkouts.

## Model Discovery And Downloads

Model discovery uses Hugging Face primitives to query MLX-tagged models and fetch preflight metadata:

- `config.json`
- tokenizer files
- processor config
- generation config
- safetensors files and size
- repository tags and license

### Discovery Resource Filter

Pines filters Hugging Face discovery results through `ModelDiscoveryResourcePolicy` before presenting them as downloadable local models. The policy is intentionally in `PinesCore`, not in a SwiftUI view, so the same decision can be reused by search result preparation, late metadata enrichment, manual preflight, and install guardrails.

The current filter level is tied to `DeviceProfile.recommendedMaxModelBytes`, which is the app's on-device weight/download ceiling for the active hardware profile:

| Device profile | Current discovery ceiling | Rationale |
| --- | ---: | --- |
| `compactA16Phone` | 2.7 GB | Keeps room for iOS, app state, tokenizer/model configs, Metal heaps, KV cache, and thermal downshift on 6 GB-class devices. |
| `balancedPhone` / A17 Pro | 3.5 GB | Targets 8 GB-class iPhone/iPad hardware without making 4B 4-bit models the default safe path. |
| A18 standard | 3.8 GB | Slightly higher than A17 Pro, but still below common 4B MLX downloads. |
| `proPhone` / A18 Pro | 5.0 GB | Allows selected 4B-class quantized models while leaving KV-cache and UI headroom. |
| A19 standard / A19 Pro thin | 5.5 GB | Uses the stronger latest phone silicon, but keeps thin chassis and sustained-memory risk conservative. |
| A19 Pro sustained | 7.0 GB | Allows larger quantized models only on the sustained Pro profile. |
| `maxTabletOrMac` | 8.0 GB | For high-memory iPad/Mac-class devices. Future verified devices with less than 14 GB physical memory are capped back to 5.5 GB. |

These are download/weight ceilings, not total process-memory ceilings. Local inference also needs KV cache, prompt cache, processor tensors for VLMs, temporary MLX allocations, vault embeddings, app UI state, and free memory for iOS. A model that barely fits on disk can still be a bad runtime default if it leaves no sustained headroom.

As of 2026-05-18, Apple Support lists iPhone 17 as A19, iPhone 17 Pro as A19 Pro, iPad mini as A17 Pro, and iPad Pro M5 as 12 GB RAM for 256/512 GB storage or 16 GB RAM for 1/2 TB storage:

- https://support.apple.com/125089
- https://support.apple.com/125090
- https://support.apple.com/en-us/121456
- https://support.apple.com/en-za/125406

Apple's iPhone technical specs do not publish RAM, so the runtime must keep using `ProcessInfo.processInfo.physicalMemory`, the hardware identifier map in `DeviceProfile`, and MLX/Metal self-test status rather than hard-coding phone RAM assumptions from third-party teardown reports.

Filtering order:

1. Exact downloadable file size wins. Search asks Hugging Face for blob metadata and the policy sums only files Pines would download: `*.safetensors`, `*.json`, `*.jinja`, tokenizer `.model`, `.txt`, and `.tiktoken`, ignoring hidden paths and text-only processor configs.
2. If exact sizes are above the device profile ceiling, the result is rejected immediately.
3. If file sizes are incomplete, the policy falls back to repository/tag hints. It parses parameter tokens such as `8B`, `1_7B`, `130M`, MoE totals such as `8x7B`, and total-vs-active names such as `21B-A3B`.
4. Quantization hints are parsed from names/tags such as `4bit`, `4-bit`, `Q4_K_M`, `NF4`, `MXFP8`, `FP8`, `BF16`, and `FP16`. If no quantization hint exists, the fallback estimate assumes 16-bit weights. For <=4-bit MLX repos, the fallback uses a conservative 1 byte per parameter floor because published MLX safetensor downloads often include packing/scales/metadata overhead and can be much closer to 1 byte/parameter than the theoretical bit width.
5. Search preparation skips rejected results. Metadata enrichment can remove a previously shown result when exact sizes arrive later. Manual preflight marks oversized repos unsupported. Install resolves missing HEAD sizes and rejects again before creating the queued download.

Unknown-size repositories with no parameter or quantization signal are not rejected at search time, because there is no defensible way to distinguish a tiny repo with incomplete metadata from a huge repo with incomplete metadata. The install path still resolves remote file sizes before downloading and applies the same ceiling.

To adjust this for new devices or runtime changes:

- Update `DeviceProfile` byte ceilings and hardware identifier mapping first. That is the source of truth for the app's local-runtime resource class.
- If MLX quantized safetensor storage becomes materially smaller or larger, adjust `ModelDiscoveryResourcePolicy.quantizedBytesPerParameterFloor`.
- Add parser coverage in `CoreContractTests` for new naming patterns before relying on them in discovery.
- Keep curated models separate. Curated status can make a model recommended or verified, but it must not bypass the resource filter.

Curated models are separate from discoverable models. Keep curated recommendations conservative and device-aware. 1-bit/BitNet models stay experimental unless the exact repository/device combination is verified.

Downloads are staged, resumable through byte ranges, checksum-verified when Hugging Face exposes an LFS SHA-256, and atomically promoted into the app model directory.

When adding model-family support:

- Update `ModelPreflightClassifier`.
- Add curated manifest entries only when compatibility is known.
- Add app-level compatibility shims in model-family files such as `MLXCompatibleModels+Llama4.swift`.
- Keep `PinesCore` contracts platform-light.
- Add package or iOS smoke coverage when the runtime surface changes.

## Cloud Providers

BYOK provider support is split between core contracts and app adapters.

- Core provider types live under `Sources/PinesCore/Cloud/`.
- App request/stream handling lives in `Pines/Cloud/BYOKCloudInferenceProvider.swift`.
- Provider payload details live in `BYOKCloudInferenceProvider+Payloads.swift`.
- Stream metadata parsing lives in `CloudProviderStreamParser.swift`.
- Secrets must go through Keychain services.

When adding or changing a provider:

- Keep request construction typed and provider-specific.
- Preserve streaming behavior and typed `InferenceEvent` output.
- Validate attachment capability checks before encoding files into a request.
- Parse provider metadata without leaking keys or raw sensitive payloads into logs.
- Add tests for stream parser edge cases.
- Keep cloud route selection explicit through `ExecutionRouter`.

## Vault And Retrieval

Vault ingestion turns user-selected files into local documents, chunks, embeddings, and retrieval context.

Rules:

- User-selected imports are staged under app support storage.
- HEIC/HEIF chat imports are converted to JPEG before provider capability checks.
- Empty or oversized files must be rejected before request construction.
- Imported chunks store FP16 embeddings for exact rerank and compressed TurboQuant-compatible codes for approximate candidate retrieval.
- Search filters by embedding model where possible, bounds candidate scans by device profile, reranks with FP16 cosine, and falls back to SQLite FTS when embeddings are unavailable.
- Retrieval events should record latency, result count, and whether vector search was used.

When changing retrieval quality or performance, update `docs/TURBOQUANT.md` and tests alongside the implementation.

## Tools, Agents, And MCP

Tool definitions are typed, versioned, schema-backed, and include:

- JSON schema
- permissions
- side-effect level
- network policy
- timeout
- explanation requirement

Built-in tool specs live in `Sources/PinesCore/Agent/BuiltInToolSpecs.swift`; execution implementations live in `Pines/Tools/` or feature services. Calculator is local. Brave Search is BYOK. Browser automation uses an isolated non-persistent `WKWebView` runtime.

Agent execution has replaceable seams:

- `AgentRuntime` owns one run and streams inference events back to chat.
- `AgentRuntimeFactory` creates runtimes from app services.
- `AgentToolCatalog` supplies Agent-mode tool inventory independently from normal chat.
- `AgentRuntimeCallbacks` carries human approval and progress reporting.

MCP support is user-driven:

- `MCPStreamableHTTPClient.swift`: transport, session headers, JSON-RPC, OAuth exchange, event parsing, local HTTP policy.
- `MCPStreamableHTTPPayloads.swift`: wire DTOs and JSON helpers.
- `MCPServerService.swift`: configured servers, discovered tools/resources/prompts, subscriptions, selected context, sampling review state.

MCP rules:

- Transport is Streamable HTTP.
- Auth modes are none, static bearer token, and OAuth PKCE.
- Production servers should use HTTPS; plain HTTP is only for explicit local development endpoints.
- Tools are namespaced as `mcp.<server>.<tool>`.
- Resources are never injected into chat automatically.
- Binary resource MIME types must be allowlisted.
- Sampling runs only when enabled for the server and approved by the user.
- MCP sampling may use BYOK only when BYOK sampling is enabled for that server.
- Global chat execution mode is not implicitly reused for sampling.
- Pines does not currently advertise MCP roots.

## Design And Frontend Standards

All app UI must use the environment-driven design system.

- Tokens, templates, theme resolution, spacing, radii, materials, motion, and semantic roles live in `PinesDesignSystem.swift`.
- Reusable controls, rows, empty states, cards, panels, pills, haptics modifiers, and view modifiers live in `PinesDesignComponents.swift`.
- Feature-specific layout belongs under `Pines/Views/<Feature>/`.
- New screens should read `@Environment(\.pinesTheme)` and use semantic tokens.
- Do not introduce feature-local palettes, hard-coded light/dark colors, or one-off card/row styles when a shared primitive belongs in the design system.
- Respect Reduce Motion.
- Keep operational screens dense and scannable; do not build marketing hero layouts inside the app.

Current themes: Evergreen, Graphite, Aurora, Paper, Slate, Porcelain, Sunset, and Obsidian. Interface modes: System, Light, and Dark.

## Scaffolding Recipes

Use these paths when adding production surface area.

New feature:

- Add ownership to `PinesArchitecture.modules`.
- Add core contracts in `Sources/PinesCore/` if the feature has persistence, routing, or policy surface.
- Add repository methods before app implementation.
- Wire live services in `PinesAppServices`.
- Inject through environment values instead of constructing services in views.
- Add SwiftUI surface under `Pines/Views/<Feature>/`.
- Use shared design tokens/components.
- Add core tests and app surface tests proportional to blast radius.

New database-backed entity:

- Add a migration and increment schema version.
- Add table ownership to architecture metadata.
- Add repository methods and DTOs in `PinesCore`.
- Implement GRDB mapping and repository methods.
- Decide explicitly whether it syncs through CloudKit.
- Add indexes for expected list/search/sync access patterns.
- Add migration and repository tests.

New tool:

- Add or update `ToolSpec`.
- Include schema, permissions, network policy, side-effect level, timeout, and explanation requirement.
- Register through the shared `ToolRegistry`.
- Enforce through `ToolPolicyGate`.
- Emit audit events with redacted payloads.
- Add approval UI if it can touch network, browser, files, photos, clipboard, cloud context, or remote state.

New cloud provider:

- Add core provider kind/contracts.
- Implement typed payload and streaming parser.
- Store credentials through Keychain only.
- Add validation, model catalog refresh, default model selection, and deletion behavior.
- Add capability checks for text, image, PDF, and tool payloads.
- Add stream parser tests and routing tests.

New MCP capability:

- Update payload DTOs first.
- Keep transport/session logic in `MCPStreamableHTTPClient`.
- Coordinate discovered state and settings in `MCPServerService`.
- Persist server state through `MCPServerRepository`.
- Add user controls before enabling context, tools, prompts, subscriptions, or sampling by default.
- Add audit events for approval, denial, and returned/blocked sampling responses.

New model family:

- Extend preflight classification.
- Add MLX compatibility shim in a family-specific file.
- Add curated manifest entries only after verified support.
- Add runtime smoke tests if MLX symbols or generation parameters change.

## Testing And Validation

Run the fastest meaningful checks before handing off:

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
```

Run Xcode validation for app-facing, project-generation, or dependency graph changes:

```sh
bash scripts/ci/run-xcode-validation.sh
```

Useful targeted scripts:

```sh
bash scripts/ci/check-public-hygiene.sh
bash scripts/ci/check-privacy-manifest.sh
bash scripts/ci/check-third-party-notices.sh
bash scripts/ci/check-mlx-package-pins.sh
bash scripts/ci/check-mlx-upstream-sync.sh
```

Testing expectations:

- Core contracts need Swift package tests.
- App surface and runtime bridge behavior need `PinesTests`.
- Environment-constrained checks belong in `PinesCoreTestRunner`.
- Stream parsers need malformed, partial, and provider-specific metadata cases.
- Persistence changes need migration and repository tests.
- Performance changes need device-profile and memory/thermal behavior tests where possible.

## CI And Release

CI runs on pull requests, pushes to `main`, and manual dispatch.

Main jobs:

- `swift-core`: public hygiene, Swift package build, `swift test`, and `PinesCoreTestRunner` with automatic package resolution disabled.
- `xcode-project`: XcodeGen generation, drift checks, locked package resolution, unsigned generic iOS build, simulator build-for-testing, simulator smoke tests when available, generated-project restoration, and lockfile drift checks.

The iOS job uses the `macos-26` hosted runner and verifies required iOS/watchOS build destinations before validation. SDK visibility from `xcodebuild -showsdks` is not enough; the workflow installs missing platform payloads only when actual scheme destinations are unavailable.

Release tags use semantic version format:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Releases currently publish source/developer-preview artifacts with SHA-256 checksums. Do not publish an unsigned `.ipa`. Production distribution remains blocked until signed archive export, TestFlight/App Store upload, real-device TurboQuant acceptance, and final App Store privacy review are configured and passed.

## Implementation Status

Implemented foundation:

- SwiftUI app shell with Chats, Models, Vault, Agents, and Settings surfaces.
- GRDB-backed persistence and repository protocols.
- Core inference/provider/model contracts with typed stream events.
- Local/cloud execution routing.
- Hugging Face discovery and model preflight.
- MLX runtime bridge and compatibility layers.
- TurboQuant runtime defaults, diagnostics, compressed vault embeddings, approximate vector search, and FP16 rerank.
- BYOK adapters for OpenAI-compatible providers, OpenRouter, Anthropic, and Gemini.
- Chat attachments for images, HEIC/HEIF as staged JPEG, PDFs, and common text-like files.
- Vault import pipeline with chunking, OCR, embedding invocation, and retrieval.
- Tool registry, policy gate, calculator, Brave Search BYOK, browser runtime, and agent policy model.
- MCP Streamable HTTP support for tools, resources, prompts, sampling, subscriptions, bearer tokens, and OAuth PKCE.
- Optional CloudKit private database sync.
- Watch support, Live Activity model download support, diagnostics, audit events, and CI validation.

Known remaining product work is tracked in [docs/STATUS.md](docs/STATUS.md). Keep that file updated when implementation reality changes.

## Documentation Index

- [Architecture](docs/ARCHITECTURE.md)
- [Security And Privacy](docs/SECURITY.md)
- [TurboQuant](docs/TURBOQUANT.md)
- [MCP Support](docs/MCP.md)
- [Design System](docs/DESIGN_SYSTEM.md)
- [Release Process](docs/RELEASES.md)
- [App Store Privacy](docs/APP_STORE_PRIVACY.md)
- [Implementation Status](docs/STATUS.md)

## Contribution Rules

- Keep app UI in `Pines/`.
- Keep testable domain/runtime contracts in `Sources/PinesCore/`.
- Do not make SwiftUI views construct persistence, cloud, or inference services directly.
- Add new feature ownership to `PinesArchitecture.modules`.
- Add new theme values to `PinesDesignSystem.swift` and reusable UI primitives to `PinesDesignComponents.swift`.
- Split large app files by concern using companion files such as `+CloudKit`, `Payloads`, `Support`, `Types`, `Components`, or model-family files.
- Keep MLX fork pins aligned in `project.yml`, `Pines.xcodeproj`, and docs.
- Do not point the app at upstream MLX package releases until required TurboQuant APIs are available there.
- Do not commit secrets, local environment files, DerivedData, `.build`, or machine-specific Xcode user state.

## License

Pines is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`). You may use, modify, and redistribute this repository only for permitted noncommercial purposes under that license. Commercial use requires a separate written license from Schtack.

Redistributions must preserve the required notices in [NOTICE](NOTICE). Third-party dependencies keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
