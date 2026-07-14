# Cloud Provider UI Roadmap

Last verified: 2026-07-15.

This document defines the shared UI work required by the provider parity roadmaps. Every new provider feature must follow the Pines design system in [DESIGN_SYSTEM.md](../DESIGN_SYSTEM.md): no feature-local palettes, no hard-coded light/dark colors, dense operational layouts, shared list/panel/card primitives, semantic colors, and theme support through `\.pinesTheme`.

## Product Goal

Add advanced cloud-provider capabilities without turning Pines into a dashboard clone. The UI should make provider power visible, controllable, and auditable while preserving the local-first mental model: local by default, explicit cloud context, clear storage boundaries, and readable run provenance.

## Implementation Status

Updated 2026-07-15:

- Pines has shared provider lifecycle records and previews for files, artifacts, caches/vector stores, batches, research runs, live sessions, and model capabilities.
- The Artifacts tab now presents a quiet, searchable output library. Images/video can use an adaptive media grid; other outputs use readable rows; active media/research work stays in a compact Activity section; creation, research, and artifact detail use typed navigation destinations.
- Vault/provider storage views show OpenAI, Anthropic, and Gemini provider-hosted files separately from local Vault items, with refresh/delete/export/import paths where supported.
- Anthropic now has Settings capability rows, prompt/thinking quick settings, file management, batch create/count/refresh/cancel/import flows, citations/source panels, hosted-tool timeline rows, and run provenance pills.
- Gemini now has file/media management, context cache management, generated media creation, Deep Research, realtime session records, batch rows, and capability previews.
- OpenAI now has file/vector-store management, artifact previews, batch rows, Deep Research, realtime session records, and media/audio artifact workflows.
- OpenAI, Anthropic, and Gemini file uploads now use a persisted transfer queue with real byte progress, retry/cancellation, relaunch recovery, retained staged sources, and provider-copy verification.
- Approval-gated hosted tools now pause before the provider request and disclose environment, data egress, side effects, network destinations, and retention before one-time approval or denial; decisions are audited.
- Remaining UI work includes richer realtime controls, source highlighting, broader compact-width fixture coverage, richer per-resource retention/billing detail, and dedicated computer-use action review.

## Design Principles

- Dense, scannable, professional surfaces instead of marketing-style pages.
- Provider capabilities are shown as operational controls, not promotional feature cards.
- Every cloud feature that stores data, executes code, uses tools, fetches web content, or generates media needs visible state and auditability.
- Use semantic status colors: success for ready/complete, warning for cost/storage/provider persistence, danger for destructive/delete/unsafe actions, info for capability notes.
- Reuse `PinesSidebarRow`, shared grouped-list chrome, `PinesEmptyState`, `pinesPanel`, metric pills, semantic rows, and existing haptics/motion patterns.
- Cards stay at the shared radius and are used for repeated items, not nested layout shells.
- New controls must work across Evergreen, Graphite, Aurora, Paper, Slate, Porcelain, Sunset, and Obsidian in light/dark/system modes.

## Shared Screens And Components

### 1. Provider Capability Dashboard

Purpose: Show what a configured provider can do and which features are enabled.

Components:

- Capability grid with compact rows: Chat, Responses, Tools, Search, Files, Structured Output, Embeddings, Rerank, Media, Realtime, Batch.
- Status chips: Supported, Enabled, Needs validation, Unavailable, Unknown, Account gated.
- "Last tested" timestamp and validation summary.
- Action buttons: Validate, Test features, Edit credentials, Advanced settings.

Production requirements:

- Capabilities must be derived from provider config plus validation/probing results.
- Unknown capability must not look like supported capability.
- Settings rows must fit on compact iPhone widths.

### 2. Advanced Provider Settings

Purpose: Keep common settings simple while allowing expert control.

Components:

- Sectioned settings list using Pines grouped-list styling.
- Toggles for hosted tools, files, caching, media, and batch.
- Segmented controls for route mode, storage mode, reasoning mode, schema mode, search mode, and provider routing mode.
- Steppers/sliders/text fields for token limits, rerank candidate counts, cache TTL, max tool calls, max price, and concurrency.
- Disclosure groups for expert JSON/additional params.

Production requirements:

- Advanced destructive or privacy-relevant toggles require explanatory inline status text.
- Expert JSON must validate before save and redacts secret-like keys in diagnostics.
- All controls must use theme colors and shared typography.

### 3. Cloud Files And Provider Storage

Purpose: Manage provider-hosted files separately from local Vault.

Components:

- Provider file list with filename, type, size, created date, provider, retention label, and linked chats/stores.
- Upload/import actions from Files, chat attachments, and Vault documents.
- Delete confirmation sheet with provider-specific retention wording.
- Storage badges: Local only, Inline this turn, Provider-hosted, Vector store, Cached context.
- Empty state explaining that provider-hosted files are optional.

Production requirements:

- Provider-hosted files must never appear indistinguishable from local Vault records.
- Deleting local Vault content must not imply deleting provider-hosted copies, and vice versa.
- Long uploads have progress, retry, cancellation, and durable relaunch state. Pines does not claim that an in-flight foreground URL-session upload continues indefinitely after iOS suspends the app.

### 4. Tool Approval And Hosted Tool Timeline

Purpose: Make hosted tools understandable and safe.

