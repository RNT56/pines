import Foundation
import XCTest
import MLX
import MLXLMCommon
#if canImport(MLXLLM)
import MLXLLM
#endif

final class MLXTurboQuantRuntimeSmokeTests: XCTestCase {
    func testLinkedMLXLLMRegistryAdvertisesProfileBackedTurboQuantFamilies() throws {
        #if canImport(MLXLLM)
        let expectedThrowingModelTypes = [
            "qwen3_5",
            "qwen3_5_text",
            "gemma3_text",
            "llama",
            "mistral3",
            "mistral4",
        ]
        for modelType in expectedThrowingModelTypes {
            XCTAssertTrue(
                MLXLLM.MLXTurboQuantRuntimeCapabilityRegistry.supportsThrowingTurboQuantAttention(modelType: modelType),
                "\(modelType) must be exported by the linked MLX-LM runtime registry before Pines may select TurboQuant by default."
            )
        }
        XCTAssertFalse(
            MLXLLM.MLXTurboQuantRuntimeCapabilityRegistry.supportsThrowingTurboQuantAttention(modelType: "gemma4_assistant")
        )
        XCTAssertFalse(
            MLXLLM.MLXTurboQuantRuntimeCapabilityRegistry.supportsThrowingTurboQuantAttention(modelType: "pixtral")
        )
        #else
        throw XCTSkip("MLXLLM is not linked in this test build.")
        #endif
    }

    func testFixedTurboQuantPinsExposeHighBitSeedPath() throws {
        let highBitSeed = UInt64(0xDEAD_BEEF_0000_0017)
        let configuration = MLX.TurboQuantConfiguration(
            preset: .turbo4v2,
            role: .key,
            groupSize: 64,
            backend: .metalPolarQJL,
            seed: highBitSeed
        )
        XCTAssertEqual(configuration.seed, highBitSeed)
        XCTAssertGreaterThan(configuration.seed, UInt64(UInt32.max))

        let parameters = MLXLMCommon.GenerateParameters(
            maxKVSize: 48,
            kvCacheStrategy: .turboQuant,
            turboQuantPreset: .turbo4v2,
            turboQuantBackend: .metalPolarQJL,
            turboQuantOptimizationPolicy: .conservative,
            turboQuantSeed: highBitSeed
        )

        XCTAssertEqual(parameters.kvCacheStrategy, .turboQuant)
        XCTAssertEqual(parameters.turboQuantPreset, .turbo4v2)
        XCTAssertEqual(parameters.turboQuantBackend, .metalPolarQJL)
        XCTAssertEqual(parameters.turboQuantOptimizationPolicy, .conservative)
        XCTAssertEqual(parameters.turboQuantSeed, highBitSeed)
        XCTAssertEqual(MLX.TurboQuantPreset.turbo4.effectiveBits, 4)
        XCTAssertEqual(MLX.TurboQuantPreset.turbo4v2.defaultValueBits, 4)
    }

    func testBundledTurboQuantProfileRegistryRecommendsCurrentGenerationPreset() throws {
        let profile = try XCTUnwrap(
            MLXLMCommon.TurboQuantProfileRegistry.bundled.profile(
                for: "mlx-community/Qwen3-4B-4bit",
                modelType: "qwen3",
                parameterCountB: 4,
                keyHeadDimension: 128,
                valueHeadDimension: 128,
                contextLength: 4096
            )
        )

        XCTAssertEqual(profile.recommendedScheme, .turbo4v2)
        XCTAssertEqual(profile.fallbackScheme, .turbo3_5)
        XCTAssertEqual(profile.recommendedScheme.preset, .turbo4v2)

        #if targetEnvironment(simulator)
        return
        #else
        let parameters = MLXLMCommon.GenerateParameters(
            turboQuantModelID: "mlx-community/Qwen3-4B-4bit",
            modelType: "qwen3",
            parameterCountB: 4,
            keyHeadDimension: 128,
            valueHeadDimension: 128,
            contextLength: 4096
        )
        XCTAssertEqual(parameters.kvCacheStrategy, .turboQuant)
        XCTAssertEqual(parameters.turboQuantPreset, .turbo4v2)
        XCTAssertEqual(parameters.turboQuantValueBits, 4)
        #endif
    }

