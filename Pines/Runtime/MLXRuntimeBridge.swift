import Foundation
import PinesCore

#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLLM)
import MLXLLM
#endif
#if canImport(MLXVLM)
import MLXVLM
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(MLXHuggingFace)
import MLXHuggingFace
#endif

struct MLXRuntimeBridge {
    private let state = MLXRuntimeState()

    var isLinked: Bool {
        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXEmbedders)
        true
        #else
        false
        #endif
    }

    var id: ProviderID { localProviderID }

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
            promptCacheIdentifier: install.repository,
            speculativeDraftModelID: nil,
            speculativeDecodingEnabled: false,
            unloadOnMemoryPressure: true
        )
    }

    func load(_ install: ModelInstall, profile: RuntimeProfile? = nil) async throws {
        try await state.load(install, profile: profile ?? defaultRuntimeProfile(for: install))
    }

    func unload() async {
        await state.unload()
    }
}

extension MLXRuntimeBridge: InferenceProvider {
    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        try await state.streamEvents(request)
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        try await state.embed(request)
    }
}

private actor MLXRuntimeState {
    private var activeInstall: ModelInstall?
    private var activeProfile = RuntimeProfile()

    #if canImport(MLXLMCommon)
    private var textContainer: MLXLMCommon.ModelContainer?
    private var visionContainer: MLXLMCommon.ModelContainer?
    #endif

    #if canImport(MLXEmbedders) && canImport(MLX)
    private let embeddingRuntime = MLXEmbeddingRuntime()
    #endif

    func load(_ install: ModelInstall, profile: RuntimeProfile) async throws {
        activeInstall = install
        activeProfile = profile

        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXLMCommon)
        let configuration = Self.lmConfiguration(for: install)
        if install.modalities.contains(.vision) {
            visionContainer = try await VLMModelFactory.shared.loadContainer(configuration: configuration)
            textContainer = nil
        } else if install.modalities.contains(.text) {
            textContainer = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
            visionContainer = nil
        }
        #else
        throw InferenceError.providerUnavailable("mlx-local")
        #endif
    }

    func unload() async {
        activeInstall = nil
        #if canImport(MLXLMCommon)
        textContainer = nil
        visionContainer = nil
        #endif
        #if canImport(MLXEmbedders) && canImport(MLX)
        await embeddingRuntime.unload()
        #endif
    }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXLMCommon)
        let requiresVision = request.messages.contains { message in
            message.attachments.contains { $0.kind == .image }
        }
        let container: MLXLMCommon.ModelContainer
        if requiresVision {
            if visionContainer == nil || activeInstall?.modelID != request.modelID {
                try await load(Self.install(for: request.modelID, modalities: [.text, .vision]), profile: activeProfile)
            }
            guard let visionContainer else { throw InferenceError.modelNotLoaded(request.modelID) }
            container = visionContainer
        } else {
            if textContainer == nil || activeInstall?.modelID != request.modelID {
                try await load(Self.install(for: request.modelID, modalities: [.text]), profile: activeProfile)
            }
            guard let textContainer else { throw InferenceError.modelNotLoaded(request.modelID) }
            container = textContainer
        }

        let profile = activeProfile
        let latestUser = request.messages.last { $0.role == .user }
        let prompt = Self.prompt(from: request.messages)
        let instructions = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        let images = latestUser?.attachments.compactMap { attachment -> UserInput.Image? in
            guard attachment.kind == .image, let localURL = attachment.localURL else { return nil }
            return .url(localURL)
        } ?? []
        let parameters = Self.generateParameters(from: request, profile: profile)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = ChatSession(
                        container,
                        instructions: instructions.isEmpty ? nil : instructions,
                        generateParameters: parameters
                    )
                    var tokenCount = 0

                    for try await item in session.streamDetails(to: prompt, images: images, videos: []) {
                        guard !Task.isCancelled else { throw InferenceError.cancelled }
                        switch item {
                        case let .chunk(text):
                            tokenCount += 1
                            continuation.yield(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                        case let .toolCall(call):
                            let argumentsData = try JSONSerialization.data(
                                withJSONObject: call.function.arguments.mapValues(\.anyValue)
                            )
                            continuation.yield(
                                .toolCall(
                                    ToolCallDelta(
                                        id: UUID().uuidString,
                                        name: call.function.name,
                                        argumentsFragment: String(decoding: argumentsData, as: UTF8.self),
                                        isComplete: true
                                    )
                                )
                            )
                        case let .info(info):
                            continuation.yield(
                                .metrics(
                                    InferenceMetrics(
                                        promptTokens: info.promptTokenCount,
                                        completionTokens: info.generationTokenCount,
                                        promptTokensPerSecond: info.promptTokensPerSecond.isFinite ? info.promptTokensPerSecond : nil,
                                        completionTokensPerSecond: info.tokensPerSecond.isFinite ? info.tokensPerSecond : nil
                                    )
                                )
                            )
                            continuation.yield(.finish(InferenceFinish(reason: Self.finishReason(from: info.stopReason))))
                        }
                    }

                    if tokenCount == 0 {
                        continuation.yield(.finish(InferenceFinish(reason: .stop)))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch InferenceError.cancelled {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch {
                    continuation.yield(
                        .failure(
                            InferenceStreamFailure(
                                code: "mlx_generation_failed",
                                message: error.localizedDescription,
                                recoverable: true
                            )
                        )
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        #else
        return AsyncThrowingStream { continuation in
            continuation.yield(
                .failure(
                    InferenceStreamFailure(
                        code: "mlx_unlinked",
                        message: "MLX runtime packages are not linked in this build.",
                        recoverable: false
                    )
                )
            )
            continuation.finish()
        }
        #endif
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        #if canImport(MLXEmbedders) && canImport(MLX)
        return try await embeddingRuntime.embed(request)
        #else
        throw InferenceError.unsupportedCapability("MLXEmbedders is not linked in this build.")
        #endif
    }

    #if canImport(MLXLMCommon)
    private static func lmConfiguration(for install: ModelInstall) -> MLXLMCommon.ModelConfiguration {
        if let localURL = install.localURL {
            return MLXLMCommon.ModelConfiguration(directory: localURL)
        }
        return MLXLMCommon.ModelConfiguration(id: install.repository, revision: install.revision ?? "main")
    }

    private static func generateParameters(from request: ChatRequest, profile: RuntimeProfile) -> GenerateParameters {
        GenerateParameters(
            maxTokens: request.sampling.maxTokens,
            maxKVSize: profile.quantization.maxKVSize,
            kvBits: profile.quantization.kvBits,
            kvGroupSize: profile.quantization.kvGroupSize,
            quantizedKVStart: profile.quantization.quantizedKVStart,
            temperature: request.sampling.temperature,
            topP: request.sampling.topP,
            repetitionPenalty: request.sampling.repetitionPenalty,
            repetitionContextSize: profile.repetitionContextSize,
            prefillStepSize: profile.prefillStepSize
        )
    }

    private static func finishReason(from reason: GenerateStopReason) -> InferenceFinishReason {
        switch reason {
        case .stop:
            .stop
        case .length:
            .length
        case .cancelled:
            .cancelled
        }
    }
    #endif

    private static func install(for modelID: ModelID, modalities: Set<ModelModality>) -> ModelInstall {
        ModelInstall(
            modelID: modelID,
            displayName: modelID.rawValue.components(separatedBy: "/").last ?? modelID.rawValue,
            repository: modelID.rawValue,
            modalities: modalities,
            verification: .installable,
            state: .remote
        )
    }

    private static func prompt(from messages: [ChatMessage]) -> String {
        let nonSystem = messages.filter { $0.role != .system }
        if let lastUser = nonSystem.last(where: { $0.role == .user }) {
            return lastUser.content
        }
        return nonSystem.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
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