Components:

- Tool call timeline with icon, provider, tool type, status, inputs summary, outputs summary, cost/usage where available.
- Approval sheets for code execution, remote MCP, computer use, web fetch, provider-hosted file access, and generated media.
- Environment labels: Local device, OpenAI hosted, Anthropic hosted, Gemini hosted, OpenRouter routed.
- Source/citation chips for search/fetch/file results.

Production requirements:

- Hosted tool calls must be visually distinct from Pines-local tools.
- Approval sheets must show data leaving Pines and expected side effects.
- Tool outputs that produce files/media must land in an artifact surface, not raw JSON.

### 5. Structured Output Builder

Purpose: Let product features request typed output without prompt-only JSON.

Components:

- Schema selection row: Text, JSON object, JSON schema.
- Schema preview/editor for developer/pro mode.
- Validation result panel with parsed object, raw output, errors, and retry options.
- Reusable schema templates for extraction tasks.

Production requirements:

- Normal users should not have to edit JSON schema for common flows.
- Validation errors must be actionable and not dump unreadable provider payloads.

### 6. Usage, Cost, And Provenance Panel

Purpose: Show what happened on every cloud run.

Components:

- Run detail sheet with provider, model, route, request ID, response ID, routed upstream provider, service tier, start/end time.
- Token metrics: input, output, reasoning, cached, cache write/read, image/audio/video units where available.
- Cost rows where provider exposes cost.
- Hosted tool usage summary.
- Privacy/storage summary: inline, provider-hosted files, cached context, provider-side state.

Production requirements:

- Metrics must degrade gracefully when a provider does not return a field.
- Cost values must show "estimated" versus "reported" where applicable.

### 7. Artifact Library

Purpose: Handle generated or provider-returned files/media.

Current implementation: a searchable, filterable library for image, video, audio, and research-report outputs; a compact Activity section; adaptive list/media layouts; full artifact detail; Vault import; original-provider links; image remix; and local-record removal. Creation metadata is retained across provider job refreshes so prompts produce readable library titles instead of opaque filenames.

Components:

- Artifact list grouped by conversation/provider/type.
- Viewers for image, video, audio, text, CSV/JSON, charts, and code outputs.
- Actions: attach to chat, import to Vault, export/share, delete local copy, delete provider copy where applicable.
- Provenance badges and provider metadata.

Production requirements:

- Generated media must not be trapped in a chat bubble.
- Artifact deletion must respect local/provider separation.

### 8. Realtime Session UI

Purpose: Support OpenAI/Gemini live audio/video without overloading chat.

Components:

- Dedicated voice/live mode with connection status, waveform/transcript, interruption control, mute/camera controls, tool approval overlay, and session summary.
- Transcript persistence into chat or separate session record.
- Session diagnostics: latency, model, transport, reconnect count, tool calls.

Production requirements:

- Realtime mode must not share assumptions with SSE chat streaming.
- Accessibility: captions/transcripts, explicit mute state, and clear recording indicators.

### 9. Deep Research Workspace

Purpose: Support long-running provider research agents without hiding minutes-long work inside normal chat.

Current implementation: a dedicated, conversation-first research destination with an explicit web-only default, opt-in provider files, optional prompt clarification, persisted run history, follow-up continuity, compact activity/source disclosure, cancellation/refresh, and direct navigation into the completed report.

Components:

- Research prompt and scope form with source policy, domain filters, provider-hosted file choices, and report format.
- Job status header: queued, planning, searching, reading, synthesizing, completed, failed, cancelled.
- Progress timeline with thought summaries/progress updates where providers expose them.
- Source/citation review panel with web, URL, file, and Vault-export provenance.
- Resume/reconnect controls for background or interrupted streams.
- Final report viewer with actions: attach to chat, save to Vault, export/share, create follow-up.
- Cost/time warning and provider-storage disclosure.

Production requirements:

- Deep research must use a job-oriented surface, not a chat typing indicator.
- Background/store requirements must be explicit before starting.
- Follow-up questions should preserve the provider interaction/response ID while making provider-side state visible.

## Theme And Component Todos

- Add missing reusable components to `PinesDesignComponents.swift` before implementing provider-specific views:
  - `PinesCapabilityRow`
  - `PinesStatusChip`
  - `PinesMetricPillGroup`
  - `PinesProviderStorageBadge`
  - `PinesToolTimelineRow`
  - `PinesRunProvenancePanel`
- `PinesArtifactRow`
- `PinesResearchJobRow`
- `PinesResearchSourcePanel`
- Add no new palette tokens unless the existing semantic colors cannot express a provider state.
- Verify each new screen under all theme templates and light/dark/system modes.
- Add compact-width previews for provider settings, file lists, tool approvals, and artifact rows.

## UI Acceptance Checklist

- Every provider feature has a visible settings/control surface.
- Every provider-hosted storage feature has a management surface and deletion path.
- Every hosted tool has an approval surface, timeline row, and audit metadata.
- Every generated artifact can be viewed, reused, imported, and deleted.
- Every run can show provenance, request IDs, token/cost metrics, and cloud storage state.
- No screen hard-codes colors, spacing, radii, shadows, or materials.
- No text overlaps or truncates badly on compact iPhone widths.
- Reduce Motion is respected for progress/timeline animations.
