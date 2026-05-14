import Foundation
import PinesCore

#if canImport(MLXLLM)
import MLXLLM
#endif
#if canImport(MLXVLM)
import MLXVLM
#endif
#if canImport(MLXEmbedders)
import MLXEmbedders
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(MLXHuggingFace)
import MLXHuggingFace
#endif

struct MLXRuntimeBridge {
    var isLinked: Bool {
        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXEmbedders)
        true
        #else
        false
        #endif
    }

    var localProviderID: ProviderID { "mlx-local" }

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            local: true,
            streaming: true,
            textGeneration: true,
            vision: true,
            embeddings: true,
            toolCalling: true,
            jsonMode: true,
            maxContextTokens: 8192
        )
    }

    func defaultRuntimeProfile(for install: ModelInstall) -> RuntimeProfile {
        let hasVision = install.modalities.contains(.vision)
        return RuntimeProfile(
            name: hasVision ? "Vision balanced" : "Local balanced",
            quantization: QuantizationProfile(
                weightBits: install.repository.localizedCaseInsensitiveContains("4bit") ? 4 : nil,
                kvBits: 8,
                kvGroupSize: 64,
                quantizedKVStart: 256,
                maxKVSize: hasVision ? 4096 : 8192
            ),
            prefillStepSize: hasVision ? 256 : 512,
            promptCacheEnabled: !hasVision,
            speculativeDraftModelID: nil,
            unloadOnMemoryPressure: true
        )
    }
}

struct LocalRuntimeStatus: Hashable {
    var mlxLinked: Bool
    var installedModels: Int
    var activeModelName: String?
    var memoryTier: DeviceMemoryTier

    static let preview = LocalRuntimeStatus(
        mlxLinked: false,
        installedModels: CuratedModelManifest.default.entries.count,
        activeModelName: "Llama 3.2 1B 4-bit",
        memoryTier: .balanced
    )
}
