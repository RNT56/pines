import Foundation
import PinesCore
import Testing

@Suite("Local model runtime policy")
struct LocalModelRuntimePolicyTests {
    @Test("Cold admission charges target weights exactly once")
    func coldAdmissionChargesTargetWeights() {
        let basis = LocalModelRuntimePolicy.admissionMemoryBasis(
            availableMemoryBytes: 3_334_584_704,
            mlxActiveMemoryBytes: 0,
            loadedModelEstimatedBytes: nil,
            targetModelEstimatedBytes: 1_533_804_712,
            hasLoadedModel: false,
            reusesLoadedModel: false
        )

        #expect(basis.kind == .coldLoad)
        #expect(basis.plannerAvailableMemoryBytes == 3_334_584_704)
        #expect(basis.incrementalTargetModelBytes == 1_533_804_712)
        #expect(basis.reclaimableLoadedModelBytes == 0)
    }

    @Test("Warm admission does not charge resident Qwen weights twice")
    func warmAdmissionDoesNotDoubleCountWeights() {
        let basis = LocalModelRuntimePolicy.admissionMemoryBasis(
            availableMemoryBytes: 1_718_908_064,
            mlxActiveMemoryBytes: 1_533_804_712,
            loadedModelEstimatedBytes: 1_533_885_748,
            targetModelEstimatedBytes: 1_533_885_748,
            hasLoadedModel: true,
            reusesLoadedModel: true
        )

        #expect(basis.kind == .warmReuse)
        #expect(basis.plannerAvailableMemoryBytes == 1_718_908_064)
        #expect(basis.incrementalTargetModelBytes == 0)
        #expect(basis.reclaimableLoadedModelBytes == 0)
    }

    @Test("Replacement credits only the outgoing model's resident bytes")
    func replacementCreditsOutgoingModel() {
        let basis = LocalModelRuntimePolicy.admissionMemoryBasis(
            availableMemoryBytes: 1_718_908_064,
            mlxActiveMemoryBytes: 1_533_804_712,
            loadedModelEstimatedBytes: 1_533_885_748,
            targetModelEstimatedBytes: 732_551_816,
            hasLoadedModel: true,
            reusesLoadedModel: false
        )

        #expect(basis.kind == .modelReplacement)
        #expect(basis.reclaimableLoadedModelBytes == 1_533_804_712)
        #expect(basis.plannerAvailableMemoryBytes == 3_252_712_776)
        #expect(basis.incrementalTargetModelBytes == 732_551_816)
    }

    @Test("Unrelated MLX allocations are not assumed reclaimable without a model estimate")
    func replacementDoesNotCreditUnknownAllocations() {
        let basis = LocalModelRuntimePolicy.admissionMemoryBasis(
            availableMemoryBytes: 1_500_000_000,
            mlxActiveMemoryBytes: 800_000_000,
            loadedModelEstimatedBytes: nil,
            targetModelEstimatedBytes: 700_000_000,
            hasLoadedModel: true,
            reusesLoadedModel: false
        )

        #expect(basis.kind == .modelReplacement)
        #expect(basis.reclaimableLoadedModelBytes == 0)
        #expect(basis.plannerAvailableMemoryBytes == 1_500_000_000)
    }

    @Test("A17 balanced context is capped by measured model weight tier")
    func a17ContextCapsUseWeightTiers() {
        let compact = Self.install(repository: "mlx-community/gemma-3-1b-it-4bit", bytes: 732_551_816, parameters: 1_000_000_000)
        let balanced = Self.install(repository: "mlx-community/Qwen3.5-2B-OptiQ-4bit", bytes: 1_533_885_748, parameters: 2_000_000_000)
        let edge = Self.install(repository: "mlx-community/Llama-3.2-3B-Instruct-4bit", bytes: 1_807_496_278, parameters: 3_000_000_000)

        #expect(LocalModelRuntimePolicy.contextTokenCap(
            for: compact,
            deviceProfile: .balancedPhone,
            userMode: .balanced,
            deviceRecommendedTokens: 24_576
        ) == 8_192)
        #expect(LocalModelRuntimePolicy.contextTokenCap(
            for: balanced,
            deviceProfile: .balancedPhone,
            userMode: .balanced,
            deviceRecommendedTokens: 24_576
        ) == 4_096)
        #expect(LocalModelRuntimePolicy.contextTokenCap(
            for: edge,
            deviceProfile: .balancedPhone,
            userMode: .balanced,
            deviceRecommendedTokens: 16_384
        ) == 2_048)
    }

    @Test("Max Context remains an explicit opt-in")
    func maxContextUsesDeviceRecommendation() {
        let install = Self.install(
            repository: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
            bytes: 1_533_885_748,
            parameters: 2_000_000_000
        )

        #expect(LocalModelRuntimePolicy.contextTokenCap(
            for: install,
            deviceProfile: .balancedPhone,
            userMode: .maxContext,
            deviceRecommendedTokens: 24_576
        ) == 24_576)
    }

    @Test("Conservation modes never loosen a tighter A17 model cap")
    func conservationModeDoesNotIncreaseModelCap() {
        let install = Self.install(
            repository: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            bytes: 1_824_807_894,
            parameters: 3_000_000_000
        )

        #expect(LocalModelRuntimePolicy.contextTokenCap(
            for: install,
            deviceProfile: .balancedPhone,
            userMode: .batterySaver,
            deviceRecommendedTokens: 16_384
        ) == 2_048)
    }

    private static func install(repository: String, bytes: Int64, parameters: Int64) -> ModelInstall {
        ModelInstall(
            modelID: ModelID(rawValue: repository),
            displayName: repository,
            repository: repository,
            modalities: [.text],
            verification: .verified,
            state: .installed,
            parameterCount: parameters,
            estimatedBytes: bytes,
            modelType: "test"
        )
    }
}