    func testBundledTurboQuantProfileRegistryMatchesExpandedSmallModels() throws {
        let registry = MLXLMCommon.TurboQuantProfileRegistry.bundled

        let qwen06 = try XCTUnwrap(registry.profile(
            for: "mlx-community/Qwen3-0.6B-4bit",
            modelType: "qwen3",
            parameterCountB: 0.6,
            keyHeadDimension: 128,
            valueHeadDimension: 128
        ))
        XCTAssertEqual(qwen06.id, "qwen3-0.6b")

        let phi4Mini = try XCTUnwrap(registry.profile(
            for: "mlx-community/Phi-4-mini-instruct-4bit",
            modelType: "phi3",
            keyHeadDimension: 128,
            valueHeadDimension: 128
        ))
        XCTAssertEqual(phi4Mini.id, "phi-4-mini")

        let qwen25Coder = try XCTUnwrap(registry.profile(
            for: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            modelType: "qwen2",
            parameterCountB: 3,
            keyHeadDimension: 128,
            valueHeadDimension: 128
        ))
        XCTAssertEqual(qwen25Coder.id, "qwen2.5-small")

        let smolLM = try XCTUnwrap(registry.profile(
            for: "mlx-community/SmolLM2-135M-Instruct",
            modelType: "llama",
            parameterCountB: 0.135,
            keyHeadDimension: 64,
            valueHeadDimension: 64
        ))
        XCTAssertEqual(smolLM.id, "smollm-small")

        let llama32ThreeB = try XCTUnwrap(registry.profile(
            for: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            modelType: "llama",
            parameterCountB: 3,
            keyHeadDimension: 128,
            valueHeadDimension: 128,
            contextLength: 16_384
        ))
        XCTAssertEqual(llama32ThreeB.id, "llama-3.2-3b")
    }

    func testBundledTurboQuantProfileRegistryMatchesQwen35AndQwen36Families() throws {
        let registry = MLXLMCommon.TurboQuantProfileRegistry.bundled
        let cases: [(String, String, String, Double)] = [
            ("mlx-community/Qwen3.5-0.8B-MLX-4bit", "qwen3_5", "qwen3.5-0.8b", 0.8),
            ("mlx-community/Qwen3.5-2B-OptiQ-4bit", "qwen3_5", "qwen3.5-2b", 2),
            ("mlx-community/Qwen3.5-4B-MLX-4bit", "qwen3_5_text", "qwen3.5-4b", 4),
            ("mlx-community/Qwen3.6-27B-4bit", "qwen3_5", "qwen3.6-27b", 27),
            ("mlx-community/Qwen3.5-35B-A3B-4bit", "qwen3_5_moe", "qwen3.5-35b-a3b", 35),
            ("mlx-community/Qwen3.6-35B-A3B-4bit", "qwen3_5_moe_text", "qwen3.6-35b-a3b", 35),
        ]

        for (modelID, modelType, expectedProfileID, parameterCountB) in cases {
            let profile = try XCTUnwrap(registry.profile(
                for: modelID,
                modelType: modelType,
                parameterCountB: parameterCountB,
                keyHeadDimension: 256,
                valueHeadDimension: 256
            ))
            XCTAssertEqual(profile.id, expectedProfileID)
            if !expectedProfileID.contains("-a3b") {
                XCTAssertEqual(profile.recommendedScheme, .turbo8)
                XCTAssertEqual(profile.recommendedScheme.preset, .turbo8)
                XCTAssertEqual(profile.valueBits, 8)
                XCTAssertEqual(profile.optimizationPolicy, .conservative)
            }
        }

        let rejected = registry.selection(
            for: MLXLMCommon.TurboQuantModelDescriptor(
                modelID: "mlx-community/Qwen3.5-4B-MLX-4bit",
                modelType: "qwen3_5",
                parameterCountB: 4
            ),
            keyHeadDimension: 128,
            valueHeadDimension: 128
        )
        XCTAssertNil(rejected.profile)
        XCTAssertFalse(rejected.rejectionReasons.isEmpty)
    }

