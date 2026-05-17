# Architecture

`pines` is structured as a modular iOS app with a testable Swift core and a SwiftUI presentation layer. The current repository is a production-oriented foundation with live GRDB persistence, MLX runtime bridges, BYOK cloud providers, CloudKit sync, MCP Streamable HTTP support, and vault ingestion isolated behind protocols so features can evolve without reshaping the app.

## Layers

- `Pines/`: iOS application target, SwiftUI screens, composition root, design system, runtime bridges, assets, entitlements, and privacy manifest.
- `Sources/PinesCore/`: platform-light core contracts for inference, model catalog, persistence schema, tools, agents, vault indexing, cloud providers, redaction, and feature ownership.
- `Tests/PinesCoreTests/`: Swift Testing coverage for core contracts.
- `PinesTests/`: iOS-target unit coverage for app-facing surface contracts.
- `Sources/PinesCoreTestRunner/`: framework-free verification runner for environments where Command Line Tools do not expose XCTest or Swift Testing.
- `project.yml`: XcodeGen source of truth for the Xcode project.

## Composition Root

`PinesAppServices` owns service construction for the app layer. The default SwiftUI environment creates a no-store instance for previews and early view construction; `PinesRootView` creates live services only after the boot mark has reached the first frame.

- `SecretStore`
- `HuggingFaceModelCatalogService`
- `ModelPreflightClassifier`
- `ExecutionRouter`
- `ToolRegistry`
- `ToolPolicyGate`
- `AgentRuntimeFactory`
- `AgentToolCatalog`
- `Redactor`
- `MLXRuntimeBridge`
- `PinesRuntimeMetrics`
- `GRDBPinesStore`
- `ModelLifecycleService`
- `VaultIngestionService`
- `CloudProviderService`
- `CloudKitSyncService`
- `MCPServerService`

Agent execution is injected through `AgentRuntimeFactory`, which produces an `AgentRuntime` per run. The default factory builds the current tool-calling `AgentRunner` with the selected provider, session policy, tool registry, policy gate, audit repository, approval callback, and activity callback. `AgentToolCatalog` separately owns the advertised Agent-mode tool set. Chat and Watch orchestration depend only on these protocols, so a future planner/executor stack, vendor agent SDK, or different tool runtime can replace the default implementation from `PinesAppServices` without rewriting message persistence, provider selection, or SwiftUI progress rendering. Runtime device monitoring lives inside the MLX runtime bridge and adapts local model defaults there.

SwiftUI views receive services via environment values. This keeps views from constructing runtime dependencies directly and makes it possible to swap live, mock, or preview implementations.

## Feature Boundaries

`PinesArchitecture.modules` documents ownership for each app feature:

- Chats own conversations, messages, message FTS, chat attachment staging, message editing, and attachment row actions.
- Models own model installs and model lifecycle state.
- Vault owns documents, chunks, vault FTS, and source attachments.
- Agents own the runtime boundary, tool/audit policy, approval callbacks, activity reporting, and opt-in cloud permissions.
- Settings owns user preferences and service configuration.

Repository protocols separate UI from storage:

- `ConversationRepository`
- `ModelInstallRepository`
- `VaultRepository`
- `SettingsRepository`
- `CloudProviderRepository`
- `MCPServerRepository`
- `ModelDownloadRepository`
- `AuditEventRepository`

The production local store is GRDB/SQLite with optional CloudKit private-database sync for user-enabled settings, conversations, messages, vault metadata, vault chunks, and source documents. API keys, model binaries, prompt caches, browser state, chat attachment files, and transient tool state do not sync. Generated embeddings and compressed vault vector codes sync only when both private iCloud sync and embedding sync are enabled.

Chat attachments are staged under app support storage, capped at eight files per draft, and limited to inline-safe sizes before they can enter provider requests. Supported user-selected files include PNG, JPEG, WebP, GIF, HEIC/HEIF, PDF, plain text, Markdown, JSON, and CSV. HEIC/HEIF and sequence variants are decoded through ImageIO and staged as JPEG attachments so downstream provider capability checks can use the existing image path. Attachment-only sends and edits normalize empty text into explicit prompts such as image or file analysis instructions before persistence and routing.

The GRDB implementation is split by repository concern: base SQLite repository operations remain in `GRDBPinesStore.swift`, while CloudKit snapshot/apply/delete merge support lives in `GRDBPinesStore+CloudKit.swift`.

## Local-First Inference

Normal chat, VLM prompts, embeddings, vault retrieval, and history are local-first. Runtime profiles request TurboQuant for local KV cache by default through the pinned MLX forks, including requested/active backend and attention-path diagnostics so the app can distinguish direct compressed Metal attention from packed-lane fallback. Normal chat can route to selected/configured BYOK providers when the user's execution mode and provider selection allow it:

