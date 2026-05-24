# Pines iOS MLX Model Notes

Checked on 2026-05-24 against the Pines codebase, the pinned Schtack/RNT56 MLX forks, and current Hugging Face Hub metadata.

This document is intentionally conservative. A Hugging Face model being tagged `mlx` is not enough for Pines. The local iOS runtime needs:

- MLX-loadable `*.safetensors` weights.
- `tokenizer.json`.
- `config.json` with a `model_type` registered by the pinned `MLXSwiftLM` runtime or by Pines' app-level aliases.
- For vision models, a processor config with a processor class registered by `MLXVLM`.
- A size that fits the target iOS memory tier after weights, KV cache, processor tensors, prompt context, and thermal pressure are considered.

Pinned runtime:

- `MLXSwift`: `https://github.com/RNT56/mlx-swift` at `a68f3b1a4aab22d518bbd652b452ca632317b9a6`
- `MLXSwiftLM`: `https://github.com/RNT56/mlx-swift-lm` at `cad1cf9bceb01ae298453ef42bb4a6cef97ddefd`

Pines status terms:

- `verified`: present in `CuratedModelManifest` or matched by `VerifiedModelFamilyManifest`; Pines enables TurboQuant only when the install metadata reports full attention-KV or Hybrid Full support.
- `installable`: passes the metadata/file/runtime-shape gate, but should be smoke-tested on device before curation.
- `experimental`: recognized but gated, usually because exact-device verification is still required.
- `avoid`: not suitable for the current Pines iOS inference engine.

## General Runnable Recommendations

These are the broad text, vision, and embedding models that are most defensible for Pines today.

| Repository | Use | Model type | Size | Tier | Pines status | Notes |
| --- | --- | --- | ---: | --- | --- | --- |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | Small chat | `llama` | ~0.71 GB | compact | verified | Current safest first-launch local chat model. |
| `mlx-community/Qwen3-4B-4bit` | General chat/reasoning | `qwen3` | ~2.28 GB | compact/balanced | verified | Current curated stronger text lane. Use as the conservative quality default. |
| `mlx-community/Qwen2.5-VL-3B-Instruct-4bit` | Vision + text | `qwen2_5_vl` | ~3.09 GB | balanced/pro | verified | Current safest vision-instruction model; uses `Qwen2_5_VLProcessor`. |
| `mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ` | Vault embeddings | `qwen3` | ~0.35 GB | compact | verified | Current curated embedding model. |
| `mlx-community/Qwen3.5-0.8B-OptiQ-4bit` | Small chat | `qwen3_5` | ~0.67 GB | compact | verified | Family-verified when config metadata reports Qwen3.5 hybrid attention/native-state topology and 256-dim attention KV. |
| `mlx-community/Qwen3.5-2B-OptiQ-4bit` | Small reasoning/chat | `qwen3_5` | ~1.55 GB | compact | verified | Family-verified Hybrid Full candidate; still resource-gated per device. |
| `mlx-community/Qwen3.5-4B-OptiQ-4bit` | Balanced chat | `qwen3_5` | ~3.29 GB | balanced | verified | Family-verified Hybrid Full candidate for healthy-memory phones. |
| `mlx-community/gemma-4-e2b-it-OptiQ-4bit` | Gemma chat | `gemma4` | ~4.33 GB | pro | verified | Family-verified attention KV; Gemma license. |
| `mlx-community/gemma-4-e4b-it-OptiQ-4bit` | Larger Gemma chat | `gemma4` | ~6.57 GB | max | verified | Runtime-supported but high-memory iPad/future/max tier only. |
| `mlx-community/gemma-3-1b-it-qat-4bit` | Small Gemma chat | `gemma3_text` | ~0.77 GB | compact | verified | Family-verified compact instruction-tuned Gemma option. |
| `mlx-community/gemma-3n-E2B-it-lm-4bit` | Gemma 3n chat | `gemma3n` | ~2.55 GB | compact edge | verified | Shared/sliding attention KV is TurboQuant-covered; smoke-test under memory pressure. |
| `mlx-community/SmolLM3-3B-4bit` | Small chat | `smollm3` | ~1.75 GB | compact | installable | Supported by pinned registry; useful alternate small model. |
| `mlx-community/LFM2-1.2B-4bit` | Small text | `lfm2` | ~0.66 GB | compact | installable | Supported by pinned registry, but less proven in Pines than Qwen/Llama/Gemma. |
| `mlx-community/LFM2.5-VL-1.6B-4bit` | Small vision + text | `lfm2_vl` | ~1.50 GB | compact | installable | Uses `Lfm2VlProcessor`; promising small VLM, less proven than curated Qwen2.5-VL. |
| `mlx-community/FastVLM-0.5B-bf16` | Small vision + text | `llava_qwen2` | ~1.27 GB | compact | installable | Uses `FastVLMProcessor`; Apple license. |
| `lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit` | Vision + text | `qwen3_vl` | ~3.11 GB | balanced/pro | installable | Metadata matches pinned VLM registry and `Qwen3VLProcessor`, but it is outside `mlx-community` discovery defaults. |

