# Voyage AI Production Parity Roadmap

Last verified: 2026-05-19. Companion gap analysis: [voyage-ai.md](voyage-ai.md).

## Product Goal

Make Voyage AI the retrieval-specialist provider in Pines. The goal is not chat parity; it is best-in-class Vault search and RAG through embeddings, reranking, contextualized chunk embeddings, multimodal embeddings, batching, and token-aware indexing.

## Viable And Relevant Scope

- Text embeddings with profile templates and dimensions.
- Rerankers for Vault search.
- Contextualized chunk embeddings for document-aware retrieval.
- Multimodal embeddings for image-heavy PDFs, slides, screenshots, and visual documents.
- Quantized output dtypes where they improve storage/performance.
- Tokenization/counting, truncation policy, batch inference, rate-limit-aware scheduling.
- Themed UI for retrieval profiles, reranking controls, token/truncation diagnostics, multimodal search results, indexing jobs, and quality/cost telemetry.

## Explicitly Out Of Scope

- Text chat/generation through Voyage, because Voyage is not a chat provider in Pines.
- Tool calling, agents, web search, realtime, generated media, or hosted file search.
- Replacing local Vault with a Voyage-hosted document store.
- Using domain-specific models automatically without user/profile selection.

## Required UI

All UI must follow the shared [cloud provider UI roadmap](ui-roadmap.md).

Provider-specific screens/components:

- Voyage retrieval profile setup with profile templates: general quality, fast, code, finance, law, multilingual, contextual, multimodal.
- Vault search tuning panel for rerank model, candidate count, top-k, timeout, fallback behavior, and cost warning.
- Retrieval diagnostics panel showing lexical score, embedding score, rerank score, model, dimensions, dtype, token counts, and truncation status.
- Contextual embedding setup showing document-grouped indexing and re-indexing requirements.
- Multimodal search result UI with page/image previews, visual hit metadata, and import/open actions.
- Embedding job monitor with queued/running/failed/completed states, rate-limit/backoff status, retry, and batch job import.
- Quantized dtype selector with storage/quality warning and index compatibility status.

UI production requirements:

- Voyage must appear as a retrieval provider, not a chat provider.
- Rerank failures must be visible but not block local fallback results.
- Multimodal results need visual previews, not only text snippets.

## Phase 1: Reranking

Goal: Improve Vault retrieval quality without replacing the existing embedding pipeline.

Todos:

- Add `VaultRerankerProfile` and provider-backed rerank service.
- Call Voyage `/rerank` after lexical/semantic candidate retrieval.
- Support `rerank-2.5` and `rerank-2.5-lite` profile defaults.
- Add candidate-count, top-k, timeout, and fallback settings.
- Store rerank scores and original scores for explainability.
- Add tests for rerank success, timeout fallback, rate limit, and empty candidates.
- Add Vault search tuning controls and rerank score diagnostics.

Possible hiccups:

- Rerank cost scales with number and length of candidates.
- Rerank latency may hurt quick search unless bounded.
- Query/document formatting affects quality.

Production complete when:

- Vault search can optionally rerank candidates with Voyage and still return local-only fallback results on failure.

## Phase 2: Profile Templates And Model Selection

Goal: Match Voyage models to user corpus types.

Todos:

- Add profile templates: general quality, general fast, code, finance, law, multilingual, contextual, multimodal.
- Store default dimensions, input types, supported dtypes, and max token hints.
- Expose profile choice during Vault embedding setup.
- Add migration path for existing `voyage-4-lite` profiles.
- Add retrieval profile setup UI with theme-backed template rows.

Possible hiccups:

- Domain-specific models may be overkill or wrong for mixed corpora.
- Model naming and recommended defaults may change.

Production complete when:

- Users can choose a Voyage retrieval profile that reflects corpus type and cost/quality target.

## Phase 3: Tokenization And Truncation Preflight

Goal: Prevent low-quality embeddings caused by accidental truncation.

Todos:

- Add Voyage token counting/tokenization support.
- Integrate counts into `VaultChunker` sizing and embedding batch construction.
- Add truncation policy: strict fail, warn and truncate, or provider-default.
- Surface skipped/truncated chunks in ingestion diagnostics.
- Add token/truncation diagnostics panel.

Possible hiccups:

- Tokenization libraries may need bundled runtime support or local implementation.
- Existing chunk sizes may need profile-specific retuning.

Production complete when:

- Pines can predict embedding/rerank token limits before submitting Voyage requests.

## Phase 4: Contextualized Chunk Embeddings

Goal: Improve retrieval for chunks that need parent-document context.

Todos:

- Add contextualized embedding profile type.
- Send document-grouped chunks to Voyage contextualized endpoint.
- Store parent document relationships and contextual embedding metadata.
- Adjust re-embedding jobs to batch by source document.
- Compare retrieval quality against normal embeddings.

Possible hiccups:

- Contextualized embeddings may be more expensive and slower.
- Document-level grouping conflicts with current flat embedding batch assumptions.
- Re-indexing existing Vaults may be required.

Production complete when:

- A Vault can opt into contextualized embeddings and retrieve ambiguous chunks more accurately.

## Phase 5: Multimodal Embeddings

Goal: Search visual documents, screenshots, slides, and image-heavy PDFs.

Todos:

- Add multimodal embedding profile and vector index compatibility flags.
- Generate page/image representations from PDFs/slides/screenshots.
- Send interleaved text/image inputs to Voyage multimodal embeddings.
- Store page/image-level search hits and previews.
- Add UI for visual search results.
- Add page/image preview result components.

Possible hiccups:

- Requires document rendering and image extraction pipeline.
- Multimodal vectors may not be comparable with existing text vectors.
- Storage footprint can grow quickly.

Production complete when:

- Users can search image-heavy documents and get page/image-level results with previews.

## Phase 6: Quantized Output Dtypes

Goal: Reduce bandwidth/storage while preserving search quality.

Todos:

- Add dtype support to `VaultEmbeddingProfile`.
- Request float, int8, uint8, binary, or ubinary where supported.
- Decide how provider quantization interacts with Pines TurboQuant.
- Benchmark recall, storage, and query latency.

Possible hiccups:

- Mixing dtypes in one vector index is unsafe.
- Provider quantization may not beat Pines local compression.

Production complete when:

- Quantized Voyage profiles are opt-in, benchmarked, and isolated by index/profile.

## Phase 7: Batch Inference And Rate Scheduling

Goal: Make large Vault ingestion robust.

Todos:

- Add Voyage batch job creation/status/result import for large embedding jobs.
- Add adaptive concurrency and backoff for online embedding/rerank calls.
- Let users configure known account tier limits.
- Add resumable ingestion state for partial batch failures.
- Add embedding job monitor with retry/backoff/batch import states.

Possible hiccups:

- Batch jobs are slower and require durable polling.
- Rate tiers can change by account.

Production complete when:

- Large Voyage-backed Vault ingestion can complete without manual retry loops or avoidable 429s.
