# Implementation Status

This repository is a working foundation for `pines`, not a signed App Store distribution yet. The current TurboQuant compatibility pair is non-green. Immediately-prior-pair physical-device synthetic smoke and a small Qwen 3.5 0.8B real-model comparison pass, but a manifest-only SwiftPM compatibility revision changed the immutable pair identity. Those results are now historical; they do not satisfy the current-pair acceptance matrix or constitute an imported product evidence tuple. Earlier synthetic attention-shape and Mac real-model results also belong to older or different tuples and are not promotion evidence for this pair. Native Sparse-V threshold/top-k/cumulative/hybrid modes are implemented but not promoted. Model/device/mode `Verified` and `Certified` claims remain gated on accepted exact-pair real-device evidence.

## Implemented

- XcodeGen iOS app project.
- Committed SwiftPM package lockfile for package/test dependency reproducibility.
- SwiftUI app shell with Chats, Models, Vault, Artifacts, and Settings surfaces, including named Project Spaces shared by Chats and Vault.
- Boot mark shown before live service construction, with lazy app-service creation after first-frame yield.
- Custom app icon assets.
- Environment-driven design system with selectable templates and light/dark modes.
- Core inference/provider/model contracts, including typed stream events.
- Local/cloud execution routing rules.
- Hugging Face model catalog search and model preflight classification.
- Curated model manifest.
- Persistence schema for conversations, messages, model installs/downloads, vault documents, chunks, FTS, settings, cloud providers, provider lifecycle records, sync records, agent/tool runs, and audit events.
- Tool registry, typed tool specs, expanded built-in tools, and policy gate.
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
- BYOK cloud streaming adapters for OpenAI-compatible, OpenRouter, Anthropic, and Gemini, including provider-specific stream metadata parsing. OpenRouter requests support persisted provider order/allow/deny/sort policy, fallback and supported-parameter enforcement, data-collection/ZDR constraints, routing-metadata opt-in, JSON object/schema response formats, beta server web search with engine selection and bounded policy, public-URL citation ingestion, terminal route/usage/search/cost receipts, and bounded model metadata for picker details, context packing, and fresh-only pre-spend capability rejection. Model catalogs hydrate from encrypted six-hour local snapshots while a network refresh runs.
- Shared provider lifecycle records, repositories, and previews, plus a zero-navigation Artifact gallery for generated images, video, speech, and research reports. Native search/filter controls, a direct New menu, one transient running line, a uniform responsive gallery, and Quick Look sheets replace nested category, dashboard, command-deck, and inspector navigation. Image generation uses a canvas-first studio with a floating prompt dock and visual session output; Research uses a conversation-first workspace with a floating chat-style composer, direct source/depth controls, brief clarification, and flat progress/evidence presentation. Every app-owned Artifact surface now uses Pines theme typography, color, spacing, stroke, navigation chrome, loading, press, and motion primitives; Video and Speech settings share the same focused setup language, with light/dark resolution coverage for every theme template. Provider-hosted file and vector-store management remains separate in Vault.
- OpenAI provider lifecycle workflows for Files, vector stores, vector-store file batches, batches, Deep Research, realtime session records, generated image/video artifacts, speech, transcription, and translation artifacts.
- Anthropic provider lifecycle workflows for Files, generated file download/import, prompt cache metrics, citations, thinking preservation, Message Batches, token counting, hosted tool metadata, and model capability rows.
- Gemini provider lifecycle workflows for Files, context caches, token counting, Deep Research, Live sessions, generated media artifacts, batches, URL context metadata, Google Search grounding, and model capability rows.
- Chat provenance surfaces for provider citations, hosted tool timelines, provider file references, request/message IDs, cache metrics, thinking mode, generated artifacts, and privacy-minimized OpenRouter route/fallback/token/cost receipts.
- Durable OpenAI, Anthropic, and Gemini provider-transfer queue with real upload-byte progress, staged local sources, relaunch interruption recovery, retry, cancellation, cloud-copy verification, and explicit local/provider storage separation.
- Pre-execution provider-hosted tool consent for approval-gated code, shell/editor, remote MCP, and computer-use requests, including provider environment, data egress, side effects, network destinations, retention wording, denial, and consent audit events.
- Persisted CloudKit conversation and Vault-document conflicts with side-by-side device/iCloud summaries and explicit keep-device or use-iCloud resolution instead of last-writer-wins overwrite.
- Always-visible local-model compatibility explanations covering exact compatibility pair, evidence level/date, device class, runtime/backend, admitted context, fallback contract, warnings, and the next evidence action.
- Settings-level OpenRouter spend inspection for 24 hours, 7 days, 30 days, or all history, aggregated only from persisted provider receipts with coverage/missing-cost disclosure, tokens, web-search runs, and upstream-provider breakdown.
- Built-in calculator, time/date, attachment read, vault search/read, conversation search, Brave Search BYOK, bounded public-network-only web fetch, and policy-gated WKWebView browser observe/action tools.
- Vault file/PDF/image import pipeline with scoped file types, bounded source size/text extraction, OCR, chunking, and embedding invocation.
- TurboQuant runtime profile defaults, requested/active backend diagnostics, Metal codec and compressed-attention availability diagnostics, compressed vault embedding storage, approximate vector search, and FP16 rerank path.
- TurboQuant control-plane runtime: pre-generation admission, memory zones, mode-specific fallback contracts, typed local failure events, RunDecision metadata, calibration samples, compatibility-pair tracking, evidence import/revocation, quality gates, and compatibility UI states.
- Context planning for pinned, recent, retrieved, summary, and dropped segments, with explicit separation between semantic retrieval and exact-prefix compressed KV pages.
- Encrypted local KV snapshot manifests and blob storage, fail-closed identity validation, partial-write quarantine, quota/eviction policy, data-erasure hooks, and disabled-by-default restore gates.
- Speculative decode contracts, target-verifier telemetry, acceptance-rate evidence gates, and auto-disable policy for poor acceptance or target mismatch.
- Platform-unlock contracts for adaptive precision, semantic/multimodal/agent memory, open KV descriptors, device mesh, personalization/adapters, and release kill switches. These are disabled by default and require compatibility-pair plus evidence gates before product activation.
- iOS runtime guardrails: memory/thermal adaptive profiles, compact 6 GB device defaults, memory-warning unload, bounded vector scans, batched vault embedding ingestion, foreground-only MLX execution, conservative background model-download network defaults, and recovered-download reconciliation.
- Read-only runtime diagnostics and OSLog/MetricKit hooks for startup phases, generation speed, vault retrieval, and memory pressure.
- Bidirectional CloudKit private-database sync for opt-in settings, Project Spaces, conversations/messages, Vault document metadata/chunks, tombstones, and explicitly enabled embedding/code blobs. Sync is triggered at launch, foreground activation, settings changes, and local content mutations; Settings exposes current sync phase, redacted failure details, last success, and explicit retry.
- Personal-team-safe default signing: generated Xcode builds omit iCloud entitlements and keep CloudKit runtime activation disabled unless a paid-team build overrides both iCloud settings.
- MCP Streamable HTTP support for tools, resources, prompts, user-approved sampling, bearer tokens, OAuth PKCE, subscriptions, safe resource previews, and persisted MCP tool safety annotations. Unannotated tools conservatively default to remote-state-changing.
- Bounded provider response ingestion for JSON, files, audio, batch results, generated media, and video so provider endpoints cannot allocate unbounded in-memory responses.
- Settings persistence, cloud provider settings flow, MCP server settings, and audit event UI.
- Cloud provider create/edit, identity-preserving rename and endpoint updates, optional Keychain credential rotation, duplicate-name rejection, validation, model catalog refresh, default model selection, and deletion.
- Chat stop, retry, edit, and regenerate controls.
- Layered `.icon` source for the app icon.
- Swift Testing core contract tests, iOS app surface tests, and framework-free verification runner.
- Shared Xcode validation script used by CI and release validation for project generation, drift checking, unsigned iOS build, simulator build-for-testing, and simulator smoke tests.
- CI privacy-manifest lint for the committed local-first manifest, including required-reason entries for file timestamps, disk space, and app-only UserDefaults.
- OAuth startup guardrails avoid crashing when authentication is attempted without an active foreground window.
- Service bootstrap logs/audits recoverable built-in tool registration and store initialization failures instead of silently discarding them.
- App architecture cleanup that splits large files into app model types, GRDB CloudKit sync, design components, MCP payloads, model download support, typed and focused Settings destinations, Models components, and MLX model-family files.
- Historical signed physical-device TurboQuant app-host smoke on `iPhone16,2` for the immediately prior immutable pair, including native compressed-path diagnostics and an explicitly unverified synthetic evidence baseline.

