import Foundation
import PinesCore

#if canImport(MLX) && canImport(MLXEmbedders)
import MLX
import MLXEmbedders

actor MLXEmbeddingRuntime {
    private var container: ModelContainer?
    private var modelID: ModelID?

    func unload() {
        container = nil
        modelID = nil
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        if container == nil || modelID != request.modelID {
            container = try await loadModelContainer(
                configuration: ModelConfiguration(id: request.modelID.rawValue)
            )
            modelID = request.modelID
        }

        guard let container else {
            throw InferenceError.modelNotLoaded(request.modelID)
        }

        let normalize = request.normalize
        let vectors = try container.perform { model, tokenizer, pooling in
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
            let result = pooling(
                model(padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask),
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
