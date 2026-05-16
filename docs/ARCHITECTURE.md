# Architecture

`pines` is structured as a modular iOS app with a testable Swift core and a SwiftUI presentation layer. The current repository is a production-oriented foundation: interfaces, boundaries, and verification are in place; the heavy runtime integrations are intentionally isolated behind protocols so they can be implemented without reshaping the app.

## Layers

- `Pines/`: iOS application target, SwiftUI screens, composition root, design system, runtime bridges, assets, entitlements, and privacy manifest.
- `Sources/PinesCore/`: platform-light core contracts for inference, model catalog, persistence schema, tools, agents, vault indexing, cloud providers, redaction, and feature ownership.
- `Tests/PinesCoreTests/`: Swift Testing coverage for core contracts.
- `PinesTests/`: iOS-target unit coverage for app-facing surface contracts.
- `Sources/PinesCoreTestRunner/`: framework-free verification runner for environments where Command Line Tools do not expose XCTest or Swift Testing.
- `project.yml`: XcodeGen source of truth for the Xcode project.

## Composition Root

`PinesAppServices` owns service construction for the app layer:

- `SecretStore`
- `HuggingFaceModelCatalogService`
- `ModelPreflightClassifier`
- `ExecutionRouter`
- `ToolRegistry`
- `ToolPolicyGate`
- `Redactor`
- `MLXRuntimeBridge`
- `DeviceRuntimeMonitor`
- `PinesRuntimeMetrics`
- `GRDBPinesStore`
- `ModelLifecycleService`
- `VaultIngestionService`
- `CloudProviderService`
- `CloudKitSyncService`
- `AgentRunner`

SwiftUI views receive services via environment values. This keeps views from constructing runtime dependencies directly and makes it possible to swap live, mock, or preview implementations.

## Feature Boundaries

`PinesArchitecture.modules` documents ownership for each app feature:

- Chats own conversations, messages, message FTS, and attachments.
- Models own model installs and model lifecycle state.
- Vault owns documents, chunks, vault FTS, and source attachments.
- Agents own tool/audit policy and opt-in cloud permissions.
- Settings owns user preferences and service configuration.

Repository protocols separate UI from storage:

- `ConversationRepository`
- `ModelInstallRepository`
- `VaultRepository`

The production local store is GRDB/SQLite with optional CloudKit private-database sync for user-enabled metadata and source documents. API keys, model binaries, prompt caches, browser state, and transient tool state do not sync. Generated embeddings and compressed vault vector codes sync only when both private iCloud sync and embedding sync are enabled.

The GRDB implementation is split by repository concern: base SQLite repository operations remain in `GRDBPinesStore.swift`, while CloudKit snapshot/apply/delete merge support lives in `GRDBPinesStore+CloudKit.swift`.

## Local-First Inference

Normal chat, VLM prompts, embeddings, vault retrieval, and history are local-first. Runtime profiles request TurboQuant for local KV cache by default through the pinned MLX forks, including requested/active backend and attention-path diagnostics so the app can distinguish direct compressed Metal attention from packed-lane fallback. Cloud execution is represented only through explicit agent policy:

- `localOnly`
- `preferLocal`
- `cloudAllowed`
- `cloudRequired`

The router must never silently fall back to cloud. If local capability is missing, the UI should show a consent/configuration path.

`DeviceRuntimeMonitor` adapts local runtime defaults from physical memory, available process memory, and thermal state. Compact 6 GB devices use lower prefill, embedding batch, and vector scan limits; iOS memory warnings stop the active run and unload transient MLX containers.

Vault retrieval stores both FP16 embeddings and compressed TurboQuant vector codes. Search first uses the compressed code path, filters by embedding model where possible, reranks with FP16 cosine, and falls back to SQLite FTS when embeddings are missing.

The app links MLX through exact fork pins in `project.yml`:

- `https://github.com/RNT56/mlx-swift` at `cf6d72f54e8619e52a746b88a0fb00f172e4ba10`
- `https://github.com/RNT56/mlx-swift-lm` at `f3479d989a606c1d1a959c1dacf184f7fb812734`

Compatibility implementations for model families not yet present in linked MLX packages are split into `MLXCompatibleModels+Llama4.swift` and `MLXCompatibleModels+DeepseekV4.swift`.

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

`ToolPolicyGate` validates invocations before execution. Calculator is implemented locally with a safe arithmetic parser. `web.search` uses a Brave Search BYOK key from Keychain, and browser automation runs through an isolated non-persistent `WKWebView` runtime with observe and user-approved action tools.

## Source Organization Notes

Large app files are intentionally split by responsibility:

- App-model presentation DTOs and helpers: `PinesAppModelTypes.swift`.
- Design tokens and environment: `PinesDesignSystem.swift`; reusable controls and modifiers: `PinesDesignComponents.swift`.
- MCP transport state and requests: `MCPStreamableHTTPClient.swift`; wire DTOs and JSON helpers: `MCPStreamableHTTPPayloads.swift`.
- Model installer orchestration: `ModelLifecycleService.swift`; background download coordination and install-mode support: `ModelDownloadSupport.swift`.
- Settings and Models screen shells remain small; their detail/component surfaces live in `SettingsDetailView.swift` and `ModelsViewComponents.swift`.
