# Voyage AI Provider Gaps

Last verified: 2026-05-19.

Primary sources:

- [Voyage AI introduction](https://docs.voyageai.com/)
- [Text embeddings](https://docs.voyageai.com/docs/embeddings)
- [Multimodal embeddings](https://docs.voyageai.com/docs/multimodal-embeddings)
- [Contextualized chunk embeddings](https://docs.voyageai.com/docs/contextualized-chunk-embeddings)
- [Rerankers](https://docs.voyageai.com/docs/reranker)
- [Tokenization](https://docs.voyageai.com/docs/tokenization)
- [Batch inference](https://docs.voyageai.com/docs/batch-inference)
- [Rate limits](https://docs.voyageai.com/docs/rate-limits)
- [Pricing](https://docs.voyageai.com/docs/pricing)

## What Pines Supports Today

- Voyage AI as an embeddings-only provider.
- `/v1/embeddings` with `model`, text `input`, `input_type`, and `output_dimension`.
- Default profile uses `voyage-4-lite` at 1024 dimensions.
- Embedding normalization in Pines after provider response.
- No text generation, tool calling, image/document chat, or model listing for Voyage.

## High-Value Unsupported Or Partial Features

### 1. Rerankers

Pines does not call Voyage `/v1/rerank`.

Value:

- Stronger Vault search quality by reranking top lexical/semantic candidates.
- Better answers with fewer chunks sent to local or cloud models.
- Clear fit for RAG-heavy users because Voyage specializes in retrieval.

Implementation notes:

- Add optional rerank phase after initial semantic/BM25 candidate retrieval.
- Support `rerank-2.5` and `rerank-2.5-lite`.
- Respect max documents, context limits, and total token limits.
- Store rerank scores separately from embedding similarity scores for explainability.

### 2. Contextualized chunk embeddings

Pines chunks documents locally and embeds chunks independently. Voyage `contextualizedembeddings` can embed chunks with document-level context.

Value:

- Better chunk retrieval when local chunks are ambiguous without neighboring context.
- Better provenance and parent-document retrieval.

Implementation notes:

- Add a provider profile type for contextualized embeddings.
- Send chunks grouped by source document rather than as a flat list.
- Ensure re-embedding jobs can handle document-level group batching.

### 3. Multimodal embeddings

Pines text-extracts documents and embeds text. Voyage multimodal embeddings can represent interleaved text and visual content such as screenshots, figures, slides, tables, and document images.

Value:

- Better search over PDFs/slides/screenshots where visual layout matters.
- Less brittle ETL for image-heavy documents.

Implementation notes:

- Add image/document-page embedding inputs and storage for multimodal vector profiles.
- Keep multimodal vectors separate from text-only indexes unless model compatibility is guaranteed.
- Define UI for image/page-level search hits.

### 4. Output data types and quantized embeddings

Voyage supports `output_dtype` values such as float, int8/uint8, binary, and ubinary on supported endpoints. Pines only requests floats and then applies its own vector compression.

Value:

- Lower bandwidth, storage, and memory use for large Vaults.
- Potentially faster indexing and search.

Implementation notes:

- Evaluate provider quantization versus Pines TurboQuant vector codec.
- Store dtype and dimension in `VaultEmbeddingProfile`.
- Avoid mixing vector dtypes in one index.

### 5. Latest/domain-specialized model selection

Pines uses a single default Voyage embedding model. Voyage offers general, lite, code, finance, law, multimodal, and contextual models.

Value:

- Better retrieval for code, finance, legal, multilingual, and visual corpora.

Implementation notes:

- Add profile templates: general quality, general fast, code, finance, law, multimodal, contextual.
- Expose compatibility notes and default dimensions.

### 6. Tokenization and count-token preflight

Pines does not use Voyage tokenizers/counting before embedding/rerank calls.

Value:

- Better batch sizing, truncation warnings, and predictable failures.

Implementation notes:

- Add provider token counting where available or use the published tokenizers.
- Integrate with Vault chunker and embedding job batching.

### 7. Batch inference

Pines sends embedding batches directly and does not use Voyage batch jobs.

Value:

- Better throughput and cost/operational control for large Vault ingestion or re-indexing.

Implementation notes:

- Add async job creation, status polling, result import, and cancellation.
- Use only for large jobs where latency is not user-facing.

### 8. Truncation controls

Voyage endpoints expose truncation behavior. Pines does not provide user-visible control beyond chunking.

Value:

- Users can choose strict failure versus provider truncation for long documents.

Implementation notes:

- Default to pre-chunking and strict preflight for high-quality Vault indexing.
- Allow provider truncation only for low-stakes quick indexing.

### 9. Rate-limit aware scheduling

Pines does not use Voyage's published rate limit tiers to tune job concurrency.

Value:

- Faster ingestion without avoidable 429s.

Implementation notes:

- Add per-provider adaptive backoff and concurrency controls.
- Optionally let users set known account tier limits.

## Suggested Priority

1. Rerankers for Vault search.
2. Contextualized chunk embeddings.
3. Multimodal embeddings.
4. Token counting and batch sizing.
5. Domain-specific profile templates.
6. Quantized output dtypes.
7. Batch inference and rate-limit aware scheduling.

## Review Checklist

- Should reranking be automatic for Voyage profiles or an opt-in per Vault?
- Should contextualized embeddings replace normal chunk embeddings or sit beside them as a premium profile?
- Should image-heavy PDFs/slides get multimodal embeddings by default?
- Should Pines prefer provider quantized embeddings or keep TurboQuant as the compression layer?
- Which domain-specific Voyage profiles belong in first-run model/profile suggestions?
