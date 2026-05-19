# OpenAI Production Parity Roadmap

Last verified: 2026-05-19. Companion gap analysis: [openai.md](openai.md).

## Product Goal

Make the official OpenAI provider in Pines feel like a first-class OpenAI API client for the parts that fit a local-first AI workbench: high-quality text/reasoning, structured outputs, tools, hosted files/search, generated media, audio/realtime, transparent cost/usage, and explicit privacy controls.

## Viable And Relevant Scope

- Default official OpenAI chat to Responses API.
- Structured Outputs and schema-backed extraction.
- Provider-hosted Files API, vector stores, File Search, and local Vault integration choices.
- Hosted tools: web search, file search, code interpreter, image generation, computer use, remote MCP, tool search.
- Deep Research through Responses/background mode for long-running citation-rich reports.
- Reasoning controls, verbosity, reasoning summaries/encrypted reasoning, state handling, prompt caching.
- Image, video, speech, transcription, translation, and realtime voice workflows.
- Batch, moderation, eval-oriented developer workflows where they support Pines power users.
- Usage/cost/governance metadata: service tier, safety identifier, prompt cache, cached/reasoning tokens, request IDs.
- Themed UI for capability management, hosted tools, provider files/vector stores, generated artifacts, realtime sessions, and run provenance.

## Explicitly Out Of Scope

- Managing OpenAI billing, projects, organization membership, or API keys beyond Pines BYOK storage.
- Training/fine-tuning job creation as a normal end-user feature unless Pines later adds a developer/pro workspace.
- Recreating the OpenAI dashboard or Playground.
- Silent provider-side file persistence. Any hosted storage must be explicit.
- Automatic moderation or data upload without user-visible policy and consent.

## Required UI

All UI must follow the shared [cloud provider UI roadmap](ui-roadmap.md).

Provider-specific screens/components:

- OpenAI capability dashboard showing Responses, Chat Completions fallback, structured outputs, hosted tools, files/vector stores, realtime, image/video generation, and batch availability.
- Deep Research workspace with prompt, scope, source policy, estimated duration/cost, progress timeline, citations, and final report export/import actions.
- Responses state controls in provider settings: storage mode, encrypted reasoning/stateless mode, background runs, service tier, prompt cache retention, and safety identifier.
- Files/vector store manager with upload, vector store membership, File Search enablement, provider retention labels, and delete paths.
- Hosted tool timeline rows for web search, file search, code interpreter, image generation, computer use, remote MCP, and tool search.
- Code Interpreter artifact viewer for generated files, charts, logs, and execution summaries.
- Generated image/video artifact gallery with provider metadata, prompt, model, dimensions/duration, status, and delete/reuse actions.
- Realtime voice/session UI with transcript, waveform, mute/interruption controls, tool approval overlay, and session diagnostics.
- OpenAI run provenance sheet with response ID, request ID, previous response ID, service tier, cached/reasoning tokens, hosted tool usage, and provider-side storage state.

UI production requirements:

- OpenAI-hosted files/vector stores must be visually distinct from local Vault.
- Hosted tools must be clearly labeled as OpenAI-hosted, not Pines-local.
- Video generation must use job/status UI, not a blocking chat spinner.
- Deep Research must use a long-running job UI with reconnect/resume, not a normal chat typing indicator.
- Realtime mode must live in a dedicated surface rather than normal text chat controls.

## Phase 1: Responses API Foundation

Goal: Use one modern OpenAI path for official OpenAI features.

Todos:

- Route all official OpenAI chat requests through `/v1/responses`.
- Keep Chat Completions only for OpenAI-compatible endpoints or explicit fallback.
- Add a Responses request model covering `input`, `instructions`, `tools`, `tool_choice`, `text`, `reasoning`, `include`, `store`, `previous_response_id`, `conversation`, `metadata`, `service_tier`, `prompt_cache_key`, `prompt_cache_retention`, `safety_identifier`, `max_tool_calls`, and `background`.
- Expand stream parsing for output items, preambles, reasoning items, phases, annotations, hosted tool calls, and failure/incomplete events.
- Persist provider response IDs, output items, response status, service tier, and usage details in message/run metadata.
- Add tests for stateful and stateless replay, including encrypted reasoning content.
- Add UI controls for Responses storage mode, background mode, service tier, and prompt cache settings.
- Add run detail UI for response IDs, previous response IDs, reasoning/cache usage, and provider-side state.

Possible hiccups:

- Existing Chat Completions replay shape differs from Responses output-item replay.
- Tool approval flow may need to pause and resume a Responses run with richer state than current tool calls.
- `store=false` plus reasoning models needs careful encrypted reasoning replay.

Production complete when:

- Normal OpenAI chat, tool calls, attachments, web search, reasoning models, and follow-up turns all work through Responses.
- Existing OpenAI threads still open and continue, with a safe migration/fallback path.
- Tests cover text, refusal, tool call, hosted tool event, incomplete, failed, usage, and cancellation streams.

## Phase 2: Structured Outputs

Goal: Make schema-backed output reliable across extraction, automation, and tool handoff use cases.

Todos:

- Add a provider-neutral structured output request type or `ChatRequest` schema field.
- Map OpenAI to Responses `text.format`.
- Add schema validation and user-facing validation errors.
- Add streaming behavior for partial JSON and final parsed objects.
- Add UI/API affordances for "plain text", "JSON object", and "JSON schema".
- Add tests for valid schema output, invalid schema recovery, refusal, truncation, and tool plus schema combinations.

Possible hiccups:

- Structured output and hosted tools may have model-specific restrictions.
- Streaming partial JSON cannot be treated like normal markdown tokens in all views.

Production complete when:

- A caller can request typed JSON and receive a validated object or explicit validation failure.
- The same abstraction is reusable by Anthropic, Gemini, OpenRouter, and compatible endpoints.

## Phase 3: Files, Vector Stores, And File Search

Goal: Let users choose provider-hosted knowledge when it beats inline attachments while keeping local Vault separate.

Todos:

- Add `CloudProviderFile` and `CloudProviderKnowledgeStore` records.
- Implement upload, list, retrieve metadata, delete, and reference file IDs.
- Implement vector store create/list/update/delete and file attach/detach where supported.
- Add File Search tool configuration and parse file-search results/citations.
- Add import path from local Vault document to OpenAI-hosted file/vector store with explicit consent.
- Add retention, billing, and provider-storage warnings.
- Add cleanup UX for orphaned hosted files.
- Build themed file/vector store management screens and source chips for File Search results.

Possible hiccups:

- Hosted vector stores may duplicate local Vault state and confuse users.
- Provider file retention and project scope may not map cleanly to local conversation scope.
- Large file upload needs background/retry behavior on iOS.

Production complete when:

- Users can upload/reuse/delete OpenAI files and choose hosted File Search per chat/agent.
- Pines clearly shows whether context came from local Vault, inline files, or OpenAI-hosted file search.

## Phase 4: Hosted Tools

Goal: Expose OpenAI-hosted tools when they reduce local implementation burden and improve output quality.

Todos:

- Code Interpreter: send tool config, parse code/tool outputs, retrieve generated files, show sandbox label.
- Image generation: support generated image output items, edits, quality/size controls, and asset persistence.
- Computer Use: add screenshot/action loop, approval gates, visible state, and action audit logs.
- Remote MCP: store server label, URL, auth, approval policy, allowlist, and data disclosure.
- Tool Search: register tool catalogs and parse dynamic tool loading events.
- Add per-tool availability checks from model capabilities.
- Add audit events for every hosted tool call.
- Add approval sheets and timeline rows for each hosted tool class.

Possible hiccups:

- Hosted tool events are more varied than simple function calls.
- Computer Use is high risk and should not ship without strong approval UX.
- Remote MCP data path differs from Pines-local MCP and needs separate consent wording.

Production complete when:

- Each hosted tool has a clear settings switch, consent surface, parser coverage, audit trail, and error handling.
- Generated artifacts can be viewed, imported, deleted, or attached to follow-up turns.

## Phase 5: Prompt Caching, State, And Background Runs

Goal: Make long OpenAI workflows cheaper, resumable, and robust.

Todos:

- Add safe `prompt_cache_key` generation and optional user/project scoping.
- Add prompt cache retention setting.
- Parse cached token metrics.
- Add `background` run support with status polling, cancel, retrieve, and resume.
- Add provider conversation support only when user opts into provider-side state.
- Add service tier selector for default/flex/priority where available.

Possible hiccups:

- Cache keys can leak identity if built carelessly.
- Background runs conflict with current foreground SSE run assumptions.

Production complete when:

- Long OpenAI runs survive app interruptions and expose cost/cache telemetry.
- Users can disable provider-side storage/state clearly.

## Phase 6: Deep Research

Goal: Add OpenAI Deep Research as a first-class research workflow.

Todos:

- Add a Deep Research run type backed by Responses/background mode.
- Support deep-research model selection and high/xhigh reasoning web-research mode where appropriate.
- Add research scope controls: web only, web plus hosted files, web plus user-approved Vault export, domain filters, source count/depth, and report format.
- Parse progress events, web-search calls, code-execution calls, citations, final report, and usage/cost.
- Add resume/poll/cancel for long-running research tasks.
- Add final report actions: attach to chat, save to Vault, export, and create follow-up chat.
- Add tests for completed, failed, cancelled, reconnect/resume, citation parsing, and partial progress.

Possible hiccups:

- Research runs can last minutes and may exceed normal mobile foreground expectations.
- Citation/source event shapes can differ from normal web-search responses.
- User-approved local Vault context may need transformation into provider-hosted files or remote MCP.

Production complete when:

- A user can start, monitor, resume, cancel, and inspect an OpenAI Deep Research run with citations and final report artifacts.

## Phase 7: Audio, Realtime, And Generated Media

Goal: Add OpenAI media workflows without overloading text chat.

Todos:

- Add speech-to-text for audio attachments and dictation.
- Add text-to-speech for assistant responses.
- Add realtime voice sessions with ephemeral credentials, audio capture/playback, interruption handling, transcripts, and tool gating.
- Add realtime translation/transcription modes.
- Add Sora video generation/editing job lifecycle and media viewer.
- Add generated media library and per-artifact retention controls.
- Add dedicated realtime session UI and generated media artifact gallery.

Possible hiccups:

- Realtime is a different transport and lifecycle than SSE.
- Generated video is asynchronous, expensive, and may have account eligibility constraints.
- iOS background audio/networking behavior needs careful handling.

Production complete when:

- Voice/media workflows have dedicated UI, persistence, cost controls, and accessibility support.
- Text chat remains stable and uncomplicated for users who do not enable media.

## Phase 8: Batch, Moderation, And Developer Workflows

Goal: Support advanced workflows only where they fit Pines.

Todos:

- Add Batch API for bulk vault summarization, extraction, embedding-adjacent tasks, and eval runs.
- Add optional moderation classification for user-controlled safety checks.
- Add eval harness integration for prompt/provider regression testing.

Possible hiccups:

- Fine-tuning and evals are more developer-platform than mobile workbench features.
- Batch jobs require durable background state and result import.

Production complete when:

- Batch/eval workflows are hidden from normal users unless enabled by a developer/pro mode.
