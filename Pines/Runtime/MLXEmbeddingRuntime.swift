import Foundation
import PinesCore

#if canImport(MLX) && canImport(MLXEmbedders) && canImport(MLXHuggingFace) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
import HuggingFace
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

actor MLXEmbeddingRuntime {
    private var container: EmbedderModelContainer?
    private var modelID: ModelID?

    func unload() {
        container = nil
        modelID = nil
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        if container == nil || modelID != request.modelID {
            container = try await EmbedderModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: MLXLMCommon.ModelConfiguration(id: request.modelID.rawValue)
            )
            modelID = request.modelID
        }

        guard let container else {
            throw InferenceError.modelNotLoaded(request.modelID)
        }

        let normalize = request.normalize
        let vectors = await container.perform { context in
            let tokenizer = context.tokenizer
            let inputs = request.inputs.map {
                tokenizer.encode(text: $0, addSpecialTokens: true)
            }
            let maxLength = inputs.reduce(into: 16) { length, tokens in
                length = max(length, tokens.count)
            }
            let padded = stacked(
                inputs.map { tokens in
                    MLXArray(tokens + Array(repeating: tokenizer.eosTokenId ?? 0, count: maxLength - tokens.count))
                }
            )
            let mask = (padded .!= tokenizer.eosTokenId ?? 0)
            let tokenTypes = MLXArray.zeros(like: padded)
            let result = context.pooling(
                context.model(padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask),
                normalize: normalize,
                applyLayerNorm: true
            )
            result.eval()
            return result.map { $0.asArray(Float.self) }
        }

        return EmbeddingResult(modelID: request.modelID, vectors: vectors)
    }
}
#endif
