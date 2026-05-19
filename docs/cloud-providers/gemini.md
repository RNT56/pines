# Gemini Provider Gaps

Last verified: 2026-05-19.

Primary sources:

- [Gemini models](https://ai.google.dev/gemini-api/docs/models/gemini-v2)
- [Files API](https://ai.google.dev/gemini-api/docs/files)
- [Structured outputs](https://ai.google.dev/gemini-api/docs/structured-output)
- [Function calling](https://ai.google.dev/gemini-api/docs/function-calling)
- [Code execution](https://ai.google.dev/gemini-api/docs/code-execution)
- [Gemini Deep Research Agent](https://ai.google.dev/gemini-api/docs/deep-research)
- [Live API](https://ai.google.dev/gemini-api/docs/live)
- [Live API capabilities guide](https://ai.google.dev/gemini-api/docs/live-guide)
- [Gemini pricing/model capability pages](https://ai.google.dev/gemini-api/docs/pricing)

## What Pines Supports Today

- Gemini Generate Content streaming with `alt=sse`.
- Gemini Interactions for recognized thinking/deep-research paths.
- Model listing from `v1beta/models` and validation via `generateContent`.
- System instruction mapping.
- Image, PDF, and UTF-8 text-document inputs on user messages.
- Function declarations and function response handling.
- Native Google Search grounding for supported model/tool combinations.
- Thinking levels for recognized models.
- Deep Research agent ID routing when model IDs contain `deep-research`.
- Gemini embeddings through `batchEmbedContents`, including task type and output dimensionality handling.
- GIF-to-PNG conversion for Gemini image compatibility.

## High-Value Unsupported Or Partial Features

### 1. Files API and reusable file URIs

Pines inlines Gemini images/PDFs/text documents. Gemini recommends the Files API when request size exceeds 20 MB and supports media reuse across prompts.

Value:

- Large audio, video, PDF, image, and document handling.
- Reuse large files across multiple turns without inlining.
- Better long-document and media workflows.

Implementation notes:

- Add resumable upload, file metadata, delete/list, and file URI references.
- Add consent UI because provider-hosted files persist outside local storage.
- Use Files API when attachments exceed current inline limits or when user chooses cloud persistence.

### 2. Audio and video inputs

Gemini models can accept audio and video, but Pines cloud attachment support only maps images, PDFs, and text documents.

Value:

- Meeting/audio summarization, video analysis, lecture review, media QA, and accessibility workflows.

Implementation notes:

- Extend `AttachmentKind` cloud mapping to audio/video for provider-capable models.
- Prefer Files API for larger media.
- Add media duration/size/token preflight.

### 3. Structured outputs

Pines does not set Gemini `response_mime_type`, `response_schema`, or `response_json_schema`.

Value:

- Typed extraction, local automations, table generation, and structured tool handoffs.
- Gemini 3 structured outputs can combine with built-in tools such as search, URL context, code execution, and file search.

Implementation notes:

- Add provider-neutral schema request support.
- Stream partial JSON separately from normal markdown/text.

### 4. Code execution

Gemini code execution lets the model generate and run Python, with file input and graph output on supported models.

Value:

- Calculations, CSV/text analysis, chart generation, and code-based reasoning without a local runtime.

Implementation notes:

- Add `code_execution` tool config.
- Parse executable code parts, execution results, and inline image outputs.
- Decide how generated charts become chat attachments or artifacts.

### 5. URL context

Pines supports its own web tools and Gemini Google Search grounding, but not Gemini URL Context.

Value:

- Users can ask about specific URLs without relying on search ranking.
- Strong fit for documentation, articles, and issue pages.

Implementation notes:

- Add provider-specific URL context tool.
- Preserve source metadata/citations in message metadata.

### 6. Context caching

Gemini supports prompt/context caching on eligible models. Pines does not create or reference cached content.

Value:

- Lower cost and latency for repeated large system prompts, tool definitions, and document context.

Implementation notes:

- Add cache creation/list/delete lifecycle and TTL/cost display.
- Use cache IDs in follow-up Generate Content requests.

### 7. Gemini Deep Research Agent

Gemini exposes a Deep Research Agent through the Interactions API. It is currently preview, requires `background=true`, is not available through `generate_content`, uses web search and URL context by default, can use File Search for user data experimentally, supports streaming progress, and can continue follow-ups with `previous_interaction_id`.

Value:

- Long-running cited reports, market analysis, due diligence, literature reviews, comparative research, and "analyst-in-a-box" workflows.
- Directly relevant to Pines because the app already has a Gemini Interactions path and local Vault context that could be bridged with consent.

Implementation notes:

- Pines currently has model-ID-based Deep Research routing, but production parity needs background execution, polling, resumable streams, event IDs, thinking summaries, citations, File Search integration, and a dedicated research UI.
- Must expose limitations: preview status, no `generate_content`, max research time, no custom function tools/MCP currently, no structured output/plan approval, store requirement, and no audio input.

### 8. Live API and realtime audio/video

Pines does not use Gemini Live API.

Value:

- Low-latency spoken conversations, streaming audio/video interaction, voice activity detection, session management, tool use, and ephemeral tokens.

Implementation notes:

- Requires WebSocket/WebRTC style session orchestration, not SSE.
- Separate normal chat from live sessions in UI and persistence.

### 9. Image, video, speech, and music generation

Pines only consumes Gemini text output today. It does not expose Imagen, Veo, speech generation, or Lyria/music generation.

Value:

- Creative generation, marketing assets, video prototyping, voice output, and media workflows.

Implementation notes:

- Add output modality types beyond text.
- Add generated media persistence and safety policy display.
- Consider separate workflows instead of mixing every media type into normal chat.

### 10. Batch API

Pines does not use Gemini Batch API.

Value:

- Cost-effective async summarization, extraction, evaluation, and embedding jobs over many documents.

Implementation notes:

- Add batch job records, result import, cancellation, and status polling.

### 11. Advanced grounding and citation controls

Pines toggles Google Search but does not expose detailed grounding metadata, source display controls, or search retrieval configuration beyond mode.

Value:

- Verifiable answers and search auditability.

Implementation notes:

- Parse grounding chunks, search queries, and rendered suggestions consistently.
- Expose search requirement and source filters where available.

### 12. Thinking budgets and summaries

Pines maps thinking level, but not detailed thinking budget/summaries and model-specific controls.

Value:

- Better user control of latency, cost, and reasoning transparency.

Implementation notes:

- Add per-model controls and display only provider-approved summaries.

### 13. Token counting and request preflight

Pines does not use Gemini token-counting endpoints before cloud requests.

Value:

- Better attachment/context limits, cost estimates, and routing decisions.

Implementation notes:

- Integrate token count into Vault context packing and cloud attachment preflight.

## Suggested Priority

1. Files API with audio/video inputs.
2. Structured outputs.
3. Code execution and URL context.
4. Context caching.
5. Grounding citation metadata.
6. Deep Research Agent as a dedicated long-running research workflow.
7. Live API/realtime.
8. Generated media.
9. Batch and token counting.

## Review Checklist

- Should Gemini Files API become automatic over 20 MB, opt-in, or both?
- Should audio/video inputs be normal chat attachments or separate media-analysis workflows?
- Should Gemini generated media appear in chat or in an artifact gallery?
- Should Gemini Live API be part of Pines chat or a separate voice mode?
- Should Google Search grounding be source-first, with visible citations by default?
