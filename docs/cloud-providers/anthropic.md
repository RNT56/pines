# Anthropic Provider Status And Gaps

Last verified: 2026-05-19.

Primary sources:

- [Anthropic features overview](https://docs.anthropic.com/en/docs/build-with-claude)
- [Messages examples](https://docs.anthropic.com/en/api/messages-examples)
- [Extended thinking](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking)
- [Prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- [Citations](https://docs.anthropic.com/en/docs/build-with-claude/citations)
- [Files API](https://docs.anthropic.com/en/docs/build-with-claude/files)
- [Web search tool](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/web-search-tool)
- [MCP connector](https://docs.anthropic.com/en/docs/agents-and-tools/mcp-connector)
- [Code execution tool](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/code-execution-tool)
- [Text editor tool](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/text-editor-tool)

## What Pines Supports Today

- Anthropic Messages streaming with BYOK credentials, model listing from `/v1/models`, validation through `/v1/messages`, request/message ID capture, token usage metadata, and provider-specific beta headers.
- Image, PDF, and UTF-8 text-document inputs, plus Anthropic provider file ID references for documents, PDFs, images, and generated files when the user chooses provider-hosted storage.
- Block-level prompt caching on eligible system, tool, message, document, and file blocks, with 5-minute and 1-hour TTL support and cache read/write token metrics.
- Structured system content blocks when caching, citations, or per-block metadata are present.
- Claude thinking controls through `AnthropicThinkingOptions`: off, adaptive, budgeted token budgets, and effort-based mode where model eligibility allows it.
- Signed thinking preservation across turns for tool-result continuity. Raw hidden thinking is stored for replay/provenance only and is not rendered as assistant text.
- Function tool definitions and tool result handling, plus hosted tool configuration for Anthropic web search, web fetch, code execution, text editor/bash, remote MCP, and a surfaced but disabled computer-use capability.
- Native web search with domain filters and approximate location, and web-source mirroring into the existing chat citation chips.
- Provider citation parsing and normalized metadata for PDFs, text, custom/search-result sources, and web-search sources, including page/file/URL/title/chunk/offset/cited-text fields when available.
- Anthropic Files API lifecycle through shared provider records: list, upload multipart, retrieve metadata, download generated file content, delete, Vault-to-Files export, and generated-file import.
- Message Batches lifecycle: create from JSON, create from prompt/model input, refresh, cancel, retrieve results, import result artifacts, and status previews.
- Token counting for Anthropic chat/batch preflight where enabled.
- Stream parser coverage for cache usage fields, request/message IDs, signed thinking, citations, `server_tool_use`, hosted tool results, web fetch/search results, code execution outputs, generated files, and Anthropic error events.
- Settings capability rows, shared lifecycle dashboard previews, Anthropic file manager, batch creator, chat quick settings, provider citation panel, hosted-tool timeline rows, and run provenance metadata.

## Remaining High-Value Gaps

### 1. Hosted tool approval depth

Pines maps and records Anthropic hosted tools, but production approval UX still needs more detail for code execution, remote MCP, text editor/bash, and web fetch.

Needed work:

- Show exact provider-hosted environment labels before execution.
- Preview external data transfer, expected side effects, allowed domains, and generated-file retention.
- Add richer denial/retry paths and per-tool policy defaults.

### 2. Source highlighting and Vault citation alignment

Pines stores normalized provider citations and shows source panels, but offsets and pages are not yet fully mapped back into local document viewers.

Needed work:

- Highlight cited local text where Vault extraction offsets are reliable.
- Distinguish inline attachment, provider-hosted file, web result, and Vault-exported chunk sources.
- Improve fallback labels when Anthropic returns partial citation metadata.

### 3. Fine-grained tool streaming and parallel behavior controls

Pines covers hosted tool events and streaming errors, but Anthropic fine-grained tool streaming and detailed parallel-tool controls need deeper UI and parser coverage.

Needed work:

- Add beta/header and fixture coverage for partial tool parameter streaming.
- Revisit approval timing when arguments arrive incrementally.
- Expose parallel tool behavior only when the current agent/tool loop can handle it safely.

### 4. Computer use safety UX

Computer use remains intentionally disabled as a surfaced capability.

Needed work:

- Add screenshot/action review, explicit target environment labeling, pause/stop controls, and high-risk action approvals.
- Keep it out of normal chat until the safety model is designed and tested.

### 5. Structured outputs and custom RAG search-result blocks

Anthropic can support schema-like workflows through tools and guidance, and citations can use custom/search-result sources. Pines does not yet expose a provider-neutral structured-output request shape.

Needed work:

- Add shared schema requests that map cleanly across OpenAI, Anthropic, Gemini, OpenRouter, and compatible endpoints.
- Map Vault snippets into Anthropic search-result blocks only after user approval for cloud context.
- Validate final structured output separately from normal markdown streaming.

### 6. Production file-transfer hardening

Anthropic files are now represented as provider-hosted records, but upload/download operations still need production-grade progress and recovery.

Needed work:

- Durable progress, retry, cancellation, and background-safe transfer state.
- Orphan cleanup for generated files and failed imports.
- Clearer retention and billing labels in every file picker and provider storage row.

## Suggested Priority

1. Harden hosted tool approval sheets and generated-file import UX.
2. Add source highlighting and Vault citation alignment.
3. Add production transfer progress/retry/cancellation.
4. Complete fine-grained tool streaming and parallel tool controls.
5. Add provider-neutral structured outputs and custom RAG search-result blocks.
6. Revisit computer use only after a dedicated safety design is ready.

## Review Checklist

- Are Anthropic-hosted files clearly separate from Vault documents in every screen?
- Which hosted tools are safe in normal chat, and which must remain agent-only?
- Do citations make the source type and storage location obvious enough for user trust?
- Are thinking modes exposed without leaking raw hidden thinking?
- Does provider-hosted MCP need a separate consent model from Pines-local MCP?
