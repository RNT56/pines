# Gemini Provider Status And Gaps

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
- Gemini Interactions for recognized thinking and deep-research paths.
- Model listing from `v1beta/models` and validation via `generateContent`.
- System instruction mapping.
- Image, PDF, and UTF-8 text-document inputs on user messages, plus GIF-to-PNG conversion for Gemini image compatibility.
- Gemini Files API lifecycle through shared provider records: upload local files, list, refresh metadata, poll processing state, delete, and reference provider file URIs from request parts.
- Gemini context cache lifecycle through shared provider cache records: create from inline data or file data, list/refresh, delete, and display cache TTL/model/token metadata.
- Token counting through Gemini request bodies for preflight and cache creation.
- Function declarations and function response handling.
- Native Google Search grounding for supported model/tool combinations, with grounding/source metadata captured in provider metadata.
- URL context metadata parsing for Generate Content and Interactions responses.
- Code execution tool mapping for Gemini request payloads and stream/parser metadata for executable code, execution results, and generated file/image references.
- Thinking levels for recognized models.
- Gemini Deep Research records through Interactions: start, refresh, cancel, resume, follow up, and show research runs in the shared long-running job UI.
- Gemini Live session service and session records for realtime-capable workflows.
- Gemini generated media workflows for image, video, and audio-style artifacts, stored as shared provider artifact records.
- Gemini Batch lifecycle records: create/import operations, refresh, cancel, and shared batch previews.
- Gemini embeddings through `batchEmbedContents`, including task type and output dimensionality handling.
- Settings/lifecycle UI for Gemini file media, context caches, generated media, Deep Research, realtime sessions, batches, and model capabilities.

## Remaining High-Value Gaps

### 1. Audio and video attachment depth

Pines can upload Gemini-hosted media files and represent file URIs, but ordinary chat attachment mapping is still strongest for images, PDFs, and text documents.

Needed work:

- Extend first-class chat attachment handling for audio/video with duration, size, MIME, and token preflight.
- Choose inline versus Files API automatically only when provider capability and user consent are clear.
- Add media-specific error handling for processing, expiry, and unsupported model combinations.

### 2. Structured outputs

Pines does not yet expose a provider-neutral structured-output request shape that maps to Gemini `response_mime_type`, `response_schema`, or `response_json_schema`.

Needed work:

- Add shared schema request support.
- Validate streamed/final JSON separately from markdown text.
- Handle built-in tool combinations and model-specific schema subsets.

### 3. Source attribution UI for grounding and URL context

Pines captures Google Search grounding and URL context metadata, but the chat/source panel still needs production detail.

Needed work:

- Show grounding chunks, search queries, URLs, rendered suggestions where required, and provider attribution text.
- Merge Gemini sources into the shared source/citation panel without losing Google-specific requirements.
- Distinguish Google Search grounding from URL Context and local Vault context.

### 4. Code execution artifact workflow

Gemini code execution mapping and parser metadata exist, but a complete artifact workflow for generated charts/files is still partial.

Needed work:

- Persist generated charts/files as provider artifacts.
- Add approval and environment labels before enabling code execution broadly.
- Support attach/import/export/delete actions from the artifact library.

### 5. Live API production UX

Gemini Live session service and records exist, but the dedicated realtime surface is not complete.

Needed work:

- Add audio/video capture, playback, interruption handling, VAD status, transcripts, reconnect/cancel, and tool approval overlays.
- Keep Live API flows separate from SSE text chat.

### 6. Deep Research production hardening

Gemini Deep Research records and workspace actions exist, but the preview agent still needs stronger source/progress handling.

Needed work:

- Persist richer event IDs, progress/thought summaries, source panels, and final report actions.
- Expose preview limitations, background/store requirements, source policy, and follow-up state.
- Add File Search data-source controls only with explicit provider-hosted file consent.

### 7. Generated media viewer and controls

Gemini generated media artifact records exist, but the media viewer and edit/reuse flow needs product polish.

Needed work:

- Add dedicated viewers for image, video, and audio outputs.
- Show model, prompt, operation status, dimensions/duration, safety/retention labels, and provider metadata.
- Add clear import/export/reuse/delete paths.

### 8. Batch and model capability hardening

Gemini batch and capability records exist, but capability-driven model selection is still partial.

Needed work:

- Replace more model-name heuristics with refreshed model capability records.
- Add partial failure/result import handling for batches.
- Tie token counts and cache eligibility into routing and Vault context packing.

## Suggested Priority

1. Finish audio/video attachment and media preflight UX.
2. Add provider-neutral structured outputs.
3. Complete source attribution for grounding and URL context.
4. Harden code execution artifacts.
5. Complete Live API and generated media UX.
6. Harden Deep Research, batches, context caches, and model capability refresh.

## Review Checklist

- Should Gemini Files API become automatic over size limits, opt-in, or both?
- Should audio/video inputs be normal chat attachments or a media-analysis workspace?
- Should Gemini generated media appear in chat, an artifact gallery, or both?
- Should Gemini Live API be part of chat or a separate voice mode?
- Are Google Search grounding attribution requirements visible enough in source panels?
