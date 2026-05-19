# OpenAI Provider Gaps

Last verified: 2026-05-19.

Primary sources:

- [Using GPT-5.5](https://developers.openai.com/api/docs/guides/latest-model)
- [Migrate to the Responses API](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [Using tools](https://developers.openai.com/api/docs/guides/tools)
- [Images and vision](https://developers.openai.com/api/docs/guides/images-vision)
- [Realtime and audio](https://developers.openai.com/api/docs/guides/realtime)
- [Video generation with Sora](https://developers.openai.com/api/docs/guides/video-generation)
- [Create a model response](https://developers.openai.com/api/reference/resources/responses/methods/create)
- [Data controls and residency](https://developers.openai.com/api/docs/guides/your-data)

## What Pines Supports Today

- Official OpenAI and OpenAI-compatible providers with BYOK credentials.
- Chat Completions streaming for OpenAI-compatible endpoints.
- Responses API for official OpenAI when reasoning models, native web search, attachments, tool call replay, or prior response IDs are involved.
- Text streaming, images, PDFs, and text documents through inline data URLs or Responses `input_file`.
- Function tools, with `parallel_tool_calls` disabled.
- Native OpenAI web search through the Responses API, with search context size, domain filters, external web access, and approximate user location.
- OpenAI reasoning effort and text verbosity for recognized reasoning models.
- Stateful Responses through `previous_response_id` when `store` is enabled, plus encrypted reasoning content inclusion for stateless-encrypted mode.
- Embeddings through `/v1/embeddings`, including `dimensions`.
- Request ID capture and basic token usage parsing.

## High-Value Unsupported Or Partial Features

### 1. Make Responses the default OpenAI path

Pines still uses Chat Completions for ordinary official OpenAI text turns unless specific features force Responses. OpenAI positions Responses as the recommended API for reasoning, tools, state, multimodal inputs, and future models.

Value:

- Better reasoning-model behavior and less split-path logic.
- One event parser for text, tools, hosted tools, files, reasoning metadata, and state.
- Cleaner support for future OpenAI models and hosted tools.

Implementation notes:

- Route all official OpenAI text/tool/image/file turns to `/v1/responses`.
- Keep Chat Completions only for OpenAI-compatible providers that do not implement Responses.
- Expand parser coverage for `phase`, assistant item replay, preambles, reasoning summaries, and output item variants.

### 2. Structured Outputs and strict JSON schema

Pines exposes a `jsonMode` capability but request builders do not send `text.format` / JSON schema for Responses or `response_format` for Chat Completions.

Value:

- Reliable typed extraction, data entry, tool planning, and local automation handoffs.
- Less brittle prompt-only JSON guidance.

Implementation notes:

- Add a typed response schema surface to `ChatRequest` or a separate structured-generation request.
- Map to Responses `text.format`.
- Preserve streaming partial JSON handling separately from plain token streaming.

### 3. Hosted File Search and vector stores

Pines has a local vault, but it does not use OpenAI vector stores or the hosted `file_search` tool.

Value:

- Users can bring large corpora to OpenAI without Pines inlining every file on each turn.
- Better long-document retrieval for cloud-specific threads.
- Useful for users already invested in OpenAI file/vector-store workflows.

Implementation notes:

- Add optional provider-hosted knowledge stores as distinct from local Vault.
- Add upload/delete/list lifecycle, retention disclosure, and per-turn consent.
- Parse `file_search_call.results` when included.

### 4. Code Interpreter hosted tool

OpenAI's hosted `code_interpreter` is not available in Pines.

Value:

- Data analysis, chart generation, file transformation, spreadsheet inspection, and repeatable calculations without implementing a local sandbox on iOS.

Implementation notes:

- Treat generated files as cloud artifacts with explicit download/import controls.
- Parse code outputs via `include: ["code_interpreter_call.outputs"]`.
- Add UI policy around executing code outside the device.

### 5. Image generation and image editing

Pines can send image inputs for analysis, but it cannot ask OpenAI to generate or edit images through the Images API or Responses `image_generation` tool.

Value:

- Visual ideation, UI asset generation, diagram/image edits, and multimodal assistant parity with ChatGPT-like workflows.

Implementation notes:

- Support generated image output items and base64/media handling.
- Decide whether this belongs in chat, a separate asset workflow, or both.
- Add safety/usage disclosures because images may have different retention and policy behavior.

### 6. Video generation and editing with Sora

OpenAI exposes Sora video generation and video editing APIs. Pines has no generated video output or provider video lifecycle support.

Value:

- Video prototyping, social/marketing assets, product storytelling, and iterative media editing.

Implementation notes:

- Add generated video job records because video generation is asynchronous and media-heavy.
- Support upload/reference/delete/download lifecycle for generated and edited videos.
- Add clear cost, eligibility, retention, and safety policy UI before exposing it in normal chat.

### 7. Realtime audio, speech-to-text, text-to-speech, and voice agents

Pines has no OpenAI Realtime, transcription, translation, or speech generation integration.

Value:

- Low-latency voice conversations, live transcription, accessibility, dictation, spoken responses, and translation.

Implementation notes:

- This is a separate transport from SSE chat: WebRTC/WebSocket sessions, ephemeral client secrets, audio buffers, VAD, interruptions, transcripts, and tool calls.
- On iOS, use server-minted ephemeral credentials if direct client sessions are supported.

### 8. Computer Use hosted tool

Pines does not expose OpenAI computer-use workflows.

Value:

- Browser/UI automation and visual task completion when combined with screenshots and actions.

Implementation notes:

- Needs strong approval gates, visible state, screenshot capture, action review, and provider-specific output parsing.
- Likely agent-only, not normal chat.

### 9. Remote MCP hosted tool and tool search

Pines has its own MCP client/server support, but it does not pass OpenAI-hosted `mcp` tools or `tool_search` to the Responses API.

Value:

- Let OpenAI models call remote MCP servers directly where the user wants provider-hosted orchestration.
- Reduce token cost for large tool catalogs by loading tools only when relevant.

Implementation notes:

- Keep this separate from local MCP approval policy; remote MCP sends data to a third-party service through OpenAI.
- Store remote MCP server configs per provider and expose per-tool allowlists.

### 10. Prompt caching controls

OpenAI can use `prompt_cache_key` and cache retention policies. Pines currently relies on provider defaults and does not expose cache keys or retention settings.

Value:

- Lower latency and cost for repeated system prompts, vault context, and long-running workflows.

Implementation notes:

- Add a stable cache key strategy that does not leak private identifiers.
- Track cached token counts in metrics.
- Allow per-thread or per-workflow cache policy.

### 11. Background mode, conversations, and response lifecycle APIs

Pines streams foreground requests only. It does not expose `background`, `conversation`, response retrieval/cancel, or provider-side conversation objects.

Value:

- Long-running research/coding/analysis tasks can continue while the app is backgrounded or reconnect after network interruptions.

Implementation notes:

- Needs local run records that can reconcile provider response IDs and statuses.
- Avoid silent provider-side persistence unless the user chooses it.

### 12. Service tier, safety identifier, metadata, and governance controls

Pines does not expose `service_tier`, `safety_identifier`, metadata, or organization/project governance fields.

Value:

- Enterprise users can control latency/cost class, abuse monitoring scoping, and audit correlation.

Implementation notes:

- Add optional per-provider advanced settings.
- Hash user/device identifiers before sending safety IDs.

### 13. Batch API, evals, moderation, and fine-tuning

These are not part of Pines today.

Value:

- Batch: cheaper asynchronous summarization, embedding, classification, and vault maintenance jobs.
- Evals: regression testing prompts/providers/models inside Pines.
- Moderation: optional user-controlled safety classification before sending cloud requests or publishing outputs.
- Fine-tuning: lower current priority because OpenAI's fine-tuning platform availability has changed and may not fit a BYOK consumer app.

Implementation notes:

- Batch and evals fit developer/pro workflows more than normal chat.
- Moderation should be optional and privacy-explicit, not hidden.

## Suggested Priority

1. Responses API as the default official OpenAI route.
2. Structured Outputs.
3. Hosted File Search/vector stores and Files API lifecycle.
4. Code Interpreter.
5. Realtime/audio.
6. Image and video generation/editing.
7. Prompt caching and lifecycle controls.
8. Remote MCP/tool search/computer use.
9. Batch/evals/moderation/governance settings.

## Review Checklist

- Should OpenAI Responses become mandatory for official OpenAI providers?
- Should provider-hosted files/vector stores be separate from local Vault, or can they be one UI with local/cloud profiles?
- Should generated images and code outputs appear inside chats, as attachments, or in a separate artifact library?
- Which OpenAI hosted tools should be available in normal chat versus agent-only mode?
- Should stateless encrypted reasoning be user-facing, automatic under ZDR-like settings, or hidden?
