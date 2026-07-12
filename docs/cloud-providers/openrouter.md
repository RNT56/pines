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
- Terminal stream receipt parsing for resolved provider/model, routing strategy/region, selected endpoint, fallback attempts and statuses, native finish reason, service tier, prompt/completion/total tokens, BYOK state, reported cost, and upstream inference cost.
- A collapsed OpenRouter receipt in each eligible assistant message, with route, fallback, usage, execution, cost, and generation details available on demand.
- Privacy-minimized persistence: Pines stores allowlisted routing and usage fields while excluding arbitrary router pipeline/plugin additions from message metadata and CloudKit sync.

## High-Value Unsupported Or Partial Features

### 1. Route provenance and remaining routing controls

Pines sends the highest-value provider routing and privacy controls and now persists/displays the successful response's selected upstream and safe fallback-attempt chain. It does not yet expose `max_price`, quantization filters, or per-thread/per-provider overrides. OpenRouter cache hits intentionally omit router metadata, so those receipts may contain accounting and generation identity without a route snapshot.

Value:

- Users should be able to verify which upstream actually handled a request, not only which route they requested.
- Price and quantization ceilings complete the operational routing policy.

Implementation notes:

- Add `max_price`, quantization, and scoped override controls after model metadata is available.
- Keep the receipt parser permissive for additive response changes while retaining the persisted allowlist.

### 2. OpenRouter server tools

Pines does not expose OpenRouter server tools such as `openrouter:web_search`.

Value:

- Model-callable real-time web search for any model, not just models with native search.

Implementation notes:

- Add server tool definitions to OpenRouter `tools`.
- Parse tool calls/results and standardized annotations.
- Prefer the server tool over deprecated web plugin shortcuts.

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

Pines parses and displays prompt/completion/total tokens, reported cost, upstream inference cost, and BYOK state per run. Cached/reasoning/media/server-tool detail, thread/provider rollups, and reconciliation through the generation accounting endpoint remain incomplete.

Value:

- Users can see actual request cost, upstream provider cost, cache savings, and reasoning token usage.

Implementation notes:

- Add cached, reasoning, media, and server-tool usage fields as product surfaces consume them.
- Add optional thread/provider spend summaries and generation-endpoint reconciliation without turning Pines into an account-management client.

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

Pines lists text models but does not deeply use OpenRouter's metadata for modalities, supported parameters, pricing, context length, or provider availability.

Value:

- Better model picker, safer routing, and clearer feature availability.

Implementation notes:

- Cache OpenRouter model metadata.
- Drive quick settings from supported parameters instead of model-name heuristics.

### 10. BYOK upstream provider routing

OpenRouter can route through user-supplied upstream provider keys in some configurations. Pines currently stores one OpenRouter key and does not manage upstream BYOK preferences.

Value:

- Users can centralize model routing while keeping spend on their own provider accounts.

Implementation notes:

- Requires careful secret UX and documentation because this nests provider credentials under OpenRouter behavior.

## Suggested Priority

1. Model metadata-driven eligibility and picker details.
2. Server web search tool and citations.
3. OpenRouter reasoning controls and detailed reasoning/cache usage.
4. Response healing for eligible non-streaming structured requests.
5. Max-price/quantization and scoped routing overrides.
6. Aggregate/reconciled spend reporting.
7. Prompt caching/transforms.
8. Additional modalities and upstream BYOK routing.

## Decisions And Open Questions

- Decision: OpenRouter has dedicated typed routing/privacy UI rather than raw JSON or generic OpenAI-compatible behavior.
- Decision: Pines requires parameter support automatically for tools and structured output.
- Decision: per-run cost accounting and upstream route provenance share one privacy-minimized, progressively disclosed chat receipt.
- Open: which routing controls should be per-thread overrides rather than provider defaults?
- Open: should OpenRouter server web search replace Pines-native or provider-native web search when selected?
