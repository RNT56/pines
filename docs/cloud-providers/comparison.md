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
| URL fetch/context tool | Partial via tools/MCP/custom | Yes, web fetch | Yes, URL context | Possible via tools/plugins | No | Current for Anthropic/Gemini metadata paths; OpenAI/OpenRouter provider-native gaps remain |
| File upload/reuse API | Yes | Yes | Yes | Provider/model dependent | No general file API | Current for OpenAI/Anthropic/Gemini provider lifecycle; OpenRouter gap |
| Inline image input | Yes | Yes | Yes | Yes | Multimodal embeddings only | Current for chat providers |
| Inline PDF/document input | Yes | Yes | Yes | Yes/PDF plugin | No chat | Current for selected chat providers; hosted file reuse current for OpenAI/Anthropic/Gemini |
| Audio input | Yes | Not primary Messages feature | Yes | Model dependent | No | Gap |
| Video input | No/limited by model/API | No | Yes | Model dependent | No | Gap |
| Text embeddings | Yes | No native embedding API | Yes | Yes | Yes | Current except Anthropic |
| Multimodal embeddings | No primary embedding API | No | Limited/model dependent | Yes for some models | Yes | Gap |
| Reranking API | No primary API | No | No primary API | Some routed models possible | Yes | Gap; Voyage highest priority |
| Structured outputs / JSON schema | Yes | Yes/guidance and tool schemas | Yes | Yes | No | Provider-neutral request shape remains a gap |
| Reasoning/thinking controls | Yes | Yes | Yes | Yes normalized | No | Current for OpenAI/Anthropic/Gemini; OpenRouter still partial |
| Reasoning summaries/visibility | Yes | Yes | Yes | Model dependent | No | Partial; safe summary display and provider parity still need hardening |
| Prompt/context caching controls | Yes | Yes | Yes | Yes | No | Current for Anthropic prompt cache and Gemini context cache lifecycle; OpenAI/OpenRouter controls remain gaps |
| Hosted code execution | Yes | Yes | Yes | Provider/model dependent | No | Parser/artifact/policy groundwork current for OpenAI/Anthropic/Gemini; broad enablement still gated |
| Hosted file search/RAG | Yes | Search-result/citations patterns | Yes on newer models/tools | Provider/model dependent | Retrieval primitives only | OpenAI vector-store lifecycle current; per-chat hosted search remains a gap |
| Deep research / long-running research agent | Yes, Responses/Deep Research | No direct equivalent | Yes, Interactions Deep Research Agent | Model/provider dependent | No | Current run records/workspaces for OpenAI and Gemini; production source UX still partial |
| Remote MCP/provider-hosted connectors | Yes | Yes | No primary public equivalent | Server tools, OpenAI-compatible tools | No | Local MCP current; provider-hosted MCP remains gated/partial |
| Computer use | Yes | Yes | No primary Gemini API equivalent | Model/provider dependent | No | Surfaced as high-risk capability; disabled pending dedicated safety UX |
| Image generation/editing | Yes | No primary Messages output | Yes/Imagen | Yes via routed models | No | Current artifact workflows for OpenAI/Gemini generated media; editing depth remains partial |
| Video generation | Yes/Sora | No | Yes/Veo | Yes via routed models | No | Current job/artifact records for OpenAI/Gemini; production viewer/cost UX partial |
| Speech generation | Yes | No primary Messages output | Yes | Yes via routed models | No | Current artifact workflows for OpenAI/Gemini speech/audio outputs |
| Realtime voice/audio session API | Yes | No comparable public Messages API | Yes Live API | Model/provider dependent | No | Current OpenAI/Gemini session records/services; dedicated realtime UX still partial |
| Batch API | Yes | Yes | Yes | Provider/model dependent | Yes | Current for OpenAI/Anthropic/Gemini lifecycle; Voyage/OpenRouter gaps |
| Token counting/preflight | Yes/tokenization usage | Yes | Yes | Metadata/usage | Yes | Current for Anthropic/Gemini preflight paths; broader routing/cost integration partial |
| Usage/cost accounting | Yes usage | Yes usage | Yes usage | Yes detailed cost/cached/reasoning | Yes tokens | Partial; cache/tool/detail coverage varies by provider |
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

Across OpenAI, Anthropic, and Gemini:

- Provider-hosted file records and storage views are represented through shared provider lifecycle types.
- Batch/job state is represented through shared `ProviderBatchRecord` previews with refresh/cancel/import hooks where supported.
- Provider artifact records are used for generated media, generated files, transcripts, and imported batch outputs.
- Provider capabilities, run provenance, citations, hosted tool events, and file references are surfaced through shared metadata rather than provider-only persistence tables.

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

### 2. Provider-hosted file lifecycle hardening

Pines now has shared provider file/cache/batch/artifact records for the major providers. The next work is production hardening:

- OpenAI Files/vector stores.
- Anthropic Files API.
- Gemini Files API.
- OpenRouter provider/model-specific files or plugins where available.

Keep these resources separate from local Vault because retention, privacy, and billing differ. Add stronger upload progress, retry/cancellation, orphan cleanup, and per-chat reuse controls.

### 3. Retrieval quality pipeline

Pines already has Vault embeddings. High-value next steps:

- Use provider token counting consistently for chunk budgets.
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
3. Harden provider-hosted file/caching/batch lifecycle UX with progress, retry, cancellation, and cleanup.
4. Add Voyage reranking and richer embedding profiles.
5. Add OpenRouter routing/cost controls.
6. Finish hosted code execution approvals and artifact import for OpenAI, Anthropic, and Gemini.
7. Finish audio/video/realtime as separate modes, not normal chat variants.
8. Expand generated media viewers and provider provenance on top of the artifact library.

## Questions To Resolve With Product Review

- Are provider-hosted files acceptable in a local-first app if they are explicit and per-provider?
- Should cloud search/fetch citations be visible by default in every provider response?
- Should provider-hosted code execution be available in ordinary chat, or only in agent sessions?
- Should OpenRouter be an expert/provider-routing surface rather than a generic OpenAI-compatible endpoint?
- Should Voyage become the first-class "retrieval specialist" provider rather than a generic embedding provider?
- Which features belong in iOS first, and which belong in a developer/pro desktop workflow later?
