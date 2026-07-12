# Cloud Provider Feature Review

Last full cross-provider review: 2026-05-19. OpenRouter implementation and documentation refreshed: 2026-07-12.

This folder tracks the current cloud-provider surface in Pines, the remaining feature gaps, and the production parity roadmaps. It is intentionally scoped to the provider kinds currently present in `CloudProviderKind`: OpenAI/OpenAI-compatible, Anthropic, Gemini, OpenRouter, and Voyage AI.

Current Pines cloud surface, based on `Pines/Cloud/BYOKCloudInferenceProvider.swift`, `Pines/Cloud/BYOKCloudInferenceProvider+Payloads.swift`, `Sources/PinesCore/Cloud/CloudProvider.swift`, and `Sources/PinesCore/Inference/InferenceTypes.swift`:

- Streaming text chat through OpenAI-compatible Chat Completions, OpenAI Responses for official OpenAI reasoning/web-search/attachment paths, Anthropic Messages, Gemini Generate Content, and Gemini Interactions.
- BYOK credentials with provider-specific model listing and validation.
- Function tool calling across OpenAI-compatible, Anthropic, Gemini, and OpenRouter routes.
- Native web search for official OpenAI, Anthropic, and Gemini, plus OpenRouter-specific PDF inputs.
- Image, PDF, and text-document inputs on selected providers, with inline size limits.
- Shared provider lifecycle records and UI previews for provider-hosted files, artifacts, caches/vector stores, batches, model capabilities, live sessions, and research runs.
- Provider storage workflows for OpenAI Files/vector stores, Anthropic Files, and Gemini Files/context caches, with explicit local Vault separation.
- Batch and long-running job records for OpenAI, Anthropic, and Gemini, including refresh/cancel/import flows where the provider supports them.
- Provider artifact workflows for OpenAI media/audio/transcript outputs, Anthropic generated-file downloads, and Gemini generated media.
- Chat provenance for request IDs, provider IDs, usage/cache metrics, citations, hosted tool events, file references, and selected provider-side state.
- Provider-backed vault embeddings for OpenAI-compatible, Gemini, OpenRouter, Voyage AI, and custom providers.
- Provider-specific reasoning controls for OpenAI, Anthropic, and Gemini where model eligibility is recognized.
- Persisted OpenRouter routing/privacy controls for provider order, allow/deny lists, route sorting, fallback, supported-parameter enforcement, data collection, and zero-data-retention eligibility, plus Chat Completions structured-output mapping.

Provider documents:

- [OpenAI status and gaps](openai.md)
- [OpenAI production parity roadmap](openai-roadmap.md)
- [OpenAI-compatible/custom endpoint gaps](openai-compatible.md)
- [OpenAI-compatible/custom endpoint production parity roadmap](openai-compatible-roadmap.md)
- [Anthropic status and gaps](anthropic.md)
- [Anthropic production parity roadmap](anthropic-roadmap.md)
- [Gemini status and gaps](gemini.md)
- [Gemini production parity roadmap](gemini-roadmap.md)
- [OpenRouter gaps](openrouter.md)
- [OpenRouter production parity roadmap](openrouter-roadmap.md)
- [Voyage AI gaps](voyage-ai.md)
- [Voyage AI production parity roadmap](voyage-ai-roadmap.md)
- [Shared cloud provider UI roadmap](ui-roadmap.md)
- [Cross-provider comparison](comparison.md)

Review order for remaining product work:

1. OpenAI: highest impact for default-Responses routing, structured outputs, hosted tool policy, and production hardening of files/vector stores, media, realtime, batches, and Deep Research.
2. Anthropic: high impact for hosted-tool approval depth, source highlighting, generated-file workflows, and production hardening around Files, citations, prompt caching, batches, and token counting.
3. Gemini: high impact for audio/video attachment depth, structured outputs, source attribution UI, Live API hardening, generated media workflows, context caches, batches, and Deep Research.
4. OpenRouter: high impact for provider routing, server tools, structured outputs, usage accounting, and model metadata.
5. Voyage AI: high impact for retrieval quality through reranking, contextualized embeddings, multimodal embeddings, and quantized embeddings.

Source set used:

- OpenAI official API docs: latest model, Responses, tools, images/vision, realtime/audio, data residency, and API reference pages.
- Anthropic/Claude official docs: features overview, Messages API, Files API, prompt caching, citations, extended/adaptive thinking, web search, MCP connector, text editor, and code execution pages.
- Google AI Gemini official docs: models, Generate Content, Files API, structured outputs, function calling, code execution, Live API, pricing/model capability pages.
- OpenRouter official docs: API reference, parameters, structured outputs, server tools, web search, plugins, provider routing, usage accounting, prompt caching, models, multimodal, embeddings.
- Voyage AI official docs: text embeddings, multimodal embeddings, contextualized chunk embeddings, rerankers, tokenization, batch inference, rate limits, and pricing.
