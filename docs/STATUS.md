# Implementation Status

This repository is a working foundation for `pines`, not a complete App Store-ready MLX client yet.

## Implemented

- XcodeGen iOS app project.
- SwiftUI app shell with Chats, Models, Vault, and Settings surfaces.
- Custom app icon assets.
- Environment-driven design system with selectable templates and light/dark modes.
- Core inference/provider/model contracts.
- Local/cloud execution routing rules.
- Hugging Face model catalog search and model preflight classification.
- Curated model manifest.
- Persistence schema for conversations, messages, model installs, vault documents, chunks, FTS, and audit events.
- Tool registry, typed tool specs, calculator tool, and policy gate.
- Agent policy and tool invocation models.
- Vault chunking and exact cosine vector index.
- Keychain-backed secret store for iOS.
- MLX runtime bridge placeholders and runtime profile generation.
- Framework-free verification runner.

## Not Complete

- Real MLX model loading, streaming, VLM inference, embedding inference, prompt cache, KV cache controls, and speculative decoding.
- Model download/resume/checksum/install/delete.
- GRDB runtime persistence and migrations.
- CloudKit sync.
- Real chat send/stop/retry/regenerate/attachment workflows.
- Live model browser backed by Hugging Face results.
- File import, PDF extraction, OCR, and embedding jobs for the vault.
- BYOK provider onboarding and validation.
- Cloud provider streaming adapters.
- Full agent loop.
- Real web search provider integration.
- WKWebView browser automation runtime.
- Audit persistence and audit UI.
- App Store privacy manifest final review.
- Full iOS build verification on a machine with full Xcode selected.

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
