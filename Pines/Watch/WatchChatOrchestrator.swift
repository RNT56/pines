import Foundation
import PinesCore
import PinesWatchSupport

struct WatchChatOrchestrator {
    let services: PinesAppServices
    let approvalHandler: @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus

    init(
        services: PinesAppServices,
        approvalHandler: @escaping @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus = { _ in .denied }
    ) {
        self.services = services
        self.approvalHandler = approvalHandler
    }

    func snapshot(selectedConversationID: UUID? = nil, activeRunID: UUID? = nil) async throws -> WatchChatSnapshot {
        guard let repository = services.conversationRepository else {
            throw WatchChatError.unavailable("Conversation repository is unavailable.")
        }

        let conversations = try await repository.listConversations()
        let selectedID = selectedConversationID ?? conversations.first?.id
        var summaries = [WatchConversationSummary]()
        summaries.reserveCapacity(conversations.count)

        for conversation in conversations {
            let messages = try await repository.messages(in: conversation.id)
            summaries.append(Self.summary(from: conversation, messages: messages))
        }

        let selectedMessages: [WatchChatMessage]
        if let selectedID {
            selectedMessages = try await repository.messages(in: selectedID)
                .suffix(40)
                .map(Self.watchMessage(from:))
        } else {
            selectedMessages = []
        }

        return WatchChatSnapshot(
            conversations: summaries,
            selectedConversationID: selectedID,
            messages: selectedMessages,
            activeRunID: activeRunID,
            status: phoneStatus()
        )
    }

    func createConversation() async throws -> WatchChatSnapshot {
        guard let repository = services.conversationRepository else {
            throw WatchChatError.unavailable("Conversation repository is unavailable.")
        }

        let modelID = try await defaultModelID()
        let conversation = try await repository.createConversation(
            title: "New chat",
            defaultModelID: modelID,
            defaultProviderID: modelID == nil ? nil : services.mlxRuntime.localProviderID
        )
        return try await snapshot(selectedConversationID: conversation.id)
    }

