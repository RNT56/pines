# OpenRouter Production Parity Roadmap

Last verified: 2026-05-19. Companion gap analysis: [openrouter.md](openrouter.md).

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

- Add OpenRouter-specific request settings for provider order, allow/deny providers, allow fallbacks, require parameters, data collection, ZDR preference, and max price.
- Default `require_parameters` for schema/tool/modality-critical requests.
- Surface actual routed provider and fallback metadata in run details where available.
- Add per-thread and per-provider defaults.
- Add tests for strict provider order, fallback disabled, and unsupported parameter rejection.
- Add routing control panel and route provenance UI.

Possible hiccups:

- Actual routed-provider metadata may be incomplete or returned out of band.
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

- Map provider-neutral schema requests to OpenRouter structured output format.
- Set `require_parameters` when schema adherence is required.
- Add optional response healing for non-streaming structured requests if still supported and useful.
- Add model/provider capability checks before sending schemas.

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

- Parse prompt/completion/reasoning/cached tokens and cost fields.
- Store upstream provider, model, route, and cost in metadata.
- Add per-thread and per-provider spend summaries if product wants it.
- Add cost inspector and run detail rows for routed provider/cost metadata.

Possible hiccups:

- Cost can be returned after generation or through a separate accounting endpoint.

Production complete when:

- Users can inspect actual OpenRouter cost and route details for every run.
