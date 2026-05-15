import Foundation
import SwiftUI
import PinesCore

@MainActor
final class PinesAppModel: ObservableObject, @unchecked Sendable {
    @Published var threads: [PinesThreadPreview]
    @Published var models: [PinesModelPreview]
    @Published var vaultItems: [PinesVaultItemPreview]
    @Published var settingsSections: [PinesSettingsSection]
    @Published var executionMode: AgentExecutionMode
    @Published var storeConfiguration: LocalStoreConfiguration
    @Published var selectedThemeTemplate: PinesThemeTemplate
    @Published var interfaceMode: PinesInterfaceMode
    @Published var serviceError: String?
    @Published var activeRunID: UUID?
    @Published var auditEvents: [AuditEvent]
    @Published var cloudProviders: [CloudProviderConfiguration]
    @Published var mcpServers: [MCPServerConfiguration] = []
    @Published var mcpTools: [MCPToolRecord] = []
    @Published var mcpResources: [MCPResourceRecord] = []
    @Published var mcpResourceTemplates: [MCPResourceTemplateRecord] = []
    @Published var mcpPrompts: [MCPPromptRecord] = []
    @Published var pendingToolApproval: ToolApprovalRequest?
    @Published var pendingMCPSamplingRequest: MCPSamplingRequest?
    @Published var pendingMCPSamplingResultReview: MCPSamplingResultReview?
    @Published var mcpSamplingPromptDraft = ""
    @Published var hapticSignal: PinesHapticSignal?
    @Published var modelDownloads: [ModelDownloadProgress] = []
    @Published var isSearchingModels = false
    @Published var modelSearchError: String?
    @Published var defaultModelID: ModelID?
    @Published var huggingFaceCredentialStatus = "Not configured"
    @Published var braveSearchCredentialStatus = "Not configured"
    private var didBootstrap = false
    private var isBootstrapping = false
    private var repositoryObservationTasks: [Task<Void, Never>] = []
    private var currentRunTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<ToolApprovalStatus, Never>?
    private var samplingContinuation: CheckedContinuation<Bool, Never>?
    private var samplingResultContinuation: CheckedContinuation<Bool, Never>?
    private var mcpSamplingRequestCountByServer: [MCPServerID: Int] = [:]
    private var isShowingModelDiscoveryResults = false

    private func setIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<PinesAppModel, Value>,
        _ value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    var modelSuggestions: [String] {
        Array(
            models
                .map(\.install.repository)
                .filter { !$0.isEmpty }
                .uniqued()
                .prefix(8)
        )
    }

    init(
        threads: [PinesThreadPreview] = [],
        models: [PinesModelPreview] = [],
        vaultItems: [PinesVaultItemPreview] = [],
        settingsSections: [PinesSettingsSection] = PinesStaticSettings.sections,
        executionMode: AgentExecutionMode = .preferLocal,
        storeConfiguration: LocalStoreConfiguration = .init(),
        selectedThemeTemplate: PinesThemeTemplate = .evergreen,
        interfaceMode: PinesInterfaceMode = .system,
        serviceError: String? = nil,
        activeRunID: UUID? = nil,
        auditEvents: [AuditEvent] = [],
        cloudProviders: [CloudProviderConfiguration] = []
    ) {
        self.threads = threads
        self.models = models
        self.vaultItems = vaultItems
        self.settingsSections = settingsSections
        self.executionMode = executionMode
        self.storeConfiguration = storeConfiguration
        self.selectedThemeTemplate = selectedThemeTemplate
        self.interfaceMode = interfaceMode
        self.serviceError = serviceError
        self.activeRunID = activeRunID
        self.auditEvents = auditEvents
        self.cloudProviders = cloudProviders
    }

    deinit {
        currentRunTask?.cancel()
        repositoryObservationTasks.forEach { $0.cancel() }
        approvalContinuation?.resume(returning: .denied)
        samplingContinuation?.resume(returning: false)
        samplingResultContinuation?.resume(returning: false)
    }

    func bootstrap(services: PinesAppServices) async {
        guard !didBootstrap else {
            await refreshAll(services: services)
            return
        }
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        try? await services.modelLifecycleService?.reconcileInterruptedDownloads()
        await refreshAll(services: services)
        observeRepositories(services: services)
        await services.mcpServerService?.start { [weak self] request, server in
            guard let self else {
                throw InferenceError.cancelled
            }
            return try await self.handleMCPSampling(request, server: server, services: services)
        }
        didBootstrap = true
    }

