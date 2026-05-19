# Anthropic Production Parity Roadmap

Last verified: 2026-05-19. Companion gap analysis: [anthropic.md](anthropic.md).

## Product Goal

Make Anthropic in Pines production-complete for Claude's relevant API strengths: high-quality reasoning, document work with citations, provider-hosted files, web search/fetch, code execution, remote MCP, batches, and safe tool use.

## Viable And Relevant Scope

- Messages API streaming, tool calls, thinking controls, and usage metadata.
- Files API for reusable provider-hosted documents/images and generated files.
- Citations for PDFs, text, and custom retrieval/search-result blocks.
- Correct prompt caching.
- Hosted tools: web search, web fetch, code execution, text editor, computer use, remote MCP.
- Token counting, batch jobs, fine-grained tool streaming, and tool-result reliability.
- Themed UI for prompt caching, Files API, citations, thinking controls, hosted tools, batches, and run provenance.

## Implementation Status

Updated 2026-05-19:

- Added shared Anthropic request options for prompt cache, thinking modes, citations, hosted tools, file IDs, batches, token count preflight, beta headers, and settings migration.
- Moved prompt caching to eligible Anthropic content blocks and added cache TTL/header handling, structured system blocks, provider file ID blocks, and citation-enabled document/text/file blocks.
- Added Anthropic Files, Message Batches, token counting, model capability refresh, retry/backoff, provider audit events, generated file download/import hooks, and generic provider record mapping.
- Extended stream parsing for request/message IDs, usage/cache metrics, signed thinking, provider citations, web-source mirroring, server tool use/results, hosted tool metadata, file references, artifacts, and streaming errors.
- Added Anthropic participation in the shared lifecycle dashboard, Settings capability rows, Vault provider storage refresh/delete, chat quick settings, file manager, batch refresh/cancel/import, chat provenance pills, and provider citation/source panel.
- Added core contract coverage for Anthropic options, legacy effort migration, hosted tool gating, provider citation metadata, cache metrics, signed thinking preservation, hosted tool parsing, and citation metadata.

## Explicitly Out Of Scope

- Anthropic organization/admin management.
- Treating Anthropic-hosted files as local Vault replacements.
- Exposing provider-hosted browser/computer use without a dedicated approval model.
- Displaying raw hidden thinking as normal assistant text.
- Anthropic-specific features that require enterprise contracts unless they can be detected and hidden safely.

## Required UI

All UI must follow the shared [cloud provider UI roadmap](ui-roadmap.md).

Provider-specific screens/components:

- Anthropic capability dashboard for Messages, Files API, citations, prompt caching, thinking, web search/fetch, code execution, remote MCP, batches, and token counting.
- Prompt cache settings showing cacheable blocks, TTL, cache read/write tokens, and cache status per run.
- Anthropic file manager for uploaded files and generated code-execution files.
- Citation/source panel for PDF/text/search-result citations with file/page/chunk labels.
- Thinking control segmented control: off, adaptive, budget/effort where supported, with cost/latency warning text.
- Hosted tool approval/timeline rows for web search, web fetch, code execution, text editor/bash, remote MCP, and computer use.
- Batch job list with queued/running/completed/failed states and result import actions.
- Anthropic run provenance sheet with request ID, message ID, model, thinking state, cache metrics, tool usage, and file references.

UI production requirements:

- Hidden thinking must not render as normal assistant text.
- Citations must be compact enough for chat but expandable into a source panel.
- Code execution files must show provider-hosted status until imported locally.

## Phase 1: Prompt Caching Correctness

Goal: Use Anthropic prompt caching exactly where it reduces cost/latency without malformed requests.

Todos:

- Audit current top-level `cache_control` usage against current Anthropic block-level requirements.
- Apply `cache_control` to eligible system, tool, and message content blocks.
- Support cache TTL options where available.
- Parse cache creation/read token usage.
- Add cache hit/miss telemetry in run details.
- Add tests for cached system prompt, cached tools, cached document context, and cache-disabled runs.
- Add UI showing cacheable blocks, TTL, and cache metrics in run details.

