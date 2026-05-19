# Gemini Production Parity Roadmap

Last verified: 2026-05-19. Companion gap analysis: [gemini.md](gemini.md).

## Product Goal

Make Gemini in Pines production-complete for Google's strongest API capabilities: multimodal understanding, large media/file workflows, structured output, code execution, URL context, grounding, context caching, Live API, and generated media.

## Viable And Relevant Scope

- Generate Content and Interactions paths.
- Files API for large/reusable media and documents.
- Image, PDF, text, audio, and video input.
- Structured outputs, function calling, code execution, URL context, Google Search grounding.
- Gemini Deep Research Agent through Interactions/background mode.
- Context caching and token counting.
- Live API for realtime audio/video sessions.
- Image/video/speech generation where it fits Pines artifact workflows.
- Batch jobs and detailed usage/citation metadata.
- Themed UI for Files API/media inputs, structured outputs, tools, grounding, context caching, Live API, generated media, and model capabilities.

## Explicitly Out Of Scope

- Managing Google Cloud projects, billing, IAM, or Vertex AI-specific admin flows.
- Shipping every Google media model as a normal chat feature.
- Hidden uploads to Gemini Files API.
- Music generation unless Pines explicitly adds a creative media workspace.
- Provider-specific enterprise controls that cannot be discovered or safely hidden.

## Required UI

All UI must follow the shared [cloud provider UI roadmap](ui-roadmap.md).

Provider-specific screens/components:

- Gemini capability dashboard for Generate Content, Interactions, Files API, audio/video, structured output, code execution, URL context, Google Search grounding, context caching, Live API, generated media, batch, and token counting.
- Deep Research workspace with agent selector, background status, stream/reconnect state, thought-summary progress, source/citation review, File Search data-source controls, and final report actions.
- Gemini file/media manager with processing state, URI references, duration/size metadata, and provider-hosted retention labels.
- Media attachment controls for audio/video with duration, token estimate, and inline versus Files API choice.
- Structured output settings and validation panel.
- Grounding/source panel for Google Search and URL Context results, including rendered suggestions where required.
- Context cache manager showing cached content, TTL, token size, linked chats, and delete actions.
- Live API session UI with audio/video controls, transcript, interruption state, VAD status, and tool approval overlay.
- Generated media artifact gallery for images, video, and speech outputs.
- Gemini run provenance sheet with response ID/model version/request ID, grounding metadata, cache usage, media token metrics, and file references.

UI production requirements:

- Audio/video controls must show recording/upload state clearly.
- Google grounding attribution requirements must be represented in the source UI.
- Deep Research must show preview/limitations, background/store requirements, source policy, and max research-time expectations.
- Live API UI must be separate from normal SSE chat.

## Phase 1: Files API And Media Inputs

Goal: Support Gemini's large-file and multimodal strengths.

Todos:

- Add Gemini file upload/list/get/delete and file URI references.
- Use Files API automatically or by user choice for large PDFs, audio, video, and images.
- Extend cloud attachment mapping for audio and video.
- Add duration, size, and token preflight for media.
- Add file retention/provider-hosted storage UI.
- Add tests for inline small media, Files API large media, deleted file references, and unsupported MIME types.
- Add file/media manager and attachment controls with provider-hosted status.

Possible hiccups:

- Gemini file processing can be asynchronous.
- Audio/video token/cost estimation is less straightforward than text.
- Media support is model-specific.

Production complete when:

- Users can analyze audio/video/PDF/image files with Gemini without manual conversion, and Pines shows whether media is inline or provider-hosted.

## Phase 2: Structured Outputs

Goal: Make Gemini usable for typed extraction and local automation.

Todos:

- Map provider-neutral schema requests to Gemini structured output fields.
- Support `response_mime_type`, schema fields, enum/object/array shapes, and streaming final validation.
- Add fallback behavior for models that do not support schemas.
- Add tests for valid JSON, schema refusal, truncation, and structured output plus tools.

Possible hiccups:

- Schema support and allowed JSON schema subset can differ by model.
- Some built-in tool combinations may restrict structured output.

Production complete when:

- Gemini can produce validated typed outputs through the same Pines API as OpenAI/OpenRouter.

## Phase 3: Code Execution, URL Context, And Grounding

Goal: Expose Gemini tools that add real user value to research and analysis.