- `localOnly`
- `preferLocal`
- `cloudAllowed`
- `cloudRequired`

The router must never silently fall back to cloud. If local capability is missing, the UI should show a consent/configuration path. When local vault or MCP resource context would be included in a cloud request, the app asks for per-turn approval and can continue without that context.

`DeviceRuntimeMonitor` adapts local runtime defaults from physical memory, available process memory, and thermal state. Compact 6 GB devices use lower prefill, embedding batch, and vector scan limits; iOS memory warnings stop the active run and unload transient MLX containers.

Vault retrieval stores both FP16 embeddings and compressed TurboQuant vector codes. Search first uses the compressed code path, filters by embedding model where possible, reranks with FP16 cosine, and falls back to SQLite FTS when embeddings are missing.

The app links MLX through exact fork pins in `project.yml`:

- `https://github.com/RNT56/mlx-swift` at `2577c8856ddfb05cad0da4eda7b502cbb5d99a3f`
- `https://github.com/RNT56/mlx-swift-lm` at `8861b2d9746128f3461b71deee5bf94ec3817a78`
- Nested `mlx` inside `RNT56/mlx-swift` at `d999c27ecd549e65f8f689bdd5c83648da977b81`

Compatibility implementations for model families not yet present in linked MLX packages are split into `MLXCompatibleModels+Llama4.swift` and `MLXCompatibleModels+DeepseekV4.swift`.

## Signing And iCloud

The generated app target is safe for personal Apple Developer teams by default. `PINES_CODE_SIGN_ENTITLEMENTS` and `PINES_ICLOUD_SWIFT_FLAGS` are empty in `project.yml`, so Xcode does not ask a personal team to provision the iCloud capability.

Paid-team CloudKit builds must opt in by overriding both build settings together:

```sh
PINES_CODE_SIGN_ENTITLEMENTS=Pines/Pines.entitlements
PINES_ICLOUD_SWIFT_FLAGS="-D PINES_CLOUDKIT_ENABLED"
```

The entitlement file alone is not enough: `PINES_CLOUDKIT_ENABLED` is the runtime guard that makes `CloudKitSyncService.hasRequiredEntitlements()` return true.

## Model Discovery

`ModelHubKit` primitives query Hugging Face MLX-tagged models, fetch preflight metadata, and drive resumable model install/delete:

- `config.json`
- tokenizer files
- processor config
- generation config
- safetensors files and size
- repository tags and license

Curated models are kept separate from discoverable models. 1-bit/BitNet models are treated as experimental unless the exact repository/device combination is verified. Downloads are staged, resumable through byte ranges, checksum-verified when Hugging Face exposes an LFS SHA-256, and atomically promoted into the app model directory.

## Tool Safety

Tool definitions are typed, versioned, schema-backed, and include permission metadata:

- required explanations
- network policy
- side-effect level
- timeout
- permissions such as network, browser, files, photos, clipboard, or cloud context

`ToolPolicyGate` validates invocations before execution. Calculator is implemented locally with a safe arithmetic parser. `web.search` uses a Brave Search BYOK key from Keychain, and browser automation runs through an isolated non-persistent `WKWebView` runtime with observe and user-approved action tools. Normal chat keeps its advertised tool list empty; Agent mode gets the explicitly enabled tool catalog and can report tool progress through `AgentActivityEvent`.

The agent replacement seam has three contracts:

- `AgentRuntime` owns a single run and streams normal inference events back to chat.
- `AgentRuntimeFactory` creates runtimes from app services so dependency swaps happen at the composition root.
- `AgentToolCatalog` supplies the Agent-mode tool inventory independently from chat orchestration.
- `AgentRuntimeCallbacks` carries human-in-the-loop approval and activity/progress reporting, keeping UI concerns out of agent execution.

MCP sampling can forward server-supplied tool definitions to the selected local or BYOK provider while the MCP server owns its tool loop.

## Source Organization Notes

Large app files are intentionally split by responsibility:

- App-model presentation DTOs and helpers: `PinesAppModelTypes.swift`.
- Design tokens and environment: `PinesDesignSystem.swift`; reusable controls and modifiers: `PinesDesignComponents.swift`.
- MCP transport state and requests: `MCPStreamableHTTPClient.swift`; wire DTOs and JSON helpers: `MCPStreamableHTTPPayloads.swift`.
- BYOK provider request/stream handling: `BYOKCloudInferenceProvider.swift`; provider stream metadata parsing: `CloudProviderStreamParser.swift`.
- Startup boot and lazy service creation: `PinesRootView.swift`; live service composition: `PinesAppServices.swift`.
- Model installer orchestration: `ModelLifecycleService.swift`; background download coordination and install-mode support: `ModelDownloadSupport.swift`.
- Settings and Models screen shells remain small; their detail/component surfaces live in `SettingsDetailView.swift` and `ModelsViewComponents.swift`.