## Not Complete

- Real-device TurboQuant acceptance on the A16 through A19 Pro hardware matrix, including stable multi-repeat real-model coverage and at least one imported model/device/mode evidence tuple before any `Verified` or `Certified` product claim.
- OpenRouter endpoint-level provider availability, provider-specific feature variance/rate limits/prices, cached/reasoning/media usage detail, and optional generation-endpoint cost reconciliation remain incomplete. Aggregate spend deliberately uses only persisted provider-reported receipt fields and does not estimate missing cost.
- Signed App Store archive/export, TestFlight/App Store upload automation, and final App Store Connect privacy review for the submitted binary.
- The platform-aware, warning-free `mlx-swift` build-tool plugin, Apple-mobile JIT compatibility fix, and SwiftPM 6.2 manifest compatibility are pinned at `bcf93af23f11428f6f01efb0bb4b9020cd2eb383`; cold iOS device and simulator builds must remain warning-free as part of release validation.
- Remaining monolith candidates are semantic rather than mechanical: `PinesAppModel` still owns high-level orchestration and `ModelsViewComponents` owns model list/detail presentation. Settings has been split into typed, focused destination pages with shared grouped-row components.

## Verification

Available in this environment:

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift run --disable-automatic-resolution PinesCoreTestRunner
bash scripts/ci/xcodegen.sh generate
bash scripts/ci/run-xcode-validation.sh all
```

For a direct generic iOS build:

```sh
xcodebuild -project Pines.xcodeproj -scheme Pines -destination 'generic/platform=iOS' build
```

The current TurboQuant compatibility pair remains non-green until its exact pins pass native backend performance, the full real-model-inference benchmark matrix, quality, memory, Sparse-V/lower-V fallback, and accepted physical-device gates. The focused 4K Qwen 3.5 0.8B run is smoke evidence, not matrix completion. Do not reuse historical evidence from another pin tuple.
