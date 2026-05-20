# OpenAI Provider Status And Gaps

Last verified: 2026-05-19.

Primary sources:

- [Using GPT-5.5](https://developers.openai.com/api/docs/guides/latest-model)
- [Migrate to the Responses API](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [Using tools](https://developers.openai.com/api/docs/guides/tools)
- [Deep Research API cookbook](https://developers.openai.com/cookbook/examples/deep_research_api/introduction_to_deep_research_api)
- [Web search](https://developers.openai.com/api/docs/guides/tools-web-search)
- [Images and vision](https://developers.openai.com/api/docs/guides/images-vision)
- [Realtime and audio](https://developers.openai.com/api/docs/guides/realtime)
- [Video generation with Sora](https://developers.openai.com/api/docs/guides/video-generation)
- [Create a model response](https://developers.openai.com/api/reference/resources/responses/methods/create)
- [Data controls and residency](https://developers.openai.com/api/docs/guides/your-data)

## What Pines Supports Today

- Official OpenAI and OpenAI-compatible providers with BYOK credentials, model catalog refresh, validation, request ID capture, token usage parsing, and provider-specific stream metadata.
- Chat Completions streaming for OpenAI-compatible endpoints.
- Responses API for official OpenAI when reasoning models, native web search, attachments, tool-call replay, prior response IDs, or stateful/stateless reasoning paths require it.
- Text streaming, images, PDFs, and text documents through inline data URLs or Responses `input_file`.
- Function tools, with `parallel_tool_calls` disabled for the current tool loop.
- Native OpenAI web search through Responses, including search context size, domain filters, external web access, approximate user location, and web-source metadata.
- OpenAI reasoning effort and text verbosity for recognized reasoning models.
- Stateful Responses through `previous_response_id` when `store` is enabled, plus encrypted reasoning content inclusion for stateless-encrypted mode.
- OpenAI Files lifecycle through shared provider records: upload from local files/Vault, list, refresh metadata, delete, and storage previews.
- OpenAI vector store lifecycle through shared provider cache records: create, list, refresh, update, delete, attach/detach files, and vector-store file batch records.
- OpenAI Batch lifecycle: create from JSONL or provider file, refresh, cancel, and import result artifacts.
- OpenAI Deep Research run records: start, refresh, cancel, resume, summarize, and show research runs in the shared long-running job UI.
- OpenAI realtime/session records and workflow plumbing for realtime client/session creation.
- OpenAI provider artifact workflows for image, video, speech, transcription, translation, batch-result, and hosted-output artifacts, with shared artifact previews.
- Hosted tool request mapping for OpenAI web search, file search, code interpreter, image generation, computer use, remote MCP, tool search, and custom hosted tool configurations, with agent-context gating for high-risk tools.
- Hosted tool and artifact metadata parsing for OpenAI stream/output variants, including generated artifacts and provider-side tool provenance where returned.
- Embeddings through `/v1/embeddings`, including `dimensions`.

## Remaining High-Value Gaps

### 1. Make Responses the default OpenAI path

Pines still uses Chat Completions for ordinary official OpenAI text turns unless specific features force Responses. OpenAI positions Responses as the recommended API for reasoning, tools, state, multimodal inputs, and future models.

Needed work:

- Route all official OpenAI text/tool/image/file turns to `/v1/responses`.
- Keep Chat Completions only for OpenAI-compatible providers that do not implement Responses.
- Expand parser coverage for every Responses output item and hosted-tool phase before making the switch.

### 2. Structured Outputs and strict JSON schema

Pines exposes JSON-oriented capability flags, but it does not yet provide a provider-neutral structured-output request shape that maps to Responses `text.format` or compatible `response_format`.

Needed work:

- Add a typed response schema surface to `ChatRequest` or a separate structured-generation request.
- Validate final objects separately from normal markdown/text streams.
- Reuse the same abstraction for Anthropic, Gemini, OpenRouter, and compatible endpoints.

### 3. Hosted File Search per chat

OpenAI Files and vector stores are represented in Pines, but enabling the hosted `file_search` tool as a normal chat/agent source still needs product and policy work.

Needed work:

- Add per-chat/agent selection of vector stores and file-search settings.
- Parse and present `file_search_call.results` with citations/source chips.
- Keep local Vault, inline files, OpenAI files, and OpenAI vector stores visually distinct.

### 4. Code Interpreter hosted tool

Pines has shared hosted-tool provenance and artifact records, but OpenAI `code_interpreter` is not yet a complete user-facing workflow.

Needed work:

- Send tool config only after explicit provider-tool approval.
- Parse code outputs via the relevant `include` fields.
- Retrieve generated files and present them as cloud artifacts with download/import/delete controls.

### 5. Generated media production UI

OpenAI media artifact workflows exist for images, video, speech, transcription, and translation, but the normal user-facing media studio/viewer flow is still partial.

Needed work:

- Add dedicated image/video/audio controls rather than hiding media inside chat.
- Show cost, model, dimensions/duration, job status, provider retention, and safety context.
- Support edit/reuse/export/import actions from the artifact library.

### 6. Realtime voice/audio production UX

OpenAI realtime/session record plumbing exists, but a complete realtime voice UI and transport lifecycle is still in progress.

Needed work:

- Add dedicated voice/session surface with audio capture/playback, interruption handling, transcripts, reconnect/cancel, and tool approval overlays.
- Keep realtime separate from SSE chat assumptions.

### 7. Computer Use, remote MCP, and tool search

Pines has local MCP support and generic hosted-tool policy primitives, but OpenAI-hosted computer use, remote MCP, and tool search need separate approval models.

Needed work:

- Computer use requires screenshot/action review, visible state, and high-risk approvals.
- Remote MCP must be labeled separately from Pines-local MCP because data flows through OpenAI and the remote server.
- Tool search needs dynamic tool-loading provenance and model capability checks.

### 8. Prompt caching, background mode, conversations, and governance controls

Pines captures stateful response IDs and can represent long-running jobs, but it does not yet expose every OpenAI lifecycle/governance field.

Needed work:

- Add safe `prompt_cache_key` generation and retention controls without leaking private identifiers.
- Add broader `background`, `conversation`, response retrieve/cancel, service tier, safety identifier, and metadata settings.
- Show cached/reasoning token metrics consistently in run provenance.

### 9. Evals, moderation, and fine-tuning

These remain lower-priority developer/pro workflows.

Needed work:

- Add only when Pines has a developer/pro workspace that can explain provider storage, cost, and policy boundaries.
- Keep moderation optional and explicit, not hidden inside normal chat.

## Suggested Priority

1. Make Responses the default official OpenAI route.
2. Add provider-neutral structured outputs.
3. Finish hosted File Search selection and citation UI.
4. Complete Code Interpreter approvals and artifact import.
5. Harden generated media and realtime UX.
6. Add prompt cache/background/conversation/governance controls.
7. Revisit computer use, remote MCP, tool search, evals, moderation, and fine-tuning.

## Review Checklist

- Should OpenAI Responses become mandatory for official OpenAI providers?
- Are OpenAI files/vector stores clearly separate from local Vault in every flow?
- Should generated images and code outputs appear inside chats, as attachments, or in a separate artifact library?
- Which OpenAI hosted tools are safe in normal chat versus agent-only mode?
- Should stateless encrypted reasoning be user-facing, automatic under ZDR-like settings, or hidden?
