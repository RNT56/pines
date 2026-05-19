# Feature Additions

This document captures adjacent, high-value feature additions for Pines. The emphasis is on turning the current local model, vault, cloud provider, MCP, tool, sync, and audit foundations into durable user workflows.

## Recently Landed Foundation

- Shared provider lifecycle records and dashboards for OpenAI, Anthropic, and Gemini files, artifacts, caches/vector stores, batches, model capabilities, live sessions, and research runs.
- Provider-hosted storage managers for OpenAI Files/vector stores, Anthropic Files, and Gemini Files/context caches, with local Vault separation.
- Provider provenance in chat for citations, hosted tool events, file references, request/message IDs, cache metrics, thinking mode, and generated artifacts.
- Long-running provider job records for OpenAI/Gemini Deep Research, OpenAI/Anthropic/Gemini batches, OpenAI/Gemini realtime/live sessions, and generated media workflows.

## Priority Recommendations

### 1. Project Spaces

Group related chats, vault documents, default model/provider choices, MCP servers/tools, and privacy policy into named workspaces.

Why it matters:

- Pines already has chats, vault documents, providers, tools, MCP servers, sync, and audit records.
- Users need a product-level container for "this context belongs together."
- This makes Pines feel less like separate surfaces and more like an owned AI workbench.

Initial scope:

- Create, rename, archive, and delete spaces.
- Assign chats and vault documents to a space.
- Store per-space defaults for model/provider, execution mode, enabled tools, and vault sharing.
- Add a space switcher to Chats and Vault.
- Keep default behavior compatible with existing unscoped data.

### 2. First-Class Agent Mode

Expose the existing agent runtime as an intentional chat mode with clear controls and visible activity.

Why it matters:

- Pines already has agent policy models, tool invocation models, tool approvals, activity events, and audit persistence.
- The visible app should make tool-using runs legible instead of hiding them inside normal chat.
- This strengthens Pines' core promise: powerful tools with consent the user can see.

Initial scope:

- Add a Chat/Agent mode control in the composer.
- Show enabled tools before a run starts.
- Let users configure step limit, tool-call limit, wall-time limit, and allowed domains.
- Render live tool activity in the transcript.
- Preserve approval, denial, and audit events as first-class run history.

### 3. Grounded Vault Answers With Citations

When a response uses vault context, show source documents and retrieved chunks beside the answer.

Why it matters:

- Vault ingestion, chunking, embeddings, approximate vector search, and FTS fallback already exist.
- Trust depends on seeing where an answer came from.
- This makes private context visibly useful without weakening local-first boundaries.

Initial scope:

- Attach retrieval metadata to assistant messages.
- Show cited documents and chunk snippets under relevant answers.
- Link citations back to Vault detail.
- Distinguish semantic matches from text-search fallback.
- Add a "save cited context" or "open cited sources" action.

## Next High-Value Additions

### 4. Capture Pipeline

Make the Vault easy to fill from normal iOS workflows.

Initial scope:

- Add a Share Extension for Safari, Files, Photos, Mail, and Notes handoff.
- Support multi-file import.
- Add a lightweight Vault inbox for captured items before organization.
- Support web clipping through the existing fetch/browser safety model.
- Add basic tags or collections once Project Spaces exist.

### 5. Model Readiness Advisor

Turn model preflight, curated manifests, runtime diagnostics, memory class, and thermal profile into clear install/use guidance.

Initial scope:

- Recommend "best private chat," "best vision," "best compact," and "best quality" models for the current device.
- Explain unsupported and experimental states in user-facing language.
- Surface expected memory tier and local runtime capability before download.
- Add a one-tap smoke test for installed models.

### 6. Per-Chat Routing Presets

Provide named routing modes that map to provider, model, execution policy, web search, tools, and vault sharing.

Initial scope:

- Add presets such as Private, Fast, Deep, Vision, Research, and Cloud Required.
- Let users customize and save presets.
- Show clearly when a preset may send private context to cloud.
- Keep the router's "no silent cloud fallback" rule intact.

### 7. CloudKit Conflict And Sync Health Center

Expose encrypted sync state and repair paths.

Initial scope:

- Show last successful sync, pending records, failed records, and conflicts.
- Provide per-record conflict review for conversations and vault documents.
- Add retry and reset actions with explicit warnings.
- Keep API keys, model binaries, prompt caches, browser state, attachments, and transient tool state out of sync.

### 8. Reusable Instructions And Memory

Add visible, scoped instructions without hidden memory behavior.

Initial scope:

- Support app-level, space-level, and thread-level instructions.
- Show when instructions are active in a run.
- Require explicit approval before instructions or private memory are included in cloud requests.
- Let users disable or delete instructions at each scope.

### 9. Run Artifacts

Let users save outputs, tool results, and provider artifacts as durable Vault items.

Initial scope:

- Save an assistant answer, selected message range, tool result, browser observation, MCP resource preview, provider-generated file, media artifact, batch output, or research report into Vault.
- Preserve provenance back to the source thread and run.
- Make saved artifacts retrievable in future chats.
- Keep local artifact import separate from provider-side deletion.

### 10. Watch Capture

Use the Watch app for fast capture rather than full chat parity.

Initial scope:

- Capture voice or text into a selected space or Vault inbox.
- Handoff a captured note to the phone for ingestion and embedding.
- Show simple confirmation and sync state on Watch.

## Recommended Build Order

1. Project Spaces.
2. First-Class Agent Mode.
3. Grounded Vault Answers With Citations.
4. Capture Pipeline.
5. Model Readiness Advisor.

Project Spaces should come first because they provide the organizing layer for the rest of the product. Agent Mode then gives Pines a visible action surface inside that context. Grounded Vault Answers make private context trustworthy and inspectable. Capture Pipeline fills the Vault from real workflows. Model Readiness Advisor reduces setup friction once the workbench has a clearer shape.

## Product Guardrails

- Preserve local-first defaults.
- Never silently fall back to cloud.
- Make private-context disclosure visible per turn.
- Prefer user-visible consent and audit trails over hidden automation.
- Build on existing repository boundaries rather than creating parallel feature silos.
