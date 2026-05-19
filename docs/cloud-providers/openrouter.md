# OpenRouter Provider Gaps

Last verified: 2026-05-19.

Primary sources:

- [OpenRouter API reference](https://openrouter.ai/docs/api/reference/overview/)
- [Parameters](https://openrouter.ai/docs/api/reference/parameters)
- [Models](https://openrouter.ai/docs/guides/overview/models)
- [Provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [Structured outputs](https://openrouter.ai/docs/features/structured-outputs)
- [Server tools](https://openrouter.ai/docs/guides/features/server-tools/overview)
- [Web search server tool](https://openrouter.ai/docs/guides/features/server-tools/web-search)
- [Plugins](https://openrouter.ai/docs/guides/features/plugins/overview)
- [Multimodal capabilities](https://openrouter.ai/docs/guides/overview/multimodal/overview)
- [Usage accounting](https://openrouter.ai/docs/guides/guides/usage-accounting)
- [Prompt caching](https://openrouter.ai/docs/features/prompt-caching)

## What Pines Supports Today

- OpenRouter as an OpenAI-compatible chat provider through `/chat/completions`.
- Model listing from `/models`.
- Streaming text and function tool calling.
- Image inputs.
- PDF inputs through OpenRouter's `file` content part shape.
- OpenRouter embeddings through `/embeddings` with `input_type`.
- Usage parsing through OpenAI-compatible stream shapes.

## High-Value Unsupported Or Partial Features

### 1. Provider routing controls

OpenRouter's main product value is routing across many upstream providers, but Pines does not expose `provider.order`, `allow_fallbacks`, `require_parameters`, `data_collection`, `zdr`, `max_price`, or provider ignore/only preferences.

Value:

- Users can enforce privacy, cost, latency, availability, or provider-specific requirements.
- Prevents silent fallback to providers that lack required parameters or retention guarantees.

Implementation notes:

- Add OpenRouter-specific advanced settings per request/thread/provider.
- Use `require_parameters: true` when Pines sends structured outputs, tools, reasoning controls, or modalities that must not be dropped.
- Surface actual routed provider and fallback metadata where available.

### 2. OpenRouter server tools

Pines does not expose OpenRouter server tools such as `openrouter:web_search`.

Value:

- Model-callable real-time web search for any model, not just models with native search.

Implementation notes:

- Add server tool definitions to OpenRouter `tools`.
- Parse tool calls/results and standardized annotations.
- Prefer the server tool over deprecated web plugin shortcuts.

### 3. Structured outputs and response healing

Pines does not send `response_format` JSON schema or OpenRouter `structured_outputs` hints. It also does not enable response healing for imperfect JSON.

Value:

- Reliable extraction across many models.
- More robust results from models that approximate JSON but do not strictly follow schemas.

Implementation notes:

- Use `require_parameters: true` when a schema is mandatory.
- Consider optional response-healing plugin for non-streaming structured requests.

### 4. Reasoning token controls

OpenRouter normalizes reasoning controls across providers. Pines only has provider-specific OpenAI/Anthropic/Gemini quick settings and does not pass OpenRouter's `reasoning` parameter.

Value:

- Unified control over thinking/reasoning budget across many routed models.
- Better model parity when using non-native providers.

Implementation notes:

- Add OpenRouter-specific `reasoning` mapping separate from official OpenAI Responses `reasoning`.
- Parse reasoning content and reasoning token usage when available.

### 5. Usage accounting and cost metadata

OpenRouter returns detailed token, cached-token, reasoning-token, and cost data. Pines only parses generic token usage.

Value:

- Users can see actual request cost, upstream provider cost, cache savings, and reasoning token usage.

Implementation notes:

- Extend `InferenceMetrics` or provider metadata to include cost and detailed token fields.
- Show per-run cost in audit/details UI.

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

1. Provider routing controls and actual routed-provider metadata.
2. Structured outputs with `require_parameters`.
3. Usage/cost accounting.
4. Server web search tool.
5. Reasoning controls.
6. Model metadata-driven picker.
7. Prompt caching/transforms.
8. Additional modalities and upstream BYOK routing.

## Review Checklist

- Should OpenRouter be treated as just OpenAI-compatible, or as its own routing platform with dedicated UI?
- Should Pines default `require_parameters: true` for tools/schema/modalities to avoid degraded requests?
- Which routing controls should be simple toggles versus expert-only JSON settings?
- Should OpenRouter cost accounting be first-class in run details?
- Should OpenRouter server web search replace Pines-native or provider-native web search when selected?
