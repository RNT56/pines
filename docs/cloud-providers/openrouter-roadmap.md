# OpenRouter Production Parity Roadmap

Last verified: 2026-07-13. Companion gap analysis: [openrouter.md](openrouter.md).

## Current Implementation State

Pines now persists a normalized OpenRouter policy and applies it to Chat Completions requests. The shipped Settings controls cover explicit provider order, allow/deny lists, price/throughput/latency sorting, fallbacks, required-parameter enforcement, data-collection denial, and zero-data-retention eligibility. Tool and structured-output requests automatically require parameter support. JSON object/schema response formats are mapped to `response_format`, and requests opt in to OpenRouter routing metadata. The terminal stream chunk is finalized into a privacy-minimized chat receipt with resolved route/fallback, usage, BYOK, and cost data.

This is a meaningful Phase 1/3/7 foundation, not production parity. Policy is currently global rather than per-thread/per-provider; max-price and quantization controls, aggregate/reconciled accounting, metadata-driven model eligibility, server tools, reasoning controls, response healing, caching/transforms, and output media remain incomplete.

## Product Goal

Treat OpenRouter as a routing platform, not just an OpenAI-compatible endpoint. Pines should expose routing, privacy, cost, model metadata, structured outputs, server tools, and provider fallback controls so users can intentionally choose the tradeoffs OpenRouter exists to manage.

## Viable And Relevant Scope

- Provider routing preferences and fallback controls.
- Supported-parameter enforcement.
- Model metadata-driven picker and capability gating.
- Structured outputs, reasoning controls, server tools, web search, and plugins where still relevant.
- Prompt caching, transforms, usage/cost accounting.
- Multimodal input/output support where model metadata confirms it.
- Themed UI for routing controls, provider/model metadata, structured outputs, server tools, usage/cost accounting, and multimodal artifacts.

## Explicitly Out Of Scope

- Recreating OpenRouter's website, rankings, account management, or credits UI.
- Exposing every routed provider as a separate Pines provider automatically.
- Silent routing to providers with weaker privacy/data policies than the user selected.
- Letting OpenRouter fallback bypass Pines capability checks.
- Treating deprecated plugin paths as primary when server tools supersede them.

## Required UI

All UI must follow the shared [cloud provider UI roadmap](ui-roadmap.md).

Provider-specific screens/components:

- OpenRouter capability dashboard centered on route, provider availability, supported parameters, modalities, pricing, context length, server tools, and structured outputs.
- Routing control panel with provider order, allowed/blocked providers, fallbacks, data collection/ZDR preference, max price, and `require_parameters`.
- Model picker enhancements: badges for price, context, modalities, supported parameters, and provider availability.
- Route provenance panel showing actual upstream provider, fallback path, route settings, request ID, model, and cost.
- Structured output controls with strict/required parameter status.
- Server web search tool approval/timeline and source panel.
- Cost inspector showing prompt/completion/reasoning/cached tokens, reported cost, and estimated fallback when unavailable.
- Multimodal artifact handling for routed image/audio/video outputs when enabled.

UI production requirements:

- Privacy/routing controls must be visible before requests that can leave the selected provider set.
- Cost and routed-provider data must be displayed in run details, not only logs.
- OpenRouter expert controls should feel like operational routing controls, not raw JSON first.

## Phase 1: Routing And Privacy Controls

Goal: Give users control over where OpenRouter sends their request.

Todos:

- [x] Add typed request settings for provider order, allow/deny providers, route sorting, fallbacks, required parameters, data collection, and ZDR preference.
- [x] Default `require_parameters` for schema/tool-critical requests.
- [x] Add persisted routing/privacy controls and direct request-construction tests.
- [ ] Add max-price and quantization controls.
- [x] Surface actual routed provider and fallback metadata in run details.
- [ ] Add per-thread and per-provider overrides.
- [x] Add privacy-minimized route provenance UI.
- [ ] Add live unsupported-parameter rejection coverage.

Possible hiccups:

- Router metadata is intentionally absent on OpenRouter cache hits and can be incomplete on early failures.
- Tight routing constraints can make requests fail more often.
- Privacy settings need clear wording, not acronyms only.

