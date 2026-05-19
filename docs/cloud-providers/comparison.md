# Cloud Provider Feature Comparison

Last verified: 2026-05-19.

This comparison is about provider API features that matter to Pines, not every product feature offered by each vendor. "Current" means implemented in Pines today. "Gap" means the provider offers a capability that Pines does not fully expose.

## Common Feature Matrix

| Feature | OpenAI | Anthropic | Gemini | OpenRouter | Voyage AI | Pines status |
| --- | --- | --- | --- | --- | --- | --- |
| Streaming text generation | Yes | Yes | Yes | Yes | No | Current for OpenAI/Anthropic/Gemini/OpenRouter |
| BYOK credentialed API access | Yes | Yes | Yes | Yes | Yes | Current |
| Model listing | Yes | Yes | Yes | Yes | No/limited | Current except Voyage returns no text models |
| Function/tool calling | Yes | Yes | Yes | Yes | No | Current for chat providers |
| Native/provider web search | Yes | Yes | Yes | Yes via server tool/plugin | No | Current only OpenAI/Anthropic/Gemini; OpenRouter gap |
| URL fetch/context tool | Partial via tools/MCP/custom | Yes, web fetch | Yes, URL context | Possible via tools/plugins | No | Gap |
| File upload/reuse API | Yes | Yes | Yes | Provider/model dependent | No general file API | Gap |
| Inline image input | Yes | Yes | Yes | Yes | Multimodal embeddings only | Current for chat providers |
| Inline PDF/document input | Yes | Yes | Yes | Yes/PDF plugin | No chat | Current for selected chat providers; no hosted file reuse |
| Audio input | Yes | Not primary Messages feature | Yes | Model dependent | No | Gap |
| Video input | No/limited by model/API | No | Yes | Model dependent | No | Gap |
| Text embeddings | Yes | No native embedding API | Yes | Yes | Yes | Current except Anthropic |
| Multimodal embeddings | No primary embedding API | No | Limited/model dependent | Yes for some models | Yes | Gap |
| Reranking API | No primary API | No | No primary API | Some routed models possible | Yes | Gap; Voyage highest priority |
| Structured outputs / JSON schema | Yes | Yes/guidance and tool schemas | Yes | Yes | No | Gap |
| Reasoning/thinking controls | Yes | Yes | Yes | Yes normalized | No | Current partly; OpenRouter gap |
| Reasoning summaries/visibility | Yes | Yes | Yes | Model dependent | No | Gap/partial |
| Prompt/context caching controls | Yes | Yes | Yes | Yes | No | Gap/partial |
| Hosted code execution | Yes | Yes | Yes | Provider/model dependent | No | Gap |
| Hosted file search/RAG | Yes | Search-result/citations patterns | Yes on newer models/tools | Provider/model dependent | Retrieval primitives only | Gap |
| Remote MCP/provider-hosted connectors | Yes | Yes | No primary public equivalent | Server tools, OpenAI-compatible tools | No | Gap |
| Computer use | Yes | Yes | No primary Gemini API equivalent | Model/provider dependent | No | Gap |
| Image generation/editing | Yes | No primary Messages output | Yes/Imagen | Yes via routed models | No | Gap |
| Video generation | Yes/Sora | No | Yes/Veo | Yes via routed models | No | Gap |
| Speech generation | Yes | No primary Messages output | Yes | Yes via routed models | No | Gap |
| Realtime voice/audio session API | Yes | No comparable public Messages API | Yes Live API | Model/provider dependent | No | Gap |
| Batch API | Yes | Yes | Yes | Provider/model dependent | Yes | Gap |
| Token counting/preflight | Yes/tokenization usage | Yes | Yes | Metadata/usage | Yes | Gap/partial |
| Usage/cost accounting | Yes usage | Yes usage | Yes usage | Yes detailed cost/cached/reasoning | Yes tokens | Partial; OpenRouter cost gap |
| Moderation/safety classification | Yes | Safety via model/policies | Safety settings | Routed/provider dependent | No | Gap/lower priority |
| Fine-tuning/evals | Yes, but changing availability | No public equivalent in same form | Tuning/eval options vary | Routed/provider dependent | No | Gap/lower priority |

