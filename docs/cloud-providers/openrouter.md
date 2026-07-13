# OpenRouter Provider Status And Gaps

Last verified: 2026-07-13.

Primary sources:

- [Chat Completions API](https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request)
- [Models](https://openrouter.ai/docs/guides/overview/models)
- [Provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [Structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs)
- [Server tools](https://openrouter.ai/docs/guides/features/server-tools/overview)
- [Web search server tool](https://openrouter.ai/docs/guides/features/server-tools/web-search)
- [Plugins](https://openrouter.ai/docs/guides/features/plugins/overview)
- [Multimodal capabilities](https://openrouter.ai/docs/guides/overview/multimodal/overview)
- [Reasoning tokens](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
- [Usage accounting](https://openrouter.ai/docs/cookbook/administration/usage-accounting)
- [Router metadata](https://openrouter.ai/docs/guides/features/router-metadata)
- [Response healing](https://openrouter.ai/docs/guides/features/plugins/response-healing)

## What Pines Supports Today

- OpenRouter as an OpenAI-compatible chat provider through `/chat/completions`.
- Model listing from `/models`.
- Streaming text and function tool calling.
- Image inputs.
- PDF inputs through OpenRouter's `file` content part shape.
- OpenRouter embeddings through `/embeddings` with `input_type`.
- Usage parsing through OpenAI-compatible stream shapes.
- Persisted, normalized routing policy for explicit provider order, provider allow/deny lists, price/throughput/latency sorting, fallback enablement, required-parameter enforcement, data-collection denial, and zero-data-retention eligibility.
- OpenRouter routing-metadata opt-in through `X-OpenRouter-Metadata: enabled`.
- Provider-neutral JSON object/schema requests mapped to Chat Completions `response_format`.
- Automatic `require_parameters: true` for requests carrying tools or structured output, so routing cannot silently drop those required features.
- Beta `openrouter:web_search` server-tool requests for automatic and required web-search modes, with an explicit engine preference, bounded result/domain/location policy, and fail-closed external-web access.
- Nested or flat web-search annotations normalized into bounded public-URL citations, plus server-search request count in the hosted-tool timeline and OpenRouter receipt.
- Terminal stream receipt parsing for resolved provider/model, routing strategy/region, selected endpoint, fallback attempts and statuses, native finish reason, service tier, prompt/completion/total tokens, BYOK state, reported cost, and upstream inference cost.
- A collapsed OpenRouter receipt in each eligible assistant message, with route, fallback, usage, execution, cost, and generation details available on demand.
- Privacy-minimized persistence: Pines stores allowlisted routing and usage fields while excluding arbitrary router pipeline/plugin additions from message metadata and CloudKit sync.

## High-Value Partial Or Unsupported Features

### 1. Route provenance and remaining routing controls

Pines sends the highest-value provider routing and privacy controls and now persists/displays the successful response's selected upstream and safe fallback-attempt chain. It does not yet expose `max_price`, quantization filters, or per-thread/per-provider overrides. OpenRouter cache hits intentionally omit router metadata, so those receipts may contain accounting and generation identity without a route snapshot.

Value:

- Users should be able to verify which upstream actually handled a request, not only which route they requested.
- Price and quantization ceilings complete the operational routing policy.

Implementation notes:

- Add `max_price`, quantization, and scoped override controls after model metadata is available.
- Keep the receipt parser permissive for additive response changes while retaining the persisted allowlist.

### 2. OpenRouter server web search

Pines maps its provider-neutral automatic/required search modes to `openrouter:web_search`, can force that exact server tool when search is required, and lets users select automatic, provider-native, Exa, Firecrawl, Parallel, or Perplexity execution. It combines server search with client function tools, disables parallel tool calls for deterministic orchestration, and does not unnecessarily constrain upstream-provider routing merely because the router-hosted search tool is present.

Safety and receipt behavior:

- External-web access must be enabled or request construction fails before network spend.
- Search results are bounded to five per search and ten total; domain lists are normalized, deduplicated, length-bounded, and capped at 20.
- When both domain policies are present, the stricter explicit allowlist wins because the portable server-tool contract treats allow/exclude lists as mutually exclusive.
- Citation ingestion accepts only public HTTP(S) destinations, strips credentials, bounds stored text, and rejects local/private addresses.
- OpenRouter's server-search request count and reported aggregate cost are surfaced in the existing progressively disclosed run details.

Current boundary:

- The OpenRouter API labels server web search beta, and availability/pricing remain model/route dependent.
- Pines uses the current server-tool contract rather than the deprecated web-search plugin or `:online` shortcut.
- Request, parsing, settings, and UI contracts are tested locally. A live end-to-end provider call requires the user's configured OpenRouter key and incurs provider charges.

### 3. Structured-output reliability and response healing

Pines sends JSON object/schema `response_format` and automatically requires supported parameters. It still relies on static provider capability rather than current model/upstream metadata and does not enable response healing for imperfect JSON.

Value:

- Metadata-driven preflight can reject impossible routes before a paid request.
- Optional response healing can improve non-streaming extraction from models that approximate JSON.

Implementation notes:

- Keep `require_parameters: true` when a schema is mandatory.
- Validate eligibility against current model and upstream-provider metadata.
- Consider optional response-healing plugin for non-streaming structured requests.

### 4. Reasoning token controls

OpenRouter normalizes reasoning controls across providers. Pines only has provider-specific OpenAI/Anthropic/Gemini quick settings and does not pass OpenRouter's `reasoning` parameter.

Value:

- Unified control over thinking/reasoning budget across many routed models.
- Better model parity when using non-native providers.

Implementation notes:

- Add OpenRouter-specific `reasoning` mapping separate from official OpenAI Responses `reasoning`.
- Parse reasoning content and reasoning token usage when available.

### 5. Detailed usage accounting and aggregate spend

Pines parses and displays prompt/completion/total tokens, reported cost, upstream inference cost, BYOK state, and server web-search request count per run. Settings also aggregates persisted receipts over 24 hours, 7 days, 30 days, or all history, with cost-coverage disclosure and upstream-provider breakdown. Cached/reasoning/media detail, per-thread rollups, and reconciliation through the generation accounting endpoint remain incomplete.

Value:

- Users can see actual request cost, upstream provider cost, cache savings, and reasoning token usage.

Implementation notes:

- Add cached, reasoning, and media usage fields as product surfaces consume them.
- Add optional per-thread spend summaries and generation-endpoint reconciliation without turning Pines into an account-management client. Never estimate cost when the provider omitted it.

### 6. Prompt caching and sticky routing

OpenRouter supports prompt caching across several upstream providers and uses sticky routing to improve cache hits. Pines does not expose cache control or inspect cache usage.

Value:

- Lower cost and latency for long conversations and repeated context.

Implementation notes:

- Add cache control only when supported by the chosen upstream model/provider.
- Avoid top-level cache controls that could change eligible providers unexpectedly unless user opts in.

### 7. Message transforms and context compression

OpenRouter supports middle-out transforms and context-compression plugin behavior. Pines does not send `transforms`.

Value:

- Graceful handling of over-context prompts when exact recall is not required.

Implementation notes:

- Prefer Pines' own context packing for privacy-sensitive local Vault context.
- Offer OpenRouter transforms as an explicit fallback when a request would otherwise fail.

### 8. Full multimodal inputs and outputs

OpenRouter supports images, PDFs, audio, video, image generation, speech generation, transcription, and embeddings depending on model. Pines supports only image/PDF input and text output.

Value:

- Access to many models' media capabilities through one BYOK route.

Implementation notes:

- Use Models API metadata to filter by input/output modality.
- Add output modality handling before exposing generated images/audio.

### 9. Model metadata filtering

Pines now requests OpenRouter's text-output catalog in popularity order and retains bounded, allowlisted metadata for context/output limits, input/output modalities, supported parameters, architecture labels, moderation, lifecycle dates, and per-unit pricing. A provider-scoped snapshot is stored in the encrypted local database, capped at 128 models, expires after six hours, cascades on provider deletion, and hydrates the picker at cold launch while a network refresh runs. The chat picker shows concise context, input/output price, modality, tool, and schema details; context packing uses the model limit; and request preflight rejects known-incompatible image, audio, video, PDF/file, tool, JSON, and strict-schema requests before inference spend.

Unknown or expired metadata remains permissive rather than creating false incompatibility claims. Pines does not yet fetch the endpoint details feed, so it cannot show provider-by-provider availability, provider-specific feature variance, rate limits, or per-endpoint prices.

Value:

- Better model picker, safer routing, and clearer feature availability.

Implementation notes:

- Fetch endpoint details before claiming that every routed upstream supports a catalog-level feature.
- Drive OpenRouter reasoning and other quick settings from supported parameters instead of model-name heuristics.

### 10. BYOK upstream provider routing

OpenRouter can route through user-supplied upstream provider keys in some configurations. Pines currently stores one OpenRouter key and does not manage upstream BYOK preferences.

Value:

- Users can centralize model routing while keeping spend on their own provider accounts.

Implementation notes:

- Requires careful secret UX and documentation because this nests provider credentials under OpenRouter behavior.

## Suggested Priority

1. Endpoint-level provider availability and metadata freshness.
2. OpenRouter reasoning controls and detailed reasoning/cache usage.
3. Response healing for eligible non-streaming structured requests.
4. Max-price/quantization and scoped routing overrides.
5. Generation-endpoint spend reconciliation and per-thread summaries.
6. Prompt caching/transforms.
7. Additional output modalities and upstream BYOK routing.

## Decisions And Open Questions

- Decision: OpenRouter has dedicated typed routing/privacy UI rather than raw JSON or generic OpenAI-compatible behavior.
- Decision: Pines requires parameter support automatically for tools and structured output.
- Decision: per-run cost accounting and upstream route provenance share one privacy-minimized, progressively disclosed chat receipt.
- Decision: provider-neutral web-search modes use OpenRouter's server tool when OpenRouter is selected; the engine preference decides automatic/provider-native/third-party execution without routing through Pines' Brave tool.
- Open: which routing controls should be per-thread overrides rather than provider defaults?
