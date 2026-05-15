# Implementation Status

This repository is a working foundation for `pines`, not a complete App Store-ready MLX client yet.

## Implemented

- XcodeGen iOS app project.
- SwiftUI app shell with Chats, Models, Vault, and Settings surfaces.
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
- MLX runtime bridge that loads MLX LLM/VLM/embedder containers when linked.
- Hugging Face preflight and resumable model install/delete service.
- BYOK cloud streaming adapters for OpenAI-compatible, OpenRouter, Anthropic, and Gemini.
- Brave Search BYOK tool and WKWebView browser observe/action runtime.
- Vault file/PDF/image import pipeline with chunking, OCR, and embedding invocation.
- CloudKit private database sync service for opt-in syncable metadata.
- Settings persistence, cloud provider settings flow, and audit event UI.
- Layered `.icon` source for the app icon.
- Framework-free verification runner.

## Not Complete

- Full iOS build/test verification on a machine with full Xcode selected.
- Production UX hardening for stop/retry/regenerate controls, provider deletion/editing, CloudKit conflict UI, and detailed model compatibility messaging.
- App Store privacy manifest validation against the final resolved package graph.

## Verification

Available in this environment:

```sh
swift build
swift run PinesCoreTestRunner
xcodegen generate
```

Full iOS verification requires full Xcode:

```sh
xcodebuild -project Pines.xcodeproj -scheme Pines -destination 'generic/platform=iOS' build
```