Production complete when:

- A user can intentionally choose cost, privacy, fallback, and provider routing behavior, and Pines shows what happened.

## Phase 2: Model Metadata And Picker

Goal: Make OpenRouter model selection capability-driven.

Todos:

- Cache model metadata: context length, modalities, pricing, architecture, supported parameters, provider availability, and rate/cost hints.
- Filter model picker by requested feature: tools, images, PDFs, schemas, reasoning, audio/video, generation outputs.
- Show pricing/context/modality badges.
- Warn when selected model may drop a requested feature.
- Add model picker badges and eligibility explanations.

Possible hiccups:

- Metadata can change frequently.
- A model can support a feature only on some upstream providers.

Production complete when:

- Pines can explain why an OpenRouter model is eligible or ineligible for a request.

## Phase 3: Structured Outputs And Response Reliability

Goal: Make extraction reliable across routed models.

Todos:

- [x] Map provider-neutral JSON object/schema requests to OpenRouter `response_format`.
- [x] Set `require_parameters` when schema adherence is required.
- [ ] Add optional response healing for non-streaming structured requests if still supported and useful.
- [ ] Replace static provider capability with model/upstream metadata checks before sending schemas.

Possible hiccups:

- Some routed providers support schemas only through specific upstreams.
- Response healing may add latency/cost and may not be available for streaming.

Production complete when:

- OpenRouter schema requests either produce validated output or fail before degraded execution.

## Phase 4: Server Tools And Web Search

Goal: Expose OpenRouter-hosted tools consistently.

Todos:

- Add `openrouter:web_search` server tool support.
- Parse annotations/citations/source metadata.
- Add settings to choose OpenRouter search versus provider-native search when both exist.
- Track server tool usage and cost.
- Add server tool timeline rows and source panel.

Possible hiccups:

- Server tool behavior differs from OpenAI/Anthropic/Gemini native search.
- Search availability and pricing can vary by model/route.

Production complete when:

- OpenRouter can provide source-backed web answers with citations and cost visibility.

## Phase 5: Reasoning, Caching, And Transforms

Goal: Expose OpenRouter's routing-layer quality/cost controls.

Todos:

- Add OpenRouter `reasoning` parameter support.
- Parse reasoning tokens/content where returned.
- Add prompt caching controls and cached-token telemetry.
- Add optional transforms/context compression with explicit warning.
- Add sticky routing/cache behavior notes in UI.

Possible hiccups:

- Reasoning controls are normalized but upstream implementations vary.
- Transforms can remove context that a local-first user expected to preserve.

Production complete when:

- Users can tune reasoning/caching/compression and see the consequences in run details.

## Phase 6: Multimodal And Generated Outputs

Goal: Use OpenRouter's model breadth without overpromising.

Todos:

- Add input/output modality support based on model metadata.
- Support generated image/audio/video outputs only after Pines artifact storage is ready.
- Add per-model payload-shape selection for files/media.
- Add preflight for unsupported media.

Possible hiccups:

- Different routed providers use different media payload shapes.
- Output media may require non-chat endpoints or polling.

Production complete when:

- OpenRouter multimodal requests are capability-gated and artifacts are handled consistently with OpenAI/Gemini generated media.

## Phase 7: Usage And Cost Accounting

Goal: Make OpenRouter cost transparent.

Todos:

- [x] Parse prompt/completion/total tokens, BYOK state, reported cost, and upstream inference cost.
- [ ] Parse reasoning, cached, media, and server-tool usage details.
- [x] Store upstream provider, model, safe fallback route, and cost in metadata after the terminal stream chunk.
- Add per-thread and per-provider spend summaries if product wants it.
- [x] Add a progressively disclosed chat receipt for routed provider/cost metadata.
- [ ] Add aggregate cost inspection and optional generation-endpoint reconciliation.

Possible hiccups:

- Cost and router metadata arrive after the ordinary finish-reason chunk; stream finalization must preserve the terminal receipt.
- Cache hits omit router metadata, while generation accounting may require a separate authenticated lookup.

Production complete when:

- Users can inspect actual OpenRouter cost and route details whenever the provider returns them, with honest missing-data behavior for cache hits and early failures.