## Instruction And Chat Models

These are the specific instruction/chat-tuned models from the research pass. Prefer the verified entries first. For installable entries, use a short on-device smoke test before making them curated.

| Repository | Instruction signal | Model type | Size | Tier | Pines status | Recommendation |
| --- | --- | --- | ---: | --- | --- | --- |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | Explicit `Instruct` | `llama` | ~0.71 GB | compact | verified | Keep as safest default instruction model. |
| `mlx-community/Qwen2.5-VL-3B-Instruct-4bit` | Explicit `Instruct`, VLM | `qwen2_5_vl` | ~3.09 GB | balanced/pro | verified | Keep as safest instruction VLM. |
| `mlx-community/Qwen3-4B-4bit` | Chat/conversational model card | `qwen3` | ~2.28 GB | compact/balanced | verified | Keep as curated stronger local chat lane. |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | Explicit `Instruct` | `llama` | ~1.82 GB | compact | verified | Family-verified stronger Llama instruction option. |
| `mlx-community/Qwen2.5-1.5B-Instruct-4bit` | Explicit `Instruct` | `qwen2` | ~0.88 GB | compact | installable | Good small Apache-2.0 instruction model. |
| `mlx-community/Phi-3.5-mini-instruct-4bit` | Explicit `instruct` | `phi3` | ~2.15 GB | compact | installable | Compact MIT-licensed instruction model. |
| `mlx-community/gemma-3-1b-it-qat-4bit` | Explicit `it` | `gemma3_text` | ~0.77 GB | compact | verified | Family-verified compact Gemma instruction model. |
| `mlx-community/gemma-3n-E2B-it-lm-4bit` | Explicit `it` | `gemma3n` | ~2.55 GB | compact edge | verified | Family-verified newer Gemma option; memory margin is thinner. |
| `mlx-community/gemma-4-e2b-it-OptiQ-4bit` | Explicit `it` | `gemma4` | ~4.33 GB | pro | verified | Family-verified Gemma instruction candidate for pro devices. |
| `mlx-community/gemma-4-e4b-it-OptiQ-4bit` | Explicit `it` | `gemma4` | ~6.57 GB | max | verified | Runtime-supported but only for high-memory iPad/future/max tier. |
| `mlx-community/Qwen3.5-0.8B-OptiQ-4bit` | Conversational/chat template | `qwen3_5` | ~0.67 GB | compact | verified | Family-verified tiny Qwen3.5 chat-style candidate. |
| `mlx-community/Qwen3.5-2B-OptiQ-4bit` | Conversational/chat template | `qwen3_5` | ~1.55 GB | compact | verified | Family-verified compact chat-style candidate. |
| `mlx-community/Qwen3.5-4B-OptiQ-4bit` | Conversational/chat template | `qwen3_5` | ~3.29 GB | balanced | verified | Family-verified balanced chat-style candidate. |
| `mlx-community/Qwen3-4B-Instruct-2507-mxfp4` | Explicit `Instruct` | `qwen3` | ~2.15 GB | compact | installable | Promising explicit Qwen3 instruction upgrade; smoke-test MXFP path first. |
| `mlx-community/Qwen3-4B-Instruct-2507-nvfp4` | Explicit `Instruct` | `qwen3` | ~2.28 GB | compact | installable | Same as above, NVFP variant; smoke-test first. |
| `mlx-community/Qwen3-4B-Instruct-2507-mxfp8` | Explicit `Instruct` | `qwen3` | ~4.16 GB | pro | installable | Larger quant variant; pro-only candidate. |