    func testBundledTurboQuantProfileRegistryMatchesExpandedGemmaFamilies() throws {
        let registry = MLXLMCommon.TurboQuantProfileRegistry.bundled

        let gemma3270m = try XCTUnwrap(registry.profile(
            for: "mlx-community/gemma-3-270m-it-qat-4bit",
            modelType: "gemma3_text",
            parameterCountB: 0.27,
            keyHeadDimension: 256,
            valueHeadDimension: 256
        ))
        XCTAssertEqual(gemma3270m.id, "gemma-3-270m")

        let gemma31b = try XCTUnwrap(registry.profile(
            for: "mlx-community/gemma-3-1b-it-4bit",
            modelType: "gemma3_text",
            parameterCountB: 1,
            keyHeadDimension: 256,
            valueHeadDimension: 256
        ))
        XCTAssertEqual(gemma31b.id, "gemma-3-1b")

        let gemma312b = try XCTUnwrap(registry.profile(
            for: "mlx-community/gemma-3-12b-it-qat-4bit",
            modelType: "gemma3",
            parameterCountB: 12,
            keyHeadDimension: 256,
            valueHeadDimension: 256
        ))
        XCTAssertEqual(gemma312b.id, "gemma-3-12b")

        let gemma3n = try XCTUnwrap(registry.profile(
            for: "mlx-community/gemma-3n-E4B-it-lm-4bit",
            modelType: "gemma3n",
            parameterCountB: 4,
            keyHeadDimension: 256,
            valueHeadDimension: 256
        ))
        XCTAssertEqual(gemma3n.id, "gemma-3n-e4b")

        let gemma4 = try XCTUnwrap(registry.profile(
            for: "mlx-community/gemma-4-31b-it-4bit",
            modelType: "gemma4",
            parameterCountB: 31,
            keyHeadDimension: 512,
            valueHeadDimension: 512
        ))
        XCTAssertEqual(gemma4.id, "gemma-4-31b")
    }

    func testBundledTurboQuantProfileRegistryFailsClosedForGemmaMetadataGaps() throws {
        let registry = MLXLMCommon.TurboQuantProfileRegistry.bundled

        XCTAssertNil(registry.profile(
            for: "mlx-community/gemma-3-12b-it-4bit",
            modelType: "gemma3",
            parameterCountB: 12
        ))
        XCTAssertNil(registry.profile(
            for: "mlx-community/gemma-3-12b-it-4bit",
            modelType: "gemma3",
            parameterCountB: 12,
            keyHeadDimension: 128,
            valueHeadDimension: 128
        ))
        XCTAssertNil(registry.profile(
            for: "mlx-community/embeddinggemma-300m-4bit",
            modelType: "gemma3_text",
            parameterCountB: 0.3,
            keyHeadDimension: 256,
            valueHeadDimension: 256
        ))
    }

    func testBundledTurboQuantProfileRegistryDoesNotMatchKnownVLMTextProfiles() throws {
        let registry = MLXLMCommon.TurboQuantProfileRegistry.bundled

        XCTAssertNil(registry.profile(
            for: "mlx-community/llava-llama-3-8b-v1_1-4bit",
            modality: .visionText,
            keyHeadDimension: 128,
            valueHeadDimension: 128
        ))
        XCTAssertNil(registry.profile(
            for: "mlx-community/Bunny-Llama-3-8B-V-4bit",
            modality: .visionText,
            keyHeadDimension: 128,
            valueHeadDimension: 128
        ))
        XCTAssertNil(registry.profile(
            for: "mlx-community/Llama-3.2-11B-Vision-Instruct-4bit",
            modelType: "mllama",
            modality: .visionText,
            keyHeadDimension: 128,
            valueHeadDimension: 128
        ))
    }