    func refreshAll(services: PinesAppServices) async {
        do {
            if let settingsRepository = services.settingsRepository {
                let settings = try await settingsRepository.loadSettings()
                setIfChanged(\.executionMode, settings.executionMode)
                setIfChanged(\.storeConfiguration, settings.storeConfiguration)
                setIfChanged(\.defaultModelID, settings.defaultModelID)
                setIfChanged(\.selectedThemeTemplate, PinesThemeTemplate(rawValue: settings.themeTemplate) ?? selectedThemeTemplate)
                setIfChanged(\.interfaceMode, PinesInterfaceMode(rawValue: settings.interfaceMode) ?? interfaceMode)
            }

            try await refreshModelPreviews(services: services)
            if defaultModelID.flatMap(installedModel(for:)) == nil {
                let normalizedDefault = preferredInstalledTextModel()?.modelID
                if defaultModelID != normalizedDefault {
                    defaultModelID = normalizedDefault
                    await saveSettings(services: services)
                }
            }

            if let conversationRepository = services.conversationRepository {
                let conversations = try await conversationRepository.listConversations()
                var previews = [PinesThreadPreview]()
                previews.reserveCapacity(conversations.count)
                for conversation in conversations {
                    let messages = try await conversationRepository.messages(in: conversation.id)
                    previews.append(Self.threadPreview(from: conversation, messages: messages))
                }
                setIfChanged(\.threads, previews)
            }

            if let vaultRepository = services.vaultRepository {
                setIfChanged(\.vaultItems, try await vaultRepository.listDocuments().map(Self.vaultPreview(from:)))
            }

            if let auditRepository = services.auditRepository {
                setIfChanged(\.auditEvents, try await auditRepository.list(category: nil, limit: 30))
            }

            if let cloudProviderRepository = services.cloudProviderRepository {
                setIfChanged(\.cloudProviders, try await cloudProviderRepository.listProviders())
            }

            if let mcpServerRepository = services.mcpServerRepository {
                setIfChanged(\.mcpServers, try await mcpServerRepository.listMCPServers())
                setIfChanged(\.mcpTools, try await mcpServerRepository.listMCPTools(serverID: nil))
                setIfChanged(\.mcpResources, try await mcpServerRepository.listMCPResources(serverID: nil))
                setIfChanged(\.mcpResourceTemplates, try await mcpServerRepository.listMCPResourceTemplates(serverID: nil))
                setIfChanged(\.mcpPrompts, try await mcpServerRepository.listMCPPrompts(serverID: nil))
            }

            await refreshCredentialStatuses(services: services)
            setIfChanged(\.serviceError, nil)
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    func createChat(services: PinesAppServices) async -> UUID? {
        do {
            guard let repository = services.conversationRepository else {
                serviceError = "Conversation repository is unavailable."
                return nil
            }
            let modelID = preferredInstalledTextModel()?.modelID
            let conversation = try await repository.createConversation(title: "New chat", defaultModelID: modelID)
            await refreshAll(services: services)
            emitHaptic(.primaryAction)
            return conversation.id
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            emitHaptic(.runFailed)
            return nil
        }
    }

    func startSending(_ draft: String, in threadID: UUID?, services: PinesAppServices) {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        emitHaptic(.sendCommitted)
        currentRunTask?.cancel()
        currentRunTask = Task { [weak self] in
            await self?.sendMessage(draft, in: threadID, services: services)
        }
    }

    func stopCurrentRun() {
        currentRunTask?.cancel()
        currentRunTask = nil
        activeRunID = nil
        emitHaptic(.runCancelled)
        resolvePendingToolApproval(.denied)
        resolvePendingMCPSampling(false)
        resolvePendingMCPSamplingResultReview(false)
    }

    func retryLastUserMessage(in thread: PinesThreadPreview, services: PinesAppServices) {
        guard let lastUser = thread.messages.last(where: { $0.role == .user }) else { return }
        startSending(lastUser.content, in: thread.id, services: services)
    }

    private func sendMessage(_ draft: String, in threadID: UUID?, services: PinesAppServices) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var runRepository: (any ConversationRepository)?
        var assistantMessageID: UUID?
        var accumulated = ""
        var tokenCount = 0
        var failureMessage: String?

        do {
            guard let repository = services.conversationRepository else {
                serviceError = "Conversation repository is unavailable."
                return
            }
            runRepository = repository

            let conversationID: UUID
            if let threadID {
                conversationID = threadID
            } else if let created = await createChat(services: services) {
                conversationID = created
            } else {
                return
            }

            let localInstall = preferredInstalledTextModel(for: conversationID)
            let availableTools = await services.toolRegistry.listSpecs()
            let cloudCandidate = cloudProviders
                .first { $0.enabledForAgents }
                .map { configuration in
                    (
                        configuration,
                        BYOKCloudInferenceProvider(configuration: configuration, secretStore: services.secretStore)
                    )
                }
            let route = services.executionRouter.routeChat(
                mode: executionMode,
                local: (services.mlxRuntime.localProviderID, services.mlxRuntime.capabilities),
                cloud: cloudCandidate.map { ($0.1.id, $0.1.capabilities) },
                requiresVision: false,
                requiresTools: !availableTools.isEmpty
            )
            let selectedProvider: any InferenceProvider
            let selectedProviderID: ProviderID
            let selectedModelID: ModelID
            switch route.destination {
            case .local:
                guard let localInstall else {
                    serviceError = "Download and select a local text model before starting local chat."
                    return
                }
                try await services.mlxRuntime.load(localInstall)
                selectedProvider = services.mlxRuntime
                selectedProviderID = services.mlxRuntime.localProviderID
                selectedModelID = localInstall.modelID
            case let .cloud(providerID):
                guard let cloudCandidate else {
                    serviceError = "No enabled cloud provider is configured for agents."
                    return
                }
                guard let cloudModelID = cloudCandidate.0.defaultModelID ?? localInstall?.modelID else {
                    serviceError = "Configure a default model for the selected cloud provider."
                    return
                }
                selectedProvider = cloudCandidate.1
                selectedProviderID = providerID
                selectedModelID = cloudModelID
            case let .denied(reason):
                serviceError = "\(reason)"
                return
            }

            let userMessage = ChatMessage(role: .user, content: trimmed)
            try await repository.appendMessage(userMessage, status: .complete, conversationID: conversationID, modelID: selectedModelID, providerID: nil)

            let assistantMessage = ChatMessage(role: .assistant, content: "")
            try await repository.appendMessage(assistantMessage, status: .streaming, conversationID: conversationID, modelID: selectedModelID, providerID: selectedProviderID)

            activeRunID = assistantMessage.id
            assistantMessageID = assistantMessage.id
            emitHaptic(.runAccepted)
            await refreshAll(services: services)

            let messages = try await repository.messages(in: conversationID)
            let vaultContext = await vaultContextMessage(for: trimmed, services: services)
            let mcpContext = await mcpResourceContextMessages(services: services)
            var requestMessages = messages.filter { $0.id != assistantMessage.id }
            if let vaultContext {
                requestMessages.insert(vaultContext.message, at: 0)
            }
            if !mcpContext.isEmpty {
                requestMessages.insert(contentsOf: mcpContext, at: 0)
            }
            let request = ChatRequest(
                modelID: selectedModelID,
                messages: requestMessages,
                allowsTools: !availableTools.isEmpty,
                availableTools: availableTools,
                vaultContextIDs: vaultContext?.documentIDs ?? []
            )
            let settings = try? await services.settingsRepository?.loadSettings()
            let session = AgentSession(
                title: "Chat",
                policy: AgentPolicy(
                    executionMode: settings?.executionMode ?? executionMode,
                    requiresConsentForNetwork: false,
                    requiresConsentForBrowser: false,
                    allowsCloudContext: selectedProviderID != services.mlxRuntime.localProviderID
                ),
                providerID: selectedProviderID
            )
            let runner = AgentRunner(
                toolRegistry: services.toolRegistry,
                policyGate: services.toolPolicyGate,
                auditRepository: services.auditRepository,
                approvalHandler: { [weak self] request in
                    await self?.requestToolApproval(request) ?? .denied
                }
            )
            let stream = runner.run(session: session, request: request, provider: selectedProvider)
            let generationStartedAt = Date()
            var streamHaptics = PinesStreamHapticGate()
            var didReceiveTerminalEvent = false

            for try await event in stream {
                guard !Task.isCancelled else { throw InferenceError.cancelled }
                switch event {
                case let .token(delta):
                    accumulated += delta.text
                    tokenCount += max(delta.tokenCount, 1)
                    if let hapticEvent = streamHaptics.event(tokenCount: tokenCount, content: accumulated) {
                        emitHaptic(hapticEvent)
                    }
                    serviceError = nil
                    try await repository.updateMessage(id: assistantMessage.id, content: accumulated, status: .streaming, tokenCount: tokenCount)
                case let .finish(finish):
                    didReceiveTerminalEvent = true
                    let status: MessageStatus = finish.reason == .cancelled ? .cancelled : .complete
                    if status == .complete && accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let message = finish.message ?? "The selected model finished without producing output."
                        failureMessage = message
                        try await repository.updateMessage(id: assistantMessage.id, content: message, status: .failed, tokenCount: tokenCount)
                        serviceError = message
                        emitHaptic(.runFailed)
                    } else {
                        try await repository.updateMessage(id: assistantMessage.id, content: accumulated, status: status, tokenCount: tokenCount)
                        serviceError = nil
                        emitHaptic(status == .cancelled ? .runCancelled : .runCompleted)
                    }
                case let .failure(failure):
                    didReceiveTerminalEvent = true
                    failureMessage = failure.message
                    try await repository.updateMessage(id: assistantMessage.id, content: failure.message, status: .failed, tokenCount: tokenCount)
                    emitHaptic(.runFailed)
                case let .metrics(metrics):
                    services.runtimeMetrics.recordGenerationMetrics(metrics, modelID: selectedModelID)
                case .toolCall:
                    emitHaptic(.streamMilestone)
                }
                await refreshAll(services: services)
            }

            if !didReceiveTerminalEvent {
                let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                if finalText.isEmpty {
                    let message = "The inference stream ended before the model produced output."
                    failureMessage = message
                    try await repository.updateMessage(id: assistantMessage.id, content: message, status: .failed, tokenCount: tokenCount)
                    serviceError = message
                    emitHaptic(.runFailed)
                } else {
                    try await repository.updateMessage(id: assistantMessage.id, content: accumulated, status: .complete, tokenCount: tokenCount)
                    serviceError = nil
                    emitHaptic(.runCompleted)
                }
                await refreshAll(services: services)
            }

            services.runtimeMetrics.recordGenerationFinished(
                modelID: selectedModelID,
                outputTokens: tokenCount,
                elapsedSeconds: Date().timeIntervalSince(generationStartedAt)
            )
            activeRunID = nil
            currentRunTask = nil
            await refreshAll(services: services)
        } catch InferenceError.cancelled {
            if let runRepository, let assistantMessageID {
                try? await runRepository.updateMessage(
                    id: assistantMessageID,
                    content: accumulated,
                    status: .cancelled,
                    tokenCount: tokenCount
                )
            }
            activeRunID = nil
            currentRunTask = nil
            emitHaptic(.runCancelled)
            await refreshAll(services: services)
        } catch {
            let message = failureMessage ?? error.localizedDescription
            if let runRepository, let assistantMessageID {
                try? await runRepository.updateMessage(
                    id: assistantMessageID,
                    content: accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? message : accumulated,
                    status: .failed,
                    tokenCount: tokenCount
                )
            }
            activeRunID = nil
            currentRunTask = nil
            serviceError = message
            emitHaptic(.runFailed)
            await refreshAll(services: services)
        }
    }

    private func vaultContextMessage(
        for query: String,
        services: PinesAppServices
    ) async -> (message: ChatMessage, documentIDs: [UUID])? {
        guard let vaultRepository = services.vaultRepository,
              let settings = try? await services.settingsRepository?.loadSettings(),
              let embeddingModelID = settings.embeddingModelID,
              let embeddingResult = try? await services.mlxRuntime.embed(
                  EmbeddingRequest(modelID: embeddingModelID, inputs: [query])
              ),
              let queryEmbedding = embeddingResult.vectors.first
        else {
            return nil
        }

        let startedAt = Date()
        guard let results = try? await vaultRepository.search(
            query: query,
            embedding: queryEmbedding,
            embeddingModelID: embeddingModelID,
            limit: 4
        ) else {
            return nil
        }
        services.runtimeMetrics.recordVaultRetrieval(
            resultCount: results.count,
            elapsedSeconds: Date().timeIntervalSince(startedAt)
        )
        guard !results.isEmpty else {
            return nil
        }

        let context = results.enumerated().map { index, result in
            "[\(index + 1)] \(result.document.title): \(result.snippet)"
        }.joined(separator: "\n")
        let documentIDs = results.map(\.document.id).uniqued()
        return (
            ChatMessage(
                role: .system,
                content: """
                Use this private local vault context when it is relevant. Cite entries by bracket number.
                \(context)
                """
            ),
            documentIDs
        )
    }

