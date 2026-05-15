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
- TurboQuant runtime profile defaults, requested/active backend diagnostics, Metal codec and compressed-attention availability diagnostics, compressed vault embedding storage, approximate vector search, and FP16 rerank path.
- iOS runtime guardrails: memory/thermal adaptive profiles, compact 6 GB device defaults, memory-warning unload, bounded vector scans, and batched vault embedding ingestion.
- Read-only runtime diagnostics and OSLog/MetricKit hooks for generation speed, vault retrieval, and memory pressure.
- CloudKit private database sync service for opt-in settings, conversations, vault chunks, and explicitly enabled embedding/code blobs.
- Settings persistence, cloud provider settings flow, and audit event UI.
- Layered `.icon` source for the app icon.
- Framework-free verification runner.

## Not Complete

- Real-device TurboQuant acceptance on the A16 through A19 Pro hardware matrix.
- Production UX hardening for stop/retry/regenerate controls, provider deletion/editing, CloudKit conflict UI, and detailed model compatibility messaging.
- App Store privacy manifest validation against the final resolved package graph.
- Fused TurboQuant compressed-attention APIs are implemented in the Schtack MLX forks: row-wise attention code blobs, direct compressed `QK^T`, direct compressed `AV`, tiled online fused decode, runtime capability/self-test probes, and selected kernel profiles. Unsupported devices or shapes still fall back to MLX packed quantized attention.
- The supported `.metalPolarQJL` rotating path is raw-free for active compressed storage. Prompt caches persist compressed blobs plus layout/ring metadata, while runtime kernel profile selection is recomputed on load.
- Pines now has a device-adaptive TurboQuant policy layer for A16, A17 Pro, A18, A18 Pro, A19, A19 Pro thin, A19 Pro sustained, and future verified devices. Real-device acceptance remains open for jetsam traces and final quality/throughput thresholds.

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
