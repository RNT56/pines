import Foundation
import PinesCore

#if canImport(PinesHubXetSupport)
import PinesHubXetSupport
#endif
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
#if canImport(Tokenizers)
import Tokenizers
#endif

struct MLXRuntimeBridge {
    private let state = MLXRuntimeState()
    private let deviceMonitor = DeviceRuntimeMonitor()

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
        let profile = deviceMonitor.currentProfile()
        return ProviderCapabilities(
            local: true,
            streaming: true,
            textGeneration: true,
            vision: profile.allowsVisionModels,
            embeddings: true,
            toolCalling: true,
            jsonMode: true,
            maxContextTokens: profile.recommendedContextTokens
        )
    }

    var runtimeDiagnostics: RuntimeQuantizationDiagnostics {
        let memoryCounters = deviceMonitor.memoryCounters()
        let backend = turboQuantBackendSnapshot()
        let linked = isLinked
        return RuntimeQuantizationDiagnostics(
            requestedAlgorithm: .turboQuant,
            activeAlgorithm: linked ? .turboQuant : .none,
            preset: .turbo3_5,
            requestedBackend: backend.requested,
            activeBackend: linked ? backend.active : nil,
            metalCodecAvailable: linked && backend.metalCodecAvailable,
            metalAttentionAvailable: linked && backend.metalAttentionAvailable,
            activeAttentionPath: linked ? backend.activeAttentionPath : .baseline,
            metalKernelProfile: linked ? backend.kernelProfile : .mlxPackedFallback,
            metalSelfTestStatus: linked ? backend.selfTestStatus : nil,
            metalSelfTestFailureReason: backend.selfTestFailureReason,
            rawFallbackAllocated: backend.rawFallbackAllocated,
            devicePerformanceClass: memoryCounters.devicePerformanceClass,
            turboQuantOptimizationPolicy: memoryCounters.devicePerformanceClass == nil
                ? nil
                : deviceMonitor.currentProfile().turboQuantOptimizationPolicy,
            thermalDownshiftActive: memoryCounters.thermalDownshiftActive,
            lastUnsupportedAttentionShape: backend.lastUnsupportedAttentionShape,
            activeFallbackReason: linked
                ? backend.fallbackReason
                : "MLX runtime packages are not linked in this build.",
            memoryCounters: memoryCounters
        )
    }

    func defaultRuntimeProfile(for install: ModelInstall) -> RuntimeProfile {
        let deviceProfile = deviceMonitor.currentProfile()
        let hasVision = install.modalities.contains(.vision)
        let isCompact = deviceProfile.memoryTier == .compact
        let isSmallTextModel = (install.parameterCount ?? Int64.max) <= 2_000_000_000
            || install.repository.localizedCaseInsensitiveContains("1B")
        let maxKVSize = hasVision
            ? min(deviceProfile.recommendedContextTokens, 4096)
            : (isSmallTextModel ? deviceProfile.recommendedSmallModelContextTokens : deviceProfile.recommendedContextTokens)
        let backend = turboQuantBackendSnapshot()
        let linked = isLinked
        return RuntimeProfile(
            name: hasVision ? "Vision balanced" : "Local balanced",
            quantization: QuantizationProfile(
                weightBits: install.repository.localizedCaseInsensitiveContains("4bit") ? 4 : nil,
                kvBits: nil,
                kvGroupSize: 64,
                quantizedKVStart: 0,
                maxKVSize: maxKVSize,
                algorithm: .turboQuant,
                kvCacheStrategy: .turboQuant,
                preset: .turbo3_5,
                requestedBackend: backend.requested,
                activeBackend: linked ? backend.active : nil,
                metalCodecAvailable: linked && backend.metalCodecAvailable,
                metalAttentionAvailable: linked && backend.metalAttentionAvailable,
                activeAttentionPath: linked ? backend.activeAttentionPath : .baseline,
                metalKernelProfile: linked ? backend.kernelProfile : .mlxPackedFallback,
                metalSelfTestStatus: linked ? backend.selfTestStatus : nil,
                metalSelfTestFailureReason: backend.selfTestFailureReason,
                rawFallbackAllocated: backend.rawFallbackAllocated,
                devicePerformanceClass: deviceProfile.performanceClass,
                turboQuantOptimizationPolicy: deviceProfile.turboQuantOptimizationPolicy,
                thermalDownshiftActive: deviceProfile.thermalDownshiftActive,
                lastUnsupportedAttentionShape: backend.lastUnsupportedAttentionShape,
                activeFallbackReason: linked
                    ? backend.fallbackReason
                    : "MLX runtime packages are not linked in this build.",
                memoryCounters: deviceMonitor.memoryCounters()
            ),
            prefillStepSize: hasVision || isCompact
                ? min(deviceProfile.recommendedPrefillStepSize, 256)
                : deviceProfile.recommendedPrefillStepSize,
            promptCacheEnabled: !hasVision,
            promptCacheIdentifier: install.repository,
            speculativeDraftModelID: nil,
            speculativeDecodingEnabled: false,
            unloadOnMemoryPressure: true,
            repetitionContextSize: isCompact ? 16 : 20,
            maxConcurrentSessions: 1
        )
    }

    private func turboQuantBackendSnapshot() -> (
        requested: PinesCore.TurboQuantRuntimeBackend,
        active: PinesCore.TurboQuantRuntimeBackend?,
        metalCodecAvailable: Bool,
        metalAttentionAvailable: Bool,
        activeAttentionPath: PinesCore.TurboQuantAttentionPath,
        kernelProfile: PinesCore.TurboQuantKernelProfile?,
        selfTestStatus: PinesCore.TurboQuantSelfTestStatus?,
        selfTestFailureReason: String?,
        rawFallbackAllocated: Bool?,
        lastUnsupportedAttentionShape: String?,
        fallbackReason: String?
    ) {
        #if canImport(MLX)
        let requested = MLX.TurboQuantBackend.metalPolarQJL
        let availability = MLX.TurboQuantKernelAvailability.current
        let activeBackend = availability.runtimeBackend(for: requested)
        let attentionPath: PinesCore.TurboQuantAttentionPath =
            activeBackend == .metalPolarQJL && availability.supportsMetalPolarQJLAttention
            ? .tiledOnlineFused
            : .mlxPackedFallback
        return (
            .metalPolarQJL,
            Self.coreTurboQuantBackend(from: activeBackend),
            availability.supportsMetalPolarQJLCodec,
            availability.supportsMetalPolarQJLAttention,
            attentionPath,
            Self.coreTurboQuantKernelProfile(from: availability.selectedKernelProfile),
            Self.coreTurboQuantSelfTestStatus(from: availability.selfTestStatus),
            availability.selfTestFailureReason,
            false,
            nil,
            availability.fallbackReason(for: requested)
        )
        #else
        return (
            .metalPolarQJL,
            nil,
            false,
            false,
            .baseline,
            .mlxPackedFallback,
            nil,
            nil,
            nil,
            nil,
            "MLX runtime packages are not linked in this build."
        )
        #endif
    }

    #if canImport(MLX)
    private static func coreTurboQuantBackend(
        from backend: MLX.TurboQuantBackend
    ) -> PinesCore.TurboQuantRuntimeBackend {
        switch backend {
        case .mlxPacked:
            .mlxPacked
        case .polarQJLReference:
            .polarQJLReference
        case .metalPolarQJL:
            .metalPolarQJL
        }
    }

    private static func coreTurboQuantKernelProfile(
        from profile: MLX.TurboQuantKernelProfile
    ) -> PinesCore.TurboQuantKernelProfile {
        switch profile {
        case .portableA16A17:
            .portableA16A17
        case .wideA18A19:
            .wideA18A19
        case .sustainedA19Pro:
            .sustainedA19Pro
        case .mlxPackedFallback:
            .mlxPackedFallback
        }
    }

    private static func coreTurboQuantSelfTestStatus(
        from status: MLX.TurboQuantRuntimeSelfTestStatus
    ) -> PinesCore.TurboQuantSelfTestStatus {
        switch status {
        case .notRun:
            .notRun
        case .passed:
            .passed
        case .failed:
            .failed
        }
    }

    #endif

    func load(_ install: ModelInstall, profile: RuntimeProfile? = nil) async throws {
        try await state.load(install, profile: profile ?? defaultRuntimeProfile(for: install))
    }

    func unload() async {
        await state.unload()
    }

    func handleMemoryPressure() async {
        await state.handleMemoryPressure()
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
    private var didRegisterModelAliases = false

    #if canImport(MLXLMCommon)
    private var textContainer: MLXLMCommon.ModelContainer?
    private var visionContainer: MLXLMCommon.ModelContainer?
    #endif

    #if canImport(MLXEmbedders) && canImport(MLXLMCommon) && canImport(MLX) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
    private let embeddingRuntime = MLXEmbeddingRuntime()
    #endif

    func load(_ install: ModelInstall, profile: RuntimeProfile) async throws {
        activeInstall = install
        activeProfile = profile

        #if canImport(MLXLLM) && canImport(MLXVLM) && canImport(MLXLMCommon) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
        await registerModelAliasesIfNeeded()
        let configuration = try Self.lmConfiguration(for: install)
        if install.modalities.contains(.vision) {
            visionContainer = try await VLMModelFactory.shared.loadContainer(
                from: PinesHubDownloader(),
                using: PinesTokenizerLoader(),
                configuration: configuration
            )
            textContainer = nil
        } else if install.modalities.contains(.text) {
            textContainer = try await LLMModelFactory.shared.loadContainer(
                from: PinesHubDownloader(),
                using: PinesTokenizerLoader(),
                configuration: configuration
            )
            visionContainer = nil
        }
        #else
        throw InferenceError.providerUnavailable("mlx-local")
        #endif
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private func registerModelAliasesIfNeeded() async {
        guard !didRegisterModelAliases else { return }
        didRegisterModelAliases = true

        await LLMTypeRegistry.shared.registerModelType(
            "gemma4_assistant",
            creator: Self.llmCreator(Gemma4Configuration.self, Gemma4Model.init)
        )
        await LLMTypeRegistry.shared.registerModelType(
            "deepseek_v32",
            creator: Self.llmCreator(DeepseekV3Configuration.self, DeepseekV3Model.init)
        )
        await LLMTypeRegistry.shared.registerModelType(
            "minimax_m2",
            creator: Self.llmCreator(MiniMaxConfiguration.self, MiniMaxModel.init)
        )
    }

    private nonisolated static func llmCreator<C: Codable, M: LanguageModel>(
        _ configurationType: C.Type,
        _ modelInit: @escaping (C) -> M
    ) -> (Data) throws -> LanguageModel {
        { data in
            let configuration = try JSONDecoder.json5().decode(configurationType, from: data)
            return modelInit(configuration)
        }
    }
    #endif

    func unload() async {
        activeInstall = nil
        #if canImport(MLXLMCommon)
        textContainer = nil
        visionContainer = nil
        #endif
        #if canImport(MLXEmbedders) && canImport(MLXLMCommon) && canImport(MLX) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
        await embeddingRuntime.unload()
        #endif
    }

    func handleMemoryPressure() async {
        guard activeProfile.unloadOnMemoryPressure else { return }
        await unload()
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
        guard let latestUserIndex = request.messages.lastIndex(where: { $0.role == .user }) else {
            throw InferenceError.invalidRequest("A local chat request requires a user message.")
        }
        let latestUser = request.messages[latestUserIndex]
        let latestPrompt = latestUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latestPrompt.isEmpty else {
            throw InferenceError.invalidRequest("A local chat request requires a non-empty user message.")
        }
        let instructions = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        let imageURLs = latestUser.attachments.compactMap { attachment -> URL? in
            guard attachment.kind == .image, let localURL = attachment.localURL else { return nil }
            return localURL
        }
        let parameters = Self.generateParameters(from: request, profile: profile, install: activeInstall)
        let toolSpecs = request.allowsTools ? Self.mlxToolSpecs(from: request.availableTools) : nil

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let images = imageURLs.map(UserInput.Image.url)
                    let history = Self.chatHistory(from: request.messages[..<latestUserIndex])
                    let session = ChatSession(
                        container,
                        instructions: instructions.isEmpty ? nil : instructions,
                        history: history,
                        generateParameters: parameters,
                        tools: toolSpecs
                    )
                    var tokenCount = 0

                    for try await item in session.streamDetails(to: latestPrompt, images: images, videos: []) {
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
                    continuation.finish()
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
        #if canImport(MLXEmbedders) && canImport(MLXLMCommon) && canImport(MLX) && canImport(PinesHubXetSupport) && canImport(Tokenizers)
        return try await embeddingRuntime.embed(request)
        #else
        throw InferenceError.unsupportedCapability("MLXEmbedders is not linked in this build.")
        #endif
    }

    #if canImport(MLXLMCommon)
    private static func lmConfiguration(for install: ModelInstall) throws -> MLXLMCommon.ModelConfiguration {
        if let localURL = install.localURL {
            guard let resolvedURL = ModelLifecycleService.resolvedModelDirectory(
                from: localURL,
                modalities: install.modalities
            ) else {
                throw InferenceError.invalidRequest(
                    "The installed model \(install.repository) is incomplete. Delete it and download it again."
                )
            }
            return MLXLMCommon.ModelConfiguration(directory: resolvedURL)
        }
        return MLXLMCommon.ModelConfiguration(id: install.repository, revision: install.revision ?? "main")
    }

    private static func generateParameters(
        from request: ChatRequest,
        profile: RuntimeProfile,
        install: ModelInstall?
    ) -> GenerateParameters {
        let turboQuantSeed: UInt64? =
            profile.quantization.kvCacheStrategy == .turboQuant
            ? MLX.TurboQuantConfiguration.deterministicSeed(
                modelID: install?.repository ?? request.modelID.rawValue,
                revision: install?.revision ?? "main",
                cacheLayoutVersion: 3
            )
            : nil

        return GenerateParameters(
            maxTokens: request.sampling.maxTokens,
            maxKVSize: profile.quantization.maxKVSize,
            kvBits: profile.quantization.kvCacheStrategy == .turboQuant ? nil : profile.quantization.kvBits,
            kvGroupSize: profile.quantization.kvGroupSize,
            quantizedKVStart: profile.quantization.quantizedKVStart,
            kvCacheStrategy: profile.quantization.kvCacheStrategy == .turboQuant ? .turboQuant : .mlxAffine,
            turboQuantPreset: mlxTurboQuantPreset(from: profile.quantization.preset),
            turboQuantBackend: mlxTurboQuantBackend(from: profile.quantization.requestedBackend),
            turboQuantSeed: turboQuantSeed,
            temperature: request.sampling.temperature,
            topP: request.sampling.topP,
            repetitionPenalty: request.sampling.repetitionPenalty,
            repetitionContextSize: profile.repetitionContextSize,
            prefillStepSize: profile.prefillStepSize
        )
    }

    private static func mlxTurboQuantPreset(from preset: PinesCore.TurboQuantPreset?) -> MLX.TurboQuantPreset {
        guard let preset else { return .turbo3_5 }
        return MLX.TurboQuantPreset(rawValue: preset.rawValue) ?? .turbo3_5
    }

    private static func mlxTurboQuantBackend(
        from backend: PinesCore.TurboQuantRuntimeBackend?
    ) -> MLXLMCommon.TurboQuantBackend {
        guard let backend else { return .metalPolarQJL }
        return MLXLMCommon.TurboQuantBackend(rawValue: backend.rawValue) ?? .metalPolarQJL
    }

    private static func mlxToolSpecs(from tools: [AnyToolSpec]) -> [MLXLMCommon.ToolSpec]? {
        let schemas = tools.map { $0.openAIFunctionToolObject() }
        return schemas.isEmpty ? nil : schemas
    }

    private static func chatHistory(from messages: ArraySlice<ChatMessage>) -> [Chat.Message] {
        let maxCharacters = 24_000
        var selected = [Chat.Message]()
        var remaining = maxCharacters

        for message in messages.reversed() {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, message.role != .system else { continue }
            guard remaining > 0 else { break }

            let clippedContent: String
            if content.count <= remaining {
                clippedContent = content
            } else {
                clippedContent = String(content.suffix(remaining))
            }
            remaining -= clippedContent.count

            switch message.role {
            case .assistant:
                selected.append(.assistant(clippedContent))
            case .tool:
                selected.append(.tool(clippedContent))
            case .user:
                selected.append(.user(clippedContent))
            case .system:
                break
            }
        }

        return selected.reversed()
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
        let maxCharacters = 24_000
        let usableMessages = messages
            .filter { message in
                message.role != .system
                    && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .suffix(24)

        var packed = [String]()
        var remaining = maxCharacters
        for message in usableMessages.reversed() {
            let label: String
            switch message.role {
            case .user:
                label = "User"
            case .assistant:
                label = "Assistant"
            case .tool:
                label = "Tool"
            case .system:
                label = "System"
            }
            let entry = "\(label): \(message.content)"
            guard remaining > 0 else { break }
            if entry.count <= remaining {
                packed.append(entry)
                remaining -= entry.count
            } else if message.role == .user, packed.isEmpty {
                packed.append(String(entry.suffix(remaining)))
                break
            }
        }
        return packed.reversed().joined(separator: "\n\n")
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