Possible hiccups:

- Minimum token thresholds and TTL availability vary by model/account.
- Misplaced cache controls can invalidate requests.

Production complete when:

- Cached Anthropic requests validate, save cost on repeated contexts, and report cache metrics.

## Phase 2: Files API

Goal: Support reusable Anthropic-hosted files with explicit user consent.

Todos:

- Add Anthropic file upload/list/get/delete/download.
- Support document/image blocks by `file_id`.
- Add file retention and provider-storage UI.
- Support generated-file retrieval from code execution.
- Add local-to-Anthropic upload flow from chat attachments and Vault documents.
- Add cleanup and orphan detection.
- Add Anthropic-hosted file manager and generated-file import/delete UI.

Possible hiccups:

- Files API requires beta headers and may have model/tool restrictions.
- Large uploads need retry/background behavior.

Production complete when:

- Users can upload/reuse/remove Anthropic-hosted files and Pines clearly labels them as provider-hosted.

## Phase 3: Citations And Source Grounding

Goal: Make Claude document answers auditable.

Todos:

- Enable citations on supported document/text blocks.
- Parse citation blocks into provider metadata and visible source chips.
- Map local Vault chunks to Anthropic custom content or search-result blocks when cloud context is approved.
- Add source highlighting where local document offsets are available.
- Add tests for PDF, plain text, search-result citations, and citation-free fallback.
- Add source chip and citation detail panel UI.

Possible hiccups:

- Citation offsets may not map cleanly back to local extracted text.
- Cloud-hosted files and inline files need different source IDs.

Production complete when:

- A Claude answer over documents can show which file/chunk/page supported each claim where provider citations are available.

## Phase 4: Thinking Controls

Goal: Let users tune Claude reasoning without exposing unsafe/raw internals.

Todos:

- Add explicit thinking modes: off, adaptive, budgeted, and effort where supported.
- Store and replay signed thinking blocks for tool-result continuity.
- Optionally show provider-approved summaries only.
- Add per-model eligibility rules based on model metadata or tested behavior.
- Add cost/latency warnings for high thinking settings.

Possible hiccups:

- Thinking signatures must be preserved exactly across turns.
- Budget/effort parameter combinations vary by model generation.

Production complete when:

- Long tool-using Claude conversations retain thinking continuity and expose only safe summaries.

## Phase 5: Hosted Tools

Goal: Add Claude hosted tools that are valuable in Pines workflows.

Todos:

- Web fetch: allow approved URL fetches and parse source metadata.
- Code execution: enable tool, parse server tool use/results, retrieve generated files.
- Text editor/bash: expose only in agent/coding workflows with explicit environment labels.
- Remote MCP: store server URL/auth/allowlist and map approvals.
- Computer use: add screenshot/action loop only after dedicated safety UX exists.
- Fine-grained tool streaming: parse partial tool args and update approval UI.
- Add hosted tool approval sheets and timeline rows.

Possible hiccups:

- Hosted tool result block shapes differ from local function tools.
- Provider tools may execute outside the user's device, which must be obvious.
- Computer use requires a separate policy level.

Production complete when:

- Each enabled Anthropic hosted tool has parser coverage, audit logging, consent, settings, and clear UI labeling.

## Phase 6: Batches And Token Counting

Goal: Support reliable large-scale Anthropic work without foreground chat hacks.

Todos:

- Add token counting to cloud preflight and Vault context packing.
- Add Message Batches job creation/status/cancel/result import.
- Add batch use cases: summarization, extraction, classification, document tagging.
- Add backoff and retry for rate limits.

Possible hiccups:

- Batch result ordering and partial failures require durable job state.
- Token counts may differ from final billed usage if tools/files are involved.

Production complete when:

- Large Anthropic jobs can run asynchronously and import results safely.
