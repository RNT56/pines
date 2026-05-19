# OpenAI-Compatible And Custom Endpoint Production Parity Roadmap

Last verified: 2026-05-19. Companion gap analysis: [openai-compatible.md](openai-compatible.md).

## Product Goal

Make OpenAI-compatible and custom endpoints safe, configurable, and capable without pretending every endpoint supports the same API. Pines should discover or let users declare capabilities, then send only the features the endpoint can actually honor.

## Viable And Relevant Scope

- Capability probing and manual capability overrides.
- OpenAI-style Chat Completions and optional Responses API support.
- Structured outputs and provider-specific request parameters.
- Configurable multimodal input support.
- Model metadata for context length, modalities, pricing, tokenizer, and supported params.
- Better error normalization and diagnostics.
- Themed UI for capability probing, manual overrides, route selection, model metadata, and expert parameters.

## Explicitly Out Of Scope

- Full parity with every OpenAI-compatible vendor.
- Maintaining hardcoded integrations for niche providers under the generic provider kind.
- Sending arbitrary user JSON by default without validation/redaction.
- Enabling network-insecure endpoints except explicit local development routes already governed by security policy.

## Required UI

All UI must follow the shared [cloud provider UI roadmap](ui-roadmap.md).

Provider-specific screens/components:

- Capability probe dashboard with tested/declared/unknown states.
- Manual capability override editor for Responses, tools, structured outputs, embeddings, images, PDFs, audio, video, and usage metadata.
- Route selection control for Chat Completions, Responses, or automatic.
- Model metadata editor for context length, modalities, tokenizer hints, pricing, and supported parameters.
- Expert additional-parameters editor with JSON validation, secret-key warnings, and reset-to-default.
- Diagnostics panel showing redacted request shape, response shape, error parser result, and last validation outcome.

UI production requirements:

- Unknown capability must never look enabled.
- Expert controls must be visually separated from normal provider setup.
- Local-development HTTP exceptions must show warning styling and cannot be buried in advanced JSON.

## Phase 1: Capability Model

Goal: Stop guessing capabilities from provider kind or host.

Todos:

- Add persisted capability fields: chat completions, responses, streaming, tools, parallel tools, structured outputs, images, PDFs, text files, audio, video, embeddings, reasoning, prompt caching, request IDs, usage, and model metadata.
- Add validation-time probes for `/models`, `/chat/completions`, `/responses`, `/embeddings`, and structured output support where safe.
- Add manual overrides for self-hosted endpoints.
- Show "tested", "declared", and "unknown" capability states in settings.
- Add capability dashboard and manual override UI.

Possible hiccups:

- Some providers bill validation requests.
- Some providers accept unknown params but ignore them.
- Minimal probe requests can still fail because of model-specific restrictions.

Production complete when:

- Feature availability is data-driven, visible, and editable.
- Pines fails closed when a required capability is unknown or unsupported.

## Phase 2: Request Shape Selection

Goal: Route compatible endpoints to the right OpenAI-style API.

Todos:

- Add per-provider route preference: Chat Completions, Responses, or automatic.
- Support Responses shape when declared/probed.
- Keep Chat Completions fallback explicit.
- Add warnings when a chosen model requires unsupported capabilities.
- Add regression tests for providers that implement only a subset.

Possible hiccups:

- Responses-compatible providers may implement event names differently.
- Tool calls and usage payloads may drift from OpenAI's exact schema.

Production complete when:

- Users can successfully use compatible endpoints with either Chat Completions or Responses without silent feature loss.

## Phase 3: Structured Outputs And Extra Parameters

Goal: Let compatible endpoints expose their useful custom behavior safely.

Todos:

- Map provider-neutral schema requests to `response_format` or Responses `text.format`.
- Add an expert "additional request parameters" map with JSON validation.
- Block overriding sensitive or Pines-owned fields unless explicitly allowed.
- Redact additional params from diagnostics where secret-like keys appear.
- Add per-feature `require_parameters` equivalent where providers support it.
- Add themed expert JSON editor with validation and diagnostics redaction.

Possible hiccups:

- Extra params can break portability.
- Some providers use the same field names with different semantics.

Production complete when:

- Structured extraction works across compatible endpoints that support it.
- Expert params are auditable and cannot accidentally leak secrets.

## Phase 4: Multimodal And Embedding Configuration

Goal: Let capable custom endpoints use images/files/media and embeddings.

Todos:

- Add per-modality toggles and payload-shape selection.
- Add limits for inline media sizes by provider.
- Add embedding dimension/dtype/profile configuration.
- Add token/context preflight when metadata or tokenizer is available.

Possible hiccups:

- Payload shapes vary even among "OpenAI-compatible" endpoints.
- Media support is often model-specific, not provider-wide.

Production complete when:

- A user can configure a self-hosted multimodal endpoint without changing code.

## Phase 5: Model Metadata And Diagnostics

Goal: Make generic providers predictable.

Todos:

- Persist model metadata from `/models` where provided.
- Add manual metadata overrides.
- Surface context length, modality, tool, schema, and pricing hints in model picker.
- Expand error parser profiles and preserve redacted raw diagnostics for debugging.
- Add model metadata editor and diagnostics panel.

Possible hiccups:

- Metadata quality varies heavily by provider.
- Manual overrides can become stale.

Production complete when:

- Users can see why a model is or is not eligible for a requested feature.