    func renameConversation(_ request: WatchRenameConversationRequest) async throws -> WatchChatSnapshot {
        guard let repository = services.conversationRepository else {
            throw WatchChatError.unavailable("Conversation repository is unavailable.")
        }

        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw WatchChatError.unavailable("Conversation title is empty.")
        }
        try await repository.updateConversationTitle(title, conversationID: request.conversationID)
        return try await snapshot(selectedConversationID: request.conversationID)
    }

    func setConversationArchived(_ request: WatchArchiveConversationRequest) async throws -> WatchChatSnapshot {
        guard let repository = services.conversationRepository else {
            throw WatchChatError.unavailable("Conversation repository is unavailable.")
        }

        try await repository.setConversationArchived(request.archived, conversationID: request.conversationID)
        return try await snapshot(selectedConversationID: request.archived ? nil : request.conversationID)
    }

    func deleteConversation(_ request: WatchDeleteConversationRequest) async throws -> WatchChatSnapshot {
        guard let repository = services.conversationRepository else {
            throw WatchChatError.unavailable("Conversation repository is unavailable.")
        }

        try await repository.deleteConversation(id: request.conversationID)
        return try await snapshot()
    }

    func sendMessage(_ input: WatchSendMessageRequest, runID: UUID) -> AsyncThrowingStream<WatchChatRunUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var conversationID = input.conversationID
                var assistantMessage: ChatMessage?
                var selectedModelID: ModelID?
                var selectedProviderID: ProviderID?
                var accumulated = ""
                var tokenCount = 0

                do {
                    let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        throw WatchChatError.unavailable("Message text is empty.")
                    }
                    guard let repository = services.conversationRepository else {
                        throw WatchChatError.unavailable("Conversation repository is unavailable.")
                    }

                    if conversationID == nil {
                        let modelID = try await defaultModelID()
                        let conversation = try await repository.createConversation(
                            title: Self.title(from: trimmed),
                            defaultModelID: modelID,
                            defaultProviderID: modelID == nil ? nil : services.mlxRuntime.localProviderID
                        )
                        conversationID = conversation.id
                    }
                    guard let conversationID else {
                        throw WatchChatError.unavailable("Could not create a conversation.")
                    }

                    let existingMessages = try await repository.messages(in: conversationID)
                    let shouldAppendUserMessage = !existingMessages.contains { $0.id == input.clientMessageID }
                    if let existingUserIndex = existingMessages.firstIndex(where: { $0.id == input.clientMessageID }) {
                        if let existingAssistant = existingMessages
                            .dropFirst(existingUserIndex + 1)
                            .first(where: { $0.role == .assistant }) {
                            continuation.yield(
                                WatchChatRunUpdate(
                                    runID: runID,
                                    conversationID: conversationID,
                                    assistantMessageID: existingAssistant.id,
                                    status: existingAssistant.content.isEmpty ? .streaming : .completed,
                                    text: existingAssistant.content,
                                    tokenCount: tokenCount
                                )
                            )
                            continuation.finish()
                            return
                        }
                    }

                    let providerSelection = try await selectProvider(conversationID: conversationID)
                    selectedModelID = providerSelection.modelID
                    selectedProviderID = providerSelection.providerID

                    if shouldAppendUserMessage {
                        let userMessage = ChatMessage(id: input.clientMessageID, role: .user, content: trimmed)
                        try await repository.appendMessage(
                            userMessage,
                            status: .complete,
                            conversationID: conversationID,
                            modelID: providerSelection.modelID,
                            providerID: nil
                        )
                    }

                    let pendingAssistant = ChatMessage(role: .assistant, content: "")
                    assistantMessage = pendingAssistant
                    try await repository.appendMessage(
                        pendingAssistant,
                        status: .streaming,
                        conversationID: conversationID,
                        modelID: providerSelection.modelID,
                        providerID: providerSelection.providerID
                    )

                    continuation.yield(
                        WatchChatRunUpdate(
                            runID: runID,
                            conversationID: conversationID,
                            assistantMessageID: pendingAssistant.id,
                            status: .accepted,
                            text: ""
                        )
                    )

                    var messages = try await repository.messages(in: conversationID)
                    let isLocalProvider = providerSelection.providerID == services.mlxRuntime.localProviderID
                    if isLocalProvider, let vaultContext = await vaultContextMessage(for: trimmed) {
                        messages.insert(vaultContext.message, at: 0)
                    }

                    // Normal chat should not advertise globally registered agent tools unless a tool mode opts in.
                    let availableTools: [AnyToolSpec] = []
                    let settings = try? await services.settingsRepository?.loadSettings()
                    let request = ChatRequest(
                        modelID: providerSelection.modelID,
                        messages: messages,
                        sampling: chatSampling(for: providerSelection.providerID, settings: settings),
                        allowsTools: !availableTools.isEmpty,
                        availableTools: availableTools
                    )
                    let session = AgentSession(
                        title: "Watch Chat",
                        policy: AgentPolicy(
                            executionMode: settings?.executionMode ?? .preferLocal,
                            requiresConsentForNetwork: false,
                            requiresConsentForBrowser: false,
                            allowsCloudContext: false
                        ),
                        providerID: providerSelection.providerID
                    )
                    let runner = AgentRunner(
                        toolRegistry: services.toolRegistry,
                        policyGate: services.toolPolicyGate,
                        auditRepository: services.auditRepository,
                        approvalHandler: approvalHandler
                    )

                    let startedAt = Date()
                    let stream = runner.run(session: session, request: request, provider: providerSelection.provider)
                    var didReceiveTerminalEvent = false
                    var didFail = false
                    var finalProviderMetadata = [String: String]()
                    for try await event in stream {
                        try Task.checkCancellation()
                        switch event {
                        case let .token(delta):
                            accumulated += delta.text
                            tokenCount += max(delta.tokenCount, 1)
                            try await repository.updateMessage(
                                id: pendingAssistant.id,
                                content: accumulated,
                                status: .streaming,
                                tokenCount: tokenCount
                            )
                            continuation.yield(
                                WatchChatRunUpdate(
                                    runID: runID,
                                    conversationID: conversationID,
                                    assistantMessageID: pendingAssistant.id,
                                    status: .streaming,
                                    text: accumulated,
                                    tokenCount: tokenCount
                                )
                            )
                        case let .finish(finish):
                            didReceiveTerminalEvent = true
                            finalProviderMetadata = finish.providerMetadata
                            if !didFail {
                                let status: MessageStatus = finish.reason == .cancelled ? .cancelled : .complete
                                let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                                if status == .complete && finalText.isEmpty {
                                    let message = Self.messageWithProviderDiagnostics(
                                        finish.message ?? "The selected model finished without producing output.",
                                        metadata: finalProviderMetadata
                                    )
                                    didFail = true
                                    try await repository.updateMessage(
                                        id: pendingAssistant.id,
                                        content: message,
                                        status: .failed,
                                        tokenCount: tokenCount,
                                        providerMetadata: finalProviderMetadata
                                    )
                                    continuation.yield(
                                        WatchChatRunUpdate(
                                            runID: runID,
                                            conversationID: conversationID,
                                            assistantMessageID: pendingAssistant.id,
                                            status: .failed,
                                            text: accumulated,
                                            tokenCount: tokenCount,
                                            errorMessage: message
                                        )
                                    )
                                } else {
                                    try await repository.updateMessage(
                                        id: pendingAssistant.id,
                                        content: accumulated,
                                        status: status,
                                        tokenCount: tokenCount,
                                        providerMetadata: finalProviderMetadata
                                    )
                                    continuation.yield(
                                        WatchChatRunUpdate(
                                            runID: runID,
                                            conversationID: conversationID,
                                            assistantMessageID: pendingAssistant.id,
                                            status: finish.reason == .cancelled ? .cancelled : .completed,
                                            text: accumulated,
                                            tokenCount: tokenCount
                                        )
                                    )
                                }
                            }
                        case let .failure(failure):
                            didReceiveTerminalEvent = true
                            didFail = true
                            try await repository.updateMessage(
                                id: pendingAssistant.id,
                                content: failure.message,
                                status: .failed,
                                tokenCount: tokenCount
                            )
                            continuation.yield(
                                WatchChatRunUpdate(
                                    runID: runID,
                                    conversationID: conversationID,
                                    assistantMessageID: pendingAssistant.id,
                                    status: .failed,
                                    text: accumulated,
                                    tokenCount: tokenCount,
                                    errorMessage: failure.message
                                )
                            )
                        case let .metrics(metrics):
                            services.runtimeMetrics.recordGenerationMetrics(metrics, modelID: providerSelection.modelID)
                        case .toolCall:
                            break
                        }
                    }

                    if !didReceiveTerminalEvent {
                        let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                        if finalText.isEmpty {
                            let message = "The inference stream ended before the model produced output."
                            try await repository.updateMessage(
                                id: pendingAssistant.id,
                                content: message,
                                status: .failed,
                                tokenCount: tokenCount
                            )
                            continuation.yield(
                                WatchChatRunUpdate(
                                    runID: runID,
                                    conversationID: conversationID,
                                    assistantMessageID: pendingAssistant.id,
                                    status: .failed,
                                    text: accumulated,
                                    tokenCount: tokenCount,
                                    errorMessage: message
                                )
                            )
                        } else {
                            try await repository.updateMessage(
                                id: pendingAssistant.id,
                                content: accumulated,
                                status: .complete,
                                tokenCount: tokenCount,
                                providerMetadata: finalProviderMetadata
                            )
                            continuation.yield(
                                WatchChatRunUpdate(
                                    runID: runID,
                                    conversationID: conversationID,
                                    assistantMessageID: pendingAssistant.id,
                                    status: .completed,
                                    text: accumulated,
                                    tokenCount: tokenCount
                                )
                            )
                        }
                    }

                    services.runtimeMetrics.recordGenerationFinished(
                        modelID: providerSelection.modelID,
                        outputTokens: tokenCount,
                        elapsedSeconds: Date().timeIntervalSince(startedAt)
                    )
                    continuation.finish()
                } catch is CancellationError {
                    await markCancelled(
                        assistantMessage: assistantMessage,
                        conversationID: conversationID,
                        selectedModelID: selectedModelID,
                        selectedProviderID: selectedProviderID,
                        accumulated: accumulated,
                        tokenCount: tokenCount
                    )
                    if let conversationID {
                        continuation.yield(
                            WatchChatRunUpdate(
                                runID: runID,
                                conversationID: conversationID,
                                assistantMessageID: assistantMessage?.id,
                                status: .cancelled,
                                text: accumulated,
                                tokenCount: tokenCount
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    if let repository = services.conversationRepository,
                       let assistantMessage {
                        try? await repository.updateMessage(
                            id: assistantMessage.id,
                            content: error.localizedDescription,
                            status: .failed,
                            tokenCount: tokenCount
                        )
                    }
                    if let conversationID {
                        continuation.yield(
                            WatchChatRunUpdate(
                                runID: runID,
                                conversationID: conversationID,
                                assistantMessageID: assistantMessage?.id,
                                status: .failed,
                                text: accumulated,
                                tokenCount: tokenCount,
                                errorMessage: error.localizedDescription
                            )
                        )
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func defaultModelID() async throws -> ModelID? {
        let installs = try await services.modelInstallRepository?.listInstalledAndCuratedModels() ?? []
        let installedTextModels = installs.filter { $0.state == .installed && $0.modalities.contains(.text) }
        if let settings = try? await services.settingsRepository?.loadSettings(),
           let modelID = settings.defaultModelID,
           installedTextModels.contains(where: { $0.modelID == modelID }) {
            return modelID
        }
        return installedTextModels.first?.modelID
    }

    private func selectProvider(conversationID: UUID) async throws -> ProviderSelection {
        let settings = try? await services.settingsRepository?.loadSettings()
        let conversations = try await services.conversationRepository?.listConversations() ?? []
        let configuredModelID = settings?.defaultModelID
            ?? conversations.first { $0.id == conversationID }?.defaultModelID
        let installs = try await services.modelInstallRepository?.listInstalledAndCuratedModels() ?? []
        let installedTextModels = installs.filter { $0.state == .installed && $0.modalities.contains(.text) }
        let localInstall = configuredModelID
            .flatMap { modelID in installedTextModels.first { $0.modelID == modelID } }
            ?? installedTextModels.first
        let cloudProviders = try await services.cloudProviderRepository?.listProviders() ?? []
        let cloudCandidate = cloudProviders
            .first { $0.enabledForAgents }
            .map { configuration in
                (
                    configuration,
                    BYOKCloudInferenceProvider(configuration: configuration, secretStore: services.secretStore)
                )
            }
        let localCandidate = localRoutingCandidate(for: localInstall)
        let route = services.executionRouter.routeChat(
            mode: settings?.executionMode ?? .preferLocal,
            local: localCandidate,
            cloud: cloudCandidate.map { ($0.1.id, $0.1.capabilities) },
            requiredInputs: .init(),
            requiresTools: false
        )

        switch route.destination {
        case .local:
            guard let localInstall else {
                throw WatchChatError.unavailable("Download and select a local text model before starting local chat.")
            }
            try await services.mlxRuntime.load(
                localInstall,
                profile: localRuntimeProfile(for: localInstall, settings: settings)
            )
            return ProviderSelection(
                provider: services.mlxRuntime,
                providerID: services.mlxRuntime.localProviderID,
                modelID: localInstall.modelID
            )
        case let .cloud(providerID):
            guard let cloudCandidate else {
                throw WatchChatError.unavailable("No enabled cloud provider is configured for agents.")
            }
            guard let cloudModelID = cloudCandidate.0.defaultModelID ?? localInstall?.modelID else {
                throw WatchChatError.unavailable("Configure a default model for the selected cloud provider.")
            }
            return ProviderSelection(
                provider: cloudCandidate.1,
                providerID: providerID,
                modelID: cloudModelID
            )
        case let .denied(reason):
            throw reason
        }
    }

    private func chatSampling(for providerID: ProviderID, settings: AppSettingsSnapshot?) -> ChatSampling {
        let maxTokens = providerID == services.mlxRuntime.localProviderID
            ? settings?.localMaxCompletionTokens ?? AppSettingsSnapshot.defaultLocalMaxCompletionTokens
            : settings?.cloudMaxCompletionTokens ?? AppSettingsSnapshot.defaultCloudMaxCompletionTokens
        return ChatSampling(maxTokens: AppSettingsSnapshot.normalizedCompletionTokens(maxTokens))
    }

    private func localRuntimeProfile(for install: ModelInstall, settings: AppSettingsSnapshot?) -> RuntimeProfile {
        var profile = services.mlxRuntime.defaultRuntimeProfile(for: install)
        let requestedContextTokens = AppSettingsSnapshot.normalizedLocalContextTokens(
            settings?.localMaxContextTokens ?? AppSettingsSnapshot.defaultLocalMaxContextTokens
        )
        if let recommendedContextTokens = profile.quantization.maxKVSize {
            profile.quantization.maxKVSize = min(requestedContextTokens, recommendedContextTokens)
        } else {
            profile.quantization.maxKVSize = requestedContextTokens
        }
        return profile
    }

    private func localRoutingCandidate(for install: ModelInstall?) -> (id: ProviderID, capabilities: ProviderCapabilities)? {
        guard services.mlxRuntime.isLinked,
              let install,
              install.state == .installed,
              install.modalities.contains(.text),
              install.localURL != nil
        else {
            return nil
        }
        var capabilities = services.mlxRuntime.capabilities
        capabilities.vision = capabilities.vision && install.modalities.contains(.vision)
        capabilities.imageInputs = capabilities.imageInputs && install.modalities.contains(.vision)
        capabilities.embeddings = capabilities.embeddings && install.modalities.contains(.embeddings)
        return (services.mlxRuntime.localProviderID, capabilities)
    }

    private static func messageWithProviderDiagnostics(_ message: String, metadata: [String: String]) -> String {
        let diagnosticKeys = [
            CloudProviderMetadataKeys.openAIRequestID,
            CloudProviderMetadataKeys.openAIResponseID,
            CloudProviderMetadataKeys.anthropicRequestID,
            CloudProviderMetadataKeys.anthropicMessageID,
            CloudProviderMetadataKeys.geminiRequestID,
            CloudProviderMetadataKeys.geminiResponseID,
            CloudProviderMetadataKeys.geminiInteractionID,
            CloudProviderMetadataKeys.geminiModelVersion,
            LocalProviderMetadataKeys.turboQuantActiveBackend,
            LocalProviderMetadataKeys.turboQuantAttentionPath,
            LocalProviderMetadataKeys.turboQuantKernelProfile,
            LocalProviderMetadataKeys.turboQuantSelfTestStatus,
            LocalProviderMetadataKeys.turboQuantFallbackReason,
            LocalProviderMetadataKeys.turboQuantLastUnsupportedShape,
        ]
        let diagnostics = diagnosticKeys.compactMap { key -> String? in
            guard let value = metadata[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }
        guard !diagnostics.isEmpty else { return message }
        return "\(message)\n\nProvider diagnostics: \(diagnostics.joined(separator: ", "))"
    }

    private func vaultContextMessage(for query: String) async -> (message: ChatMessage, documentIDs: [UUID])? {
        await services.vaultRetrievalService?.contextMessage(for: query, limit: 4)
    }

    private func uniqueDocumentIDs(from results: [VaultSearchResult]) -> [UUID] {
        var seen = Set<UUID>()
        var ids = [UUID]()
        for id in results.map(\.document.id) where seen.insert(id).inserted {
            ids.append(id)
        }
        return ids
    }

    private func markCancelled(
        assistantMessage: ChatMessage?,
        conversationID: UUID?,
        selectedModelID: ModelID?,
        selectedProviderID: ProviderID?,
        accumulated: String,
        tokenCount: Int
    ) async {
        guard let repository = services.conversationRepository,
              let assistantMessage,
              conversationID != nil
        else {
            return
        }

        try? await repository.updateMessage(
            id: assistantMessage.id,
            content: accumulated,
            status: .cancelled,
            tokenCount: tokenCount
        )

        _ = selectedModelID
        _ = selectedProviderID
    }

    private func phoneStatus() -> WatchPhoneStatus {
        WatchPhoneStatus(
            reachable: true,
            runtimeReady: services.mlxRuntime.isLinked,
            summary: services.mlxRuntime.isLinked ? "iPhone runtime ready" : "Open Pines on iPhone to resolve the runtime"
        )
    }

    private static func summary(from record: ConversationRecord, messages: [ChatMessage]) -> WatchConversationSummary {
        let lastMessage = messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return WatchConversationSummary(
            id: record.id,
            title: record.title,
            lastMessage: lastMessage?.isEmpty == false ? lastMessage! : "No messages yet.",
            updatedAt: record.updatedAt,
            modelName: record.defaultModelID?.rawValue.components(separatedBy: "/").last ?? "Local model",
            archived: record.archived
        )
    }

    private static func watchMessage(from message: ChatMessage) -> WatchChatMessage {
        WatchChatMessage(
            id: message.id,
            role: WatchChatRole(rawValue: message.role.rawValue) ?? .assistant,
            content: message.content,
            createdAt: message.createdAt
        )
    }

    private static func title(from text: String) -> String {
        let title = text
            .split(separator: " ")
            .prefix(6)
            .joined(separator: " ")
        return title.isEmpty ? "Watch chat" : title
    }
}

private struct ProviderSelection {
    let provider: any InferenceProvider
    let providerID: ProviderID
    let modelID: ModelID
}

private enum WatchChatError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            message
        }
    }
}