    func testTurboQuantCacheUsesFixedHighBitSeedOnDevice() throws {
        try skipSimulatorMLXRuntime("TurboQuant cache construction probes Metal and is device-only.")

        let highBitSeed = UInt64(0xDEAD_BEEF_0000_0017)
        let parameters = MLXLMCommon.GenerateParameters(
            maxKVSize: 48,
            kvCacheStrategy: .turboQuant,
            turboQuantPreset: .turbo2_5,
            turboQuantBackend: .metalPolarQJL,
            turboQuantOptimizationPolicy: .conservative,
            turboQuantSeed: highBitSeed
        )
        let cache = try XCTUnwrap(
            MLXLMCommon.makeAttentionKVCache(parameters: parameters, maxKVSize: 16, keep: 2)
                as? MLXLMCommon.RotatingTurboQuantKVCache
        )

        XCTAssertEqual(cache.preset, .turbo2_5)
        XCTAssertEqual(cache.requestedBackend, .metalPolarQJL)
        XCTAssertEqual(cache.optimizationPolicy, .conservative)
        XCTAssertEqual(cache.seed, highBitSeed)
        XCTAssertEqual(
            cache.diagnostics.selfTestStatus,
            MLX.TurboQuantKernelAvailability.current.selfTestStatus
        )
    }

    func testTurboQuantBackendAvailabilityContract() throws {
        try skipSimulatorMLXRuntime("TurboQuant availability probes Metal and is device-only.")

        let availability = MLX.TurboQuantKernelAvailability.current

        XCTAssertTrue(availability.supports(.mlxPacked))
        XCTAssertTrue(availability.supports(.polarQJLReference))

        let activeBackend = availability.runtimeBackend(for: .metalPolarQJL)
        XCTAssertTrue(activeBackend == .metalPolarQJL || activeBackend == .mlxPacked)
        if activeBackend == .metalPolarQJL {
            XCTAssertEqual(availability.selfTestStatus, .passed)
        } else {
            XCTAssertNotNil(availability.fallbackReason(for: .metalPolarQJL))
        }
    }

    func testHighBitSeedMetalCodecRoundTripWhenAvailable() throws {
        try skipSimulatorMLXRuntime("TurboQuant Metal codec probes Metal and is device-only.")

        guard MLX.TurboQuantKernelAvailability.current.supportsMetalPolarQJLCodec else {
            throw XCTSkip("TurboQuant Metal codec is unavailable on this test runner.")
        }

        let values = (0 ..< 128).map { index in
            Float(sin(Double(index) * 0.05))
        }
        let input = MLXArray(values, [2, 64])
        let configuration = MLX.TurboQuantConfiguration(
            preset: .turbo4v2,
            role: .key,
            groupSize: 64,
            backend: .metalPolarQJL,
            seed: 0xDEAD_BEEF_0000_0017
        )

        let code = try MLX.turboQuantMetalEncode(input, configuration: configuration)
        let decoded = try MLX.turboQuantMetalDecode(code).asArray(Float.self)
        let mse = zip(values, decoded)
            .map { lhs, rhs in
                let delta = lhs - rhs
                return delta * delta
            }
            .reduce(Float(0), +) / Float(values.count)

        XCTAssertEqual(code.shape, [2, 64])
        XCTAssertLessThan(mse, 0.02)
    }

    private func skipSimulatorMLXRuntime(_ reason: String) throws {
        #if targetEnvironment(simulator)
        throw XCTSkip(reason)
        #else
        _ = reason
        #endif
    }
}