## Experimental Or Avoid

| Repository or family | Decision | Reason |
| --- | --- | --- |
| `mlx-community/Qwen3-1.7B-4bit` | experimental | Pines explicitly gates Qwen3 1.7B 4-bit variants until the fixed TurboQuant UInt32 seed path and on-device TurboQuant Metal self-test pass. |
| `mlx-community/bitnet-b1.58-2B-4T-4bit` | experimental | Curated but intentionally experimental; 1-bit/BitNet models require exact-device verification. |
| `mlx-community/Irodori-TTS-*` | avoid | `model_type=irodori_tts`; Pines does not link a local TTS runtime. |
| ASR models such as `mlx-community/MiMo-V2.5-ASR-MLX` | avoid | Current Pines local inference surface is LLM/VLM/embeddings, not speech recognition. |
| Huge GLM, DeepSeek, Qwen3-Coder, RAI, and 20B+ or 100B+ repos | avoid for iOS | Some architectures are registered, but the weights are far outside Pines' iOS memory tiers. |
| GGUF-only repos | avoid | Pines' MLX runtime path expects MLX safetensors, not GGUF. |

## Practical Promotion Order

1. Keep verified defaults: `Llama-3.2-1B-Instruct-4bit`, `Qwen3-4B-4bit`, `Qwen2.5-VL-3B-Instruct-4bit`, and `Qwen3-Embedding-0.6B-4bit-DWQ`.
2. Smoke-test compact instruction alternatives: `Qwen2.5-1.5B-Instruct-4bit`, `gemma-3-1b-it-qat-4bit`, and `Qwen3.5-2B-OptiQ-4bit`.
3. Smoke-test the explicit newer Qwen3 instruction variants: `Qwen3-4B-Instruct-2507-mxfp4` first, then `nvfp4`.
4. Only promote `gemma-4-e2b-it-OptiQ-4bit` or larger models after a pro-device memory and thermal pass.
5. Treat family-verified models as runtime-supported, not device-fit guaranteed; resource gates still block unsuitable downloads and on-device acceptance is still required before adding curated defaults.

## Source Links

- Hugging Face MLX Community: https://huggingface.co/mlx-community
- Qwen3.5 0.8B OptiQ: https://huggingface.co/mlx-community/Qwen3.5-0.8B-OptiQ-4bit
- Qwen3.5 2B OptiQ: https://huggingface.co/mlx-community/Qwen3.5-2B-OptiQ-4bit
- Gemma 4 E2B OptiQ: https://huggingface.co/mlx-community/gemma-4-e2b-it-OptiQ-4bit
- Gemma 4 E4B OptiQ: https://huggingface.co/mlx-community/gemma-4-e4b-it-OptiQ-4bit
- Qwen3 4B 4-bit: https://huggingface.co/mlx-community/Qwen3-4B-4bit
- Qwen3 Embedding 0.6B 4-bit DWQ: https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ
- Qwen2.5 VL 3B Instruct 4-bit: https://huggingface.co/mlx-community/Qwen2.5-VL-3B-Instruct-4bit
- Pinned MLX Swift LM compatibility docs: https://github.com/RNT56/mlx-swift-lm/blob/cad1cf9bceb01ae298453ef42bb4a6cef97ddefd/Libraries/MLXLMCommon/Documentation.docc/model-compatibility.md