## Features Present Across All Current Cloud Providers

Strictly across OpenAI, Anthropic, Gemini, OpenRouter, and Voyage AI:

- BYOK-style API access.
- Usage metering.
- Some form of model/service-specific limits and rate limits.

Across the four chat providers only, excluding Voyage AI:

- Streaming text responses.
- Model catalog/listing.
- User/system conversation input.
- Function/tool calling.
- Image input on capable models.
- Provider-specific request IDs and token usage metadata.

Across OpenAI, Gemini, OpenRouter, and Voyage AI:

- Embeddings. Anthropic does not provide a native embedding API, so Pines correctly excludes Anthropic from Vault embeddings.

Across OpenAI, Anthropic, Gemini, and OpenRouter:

- Some form of web/current-information retrieval is available. Pines supports OpenAI, Anthropic, and Gemini native search today; OpenRouter's current server tool/plugin path remains a gap.
- Some form of structured output is available. Pines does not expose a provider-neutral structured-output request shape today.

## Cross-Provider Architecture Opportunities

### 1. Provider-neutral structured output requests

Add a schema-bearing request type and map it to:

- OpenAI Responses `text.format`.
- OpenAI-compatible/OpenRouter `response_format`.
- Gemini `response_mime_type` plus schema fields.
- Anthropic tool/schema patterns or current structured-output support.

This would immediately improve extraction, automation, and settings-driven workflows across providers.

### 2. Provider-hosted file lifecycle abstraction

Define a `CloudProviderFile` abstraction with upload/list/delete/reference capabilities where supported:

- OpenAI Files/vector stores.
- Anthropic Files API.
- Gemini Files API.
- OpenRouter provider/model-specific files or plugins where available.

Keep this separate from local Vault because retention, privacy, and billing differ.

### 3. Retrieval quality pipeline

Pines already has Vault embeddings. High-value next steps:

- Add provider token counting for chunk budgets.
- Add Voyage rerankers as a post-retrieval rerank phase.
- Add contextualized and multimodal embedding profiles.
- Add optional provider-hosted file search only when the user chooses cloud persistence.

### 4. Tool and hosted-tool policy layer

Provider-hosted tools should flow through a shared policy surface:

- Read-only search/fetch.
- Code execution/sandbox.
- Remote MCP/server tools.
- Computer use.
- Generated media.

Each class needs consent, audit logging, and clear UI labels because data leaves Pines and may execute in provider infrastructure.

### 5. Realtime/media mode

OpenAI and Gemini both support realtime voice-style APIs. This should not be bolted onto the existing SSE chat path.

Recommended shape:

- Separate realtime session service.
- Ephemeral credential support.
- Audio/video capture and playback pipeline.
- Interruptions, transcripts, and session state persistence.
- Optional tool integration only after approval UI exists.

### 6. Usage and cost telemetry

Extend `InferenceMetrics` or provider metadata to represent:

- Input/output/reasoning/cached tokens.
- Cache writes and reads.
- Provider cost when available.
- Routed upstream provider when available.
- Hosted tool usage counts/costs.

This is especially important for OpenRouter and hosted tools.

## Proposed Implementation Themes

1. Make official OpenAI Responses the default path.
2. Add provider-neutral structured outputs.
3. Add provider-hosted files with explicit consent and retention UX.
4. Add Voyage reranking and richer embedding profiles.
5. Add OpenRouter routing/cost controls.
6. Add hosted code execution for OpenAI, Anthropic, and Gemini behind agent-only approval.
7. Add audio/video/realtime as a separate mode.
8. Add generated media output support after artifact persistence is ready.

## Questions To Resolve With Product Review

- Are provider-hosted files acceptable in a local-first app if they are explicit and per-provider?
- Should cloud search/fetch citations be visible by default in every provider response?
- Should provider-hosted code execution be available in ordinary chat, or only in agent sessions?
- Should OpenRouter be an expert/provider-routing surface rather than a generic OpenAI-compatible endpoint?
- Should Voyage become the first-class "retrieval specialist" provider rather than a generic embedding provider?
- Which features belong in iOS first, and which belong in a developer/pro desktop workflow later?