    private func mcpResourceContextMessages(services: PinesAppServices) async -> [ChatMessage] {
        let selected = mcpResources.filter(\.selectedForContext).prefix(4)
        guard !selected.isEmpty else { return [] }
        var sections = [String]()
        var attachments = [ChatAttachment]()
        for resource in selected {
            guard let contents = try? await services.mcpServerService?.readResource(resource) else {
                continue
            }
            for content in contents {
                if let text = content.text, !text.isEmpty {
                    sections.append("Resource \(resource.name) (\(resource.uri)):\n\(String(text.prefix(4_000)))")
                } else if let blob = content.blob {
                    do {
                        let attachment = try Self.mcpAttachment(
                            fromBase64: blob,
                            mimeType: content.mimeType,
                            fileNameHint: resource.uri
                        )
                        attachments.append(attachment)
                        sections.append("Resource \(resource.name) (\(resource.uri)) attached as \(attachment.fileName).")
                    } catch {
                        sections.append("Resource \(resource.name) (\(resource.uri)) was not attached: \(error.localizedDescription)")
                    }
                }
            }
        }
        guard !sections.isEmpty || !attachments.isEmpty else { return [] }
        var messages = [
            ChatMessage(
                role: .system,
                content: """
                Use this user-selected MCP resource context when relevant. Treat it as external, server-provided context.
                \(sections.joined(separator: "\n\n"))
                """
            )
        ]
        if !attachments.isEmpty {
            messages.append(
                ChatMessage(
                    role: .user,
                    content: "User-selected MCP resource attachments are available for this turn.",
                    attachments: attachments
                )
            )
        }
        return messages
    }

    private func preferredInstalledTextModel(for conversationID: UUID? = nil) -> ModelInstall? {
        let installedTextModels = models
            .map(\.install)
            .filter { install in
                install.state == .installed && install.modalities.contains(.text)
            }

        let preferredIDs = [
            defaultModelID,
            conversationID.flatMap { id in threads.first { $0.id == id }?.modelID },
        ].compactMap { $0 }

        for modelID in preferredIDs {
            if let install = installedTextModels.first(where: { $0.modelID == modelID }) {
                return install
            }
        }

        return installedTextModels.first
    }

