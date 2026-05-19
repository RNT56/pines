# Cloud Provider Feature Gap Review

Last verified: 2026-05-19.

This folder tracks cloud-provider API features that Pines does not fully expose today but that would add concrete user value if enabled. It is intentionally scoped to the provider kinds currently present in `CloudProviderKind`: OpenAI/OpenAI-compatible, Anthropic, Gemini, OpenRouter, and Voyage AI.

Current Pines cloud surface, based on `Pines/Cloud/BYOKCloudInferenceProvider.swift`, `Pines/Cloud/BYOKCloudInferenceProvider+Payloads.swift`, `Sources/PinesCore/Cloud/CloudProvider.swift`, and `Sources/PinesCore/Inference/InferenceTypes.swift`:

- Streaming text chat through OpenAI-compatible Chat Completions, OpenAI Responses for official OpenAI reasoning/web-search/attachment paths, Anthropic Messages, Gemini Generate Content, and Gemini Interactions.
- BYOK credentials with provider-specific model listing and validation.
- Function tool calling across OpenAI-compatible, Anthropic, Gemini, and OpenRouter routes.
- Native web search for official OpenAI, Anthropic, and Gemini, plus OpenRouter-specific PDF inputs.
- Image, PDF, and text-document inputs on selected providers, with inline size limits.
- Provider-backed vault embeddings for OpenAI-compatible, Gemini, OpenRouter, Voyage AI, and custom providers.
- Provider-specific reasoning controls for OpenAI, Anthropic, and Gemini where model eligibility is recognized.

Provider documents:

- [OpenAI gaps](openai.md)
- [OpenAI production parity roadmap](openai-roadmap.md)
- [OpenAI-compatible/custom endpoint gaps](openai-compatible.md)
- [OpenAI-compatible/custom endpoint production parity roadmap](openai-compatible-roadmap.md)
- [Anthropic gaps](anthropic.md)
- [Anthropic production parity roadmap](anthropic-roadmap.md)
- [Gemini gaps](gemini.md)
- [Gemini production parity roadmap](gemini-roadmap.md)
- [OpenRouter gaps](openrouter.md)
- [OpenRouter production parity roadmap](openrouter-roadmap.md)
- [Voyage AI gaps](voyage-ai.md)
- [Voyage AI production parity roadmap](voyage-ai-roadmap.md)
- [Shared cloud provider UI roadmap](ui-roadmap.md)
- [Cross-provider comparison](comparison.md)

Review order for a product pass:

1. OpenAI: highest impact because Pines already uses Responses, but only a subset of hosted tools and state controls.
2. Anthropic: high impact for code execution, Files API, citations, web fetch, and remote MCP.
3. Gemini: high impact for Files API, URL context, code execution, structured outputs, Live API, and generated media.
4. OpenRouter: high impact for provider routing, server tools, structured outputs, usage accounting, and model metadata.
5. Voyage AI: high impact for retrieval quality through reranking, contextualized embeddings, multimodal embeddings, and quantized embeddings.

Source set used:

- OpenAI official API docs: latest model, Responses, tools, images/vision, realtime/audio, data residency, and API reference pages.
- Anthropic/Claude official docs: features overview, Messages API, Files API, prompt caching, citations, extended/adaptive thinking, web search, MCP connector, text editor, and code execution pages.
- Google AI Gemini official docs: models, Generate Content, Files API, structured outputs, function calling, code execution, Live API, pricing/model capability pages.
- OpenRouter official docs: API reference, parameters, structured outputs, server tools, web search, plugins, provider routing, usage accounting, prompt caching, models, multimodal, embeddings.
- Voyage AI official docs: text embeddings, multimodal embeddings, contextualized chunk embeddings, rerankers, tokenization, batch inference, rate limits, and pricing.
