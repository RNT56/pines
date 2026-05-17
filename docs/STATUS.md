# Implementation Status

This repository is a working foundation for `pines`, not a complete App Store-ready MLX client yet.

## Implemented

- XcodeGen iOS app project.
- Committed SwiftPM package lockfile for package/test dependency reproducibility.
- SwiftUI app shell with Chats, Models, Vault, and Settings surfaces.
- Boot mark shown before live service construction, with lazy app-service creation after first-frame yield.
- Custom app icon assets.
- Environment-driven design system with selectable templates and light/dark modes.
- Core inference/provider/model contracts, including typed stream events.
- Local/cloud execution routing rules.
- Hugging Face model catalog search and model preflight classification.
- Curated model manifest.
- Persistence schema for conversations, messages, model installs/downloads, vault documents, chunks, FTS, settings, cloud providers, sync records, agent/tool runs, and audit events.
- Tool registry, typed tool specs, calculator tool, and policy gate.
- Agent policy and tool invocation models.
- Vault chunking and exact cosine vector index.
- Keychain-backed secret store for iOS.
- GRDB-backed app store/repository implementation.
- Chat attachments for images, HEIC/HEIF imports staged as JPEG, PDFs, and text-like files with provider capability checks and local file staging.
- Attachment-only chat sends and user-message edits normalize empty text into explicit attachment analysis prompts.
- Chat message row actions for copying content, editing user messages while no run is active, and importing local message attachments into Vault.
- MLX runtime bridge that loads MLX LLM/VLM/embedder containers when linked.
- Exact app-level pins to the maintained `RNT56/mlx-swift` and `RNT56/mlx-swift-lm` forks for TurboQuant and compatibility APIs.
- Split MLX compatibility implementations for Llama 4 and DeepSeek V4 model families.
- Hugging Face preflight and resumable model install/delete service.
- BYOK cloud streaming adapters for OpenAI-compatible, OpenRouter, Anthropic, and Gemini, including provider-specific stream metadata parsing.
- Brave Search BYOK tool and WKWebView browser observe/action runtime.
- Vault file/PDF/image import pipeline with chunking, OCR, and embedding invocation.
- TurboQuant runtime profile defaults, requested/active backend diagnostics, Metal codec and compressed-attention availability diagnostics, compressed vault embedding storage, approximate vector search, and FP16 rerank path.
- iOS runtime guardrails: memory/thermal adaptive profiles, compact 6 GB device defaults, memory-warning unload, bounded vector scans, and batched vault embedding ingestion.
- Read-only runtime diagnostics and OSLog/MetricKit hooks for startup phases, generation speed, vault retrieval, and memory pressure.
- CloudKit private database sync service for opt-in settings, conversations, vault chunks, and explicitly enabled embedding/code blobs.
- Personal-team-safe default signing: generated Xcode builds omit iCloud entitlements and keep CloudKit runtime activation disabled unless a paid-team build overrides both iCloud settings.
- MCP Streamable HTTP support for tools, resources, prompts, user-approved sampling, bearer tokens, OAuth PKCE, subscriptions, and safe resource previews.
- Settings persistence, cloud provider settings flow, MCP server settings, and audit event UI.
- Cloud provider create/update-by-name, validation, model catalog refresh, default model selection, and deletion.
- Chat stop and retry controls.
- Layered `.icon` source for the app icon.
- Swift Testing core contract tests, iOS app surface tests, and framework-free verification runner.
- App architecture cleanup that splits large files into app model types, GRDB CloudKit sync, design components, MCP payloads, model download support, Settings detail, Models components, and MLX model-family files.

## Not Complete

- Real-device TurboQuant acceptance on the A16 through A19 Pro hardware matrix.
- Production UX hardening for regenerate controls, fuller provider editing, CloudKit conflict UI, and detailed model compatibility messaging.
- App Store privacy manifest validation against the final resolved package graph.
- Remaining monolith candidates are semantic rather than mechanical: `PinesAppModel` still owns high-level orchestration, `SettingsDetailView` owns the full settings editor, and `ModelsViewComponents` owns model list/detail presentation. Split these further only alongside focused feature changes.

## Verification

Available in this environment:

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
xcodegen generate
```

Full iOS verification requires full Xcode:

```sh
xcodebuild -project Pines.xcodeproj -scheme Pines -destination 'generic/platform=iOS' build
```