Todos:

- Add Gemini code execution tool config.
- Parse executable code, execution results, and generated images/charts.
- Add URL context tool with approval and citation/source parsing.
- Expand Google Search grounding metadata parsing: queries, grounding chunks, rendered suggestions, and citations.
- Add UI source chips common with OpenAI/Anthropic web results.
- Add code execution artifact rows and URL/grounding source detail panel.

Possible hiccups:

- Code execution outputs can include binary/media artifacts.
- Google Search grounding has required rendering/attribution details.

Production complete when:

- Gemini can search, fetch specific URLs, run code, and show reliable sources/artifacts in Pines.

## Phase 4: Context Caching And Token Counting

Goal: Reduce cost and prevent over-context failures.

Todos:

- Add token counting endpoint usage before large requests.
- Add context cache create/list/delete and TTL handling.
- Use cached content for repeated system prompts, tools, and document/media context.
- Parse cache usage and expose cost savings where available.
- Integrate token counts with Vault context packing.
- Add context cache manager and token estimate UI.

Possible hiccups:

- Cache eligibility varies by model and minimum size.
- Cached content is provider-hosted and needs disclosure.

Production complete when:

- Large Gemini threads can reuse cached context with visible cache state and safe cleanup.

## Phase 5: Deep Research Agent

Goal: Make Gemini Deep Research a first-class long-running research workflow.

Todos:

- Add explicit Deep Research run type using `v1beta/interactions` with `agent`, `background=true`, optional `stream=true`, and `agent_config`.
- Persist `interaction_id`, `event_id`, status, final outputs, sources/citations, and previous interaction ID.
- Add poll/resume/cancel/retry behavior for long-running tasks and interrupted streams.
- Support thought-summary progress when enabled.
- Add File Search data-source selection for user-approved provider-hosted files/stores.
- Expose limitations in UI: preview, no Generate Content access, no custom function tools/MCP, no structured output/plan approval, store requirement, no audio input.
- Add follow-up interaction support via `previous_interaction_id`.
- Add tests for start, poll complete, failed, reconnect from last event, streamed progress, File Search config, and follow-up.

Possible hiccups:

- The agent is preview and Interactions schemas can change.
- Background/store requirements conflict with local-first defaults and need explicit user consent.
- File Search integration for own data is experimental.

Production complete when:

- A user can start, monitor, resume, follow up on, and save a Gemini Deep Research report with cited sources and clear provider-storage disclosure.

## Phase 6: Live API

Goal: Add Gemini realtime mode without destabilizing text chat.

Todos:

- Add separate Live session service for WebSocket/WebRTC style flows.
- Support ephemeral/session credentials where applicable.
- Add audio capture/playback, video frame input, interruption handling, transcripts, VAD, and session persistence.
- Add function tool gating in live sessions.
- Add reconnect/cancel/error handling.
- Add dedicated Live API session UI.

Possible hiccups:

- Live API is not SSE and needs different app architecture.
- Mobile audio session management is complex.
- Tool calls during live audio need user-understandable interruptions.

Production complete when:

- Gemini realtime sessions have dedicated UI, transcript persistence, and predictable cancellation/reconnect behavior.

## Phase 7: Generated Media

Goal: Support Gemini media generation where it fits Pines artifacts.

Todos:

- Add image generation/editing through Gemini/Imagen where available.
- Add video generation through Veo job lifecycle.
- Add speech generation/audio output.
- Store generated artifacts locally with provider metadata.
- Add cost, eligibility, safety, and retention disclosure.
- Add generated media artifact gallery and viewer controls.

Possible hiccups:

- Media generation APIs may be asynchronous and region/account gated.
- Generated media needs an artifact library, not only chat bubbles.

Production complete when:

- Users can generate and manage media artifacts without losing provenance, cost, or deletion controls.

## Phase 8: Batch And Model Metadata

Goal: Improve large-job reliability and model selection.

Todos:

- Add Batch API for bulk document/media work.
- Cache model capabilities: modalities, tools, context, output types, structured output support.
- Replace model-name heuristics with metadata where available.

Possible hiccups:

- Model metadata may not expose every tool combination.
- Batch outputs require durable import and partial failure handling.

Production complete when:

- Gemini model selection is capability-driven and bulk jobs are durable.
