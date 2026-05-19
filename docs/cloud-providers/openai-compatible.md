# OpenAI-Compatible And Custom Endpoint Gaps

Last verified: 2026-05-19.

This is not a single provider API. Pines has `openAICompatible` and `custom` provider kinds for services that mimic OpenAI request/response shapes, including self-hosted gateways and third-party providers. Because these services vary widely, the goal is not feature parity with every possible endpoint; the goal is to avoid silently degrading a provider that advertises specific OpenAI-compatible features.

Related sources:

- [OpenAI Chat Completions API](https://developers.openai.com/api/docs/api-reference/chat)
- [OpenAI Responses API](https://developers.openai.com/api/reference/responses/overview)
- [OpenAI-compatible OpenRouter API reference](https://openrouter.ai/docs/api/reference/overview/)

## What Pines Supports Today

- Configurable base URL, headers, and BYOK credential.
- `/models` listing when the provider implements an OpenAI-style model catalog.
- `/chat/completions` streaming.
- Plain text messages.
- Function tools for non-custom OpenAI-compatible providers.
- Images/PDF/text documents only when the base URL is detected as official OpenAI; otherwise generic OpenAI-compatible providers are treated as text-first.
- Embeddings through `/embeddings`.
- Basic usage and finish-reason parsing through OpenAI-compatible stream chunks.

## High-Value Unsupported Or Partial Features

### 1. Capability probing

Pines currently infers most capabilities from provider kind and, in some cases, host name. It does not probe whether a compatible endpoint supports Responses, images, files, tools, JSON schema, reasoning, or audio.

Value:

- Avoids hiding features that a compatible provider actually supports.
- Avoids sending unsupported parameters that providers ignore or reject.

Implementation notes:

- Add optional capability tests during validation.
- Cache per-provider capability flags with last-tested timestamps.
- Let users override capabilities for self-hosted endpoints.

### 2. Responses API compatibility

Some OpenAI-compatible providers implement `/responses`; Pines only uses Responses for official OpenAI.

Value:

- Unlocks state, richer tool events, file inputs, and reasoning outputs for compatible providers that support them.

Implementation notes:

- Add an advanced "supports Responses API" flag.
- Probe `/responses` with a minimal non-streaming request where safe.
- Keep fallback to Chat Completions explicit and visible.

### 3. Structured outputs

OpenAI-compatible providers often support `response_format` with `json_object` or `json_schema`. Pines does not expose this.

Value:

- Provider-neutral extraction and automation.

Implementation notes:

- Add schema support to the request model.
- Let provider capabilities determine whether to use `response_format`, Responses `text.format`, or prompt-only fallback.

### 4. Multimodal capability configuration

Many compatible endpoints support image, audio, PDF, or file inputs, but Pines disables those unless the endpoint is official OpenAI or OpenRouter/Gemini/Anthropic-specific.

Value:

- Self-hosted and third-party providers can use their full model capability.

Implementation notes:

- Add per-provider toggles for image, PDF, text document, audio, and video input.
- Add per-modality payload-shape selection where needed.

### 5. Provider-specific parameters

Compatible providers often add parameters such as reasoning, seed, safety settings, provider routing, cache controls, raw mode, or service tiers. Pines only sends a narrow common subset.

Value:

- Users can access the differentiating features of their chosen provider.

Implementation notes:

- Add typed fields for common cross-provider parameters first.
- Add an expert-only JSON "additional request parameters" map after redaction and validation rules exist.

### 6. Model metadata beyond IDs

Pines does not persist compatible-provider model metadata such as context length, modalities, pricing, supported parameters, or tokenizer.

Value:

- Better model picker, request preflight, and feature gating.

Implementation notes:

- Support OpenRouter-style metadata when available.
- Allow manual metadata overrides for self-hosted providers.

### 7. Error normalization

Compatible endpoints may return non-OpenAI error shapes. Pines has a small set of generic error parsers.

Value:

- Better user-facing diagnostics and fewer opaque "invalid response" failures.

Implementation notes:

- Store provider kind plus error body shape samples in tests.
- Parse common `error`, `message`, `detail`, and `errors[]` patterns already present, then add provider profiles as needed.

## Suggested Priority

1. Capability probing and manual capability overrides.
2. Structured output support.
3. Responses API opt-in/probing.
4. Multimodal capability toggles.
5. Model metadata and context-window preflight.
6. Expert additional parameters.
7. Error normalization profiles.

## Review Checklist

- Should custom providers be text-only by default until capabilities are explicitly enabled?
- Should unsupported provider features fail closed, or should users be allowed to send expert JSON parameters?
- Should capability probing happen automatically during validation or only when the user taps "test features"?
- How much provider-specific behavior should live in generic compatible endpoints versus first-class provider kinds?