    func saveSettings(services: PinesAppServices) async {
        do {
            let snapshot = AppSettingsSnapshot(
                executionMode: executionMode,
                storeConfiguration: storeConfiguration,
                defaultModelID: defaultModelID ?? preferredInstalledTextModel()?.modelID,
                embeddingModelID: models.first(where: { $0.install.modalities.contains(.embeddings) })?.install.modelID,
                requireToolApproval: true,
                braveSearchEnabled: braveSearchCredentialStatus.hasPrefix("Configured"),
                onboardingCompleted: true,
                themeTemplate: selectedThemeTemplate.rawValue,
                interfaceMode: interfaceMode.rawValue
            )
            try await services.settingsRepository?.saveSettings(snapshot)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func installModel(repository: String, services: PinesAppServices) async {
        do {
            guard let lifecycle = services.modelLifecycleService else {
                setIfChanged(\.serviceError, "Model lifecycle service is unavailable.")
                return
            }
            try await lifecycle.install(repository: repository)
            if defaultModelID == nil {
                let installs = try await services.modelInstallRepository?.listInstalledAndCuratedModels() ?? []
                if let installed = installs.first(where: { $0.repository.caseInsensitiveCompare(repository) == .orderedSame && $0.state == .installed }),
                   installed.modalities.contains(.text) {
                    setIfChanged(\.defaultModelID, installed.modelID)
                    await saveSettings(services: services)
                }
            }
            if !isShowingModelDiscoveryResults {
                try await refreshModelPreviews(services: services)
            }
        } catch InferenceError.cancelled {
            setIfChanged(\.serviceError, nil)
            if !isShowingModelDiscoveryResults {
                try? await refreshModelPreviews(services: services)
            }
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            if !isShowingModelDiscoveryResults {
                try? await refreshModelPreviews(services: services)
            }
        }
    }

    func deleteModel(repository: String, services: PinesAppServices) async {
        do {
            guard let lifecycle = services.modelLifecycleService else {
                setIfChanged(\.serviceError, "Model lifecycle service is unavailable.")
                return
            }
            try await lifecycle.delete(repository: repository)
            if defaultModelID?.rawValue.lowercased() == repository.lowercased() {
                setIfChanged(\.defaultModelID, nil)
                await saveSettings(services: services)
            }
            if !isShowingModelDiscoveryResults {
                try await refreshModelPreviews(services: services)
            }
        } catch InferenceError.cancelled {
            setIfChanged(\.serviceError, nil)
            if !isShowingModelDiscoveryResults {
                try? await refreshModelPreviews(services: services)
            }
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            if !isShowingModelDiscoveryResults {
                try? await refreshModelPreviews(services: services)
            }
        }
    }

    func cancelModelDownload(repository: String, services: PinesAppServices) async {
        do {
            guard let lifecycle = services.modelLifecycleService else {
                setIfChanged(\.serviceError, "Model lifecycle service is unavailable.")
                return
            }
            try await lifecycle.cancelDownload(repository: repository)
            if !isShowingModelDiscoveryResults {
                try await refreshModelPreviews(services: services)
            }
        } catch InferenceError.cancelled {
            setIfChanged(\.serviceError, nil)
            if !isShowingModelDiscoveryResults {
                try? await refreshModelPreviews(services: services)
            }
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            if !isShowingModelDiscoveryResults {
                try? await refreshModelPreviews(services: services)
            }
        }
    }

    func selectDefaultModel(_ model: PinesModelPreview, services: PinesAppServices) async {
        guard model.install.state == .installed else {
            setIfChanged(\.serviceError, "Download the model before selecting it as the default.")
            return
        }
        setIfChanged(\.defaultModelID, model.install.modelID)
        await saveSettings(services: services)
    }

    func searchModels(
        query: String,
        task: HubTask? = nil,
        verification: ModelVerificationState? = nil,
        installState: ModelInstallState? = nil,
        services: PinesAppServices
    ) async {
        setIfChanged(\.isSearchingModels, true)
        setIfChanged(\.modelSearchError, nil)
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, task == nil, verification == nil, installState == nil {
                isShowingModelDiscoveryResults = false
                try await refreshModelPreviews(services: services)
            } else {
                isShowingModelDiscoveryResults = true
                let token = try await services.huggingFaceCredentialService.readToken()
                let filters = ModelSearchFilters(query: trimmed, task: task, limit: 50)
                let remoteModels = try await services.modelCatalog.search(filters: filters, accessToken: token)
                let installed = try await services.modelInstallRepository?.listInstalledAndCuratedModels() ?? []
                let installedByRepository = Dictionary(uniqueKeysWithValues: installed.map { ($0.repository.lowercased(), $0) })
                let downloadByRepository = Self.latestDownloadByRepository(modelDownloads)
                let previews = remoteModels.compactMap { summary -> PinesModelPreview? in
                    let preflight = services.preflightClassifier.classify(summary.preflightInput)
                    let existingInstall = installedByRepository[summary.repository.lowercased()]
                    let install = existingInstall?.enriched(with: preflight)
                        ?? Self.install(from: summary, preflight: preflight)
                    guard preflight.verification != .unsupported || verification == .unsupported || installState == .unsupported else { return nil }
                    guard verification == nil || install.verification == verification else { return nil }
                    guard installState == nil || install.state == installState else { return nil }
                    return Self.modelPreview(
                        from: install,
                        runtime: services.mlxRuntime,
                        download: downloadByRepository[install.repository.lowercased()]
                    )
                }
                setIfChanged(\.models, previews)
            }
            setIfChanged(\.isSearchingModels, false)
            setIfChanged(\.serviceError, nil)
        } catch {
            setIfChanged(\.isSearchingModels, false)
            setIfChanged(\.modelSearchError, error.localizedDescription)
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    func preflightModel(repository: String, services: PinesAppServices) async {
        do {
            guard let lifecycle = services.modelLifecycleService else { return }
            let result = try await lifecycle.preflight(repository: repository)
            let install = ModelInstall(
                modelID: ModelID(rawValue: repository),
                displayName: repository.components(separatedBy: "/").last ?? repository,
                repository: repository,
                revision: "main",
                modalities: result.modalities,
                verification: result.verification,
                state: result.verification == .unsupported ? .unsupported : .remote,
                estimatedBytes: result.estimatedBytes,
                license: result.license,
                modelType: result.modelType,
                processorClass: result.processorClass
            )
            let download = Self.latestDownloadByRepository(modelDownloads)[repository.lowercased()]
            let preview = Self.modelPreview(from: install, runtime: services.mlxRuntime, download: download)
            if let index = models.firstIndex(where: { $0.install.repository.caseInsensitiveCompare(repository) == .orderedSame }) {
                models[index] = preview
            }
            setIfChanged(\.modelSearchError, nil)
        } catch {
            setIfChanged(\.modelSearchError, error.localizedDescription)
        }
    }

    func importVaultFile(_ url: URL, services: PinesAppServices) async {
        do {
            guard let ingestion = services.vaultIngestionService else {
                serviceError = "Vault ingestion service is unavailable."
                return
            }
            _ = try await ingestion.importFile(url: url)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func saveCloudProvider(
        kind: CloudProviderKind,
        displayName: String,
        baseURLString: String,
        defaultModelID: String,
        apiKey: String,
        enabledForAgents: Bool,
        services: PinesAppServices
    ) async {
        do {
            guard let service = services.cloudProviderService else {
                serviceError = "Cloud provider service is unavailable."
                return
            }
            guard let baseURL = URL(string: baseURLString) else {
                serviceError = "Cloud provider base URL is invalid."
                return
            }
            let provider = CloudProviderConfiguration(
                id: ProviderID(rawValue: displayName.lowercased().replacingOccurrences(of: " ", with: "-")),
                kind: kind,
                displayName: displayName,
                baseURL: baseURL,
                defaultModelID: defaultModelID.isEmpty ? nil : ModelID(rawValue: defaultModelID),
                keychainAccount: displayName.lowercased().replacingOccurrences(of: " ", with: "-"),
                enabledForAgents: enabledForAgents
            )
            try await service.saveProvider(provider, apiKey: apiKey.isEmpty ? nil : apiKey)
            _ = try? await service.validate(provider)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func validateCloudProvider(_ provider: CloudProviderConfiguration, services: PinesAppServices) async {
        do {
            guard let service = services.cloudProviderService else {
                serviceError = "Cloud provider service is unavailable."
                return
            }
            _ = try await service.validate(provider)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func deleteCloudProvider(_ provider: CloudProviderConfiguration, services: PinesAppServices) async {
        do {
            guard let service = services.cloudProviderService else {
                serviceError = "Cloud provider service is unavailable."
                return
            }
            try await service.deleteProvider(provider)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func saveMCPServer(
        existingID: MCPServerID? = nil,
        displayName: String,
        endpointURLString: String,
        authMode: MCPAuthMode,
        bearerToken: String,
        oauthAuthorizationURLString: String,
        oauthTokenURLString: String,
        oauthClientID: String,
        oauthScopes: String,
        oauthResource: String,
        resourcesEnabled: Bool,
        promptsEnabled: Bool,
        samplingEnabled: Bool,
        byokSamplingEnabled: Bool,
        subscriptionsEnabled: Bool,
        maxSamplingRequestsPerSession: Int,
        enabled: Bool,
        allowInsecureLocalHTTP: Bool,
        services: PinesAppServices
    ) async {
        do {
            guard let service = services.mcpServerService else {
                serviceError = "MCP server service is unavailable."
                return
            }
            guard let endpointURL = URL(string: endpointURLString), endpointURL.scheme != nil else {
                serviceError = "MCP endpoint URL is invalid."
                return
            }
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let serverID = existingID ?? MCPServerID(rawValue: MCPNameSanitizer.serverSlug(displayName: trimmedName, fallback: endpointURL.host(percentEncoded: false) ?? "mcp"))
            let server = MCPServerConfiguration(
                id: serverID,
                displayName: trimmedName.isEmpty ? serverID.rawValue : trimmedName,
                endpointURL: endpointURL,
                authMode: authMode,
                enabled: enabled,
                allowInsecureLocalHTTP: allowInsecureLocalHTTP,
                keychainAccount: serverID.rawValue,
                oauthAuthorizationURL: URL(string: oauthAuthorizationURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
                oauthTokenURL: URL(string: oauthTokenURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
                oauthClientID: oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                oauthScopes: oauthScopes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                oauthResource: oauthResource.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                resourcesEnabled: resourcesEnabled,
                promptsEnabled: promptsEnabled,
                samplingEnabled: samplingEnabled,
                byokSamplingEnabled: byokSamplingEnabled,
                subscriptionsEnabled: subscriptionsEnabled,
                maxSamplingRequestsPerSession: maxSamplingRequestsPerSession
            )
            try await service.saveServer(server, bearerToken: bearerToken.isEmpty ? nil : bearerToken)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
            await refreshAll(services: services)
        }
    }

    func discoverMCPOAuth(
        endpointURLString: String,
        allowInsecureLocalHTTP: Bool,
        services: PinesAppServices
    ) async -> MCPDiscoveredOAuthConfiguration? {
        do {
            guard let endpointURL = URL(string: endpointURLString), endpointURL.scheme != nil else {
                serviceError = "MCP endpoint URL is invalid."
                return nil
            }
            let temporary = MCPServerConfiguration(
                id: "oauth-discovery",
                displayName: "OAuth discovery",
                endpointURL: endpointURL,
                authMode: .oauthPKCE,
                enabled: false,
                allowInsecureLocalHTTP: allowInsecureLocalHTTP,
                keychainAccount: "oauth-discovery"
            )
            let discovery = try await MCPOAuthService(
                secretStore: services.secretStore,
                auditRepository: services.auditRepository
            ).discover(server: temporary)
            serviceError = nil
            return discovery
        } catch {
            serviceError = error.localizedDescription
            return nil
        }
    }

    func refreshMCPServer(_ server: MCPServerConfiguration, services: PinesAppServices) async {
        do {
            guard let service = services.mcpServerService else {
                serviceError = "MCP server service is unavailable."
                return
            }
            try await service.refresh(server)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
            await refreshAll(services: services)
        }
    }

    func deleteMCPServer(_ server: MCPServerConfiguration, services: PinesAppServices) async {
        do {
            guard let service = services.mcpServerService else {
                serviceError = "MCP server service is unavailable."
                return
            }
            try await service.deleteServer(server)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
            await refreshAll(services: services)
        }
    }

    func setMCPToolEnabled(_ tool: MCPToolRecord, enabled: Bool, services: PinesAppServices) async {
        do {
            guard let service = services.mcpServerService else {
                serviceError = "MCP server service is unavailable."
                return
            }
            try await service.setToolEnabled(serverID: tool.serverID, namespacedName: tool.namespacedName, enabled: enabled)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
            await refreshAll(services: services)
        }
    }

    func refreshMCPResources(_ server: MCPServerConfiguration, services: PinesAppServices) async {
        do {
            try await services.mcpServerService?.refreshResources(server)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func refreshMCPPrompts(_ server: MCPServerConfiguration, services: PinesAppServices) async {
        do {
            try await services.mcpServerService?.refreshPrompts(server)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func setMCPResourceSelected(_ resource: MCPResourceRecord, selected: Bool, services: PinesAppServices) async {
        do {
            try await services.mcpServerService?.setResourceSelected(resource, selected: selected)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func setMCPResourceSubscribed(_ resource: MCPResourceRecord, subscribed: Bool, services: PinesAppServices) async {
        do {
            try await services.mcpServerService?.setResourceSubscribed(resource, subscribed: subscribed)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func previewMCPResource(_ resource: MCPResourceRecord, services: PinesAppServices) async -> String? {
        do {
            guard let contents = try await services.mcpServerService?.readResource(resource) else {
                return nil
            }
            let preview = contents.map { content in
                if let text = content.text, !text.isEmpty {
                    return String(text.prefix(6_000))
                }
                if let blob = content.blob {
                    do {
                        let attachment = try Self.mcpAttachment(
                            fromBase64: blob,
                            mimeType: content.mimeType,
                            fileNameHint: resource.uri
                        )
                        return "[Attachment: \(attachment.fileName), \(attachment.contentType), \(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))]"
                    } catch {
                        return "[Blocked binary resource: \(error.localizedDescription)]"
                    }
                }
                return "[Empty resource content]"
            }.joined(separator: "\n\n")
            return preview.isEmpty ? "[Empty resource content]" : preview
        } catch {
            serviceError = error.localizedDescription
            return nil
        }
    }

    func useMCPPrompt(_ prompt: MCPPromptRecord, arguments: [String: String] = [:], services: PinesAppServices) async {
        do {
            let trimmedArguments = arguments.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let missing = prompt.arguments.first { ($0.required ?? false) && (trimmedArguments[$0.name]?.isEmpty ?? true) }
            if let missing {
                serviceError = "Missing MCP prompt argument: \(missing.name)."
                return
            }
            let completeArguments = Dictionary(uniqueKeysWithValues: prompt.arguments.map { argument in
                (argument.name, trimmedArguments[argument.name] ?? "")
            })
            guard let result = try await services.mcpServerService?.getPrompt(prompt, arguments: completeArguments) else { return }
            let text = Self.chatText(from: result.messages)
            startSending(text, in: nil, services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func connectMCPOAuth(_ server: MCPServerConfiguration, services: PinesAppServices) async {
        do {
            try await MCPOAuthService(secretStore: services.secretStore, auditRepository: services.auditRepository).connect(server: server)
            await refreshMCPServer(server, services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func disconnectMCPOAuth(_ server: MCPServerConfiguration, services: PinesAppServices) async {
        do {
            try await MCPOAuthService(secretStore: services.secretStore, auditRepository: services.auditRepository).disconnect(server: server)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func saveHuggingFaceToken(_ token: String, services: PinesAppServices) async {
        do {
            try await services.huggingFaceCredentialService.saveToken(token)
            huggingFaceCredentialStatus = try await services.huggingFaceCredentialService.validateToken(token)
            serviceError = nil
        } catch {
            huggingFaceCredentialStatus = "Validation failed."
            serviceError = error.localizedDescription
        }
    }

    func validateHuggingFaceToken(services: PinesAppServices) async {
        do {
            huggingFaceCredentialStatus = try await services.huggingFaceCredentialService.validateToken()
            serviceError = nil
        } catch {
            huggingFaceCredentialStatus = "Validation failed."
            serviceError = error.localizedDescription
        }
    }

    func deleteHuggingFaceToken(services: PinesAppServices) async {
        do {
            try await services.huggingFaceCredentialService.deleteToken()
            huggingFaceCredentialStatus = "Not configured"
            serviceError = nil
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func saveBraveSearchKey(_ key: String, services: PinesAppServices) async {
        do {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                try await services.secretStore.delete(service: BraveSearchTool.keychainService, account: BraveSearchTool.keychainAccount)
                braveSearchCredentialStatus = "Not configured"
                await saveSettings(services: services)
                return
            }
            try await services.secretStore.write(trimmed, service: BraveSearchTool.keychainService, account: BraveSearchTool.keychainAccount)
            braveSearchCredentialStatus = "Configured"
            await saveSettings(services: services)
            serviceError = nil
        } catch {
            serviceError = error.localizedDescription
        }
    }

    private func observeRepositories(services: PinesAppServices) {
        guard repositoryObservationTasks.isEmpty else { return }

        if let modelRepository = services.modelInstallRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await installs in modelRepository.observeInstalledAndCuratedModels() {
                    let downloads = await MainActor.run { self?.modelDownloads ?? [] }
                    let downloadByRepository = Self.latestDownloadByRepository(downloads)
                    let installByRepository = Dictionary(uniqueKeysWithValues: installs.map { ($0.repository.lowercased(), $0) })
                    await MainActor.run {
                        guard let self else { return }
                        if self.isShowingModelDiscoveryResults {
                            self.setIfChanged(\.models, self.models.map { preview in
                                let key = preview.install.repository.lowercased()
                                if let install = installByRepository[key] {
                                    return Self.modelPreview(
                                        from: install,
                                        runtime: services.mlxRuntime,
                                        download: downloadByRepository[key]
                                    )
                                }

                                var remoteInstall = preview.install
                                if remoteInstall.state != .unsupported {
                                    remoteInstall.state = .remote
                                }
                                remoteInstall.localURL = nil
                                return Self.modelPreview(
                                    from: remoteInstall,
                                    runtime: services.mlxRuntime,
                                    download: downloadByRepository[key]
                                )
                            })
                        } else {
                            self.setIfChanged(\.models, installs.map { install in
                                Self.modelPreview(
                                    from: install,
                                    runtime: services.mlxRuntime,
                                    download: downloadByRepository[install.repository.lowercased()]
                                )
                            })
                        }
                    }
                }
            })
        }

        if let downloadRepository = services.modelDownloadRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await downloads in downloadRepository.observeDownloads() {
                    await MainActor.run {
                        guard let self else { return }
                        self.setIfChanged(\.modelDownloads, downloads)
                        let downloadByRepository = Self.latestDownloadByRepository(downloads)
                        self.setIfChanged(\.models, self.models.map { preview in
                            Self.modelPreview(
                                from: preview.install,
                                runtime: services.mlxRuntime,
                                download: downloadByRepository[preview.install.repository.lowercased()]
                            )
                        })
                    }
                }
            })
        }

        if let settingsRepository = services.settingsRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await settings in settingsRepository.observeSettings() {
                    await MainActor.run {
                        self?.setIfChanged(\.defaultModelID, settings.defaultModelID)
                        self?.setIfChanged(\.executionMode, settings.executionMode)
                        self?.setIfChanged(\.storeConfiguration, settings.storeConfiguration)
                        if let theme = PinesThemeTemplate(rawValue: settings.themeTemplate) {
                            self?.setIfChanged(\.selectedThemeTemplate, theme)
                        }
                        if let mode = PinesInterfaceMode(rawValue: settings.interfaceMode) {
                            self?.setIfChanged(\.interfaceMode, mode)
                        }
                    }
                }
            })
        }

        if let conversationRepository = services.conversationRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await conversations in conversationRepository.observeConversations() {
                    var previews = [PinesThreadPreview]()
                    previews.reserveCapacity(conversations.count)
                    for conversation in conversations {
                        guard let messages = try? await conversationRepository.messages(in: conversation.id) else { continue }
                        let preview = await MainActor.run {
                            Self.threadPreview(from: conversation, messages: messages)
                        }
                        previews.append(preview)
                    }
                    await MainActor.run {
                        self?.setIfChanged(\.threads, previews)
                    }
                }
            })
        }

        if let vaultRepository = services.vaultRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await documents in vaultRepository.observeDocuments() {
                    await MainActor.run {
                        self?.setIfChanged(\.vaultItems, documents.map(Self.vaultPreview(from:)))
                    }
                }
            })
        }

        if let auditRepository = services.auditRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await events in auditRepository.observeRecent(limit: 30) {
                    await MainActor.run {
                        self?.setIfChanged(\.auditEvents, events)
                    }
                }
            })
        }

        if let cloudProviderRepository = services.cloudProviderRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await providers in cloudProviderRepository.observeProviders() {
                    await MainActor.run {
                        self?.setIfChanged(\.cloudProviders, providers)
                    }
                }
            })
        }

        if let mcpServerRepository = services.mcpServerRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await servers in mcpServerRepository.observeMCPServers() {
                    await MainActor.run {
                        self?.setIfChanged(\.mcpServers, servers)
                    }
                }
            })
            repositoryObservationTasks.append(Task { [weak self] in
                for await tools in mcpServerRepository.observeMCPTools() {
                    await MainActor.run {
                        self?.setIfChanged(\.mcpTools, tools)
                    }
                }
            })
            repositoryObservationTasks.append(Task { [weak self] in
                for await resources in mcpServerRepository.observeMCPResources() {
                    await MainActor.run {
                        self?.setIfChanged(\.mcpResources, resources)
                    }
                }
            })
            repositoryObservationTasks.append(Task { [weak self] in
                for await prompts in mcpServerRepository.observeMCPPrompts() {
                    await MainActor.run {
                        self?.setIfChanged(\.mcpPrompts, prompts)
                    }
                }
            })
        }
    }

    func requestToolApproval(_ request: ToolApprovalRequest) async -> ToolApprovalStatus {
        pendingToolApproval = request
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    func resolvePendingToolApproval(_ status: ToolApprovalStatus) {
        pendingToolApproval = nil
        emitHaptic(status == .approved ? .primaryAction : .runCancelled)
        approvalContinuation?.resume(returning: status)
        approvalContinuation = nil
    }

    func resolvePendingMCPSampling(_ approved: Bool) {
        pendingMCPSamplingRequest = nil
        samplingContinuation?.resume(returning: approved)
        samplingContinuation = nil
    }

    func resolvePendingMCPSamplingResultReview(_ approved: Bool) {
        pendingMCPSamplingResultReview = nil
        samplingResultContinuation?.resume(returning: approved)
        samplingResultContinuation = nil
    }

    private func requestMCPSamplingApproval(_ request: MCPSamplingRequest) async -> Bool {
        pendingMCPSamplingRequest = request
        mcpSamplingPromptDraft = Self.chatText(from: request.messages)
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            samplingContinuation = continuation
        }
    }

    private func requestMCPSamplingResultApproval(_ result: MCPSamplingResult, serverID: MCPServerID) async -> Bool {
        pendingMCPSamplingResultReview = MCPSamplingResultReview(
            serverID: serverID,
            result: result,
            summary: Self.samplingResultSummary(result)
        )
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            samplingResultContinuation = continuation
        }
    }

    private func emitHaptic(_ event: PinesHapticEvent) {
        hapticSignal = PinesHapticSignal(event: event)
    }

    private func handleMCPSampling(
        _ request: MCPSamplingRequest,
        server: MCPServerConfiguration,
        services: PinesAppServices
    ) async throws -> MCPSamplingResult {
        guard server.samplingEnabled else {
            throw InferenceError.unsupportedCapability("Sampling is disabled for this MCP server.")
        }
        let usedRequests = mcpSamplingRequestCountByServer[server.id, default: 0]
        guard usedRequests < server.maxSamplingRequestsPerSession else {
            throw InferenceError.invalidRequest("MCP sampling request limit reached for \(server.displayName).")
        }
        await auditMCPSampling(
            server: server,
            summary: "MCP sampling requested by \(server.displayName)",
            request: request,
            services: services
        )
        let approved = await requestMCPSamplingApproval(request)
        await auditMCPSampling(
            server: server,
            summary: approved ? "Approved MCP sampling for \(server.displayName)" : "Denied MCP sampling for \(server.displayName)",
            request: request,
            services: services
        )
        guard approved else {
            throw AgentError.permissionDenied("MCP sampling request was denied.")
        }
        mcpSamplingRequestCountByServer[server.id, default: 0] += 1
        let editedPrompt = mcpSamplingPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = try Self.chatMessages(
            from: request.messages,
            systemPrompt: request.systemPrompt,
            editedPrompt: editedPrompt.isEmpty ? nil : editedPrompt
        )
        let tools = try request.tools.map {
            try AnyToolSpec(
                name: $0.name,
                version: "mcp-sampling",
                description: $0.description ?? "MCP sampling tool \($0.name).",
                inputJSONSchema: $0.inputSchema
            )
        }
        let requiresVision = messages.contains { message in
            message.attachments.contains { $0.kind == .image }
        }
        let sampling = ChatSampling(
            maxTokens: request.maxTokens ?? 512,
            temperature: Float(request.temperature ?? 0.6)
        )

        if let localModelID = rankedLocalModelID(for: request, requiresVision: requiresVision),
           let localInstall = installedModel(for: localModelID) {
            try await services.mlxRuntime.load(localInstall)
            let localChatRequest = ChatRequest(
                modelID: localModelID,
                messages: messages,
                sampling: sampling,
                allowsTools: !tools.isEmpty,
                availableTools: tools
            )

            if let result = try? await runMCPSampling(localChatRequest, provider: services.mlxRuntime, modelID: localModelID) {
                let returnApproved = await requestMCPSamplingResultApproval(result, serverID: server.id)
                await auditMCPSampling(
                    server: server,
                    summary: returnApproved ? "Returned MCP sampling result to \(server.displayName)" : "Blocked MCP sampling result for \(server.displayName)",
                    request: request,
                    result: result,
                    services: services
                )
                guard returnApproved else {
                    throw AgentError.permissionDenied("MCP sampling result was not approved for return.")
                }
                return result
            }
        }

        guard server.byokSamplingEnabled,
              let cloudProvider = rankedCloudProvider(for: request, requiresVision: requiresVision, requiresTools: !tools.isEmpty)
        else {
            throw InferenceError.providerUnavailable(services.mlxRuntime.localProviderID)
        }
        guard let cloudModelID = cloudProvider.defaultModelID else {
            throw InferenceError.invalidRequest("The selected cloud provider does not define a default model.")
        }
        let cloudChatRequest = ChatRequest(
            modelID: cloudModelID,
            messages: messages,
            sampling: sampling,
            allowsTools: !tools.isEmpty,
            availableTools: tools
        )
        let provider = BYOKCloudInferenceProvider(configuration: cloudProvider, secretStore: services.secretStore)
        let result = try await runMCPSampling(
            cloudChatRequest,
            provider: provider,
            modelID: cloudModelID
        )
        let returnApproved = await requestMCPSamplingResultApproval(result, serverID: server.id)
        await auditMCPSampling(
            server: server,
            summary: returnApproved ? "Returned MCP sampling result to \(server.displayName)" : "Blocked MCP sampling result for \(server.displayName)",
            request: request,
            result: result,
            services: services
        )
        guard returnApproved else {
            throw AgentError.permissionDenied("MCP sampling result was not approved for return.")
        }
        return result
    }

    private func rankedLocalModelID(for request: MCPSamplingRequest, requiresVision: Bool) -> ModelID? {
        let preference = MCPModelPreferenceProfile(json: request.modelPreferences)
        let candidates = models
            .map(\.install)
            .filter { install in
                install.state == .installed
                    && install.modalities.contains(.text)
                    && (!requiresVision || install.modalities.contains(.vision))
            }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { left, right in
            samplingModelScore(install: left, preference: preference) < samplingModelScore(install: right, preference: preference)
        }?.modelID
    }

    private func installedModel(for modelID: ModelID) -> ModelInstall? {
        models
            .map(\.install)
            .first { install in
                install.modelID == modelID && install.state == .installed
            }
    }

    private func rankedCloudProvider(for request: MCPSamplingRequest, requiresVision: Bool, requiresTools: Bool) -> CloudProviderConfiguration? {
        let preference = MCPModelPreferenceProfile(json: request.modelPreferences)
        let candidates = cloudProviders.filter { provider in
            provider.enabledForAgents
                && provider.capabilities.textGeneration
                && (!requiresVision || provider.capabilities.vision)
                && (!requiresTools || provider.capabilities.toolCalling)
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { left, right in
            samplingCloudScore(provider: left, preference: preference) < samplingCloudScore(provider: right, preference: preference)
        }
    }

    private func samplingModelScore(install: ModelInstall, preference: MCPModelPreferenceProfile) -> Double {
        let searchable = [
            install.modelID.rawValue,
            install.displayName,
            install.repository,
            install.modelType ?? "",
            install.processorClass ?? "",
        ].joined(separator: " ").lowercased()
        var score = 10.0
        for hint in preference.hints {
            let normalizedHint = hint.lowercased()
            if searchable == normalizedHint {
                score += 120
            } else if searchable.contains(normalizedHint) {
                score += 60
            }
        }
        if install.modelID == defaultModelID {
            score += 12
        }
        let parameterScale = min(Double(install.parameterCount ?? 0) / 10_000_000_000, 1)
        let byteScale = min(Double(install.estimatedBytes ?? 0) / 10_000_000_000, 1)
        score += preference.intelligencePriority * parameterScale * 24
        score += preference.speedPriority * (1 - max(parameterScale, byteScale)) * 18
        score += preference.costPriority * (1 - byteScale) * 12
        return score
    }

    private func samplingCloudScore(provider: CloudProviderConfiguration, preference: MCPModelPreferenceProfile) -> Double {
        let searchable = [
            provider.displayName,
            provider.kind.rawValue,
            provider.baseURL.host(percentEncoded: false) ?? "",
            provider.defaultModelID?.rawValue ?? "",
        ].joined(separator: " ").lowercased()
        var score = 5.0
        for hint in preference.hints {
            let normalizedHint = hint.lowercased()
            if searchable == normalizedHint {
                score += 120
            } else if searchable.contains(normalizedHint) {
                score += 60
            }
        }
        score += preference.intelligencePriority * 8
        score += preference.speedPriority * (provider.kind == .openAICompatible ? 6 : 4)
        score -= preference.costPriority * 4
        return score
    }

    private func auditMCPSampling(
        server: MCPServerConfiguration,
        summary: String,
        request: MCPSamplingRequest,
        result: MCPSamplingResult? = nil,
        services: PinesAppServices
    ) async {
        let payload = [
            "server=\(server.id.rawValue)",
            "messages=\(request.messages.count)",
            "tools=\(request.tools.count)",
            "maxTokens=\(request.maxTokens ?? 512)",
            "includeContext=\(request.includeContext ?? "unspecified")",
            result.map { "result=\(Self.samplingResultKind($0))" },
        ].compactMap { $0 }.joined(separator: ", ")
        try? await services.auditRepository?.append(
            AuditEvent(
                category: .consent,
                summary: summary,
                redactedPayload: payload,
                networkDomains: server.endpointURL.host(percentEncoded: false).map { [$0] } ?? []
            )
        )
    }

    private static func samplingResultKind(_ result: MCPSamplingResult) -> String {
        switch result.content {
        case .text:
            return "text"
        case .toolUse:
            return "tool_use"
        case .toolResult:
            return "tool_result"
        case .resource:
            return "resource"
        case .image:
            return "image"
        case .audio:
            return "audio"
        case .unknown:
            return "unknown"
        }
    }

    private func runMCPSampling(
        _ request: ChatRequest,
        provider: any InferenceProvider,
        modelID: ModelID
    ) async throws -> MCPSamplingResult {
        let stream = try await provider.streamEvents(request)
        var text = ""
        var stopReason = "endTurn"
        for try await event in stream {
            switch event {
            case let .token(delta):
                text += delta.text
            case let .toolCall(toolCall):
                let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(toolCall.argumentsFragment.utf8))) ?? .object([:])
                return MCPSamplingResult(
                    content: .toolUse(id: toolCall.id, name: toolCall.name, input: input),
                    model: modelID.rawValue,
                    stopReason: "toolUse"
                )
            case let .finish(finish):
                stopReason = finish.reason == .length ? "maxTokens" : "endTurn"
            case let .failure(failure):
                throw InferenceError.invalidRequest(failure.message)
            case .metrics:
                break
            }
        }
        return MCPSamplingResult(content: .text(text), model: modelID.rawValue, stopReason: stopReason)
    }

    private static func chatMessages(from messages: [MCPPromptMessage], systemPrompt: String?, editedPrompt: String? = nil) throws -> [ChatMessage] {
        var chatMessages = [ChatMessage]()
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatMessages.append(ChatMessage(role: .system, content: systemPrompt))
        }
        if let editedPrompt, !editedPrompt.isEmpty {
            chatMessages.append(ChatMessage(role: .user, content: editedPrompt))
            return chatMessages
        }
        for message in messages {
            let role: ChatRole = message.role == .assistant ? .assistant : .user
            let converted = try textAndAttachments(from: message.content)
            chatMessages.append(ChatMessage(role: role, content: converted.text, attachments: converted.attachments))
        }
        return chatMessages
    }

    private static func samplingResultSummary(_ result: MCPSamplingResult) -> String {
        switch result.content {
        case let .text(text):
            return text
        case let .toolUse(id, name, _):
            return "Tool use \(id): \(name)"
        case let .toolResult(toolUseID, content):
            let text = (try? textAndAttachments(from: content).text) ?? ""
            return "Tool result \(toolUseID)\n\(text)"
        case let .resource(resource):
            return resource.text ?? "[Resource: \(resource.uri)]"
        case let .image(_, mimeType):
            return "[Image: \(mimeType)]"
        case let .audio(_, mimeType):
            return "[Audio: \(mimeType)]"
        case .unknown:
            return "[Unsupported sampling result content]"
        }
    }

    private static func chatText(from messages: [MCPPromptMessage]) -> String {
        messages.map { message in
            (try? textAndAttachments(from: message.content).text) ?? ""
        }.joined(separator: "\n\n")
    }

    private static func textAndAttachments(from contents: [MCPMessageContent]) throws -> (text: String, attachments: [ChatAttachment]) {
        var parts = [String]()
        var attachments = [ChatAttachment]()
        for content in contents {
            switch content {
            case let .text(text):
                parts.append(text)
            case let .resource(resource):
                if let text = resource.text {
                    parts.append(text)
                } else if let blob = resource.blob {
                    let attachment = try mcpAttachment(
                        fromBase64: blob,
                        mimeType: resource.mimeType,
                        fileNameHint: resource.uri
                    )
                    attachments.append(attachment)
                    parts.append("[Embedded resource attachment: \(attachment.fileName), \(attachment.contentType)]")
                }
            case let .image(data, mimeType):
                let attachment = try mcpAttachment(fromBase64: data, mimeType: mimeType, fileNameHint: "sampling-image")
                guard attachment.kind == .image else {
                    throw InferenceError.unsupportedCapability("MCP image content used unsupported MIME type \(mimeType).")
                }
                attachments.append(attachment)
                parts.append("[Image: \(attachment.contentType)]")
            case .audio:
                throw InferenceError.unsupportedCapability("Audio sampling content is not supported yet.")
            case let .toolUse(id, name, _):
                parts.append("[Tool use \(id): \(name)]")
            case let .toolResult(toolUseID, content):
                let nested = try textAndAttachments(from: content)
                parts.append("[Tool result \(toolUseID)]\n\(nested.text)")
            case .unknown:
                break
            }
        }
        return (parts.joined(separator: "\n\n"), attachments)
    }

    private static let maxMCPAttachmentBytes = 10 * 1024 * 1024

    private static func mcpAttachment(fromBase64 data: String, mimeType: String?, fileNameHint: String) throws -> ChatAttachment {
        guard let decoded = Data(base64Encoded: data) else {
            throw InferenceError.invalidRequest("MCP resource content was not valid base64.")
        }
        guard decoded.count <= maxMCPAttachmentBytes else {
            throw InferenceError.invalidRequest("MCP resource exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(maxMCPAttachmentBytes), countStyle: .file)) attachment limit.")
        }
        let normalizedMimeType = (mimeType ?? "application/octet-stream").lowercased()
        guard let policy = mcpAttachmentPolicy(for: normalizedMimeType) else {
            throw InferenceError.unsupportedCapability("MCP resource MIME type \(normalizedMimeType) is not allowed as an attachment.")
        }
        let safeName = sanitizedMCPFileName(from: fileNameHint, fallbackExtension: policy.fileExtension)
        let url = FileManager.default.temporaryDirectory.appending(path: "mcp-\(UUID().uuidString)-\(safeName)")
        try decoded.write(to: url)
        return ChatAttachment(
            kind: policy.kind,
            fileName: url.lastPathComponent,
            contentType: normalizedMimeType,
            localURL: url,
            byteCount: decoded.count
        )
    }

    private static func mcpAttachmentPolicy(for mimeType: String) -> (kind: AttachmentKind, fileExtension: String)? {
        switch mimeType {
        case "image/png":
            return (.image, "png")
        case "image/jpeg", "image/jpg":
            return (.image, "jpg")
        case "image/webp":
            return (.image, "webp")
        case "image/gif":
            return (.image, "gif")
        case "application/pdf":
            return (.document, "pdf")
        case "text/plain":
            return (.document, "txt")
        case "text/markdown", "text/x-markdown":
            return (.document, "md")
        case "application/json":
            return (.document, "json")
        case "text/csv":
            return (.document, "csv")
        default:
            return nil
        }
    }

    private static func sanitizedMCPFileName(from hint: String, fallbackExtension: String) -> String {
        let candidate = hint
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "resource"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitizedScalars = candidate.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
        var name = sanitizedScalars.joined().trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        if name.isEmpty {
            name = "resource"
        }
        if !name.lowercased().hasSuffix(".\(fallbackExtension)") {
            name += ".\(fallbackExtension)"
        }
        return String(name.prefix(96))
    }

    private func refreshCredentialStatuses(services: PinesAppServices) async {
        setIfChanged(\.huggingFaceCredentialStatus, (try? await services.huggingFaceCredentialService.readToken())?.isEmpty == false
            ? "Configured"
            : "Not configured")
        setIfChanged(\.braveSearchCredentialStatus, (try? await services.secretStore.read(
            service: BraveSearchTool.keychainService,
            account: BraveSearchTool.keychainAccount
        ))?.isEmpty == false ? "Configured" : "Not configured")
    }

    private func refreshModelPreviews(services: PinesAppServices) async throws {
        let downloads = try await services.modelDownloadRepository?.listDownloads() ?? []
        setIfChanged(\.modelDownloads, downloads)

        guard let modelRepository = services.modelInstallRepository else {
            setIfChanged(\.models, [])
            return
        }

        let downloadByRepository = Self.latestDownloadByRepository(downloads)
        let previews = try await modelRepository
            .listInstalledAndCuratedModels()
            .map { install in
                Self.modelPreview(
                    from: install,
                    runtime: services.mlxRuntime,
                    download: downloadByRepository[install.repository.lowercased()]
                )
            }
        setIfChanged(\.models, previews)
    }

    private static func threadPreview(from record: ConversationRecord, messages: [ChatMessage]) -> PinesThreadPreview {
        let lastMessage = messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return PinesThreadPreview(
            id: record.id,
            title: record.title,
            modelName: record.defaultModelID?.rawValue.components(separatedBy: "/").last ?? "No model selected",
            modelID: record.defaultModelID ?? ModelID(rawValue: "unselected-local-model"),
            lastMessage: lastMessage?.isEmpty == false ? lastMessage! : "No messages yet.",
            messages: messages,
            status: record.archived ? .archived : .local,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            tokenCount: messages.reduce(0) { $0 + max(1, $1.content.split(separator: " ").count) }
        )
    }

    private static func install(from summary: RemoteModelSummary, preflight: ModelPreflightResult) -> ModelInstall {
        return ModelInstall(
            modelID: ModelID(rawValue: summary.repository),
            displayName: summary.repository.components(separatedBy: "/").last ?? summary.repository,
            repository: summary.repository,
            modalities: preflight.modalities.isEmpty ? Self.modalities(from: summary) : preflight.modalities,
            verification: preflight.verification,
            state: preflight.verification == .unsupported ? .unsupported : .remote,
            estimatedBytes: preflight.estimatedBytes > 0 ? preflight.estimatedBytes : nil,
            license: preflight.license,
            modelType: preflight.modelType,
            processorClass: preflight.processorClass
        )
    }

    private static func modalities(from summary: RemoteModelSummary) -> Set<ModelModality> {
        if summary.tags.contains(where: { $0 == "feature-extraction" || $0 == "sentence-similarity" || $0 == "sentence-transformers" }) {
            return [.embeddings]
        }
        switch summary.task {
        case .imageTextToText:
            return [.text, .vision]
        case .featureExtraction, .sentenceSimilarity:
            return [.embeddings]
        case .textGeneration, .none:
            return [.text]
        }
    }

    private static func modelPreview(
        from install: ModelInstall,
        runtime: MLXRuntimeBridge,
        download: ModelDownloadProgress? = nil
    ) -> PinesModelPreview {
        let status: PinesModelStatus
        switch download?.status {
        case .queued, .downloading, .verifying, .installing:
            status = .indexing
        case .failed:
            status = .failed
        case .cancelled, .installed, .none:
            switch install.state {
            case .installed:
                status = .ready
            case .downloading:
                status = .indexing
            case .failed:
                status = .failed
            case .unsupported:
                status = .unsupported
            case .remote:
                status = .available
            }
        }

        let readiness: Double
        if download?.status == .cancelled {
            readiness = install.state == .installed ? 1 : 0
        } else if let download {
            if let total = download.totalBytes, total > 0 {
                readiness = min(0.98, max(0, Double(download.bytesReceived) / Double(total)))
            } else {
                readiness = status == .ready ? 1 : 0.1
            }
        } else {
            readiness = install.state == .installed ? 1 : (install.state == .downloading ? 0.5 : 0)
        }

        let compatibilityWarnings: [String]
        switch install.verification {
        case .unsupported:
            compatibilityWarnings = ["This repository is not compatible with the current MLX runtime profile."]
        case .experimental:
            compatibilityWarnings = ["This repository looks compatible but needs device verification before production use."]
        case .installable:
            compatibilityWarnings = install.state == .remote ? ["Compatibility is based on Hugging Face metadata until preflight completes."] : []
        case .verified:
            compatibilityWarnings = []
        }

        return PinesModelPreview(
            id: install.id,
            install: install,
            runtimeProfile: runtime.defaultRuntimeProfile(for: install),
            name: install.displayName,
            family: install.modelType ?? install.modalities.map(\.rawValue).sorted().joined(separator: ", "),
            footprint: install.estimatedBytes.map(Self.byteLabel) ?? download?.totalBytes.map(Self.byteLabel) ?? "Remote",
            contextWindow: runtime.capabilities.maxContextTokens.map { "\($0 / 1000)K" } ?? "Unknown",
            runtime: install.modalities.contains(.embeddings) ? "MLX Embedders" : (install.modalities.contains(.vision) ? "MLX VLM" : "MLX"),
            status: status,
            capabilities: install.modalities.map(\.rawValue).sorted(),
            readiness: readiness,
            downloadProgress: download,
            compatibilityWarnings: compatibilityWarnings
        )
    }

    private static func latestDownloadByRepository(_ downloads: [ModelDownloadProgress]) -> [String: ModelDownloadProgress] {
        Dictionary(grouping: downloads, by: { $0.repository.lowercased() }).mapValues { values in
            values.sorted { $0.updatedAt > $1.updatedAt }.first!
        }
    }

    private static func vaultPreview(from record: VaultDocumentRecord) -> PinesVaultItemPreview {
        let kind: PinesVaultKind
        switch record.sourceType.lowercased() {
        case "image", "photo":
            kind = .image
        case "key":
            kind = .key
        case "note":
            kind = .note
        default:
            kind = .document
        }

        return PinesVaultItemPreview(
            id: record.id,
            title: record.title,
            kind: kind,
            detail: "\(record.chunkCount) indexed chunks",
            chunks: [],
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            sensitivity: .local,
            linkedThreads: 0
        )
    }

    private static func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension ModelInstall {
    func enriched(with preflight: ModelPreflightResult) -> ModelInstall {
        var copy = self
        if !preflight.modalities.isEmpty {
            copy.modalities = preflight.modalities
        }
        copy.verification = CuratedModelManifest.default.contains(repository: repository) ? .verified : preflight.verification
        if copy.state == .remote, preflight.verification == .unsupported {
            copy.state = .unsupported
        }
        if preflight.estimatedBytes > 0 {
            copy.estimatedBytes = preflight.estimatedBytes
        }
        copy.license = preflight.license ?? copy.license
        copy.modelType = preflight.modelType ?? copy.modelType
        copy.processorClass = preflight.processorClass ?? copy.processorClass
        return copy
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values = [T]()
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }

    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var values = [T]()
        values.reserveCapacity(count)
        for element in self {
            if let value = await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}

private extension RelativeDateTimeFormatter {
    static func shortLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PinesThreadPreview: Identifiable, Hashable {
    let id: UUID
    let title: String
    let modelName: String
    let modelID: ModelID
    let lastMessage: String
    let messages: [ChatMessage]
    let status: PinesThreadStatus
    let updatedLabel: String
    let tokenCount: Int

    var request: ChatRequest {
        ChatRequest(
            modelID: modelID,
            messages: messages,
            allowsTools: true,
            vaultContextIDs: []
        )
    }
}

enum PinesThreadStatus: String, Hashable {
    case local
    case streaming
    case archived

    var title: String {
        switch self {
        case .local:
            "Local"
        case .streaming:
            "Live"
        case .archived:
            "Archived"
        }
    }

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .local:
            theme.colors.success
        case .streaming:
            theme.colors.info
        case .archived:
            theme.colors.tertiaryText
        }
    }
}

struct MCPSamplingResultReview: Identifiable, Hashable {
    let id = UUID()
    let serverID: MCPServerID
    let result: MCPSamplingResult
    let summary: String
}

private struct MCPModelPreferenceProfile: Hashable {
    var hints: [String]
    var costPriority: Double
    var speedPriority: Double
    var intelligencePriority: Double

    init(json: JSONValue?) {
        let object = json?.objectValue ?? [:]
        hints = Self.hints(from: object["hints"])
        costPriority = Self.priority(from: object["costPriority"])
        speedPriority = Self.priority(from: object["speedPriority"])
        intelligencePriority = Self.priority(from: object["intelligencePriority"])
    }

    private static func hints(from value: JSONValue?) -> [String] {
        guard case let .array(items)? = value else { return [] }
        return items.compactMap { item in
            switch item {
            case let .string(name):
                return name
            case let .object(object):
                if case let .string(name)? = object["name"] {
                    return name
                }
                return nil
            default:
                return nil
            }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func priority(from value: JSONValue?) -> Double {
        guard case let .number(priority)? = value else { return 0 }
        return min(max(priority, 0), 1)
    }
}

struct PinesModelPreview: Identifiable, Hashable {
    let id: UUID
    let install: ModelInstall
    let runtimeProfile: RuntimeProfile
    let name: String
    let family: String
    let footprint: String
    let contextWindow: String
    let runtime: String
    let status: PinesModelStatus
    let capabilities: [String]
    let readiness: Double
    let downloadProgress: ModelDownloadProgress?
    let compatibilityWarnings: [String]
}

enum PinesModelStatus: String, Hashable {
    case ready
    case available
    case indexing
    case failed
    case unsupported

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .available:
            "Available"
        case .indexing:
            "Downloading"
        case .failed:
            "Failed"
        case .unsupported:
            "Unsupported"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.seal.fill"
        case .available:
            "arrow.down.circle.fill"
        case .indexing:
            "waveform.path.ecg"
        case .failed:
            "exclamationmark.triangle.fill"
        case .unsupported:
            "slash.circle.fill"
        }
    }
}

struct PinesVaultItemPreview: Identifiable, Hashable {
    let id: UUID
    let title: String
    let kind: PinesVaultKind
    let detail: String
    let chunks: [VaultChunk]
    let updatedLabel: String
    let sensitivity: PinesVaultSensitivity
    let linkedThreads: Int
}

enum PinesVaultKind: String, Hashable {
    case note
    case document
    case image
    case key

    var title: String {
        switch self {
        case .note:
            "Note"
        case .document:
            "Document"
        case .image:
            "Image"
        case .key:
            "Key"
        }
    }

    var systemImage: String {
        switch self {
        case .note:
            "note.text"
        case .document:
            "doc.text"
        case .image:
            "photo"
        case .key:
            "key.fill"
        }
    }
}

enum PinesVaultSensitivity: String, Hashable {
    case local
    case privateCloud
    case locked

    var title: String {
        switch self {
        case .local:
            "On Device"
        case .privateCloud:
            "Private Cloud"
        case .locked:
            "Locked"
        }
    }

    var systemImage: String {
        switch self {
        case .local:
            "iphone"
        case .privateCloud:
            "icloud.fill"
        case .locked:
            "lock.fill"
        }
    }
}

struct PinesSettingsSection: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let systemImage: String
    let rows: [PinesSettingsRow]
}

struct PinesSettingsRow: Identifiable, Hashable {
    let id: UUID
    let title: String
    let detail: String
    let systemImage: String
}

private enum PinesStaticSettings {
    static let sections: [PinesSettingsSection] = [
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20000")!,
            title: "Design",
            subtitle: "Theme, motion, haptics, and visual feel.",
            systemImage: "paintpalette",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20010")!,
                    title: "Theme template",
                    detail: "Color and surface system",
                    systemImage: "swatchpalette"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20011")!,
                    title: "Interaction feel",
                    detail: "Haptics and motion",
                    systemImage: "waveform.path"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20001")!,
            title: "Inference",
            subtitle: "Execution mode, local runtime, memory, and model access.",
            systemImage: "cpu",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21001")!,
                    title: "Execution policy",
                    detail: "Local or BYOK cloud",
                    systemImage: "sparkles"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21002")!,
                    title: "Runtime diagnostics",
                    detail: "MLX and memory state",
                    systemImage: "memorychip"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20002")!,
            title: "Privacy",
            subtitle: "Storage, sync, and bring-your-own-key providers.",
            systemImage: "lock.shield",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A22001")!,
                    title: "Vault storage",
                    detail: "On device",
                    systemImage: "internaldrive"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A22002")!,
                    title: "Provider keys",
                    detail: "Stored in Keychain",
                    systemImage: "icloud"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20003")!,
            title: "Tools",
            subtitle: "Agent search keys, MCP servers, resources, and prompts.",
            systemImage: "wrench.and.screwdriver",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A23001")!,
                    title: "Tool approval",
                    detail: "Ask each time",
                    systemImage: "hand.raised"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A23002")!,
                    title: "MCP servers",
                    detail: "Tools and context",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20004")!,
            title: "System",
            subtitle: "Service health, readiness, and recent audit activity.",
            systemImage: "waveform.path.ecg",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A24001")!,
                    title: "Architecture health",
                    detail: "Service readiness",
                    systemImage: "stethoscope"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A24002")!,
                    title: "Audit trail",
                    detail: "Recent local events",
                    systemImage: "list.bullet.clipboard"
                )
            ]
        )
    ]

}

private extension CloudProviderConfiguration {
    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            local: false,
            streaming: true,
            textGeneration: true,
            vision: true,
            embeddings: false,
            toolCalling: true,
            jsonMode: true,
            maxContextTokens: nil
        )
    }
}
