import Foundation
import SwiftUI
import PinesCore

private enum ChatStreamPerformance {
    static let renderInterval: TimeInterval = 0.05
    static let persistenceInterval: TimeInterval = 0.25
}

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
    @Published var chatError: String?
    @Published var activeRunID: UUID?
    @Published var auditEvents: [AuditEvent]
    @Published var cloudProviders: [CloudProviderConfiguration]
    @Published var mcpServers: [MCPServerConfiguration] = []
    @Published var mcpTools: [MCPToolRecord] = []
    @Published var mcpResources: [MCPResourceRecord] = []
    @Published var mcpResourceTemplates: [MCPResourceTemplateRecord] = []
    @Published var mcpPrompts: [MCPPromptRecord] = []
    @Published var pendingToolApproval: ToolApprovalRequest?
    @Published var pendingCloudContextApproval: CloudContextApprovalRequest?
    @Published var pendingCloudVaultEmbeddingApproval: CloudVaultEmbeddingApprovalRequest?
    @Published var pendingMCPSamplingRequest: MCPSamplingRequest?
    @Published var pendingMCPSamplingResultReview: MCPSamplingResultReview?
    @Published var mcpSamplingPromptDraft = ""
    @Published var hapticSignal: PinesHapticSignal?
    @Published var modelDownloads: [ModelDownloadProgress] = []
    @Published var isSearchingModels = false
    @Published var modelSearchError: String?
    @Published var defaultProviderID: ProviderID?
    @Published var defaultModelID: ModelID?
    @Published var cloudMaxCompletionTokens = AppSettingsSnapshot.defaultCloudMaxCompletionTokens
    @Published var localMaxCompletionTokens = AppSettingsSnapshot.defaultLocalMaxCompletionTokens
    @Published var localMaxContextTokens = AppSettingsSnapshot.defaultLocalMaxContextTokens
    @Published var cloudModelCatalog: [ProviderID: [CloudProviderModel]] = [:]
    @Published var isRefreshingCloudModels = false
    @Published var isSavingCloudProvider = false
    @Published var validatingCloudProviderIDs: Set<ProviderID> = []
    @Published var vaultEmbeddingProfiles: [VaultEmbeddingProfile] = []
    @Published var vaultEmbeddingJobs: [VaultEmbeddingJob] = []
    @Published var vaultRetrievalEvents: [VaultRetrievalEvent] = []
    @Published var vaultSearchQuery = ""
    @Published var vaultSearchResults: [VaultSearchResult] = []
    @Published var isVaultSearchPresented = false
    @Published var isVaultReindexing = false
    @Published var huggingFaceCredentialStatus = "Not configured"
    @Published var braveSearchCredentialStatus = "Not configured"
    private var didBootstrap = false
    private var didLoadStartupState = false
    private var isBootstrapping = false
    private var bootstrapBackgroundTask: Task<Void, Never>?
    private var didStartMCPServers = false
    private var shouldEnrichRuntimeModelPreviews = false
    private var repositoryObservationTasks: [Task<Void, Never>] = []
    private var currentRunTask: Task<Void, Never>?
    private var currentRunToken: UUID?
    private var vaultReindexToken: UUID?
    private var approvalContinuation: CheckedContinuation<ToolApprovalStatus, Never>?
    private var cloudContextContinuation: CheckedContinuation<CloudContextApprovalDecision, Never>?
    private var cloudVaultEmbeddingContinuation: CheckedContinuation<Bool, Never>?
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

    func dismissChatError() {
        clearChatError()
    }

    private func setChatError(_ message: String) {
        setIfChanged(\.chatError, message)
        setIfChanged(\.serviceError, message)
    }

    private func clearChatError() {
        setIfChanged(\.chatError, nil)
        setIfChanged(\.serviceError, nil)
    }

    private func failPendingChatStart(_ message: String, runToken: UUID? = nil) {
        if runToken == nil || currentRunToken == runToken {
            activeRunID = nil
            currentRunTask = nil
            currentRunToken = nil
        }
        setChatError(message)
        emitHaptic(.runFailed)
    }

    private func clearRunStateIfCurrent(_ runToken: UUID) {
        guard currentRunToken == runToken else { return }
        activeRunID = nil
        currentRunTask = nil
        currentRunToken = nil
    }

    private func upsertThreadPreview(_ preview: PinesThreadPreview, moveToFront: Bool) {
        var nextThreads = threads
        if let index = nextThreads.firstIndex(where: { $0.id == preview.id }) {
            nextThreads[index] = preview
            if moveToFront, index > 0, preview.status != .archived {
                let updated = nextThreads.remove(at: index)
                nextThreads.insert(updated, at: 0)
            }
        } else if moveToFront {
            nextThreads.insert(preview, at: 0)
        } else {
            nextThreads.append(preview)
        }
        setIfChanged(\.threads, nextThreads)
    }

    private func applyThreadMessages(
        _ messages: [ChatMessage],
        conversationID: UUID,
        fallbackRecord: ConversationRecord? = nil,
        status: PinesThreadStatus? = nil,
        moveToFront: Bool = false
    ) {
        if let existing = threads.first(where: { $0.id == conversationID }) {
            upsertThreadPreview(
                Self.threadPreview(from: existing, messages: messages, status: status),
                moveToFront: moveToFront
            )
        } else if let fallbackRecord {
            upsertThreadPreview(
                Self.threadPreview(from: fallbackRecord, messages: messages, status: status),
                moveToFront: moveToFront
            )
        }
    }

    private func appendThreadMessage(
        _ message: ChatMessage,
        conversationID: UUID,
        fallbackRecord: ConversationRecord? = nil,
        status: PinesThreadStatus? = nil,
        moveToFront: Bool = false
    ) {
        var messages = threads.first(where: { $0.id == conversationID })?.messages ?? []
        messages.append(message)
        applyThreadMessages(
            messages,
            conversationID: conversationID,
            fallbackRecord: fallbackRecord,
            status: status,
            moveToFront: moveToFront
        )
    }

    private func updateThreadMessage(
        conversationID: UUID,
        messageID: UUID,
        content: String,
        status: PinesThreadStatus? = nil,
        fallbackMessage: ChatMessage? = nil
    ) {
        guard let thread = threads.first(where: { $0.id == conversationID }) else { return }
        var messages = thread.messages
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].content = content
        } else if var fallbackMessage {
            fallbackMessage.content = content
            messages.append(fallbackMessage)
        } else {
            return
        }
        applyThreadMessages(messages, conversationID: conversationID, status: status)
    }

    private func refreshThread(
        conversationID: UUID,
        repository: any ConversationRepository,
        fallbackRecord: ConversationRecord? = nil,
        status: PinesThreadStatus? = nil,
        moveToFront: Bool = false
    ) async {
        do {
            let messages = try await repository.messages(in: conversationID)
            let fallback: ConversationRecord?
            if let fallbackRecord {
                fallback = fallbackRecord
            } else if threads.contains(where: { $0.id == conversationID }) {
                fallback = nil
            } else {
                fallback = try await repository.listConversations().first { $0.id == conversationID }
            }
            applyThreadMessages(
                messages,
                conversationID: conversationID,
                fallbackRecord: fallback,
                status: status,
                moveToFront: moveToFront
            )
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
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
        bootstrapBackgroundTask?.cancel()
        currentRunTask?.cancel()
        repositoryObservationTasks.forEach { $0.cancel() }
        approvalContinuation?.resume(returning: .denied)
        cloudContextContinuation?.resume(returning: .cancel)
        cloudVaultEmbeddingContinuation?.resume(returning: false)
        samplingContinuation?.resume(returning: false)
        samplingResultContinuation?.resume(returning: false)
    }

    func bootstrap(services: PinesAppServices) async {
        let startedAt = Date()
        guard !didBootstrap else {
            await refreshAll(services: services)
            return
        }
        guard !isBootstrapping else { return }
        isBootstrapping = true

        if !didLoadStartupState {
            let startupStateStartedAt = Date()
            await refreshStartupState(services: services)
            services.runtimeMetrics.recordStartupPhase("startup_state", elapsedSeconds: Date().timeIntervalSince(startupStateStartedAt))
            didLoadStartupState = true
        }

        observeRepositories(services: services)
        bootstrapBackgroundTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            await self?.finishBackgroundBootstrap(services: services)
        }
        services.runtimeMetrics.recordStartupPhase("bootstrap_visible", elapsedSeconds: Date().timeIntervalSince(startedAt))
    }

    private func refreshStartupState(services: PinesAppServices) async {
        do {
            if let settingsRepository = services.settingsRepository {
                let settings = try await settingsRepository.loadSettings()
                applySettings(settings)
            }

            if let cloudProviderRepository = services.cloudProviderRepository {
                setIfChanged(\.cloudProviders, try await cloudProviderRepository.listProviders())
            }

            try await refreshModelPreviews(services: services, enrichRuntime: false)
            await refreshVaultEmbeddingState(services: services)
            await normalizeDefaultModelIfNeeded(services: services)
            setIfChanged(\.serviceError, nil)
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    private func finishBackgroundBootstrap(services: PinesAppServices) async {
        let startedAt = Date()
        await services.bootstrap()
        try? await services.modelLifecycleService?.reconcileInterruptedDownloads()
        await refreshPostBootstrapState(services: services)
        didBootstrap = true
        isBootstrapping = false
        services.runtimeMetrics.recordStartupPhase("background_bootstrap", elapsedSeconds: Date().timeIntervalSince(startedAt))
    }

    private func refreshPostBootstrapState(services: PinesAppServices) async {
        do {
            shouldEnrichRuntimeModelPreviews = true
            try await refreshModelPreviews(services: services, enrichRuntime: true)
            await refreshCloudModelCatalog(services: services)
            await refreshVaultEmbeddingState(services: services)
            await normalizeDefaultModelIfNeeded(services: services)
            await refreshCredentialStatuses(services: services)
            setIfChanged(\.serviceError, nil)
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    func refreshAll(services: PinesAppServices) async {
        do {
            if let settingsRepository = services.settingsRepository {
                let settings = try await settingsRepository.loadSettings()
                applySettings(settings)
            }

            try await refreshModelPreviews(services: services)
            await normalizeDefaultModelIfNeeded(services: services)
            await refreshVaultEmbeddingState(services: services)

            if let conversationRepository = services.conversationRepository {
                let previews = try await conversationRepository.listConversationPreviews()
                setIfChanged(\.threads, mergeThreadPreviews(previews.map(Self.threadPreview(from:))))
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

            await refreshCloudModelCatalog(services: services)

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

    private func refreshCloudProviders(services: PinesAppServices) async {
        do {
            guard let cloudProviderRepository = services.cloudProviderRepository else { return }
            setIfChanged(\.cloudProviders, try await cloudProviderRepository.listProviders())
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    private func refreshVaultEmbeddingState(services: PinesAppServices) async {
        do {
            if let embeddingService = services.vaultEmbeddingService {
                setIfChanged(\.vaultEmbeddingProfiles, try await embeddingService.refreshProfiles())
            } else if let vaultRepository = services.vaultRepository {
                setIfChanged(\.vaultEmbeddingProfiles, try await vaultRepository.listEmbeddingProfiles())
            }
            if let vaultRepository = services.vaultRepository {
                setIfChanged(\.vaultEmbeddingJobs, try await vaultRepository.listEmbeddingJobs(limit: 20))
                setIfChanged(\.vaultRetrievalEvents, try await vaultRepository.listRetrievalEvents(limit: 20))
            }
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    private func upsertCloudProvider(_ provider: CloudProviderConfiguration) {
        var providers = cloudProviders
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        setIfChanged(\.cloudProviders, providers)
    }

    func loadThreadMessages(threadID: UUID, services: PinesAppServices, force: Bool = false) async {
        guard let repository = services.conversationRepository else { return }
        guard let existing = threads.first(where: { $0.id == threadID }) else { return }
        guard force || existing.messages.isEmpty else { return }
        guard existing.status != .streaming else { return }

        await refreshThread(conversationID: threadID, repository: repository)
    }

    private func mergeThreadPreviews(_ previews: [PinesThreadPreview]) -> [PinesThreadPreview] {
        previews.map { preview in
            guard let existing = threads.first(where: { $0.id == preview.id }) else {
                return preview
            }
            if existing.status == .streaming,
               let activeRunID,
               existing.messages.contains(where: { $0.id == activeRunID }) {
                return Self.threadPreview(from: existing, messages: existing.messages, status: .streaming)
            }
            guard !existing.messages.isEmpty else {
                return preview
            }
            return PinesThreadPreview(
                id: preview.id,
                title: preview.title,
                modelName: preview.modelName,
                modelID: preview.modelID,
                providerID: preview.providerID,
                lastMessage: preview.lastMessage,
                messages: existing.messages,
                status: preview.status,
                isPinned: preview.isPinned,
                updatedLabel: preview.updatedLabel,
                tokenCount: preview.tokenCount
            )
        }
    }

    func startMCPServersIfNeeded(services: PinesAppServices) async {
        guard !didStartMCPServers else { return }
        didStartMCPServers = true
        let startedAt = Date()
        await services.mcpServerService?.start { [weak self] request, server in
            guard let self else {
                throw InferenceError.cancelled
            }
            return try await self.handleMCPSampling(request, server: server, services: services)
        }
        services.runtimeMetrics.recordStartupPhase("mcp_servers_start", elapsedSeconds: Date().timeIntervalSince(startedAt))
    }

    private func applySettings(_ settings: AppSettingsSnapshot) {
        setIfChanged(\.executionMode, settings.executionMode)
        setIfChanged(\.storeConfiguration, settings.storeConfiguration)
        setIfChanged(\.defaultProviderID, settings.defaultProviderID)
        setIfChanged(\.defaultModelID, settings.defaultModelID)
        setIfChanged(\.cloudMaxCompletionTokens, settings.cloudMaxCompletionTokens)
        setIfChanged(\.localMaxCompletionTokens, settings.localMaxCompletionTokens)
        setIfChanged(\.localMaxContextTokens, settings.localMaxContextTokens)
        setIfChanged(\.selectedThemeTemplate, PinesThemeTemplate(rawValue: settings.themeTemplate) ?? selectedThemeTemplate)
        setIfChanged(\.interfaceMode, PinesInterfaceMode(rawValue: settings.interfaceMode) ?? interfaceMode)
    }

    private func normalizeDefaultModelIfNeeded(services: PinesAppServices) async {
        if let providerID = defaultProviderID,
           providerID != services.mlxRuntime.localProviderID {
            return
        }
        guard defaultModelID.flatMap(installedModel(for:)) == nil else {
            if defaultProviderID == nil {
                defaultProviderID = services.mlxRuntime.localProviderID
                await saveSettings(services: services)
            }
            return
        }
        let normalizedDefault = preferredInstalledTextModel()?.modelID
        guard defaultModelID != normalizedDefault || defaultProviderID != services.mlxRuntime.localProviderID else { return }
        defaultModelID = normalizedDefault
        defaultProviderID = normalizedDefault == nil ? nil : services.mlxRuntime.localProviderID
        await saveSettings(services: services)
    }

    func createChat(services: PinesAppServices) async -> UUID? {
        do {
            guard let repository = services.conversationRepository else {
                serviceError = "Conversation repository is unavailable."
                return nil
            }
            let selection = preferredModelSelection(services: services)
            let conversation = try await repository.createConversation(
                title: "New chat",
                defaultModelID: selection?.modelID,
                defaultProviderID: selection?.providerID
            )
            upsertThreadPreview(
                Self.threadPreview(from: conversation, messages: []),
                moveToFront: true
            )
            emitHaptic(.primaryAction)
            return conversation.id
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            emitHaptic(.runFailed)
            return nil
        }
    }

    func startSending(_ draft: String, attachments: [ChatAttachment] = [], in threadID: UUID?, services: PinesAppServices) {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        clearChatError()
        emitHaptic(.sendCommitted)
        currentRunTask?.cancel()
        let runToken = UUID()
        currentRunToken = runToken
        currentRunTask = Task { [weak self] in
            await self?.sendMessage(draft, attachments: attachments, in: threadID, services: services, runToken: runToken)
        }
    }

    func stopCurrentRun() {
        currentRunTask?.cancel()
        currentRunTask = nil
        currentRunToken = nil
        activeRunID = nil
        emitHaptic(.runCancelled)
        resolvePendingToolApproval(.denied)
        resolvePendingCloudContextApproval(.cancel)
        resolvePendingCloudVaultEmbeddingApproval(false)
        cancelVaultReindex()
        resolvePendingMCPSampling(false)
        resolvePendingMCPSamplingResultReview(false)
    }

    func retryLastUserMessage(in thread: PinesThreadPreview, services: PinesAppServices) {
        guard let lastUser = thread.messages.last(where: { $0.role == .user }) else { return }
        startSending(lastUser.content, attachments: lastUser.attachments, in: thread.id, services: services)
    }

    func setThreadArchived(_ thread: PinesThreadPreview, archived: Bool, services: PinesAppServices) async {
        do {
            guard let repository = services.conversationRepository else {
                setChatError("Conversation repository is unavailable.")
                return
            }
            try await repository.setConversationArchived(archived, conversationID: thread.id)
            emitHaptic(archived ? .destructiveAction : .primaryAction)
            await refreshAll(services: services)
        } catch {
            setChatError(error.localizedDescription)
            emitHaptic(.runFailed)
        }
    }

    func setThreadPinned(_ thread: PinesThreadPreview, pinned: Bool, services: PinesAppServices) async {
        do {
            guard let repository = services.conversationRepository else {
                setChatError("Conversation repository is unavailable.")
                return
            }
            try await repository.setConversationPinned(pinned, conversationID: thread.id)
            emitHaptic(.primaryAction)
            await refreshAll(services: services)
        } catch {
            setChatError(error.localizedDescription)
            emitHaptic(.runFailed)
        }
    }

    func deleteThread(_ thread: PinesThreadPreview, services: PinesAppServices) async {
        do {
            guard let repository = services.conversationRepository else {
                setChatError("Conversation repository is unavailable.")
                return
            }
            try await repository.deleteConversation(id: thread.id)
            if let activeRunID, thread.messages.contains(where: { $0.id == activeRunID }) {
                stopCurrentRun()
            }
            emitHaptic(.destructiveAction)
            await refreshAll(services: services)
        } catch {
            setChatError(error.localizedDescription)
            emitHaptic(.runFailed)
        }
    }

    private func sendMessage(_ draft: String, attachments: [ChatAttachment], in threadID: UUID?, services: PinesAppServices, runToken: UUID) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        var runRepository: (any ConversationRepository)?
        var runConversationID: UUID?
        var assistantMessageID: UUID?
        var accumulated = ""
        var tokenCount = 0
        var failureMessage: String?
        var lastRenderedContent = ""
        var lastPersistedContent = ""
        var lastRenderedAt = Date.distantPast
        var lastPersistedAt = Date.distantPast

        do {
            guard let repository = services.conversationRepository else {
                failPendingChatStart("Conversation repository is unavailable.", runToken: runToken)
                return
            }
            runRepository = repository

            let conversationID: UUID
            if let threadID {
                conversationID = threadID
            } else if let created = await createChat(services: services) {
                conversationID = created
            } else {
                failPendingChatStart(serviceError ?? "Unable to create a chat.", runToken: runToken)
                return
            }
            runConversationID = conversationID
            let settings = try? await services.settingsRepository?.loadSettings()

            let userMessage = ChatMessage(role: .user, content: trimmed, attachments: attachments)
            try await repository.appendMessage(userMessage, status: .complete, conversationID: conversationID, modelID: nil, providerID: nil)
            appendThreadMessage(userMessage, conversationID: conversationID, status: .local, moveToFront: true)

            // Normal chat should not advertise globally registered agent tools unless a tool mode opts in.
            let availableTools: [AnyToolSpec] = []
            let messages = try await repository.messages(in: conversationID)
            let vaultContext = trimmed.isEmpty ? nil : await vaultContextMessage(for: trimmed, services: services)
            let mcpContext = await mcpResourceContextMessages(services: services)
            let routeRequiredInputs = ProviderInputRequirements(messages: messages + mcpContext)
            let requestedSelection = selection(for: conversationID, services: services)
            let selectedProvider: any InferenceProvider
            let selectedProviderID: ProviderID
            let selectedModelID: ModelID
            if let requestedSelection {
                if requestedSelection.providerID == services.mlxRuntime.localProviderID {
                    guard let localInstall = installedModel(for: requestedSelection.modelID) else {
                        failPendingChatStart("Download the selected local text model before starting chat.", runToken: runToken)
                        return
                    }
                    guard let localCandidate = localRoutingCandidate(for: localInstall, services: services),
                          routeRequiredInputs.isSatisfied(by: localCandidate.capabilities)
                    else {
                        failPendingChatStart("The selected local model does not support the attachments selected for this turn.", runToken: runToken)
                        return
                    }
                    try await services.mlxRuntime.load(
                        localInstall,
                        profile: localRuntimeProfile(for: localInstall, settings: settings, services: services)
                    )
                    selectedProvider = services.mlxRuntime
                    selectedProviderID = services.mlxRuntime.localProviderID
                    selectedModelID = localInstall.modelID
                } else {
                    guard let cloudProvider = cloudProviders.first(where: { $0.id == requestedSelection.providerID }) else {
                        failPendingChatStart("The selected cloud provider is no longer configured.", runToken: runToken)
                        return
                    }
                    guard routeRequiredInputs.isSatisfied(by: cloudProvider.capabilities) else {
                        failPendingChatStart("The selected cloud provider does not support the attachments selected for this turn.", runToken: runToken)
                        return
                    }
                    selectedProvider = BYOKCloudInferenceProvider(configuration: cloudProvider, secretStore: services.secretStore)
                    selectedProviderID = cloudProvider.id
                    selectedModelID = requestedSelection.modelID
                }
            } else {
                let localInstall = preferredInstalledTextModel(for: conversationID)
                let cloudCandidate = cloudProviders
                    .first { $0.enabledForAgents && $0.capabilities.textGeneration }
                    .map { configuration in
                        (
                            configuration,
                            BYOKCloudInferenceProvider(configuration: configuration, secretStore: services.secretStore)
                        )
                    }
                let localCandidate = localRoutingCandidate(for: localInstall, services: services)
                let route = services.executionRouter.routeChat(
                    mode: executionMode,
                    local: localCandidate,
                    cloud: cloudCandidate.map { ($0.1.id, $0.1.capabilities) },
                    requiredInputs: routeRequiredInputs,
                    requiresTools: false
                )
                switch route.destination {
                case .local:
                    guard let localInstall else {
                        failPendingChatStart("Download and select a local text model before starting local chat.", runToken: runToken)
                        return
                    }
                    try await services.mlxRuntime.load(
                        localInstall,
                        profile: localRuntimeProfile(for: localInstall, settings: settings, services: services)
                    )
                    selectedProvider = services.mlxRuntime
                    selectedProviderID = services.mlxRuntime.localProviderID
                    selectedModelID = localInstall.modelID
                case let .cloud(providerID):
                    guard let cloudCandidate else {
                        failPendingChatStart("No enabled cloud provider is configured for agents.", runToken: runToken)
                        return
                    }
                    guard let cloudModelID = cloudCandidate.0.defaultModelID ?? localInstall?.modelID else {
                        failPendingChatStart("Configure a default model for the selected cloud provider.", runToken: runToken)
                        return
                    }
                    selectedProvider = cloudCandidate.1
                    selectedProviderID = providerID
                    selectedModelID = cloudModelID
                case let .denied(reason):
                    failPendingChatStart("\(reason)", runToken: runToken)
                    return
                }
            }

            let assistantMessage = ChatMessage(role: .assistant, content: "")
            try await repository.appendMessage(assistantMessage, status: .streaming, conversationID: conversationID, modelID: selectedModelID, providerID: selectedProviderID)

            activeRunID = assistantMessage.id
            assistantMessageID = assistantMessage.id
            emitHaptic(.runAccepted)
            appendThreadMessage(assistantMessage, conversationID: conversationID, status: .streaming, moveToFront: true)

            func flushAssistantUpdate(
                content: String,
                messageStatus: MessageStatus,
                threadStatus: PinesThreadStatus,
                force: Bool = false,
                providerMetadata: [String: String]? = nil
            ) async throws {
                let now = Date()
                if force || (content != lastRenderedContent && now.timeIntervalSince(lastRenderedAt) >= ChatStreamPerformance.renderInterval) {
                    updateThreadMessage(
                        conversationID: conversationID,
                        messageID: assistantMessage.id,
                        content: content,
                        status: threadStatus,
                        fallbackMessage: assistantMessage
                    )
                    lastRenderedContent = content
                    lastRenderedAt = now
                }
                if force || (content != lastPersistedContent && now.timeIntervalSince(lastPersistedAt) >= ChatStreamPerformance.persistenceInterval) {
                    try await repository.updateMessage(
                        id: assistantMessage.id,
                        content: content,
                        status: messageStatus,
                        tokenCount: tokenCount,
                        providerMetadata: providerMetadata
                    )
                    lastPersistedContent = content
                    lastPersistedAt = now
                }
            }

            var requestMessages = messages
            let cloudContextDecision = try await resolveCloudContextDecision(
                providerID: selectedProviderID,
                modelID: selectedModelID,
                vaultContext: vaultContext,
                mcpContext: mcpContext,
                services: services
            )
            let includePrivateContext = selectedProviderID == services.mlxRuntime.localProviderID || cloudContextDecision == .sendWithContext
            if includePrivateContext, let vaultContext {
                requestMessages.insert(vaultContext.message, at: 0)
            }
            if includePrivateContext, !mcpContext.isEmpty {
                requestMessages.insert(contentsOf: mcpContext, at: 0)
            }
            let request = ChatRequest(
                modelID: selectedModelID,
                messages: requestMessages,
                sampling: chatSampling(for: selectedProviderID, settings: settings, services: services),
                allowsTools: !availableTools.isEmpty,
                availableTools: availableTools,
                vaultContextIDs: includePrivateContext ? (vaultContext?.documentIDs ?? []) : []
            )
            let session = AgentSession(
                title: "Chat",
                policy: AgentPolicy(
                    executionMode: settings?.executionMode ?? executionMode,
                    requiresConsentForNetwork: false,
                    requiresConsentForBrowser: false,
                    allowsCloudContext: selectedProviderID != services.mlxRuntime.localProviderID && includePrivateContext
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
            var finalProviderMetadata = [String: String]()

            for try await event in stream {
                guard !Task.isCancelled else { throw InferenceError.cancelled }
                switch event {
                case let .token(delta):
                    accumulated += delta.text
                    tokenCount += max(delta.tokenCount, 1)
                    if let hapticEvent = streamHaptics.event(tokenCount: tokenCount, content: accumulated) {
                        emitHaptic(hapticEvent)
                    }
                    clearChatError()
                    try await flushAssistantUpdate(content: accumulated, messageStatus: .streaming, threadStatus: .streaming)
                case let .finish(finish):
                    didReceiveTerminalEvent = true
                    finalProviderMetadata = finish.providerMetadata
                    if failureMessage == nil {
                        let status: MessageStatus = finish.reason == .cancelled ? .cancelled : .complete
                        if status == .complete && accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let baseMessage = finish.message ?? emptyCloudOutputMessage(
                                providerID: selectedProviderID,
                                modelID: selectedModelID,
                                services: services
                            )
                            let message = messageWithProviderDiagnostics(baseMessage, metadata: finalProviderMetadata)
                            failureMessage = message
                            try await flushAssistantUpdate(content: message, messageStatus: .failed, threadStatus: .local, force: true, providerMetadata: finalProviderMetadata)
                            setChatError(message)
                            emitHaptic(.runFailed)
                        } else {
                            try await flushAssistantUpdate(content: accumulated, messageStatus: status, threadStatus: .local, force: true, providerMetadata: finalProviderMetadata)
                            clearChatError()
                            emitHaptic(status == .cancelled ? .runCancelled : .runCompleted)
                        }
                    }
                case let .failure(failure):
                    didReceiveTerminalEvent = true
                    failureMessage = failure.message
                    try await flushAssistantUpdate(content: failure.message, messageStatus: .failed, threadStatus: .local, force: true)
                    setChatError(failure.message)
                    emitHaptic(.runFailed)
                case let .metrics(metrics):
                    services.runtimeMetrics.recordGenerationMetrics(metrics, modelID: selectedModelID)
                case .toolCall:
                    emitHaptic(.streamMilestone)
                }
            }

            if !didReceiveTerminalEvent {
                let finalText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                if finalText.isEmpty {
                    let message = "The inference stream ended before the model produced output."
                    failureMessage = message
                    try await flushAssistantUpdate(content: message, messageStatus: .failed, threadStatus: .local, force: true)
                    setChatError(message)
                    emitHaptic(.runFailed)
                } else {
                    try await flushAssistantUpdate(content: accumulated, messageStatus: .complete, threadStatus: .local, force: true, providerMetadata: finalProviderMetadata)
                    clearChatError()
                    emitHaptic(.runCompleted)
                }
            }

            services.runtimeMetrics.recordGenerationFinished(
                modelID: selectedModelID,
                outputTokens: tokenCount,
                elapsedSeconds: Date().timeIntervalSince(generationStartedAt)
            )
            clearRunStateIfCurrent(runToken)
            await refreshThread(conversationID: conversationID, repository: repository, status: .local)
        } catch InferenceError.cancelled {
            if let runRepository, let assistantMessageID {
                try? await runRepository.updateMessage(
                    id: assistantMessageID,
                    content: accumulated,
                    status: .cancelled,
                    tokenCount: tokenCount
                )
            }
            if let runConversationID, let assistantMessageID {
                updateThreadMessage(
                    conversationID: runConversationID,
                    messageID: assistantMessageID,
                    content: accumulated,
                    status: .local
                )
            }
            if currentRunToken == runToken {
                clearRunStateIfCurrent(runToken)
                emitHaptic(.runCancelled)
            }
            if let runRepository, let runConversationID {
                await refreshThread(conversationID: runConversationID, repository: runRepository, status: .local)
            }
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
            if let runConversationID, let assistantMessageID {
                updateThreadMessage(
                    conversationID: runConversationID,
                    messageID: assistantMessageID,
                    content: accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? message : accumulated,
                    status: .local
                )
            }
            if currentRunToken == runToken {
                clearRunStateIfCurrent(runToken)
                emitHaptic(.runFailed)
            }
            if let runRepository, let runConversationID {
                await refreshThread(conversationID: runConversationID, repository: runRepository, status: .local)
            }
            if currentRunToken == nil || currentRunToken == runToken {
                setChatError(message)
            }
        }
    }

    private func vaultContextMessage(
        for query: String,
        services: PinesAppServices
    ) async -> (message: ChatMessage, documentIDs: [UUID])? {
        await services.vaultRetrievalService?.contextMessage(for: query, limit: 4)
    }

    private func mcpResourceContextMessages(services: PinesAppServices) async -> [ChatMessage] {
        let selected = mcpResources.filter(\.selectedForContext).prefix(4)
        guard !selected.isEmpty else { return [] }
        await startMCPServersIfNeeded(services: services)
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

    private func localRoutingCandidate(
        for install: ModelInstall?,
        services: PinesAppServices
    ) -> (id: ProviderID, capabilities: ProviderCapabilities)? {
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

    private func resolveCloudContextDecision(
        providerID: ProviderID,
        modelID: ModelID,
        vaultContext: (message: ChatMessage, documentIDs: [UUID])?,
        mcpContext: [ChatMessage],
        services: PinesAppServices
    ) async throws -> CloudContextApprovalDecision {
        guard providerID != services.mlxRuntime.localProviderID else {
            return .sendWithContext
        }

        let documentIDs = vaultContext?.documentIDs ?? []
        let mcpResourceIDs = Array(mcpResources.filter(\.selectedForContext).prefix(4).map(\.id))
        guard !documentIDs.isEmpty || !mcpContext.isEmpty else {
            return .sendWithoutContext
        }

        let estimatedBytes = (vaultContext?.message.content.utf8.count ?? 0)
            + mcpContext.reduce(0) { total, message in
                total + message.content.utf8.count + message.attachments.reduce(0) { $0 + Int($1.byteCount) }
            }
        let request = CloudContextApprovalRequest(
            providerID: providerID,
            modelID: modelID,
            documentIDs: documentIDs,
            mcpResourceIDs: mcpResourceIDs,
            estimatedContextBytes: estimatedBytes
        )
        let decision = await requestCloudContextApproval(request)
        if decision == .cancel {
            throw InferenceError.cancelled
        }
        if decision == .sendWithoutContext {
            try? await services.auditRepository?.append(
                AuditEvent(
                    category: .security,
                    summary: "Sent cloud chat without selected local vault or MCP context."
                )
            )
        }
        return decision
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

    private func preferredModelSelection(services: PinesAppServices) -> ModelPickerOption? {
        if let defaultModelID,
           let providerID = defaultProviderID ?? (installedModel(for: defaultModelID) == nil ? nil : services.mlxRuntime.localProviderID) {
            return ModelPickerOption(
                providerID: providerID,
                providerName: providerDisplayName(for: providerID, services: services),
                providerKind: providerKind(for: providerID, services: services),
                modelID: defaultModelID,
                displayName: displayName(for: defaultModelID, providerID: providerID),
                isLocal: providerID == services.mlxRuntime.localProviderID,
                rank: 0
            )
        }

        if let local = preferredInstalledTextModel() {
            return ModelPickerOption(
                providerID: services.mlxRuntime.localProviderID,
                providerName: "Local",
                providerKind: nil,
                modelID: local.modelID,
                displayName: Self.localModelDisplayName(local),
                isLocal: true,
                rank: 0
            )
        }

        return modelPickerSections(services: services).flatMap(\.models).first
    }

    private func selection(for conversationID: UUID, services: PinesAppServices) -> ModelPickerOption? {
        if let thread = threads.first(where: { $0.id == conversationID }),
           let providerID = thread.providerID {
            return ModelPickerOption(
                providerID: providerID,
                providerName: providerDisplayName(for: providerID, services: services),
                providerKind: providerKind(for: providerID, services: services),
                modelID: thread.modelID,
                displayName: displayName(for: thread.modelID, providerID: providerID),
                isLocal: providerID == services.mlxRuntime.localProviderID,
                rank: 0
            )
        }
        return preferredModelSelection(services: services)
    }

    func saveSettings(services: PinesAppServices) async {
        do {
            cloudMaxCompletionTokens = AppSettingsSnapshot.normalizedCompletionTokens(cloudMaxCompletionTokens)
            localMaxCompletionTokens = AppSettingsSnapshot.normalizedCompletionTokens(localMaxCompletionTokens)
            localMaxContextTokens = AppSettingsSnapshot.normalizedLocalContextTokens(localMaxContextTokens)
            let resolvedDefaultModelID = defaultModelID ?? preferredInstalledTextModel()?.modelID
            let resolvedProviderID = defaultProviderID
                ?? resolvedDefaultModelID.flatMap { installedModel(for: $0) == nil ? nil : services.mlxRuntime.localProviderID }
            let snapshot = AppSettingsSnapshot(
                executionMode: executionMode,
                storeConfiguration: storeConfiguration,
                defaultProviderID: resolvedProviderID,
                defaultModelID: resolvedDefaultModelID,
                embeddingModelID: models.first(where: {
                    $0.install.state == .installed && $0.install.modalities.contains(.embeddings)
                })?.install.modelID,
                cloudMaxCompletionTokens: cloudMaxCompletionTokens,
                localMaxCompletionTokens: localMaxCompletionTokens,
                localMaxContextTokens: localMaxContextTokens,
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

    private func chatSampling(
        for providerID: ProviderID,
        settings: AppSettingsSnapshot?,
        services: PinesAppServices,
        requestedMaxTokens: Int? = nil,
        temperature: Float = 0.6
    ) -> ChatSampling {
        let fallback = providerID == services.mlxRuntime.localProviderID
            ? localMaxCompletionTokens
            : cloudMaxCompletionTokens
        let settingsMaxTokens = providerID == services.mlxRuntime.localProviderID
            ? settings?.localMaxCompletionTokens
            : settings?.cloudMaxCompletionTokens
        return ChatSampling(
            maxTokens: AppSettingsSnapshot.normalizedCompletionTokens(requestedMaxTokens ?? settingsMaxTokens ?? fallback),
            temperature: temperature
        )
    }

    private func localRuntimeProfile(
        for install: ModelInstall,
        settings: AppSettingsSnapshot?,
        services: PinesAppServices
    ) -> RuntimeProfile {
        var profile = services.mlxRuntime.defaultRuntimeProfile(for: install)
        let requestedContextTokens = AppSettingsSnapshot.normalizedLocalContextTokens(
            settings?.localMaxContextTokens ?? localMaxContextTokens
        )
        if let recommendedContextTokens = profile.quantization.maxKVSize {
            profile.quantization.maxKVSize = min(requestedContextTokens, recommendedContextTokens)
        } else {
            profile.quantization.maxKVSize = requestedContextTokens
        }
        return profile
    }

    func installModel(
        repository: String,
        mode: ModelInstallMode = .automatic,
        services: PinesAppServices
    ) async {
        do {
            guard let lifecycle = services.modelLifecycleService else {
                setIfChanged(\.serviceError, "Model lifecycle service is unavailable.")
                return
            }
            markModelDownloadQueued(repository: repository, services: services)
            try await lifecycle.install(repository: repository, mode: mode)
            if defaultModelID == nil {
                let installs = try await services.modelInstallRepository?.listInstalledAndCuratedModels() ?? []
                if let installed = installs.first(where: { $0.repository.caseInsensitiveCompare(repository) == .orderedSame && $0.state == .installed }),
                   installed.modalities.contains(.text) {
                    setIfChanged(\.defaultModelID, installed.modelID)
                    setIfChanged(\.defaultProviderID, services.mlxRuntime.localProviderID)
                    await saveSettings(services: services)
                }
            }
            if !isShowingModelDiscoveryResults {
                try await refreshModelPreviews(services: services)
            }
            await refreshVaultEmbeddingState(services: services)
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
                setIfChanged(\.defaultProviderID, nil)
                await saveSettings(services: services)
            }
            if !isShowingModelDiscoveryResults {
                try await refreshModelPreviews(services: services)
            }
            await refreshVaultEmbeddingState(services: services)
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

    private func markModelDownloadQueued(repository: String, services: PinesAppServices) {
        let key = repository.lowercased()
        let previews = models.map { preview in
            guard preview.install.repository.lowercased() == key else { return preview }
            var install = preview.install
            guard install.state != .installed && install.state != .unsupported else { return preview }
            install.state = .downloading
            let queuedProgress = preview.downloadProgress ?? ModelDownloadProgress(
                repository: repository,
                status: .queued,
                totalBytes: install.estimatedBytes
            )
            return Self.modelPreview(
                from: install,
                runtime: services.mlxRuntime,
                download: queuedProgress
            )
        }
        setIfChanged(\.models, Self.downloadingFirst(previews))
    }

    func selectDefaultModel(_ model: PinesModelPreview, services: PinesAppServices) async {
        guard model.install.state == .installed else {
            setIfChanged(\.serviceError, "Download the model before selecting it as the default.")
            return
        }
        setIfChanged(\.defaultModelID, model.install.modelID)
        setIfChanged(\.defaultProviderID, services.mlxRuntime.localProviderID)
        await saveSettings(services: services)
    }

    func searchModels(
        query: String,
        task: HubTask? = nil,
        verification: ModelVerificationState? = nil,
        installState: ModelInstallState? = nil,
        services: PinesAppServices
    ) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDiscoveryCriteria = !trimmed.isEmpty || task != nil || verification != nil || installState != nil

        setIfChanged(\.modelSearchError, nil)
        do {
            if !hasDiscoveryCriteria {
                isShowingModelDiscoveryResults = false
                setIfChanged(\.isSearchingModels, false)
                try await refreshModelPreviews(services: services)
            } else {
                setIfChanged(\.isSearchingModels, true)
                isShowingModelDiscoveryResults = true
                let token = try await services.huggingFaceCredentialService.readToken()
                let filters = ModelSearchFilters(query: trimmed, task: task, limit: 100)
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
                setIfChanged(\.models, Self.downloadingFirst(previews))
                setIfChanged(\.isSearchingModels, false)
            }
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
            _ = await ensureVaultEmbeddingProfile(services: services, reason: "Pines will send imported document chunks to this cloud embedding provider to build your private vault index.")
            _ = try await ingestion.importFile(url: url)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    @discardableResult
    func ensureVaultEmbeddingProfile(services: PinesAppServices, reason: String) async -> VaultEmbeddingProfile? {
        do {
            guard let embeddingService = services.vaultEmbeddingService else { return nil }
            let profiles = try await embeddingService.refreshProfiles()
            setIfChanged(\.vaultEmbeddingProfiles, profiles)

            if let active = profiles.first(where: \.isActive) {
                if active.canUseWithoutPrompt {
                    return active
                }
                let approved = await requestCloudVaultEmbeddingApproval(
                    CloudVaultEmbeddingApprovalRequest(profile: active, reason: reason)
                )
                guard approved else { return nil }
                let updated = try await embeddingService.setActiveProfile(active, grantConsent: true)
                await refreshVaultEmbeddingState(services: services)
                return updated
            }

            if let local = profiles.first(where: { $0.kind == .localMLX }) {
                let updated = try await embeddingService.setActiveProfile(local)
                await refreshVaultEmbeddingState(services: services)
                return updated
            }

            let cloudProfiles = profiles.filter { $0.kind.isCloud }
            if cloudProfiles.count == 1, let profile = cloudProfiles.first {
                let approved = await requestCloudVaultEmbeddingApproval(
                    CloudVaultEmbeddingApprovalRequest(profile: profile, reason: reason)
                )
                guard approved else { return nil }
                let updated = try await embeddingService.setActiveProfile(profile, grantConsent: true)
                await refreshVaultEmbeddingState(services: services)
                return updated
            }

            if cloudProfiles.count > 1 {
                setIfChanged(\.serviceError, "Select a vault embedding provider before semantic indexing.")
            } else {
                setIfChanged(\.serviceError, "Install a local embedding model or add OpenAI, Gemini, OpenRouter, or Voyage AI credentials to enable semantic vault indexing.")
            }
            return nil
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            return nil
        }
    }

    func selectVaultEmbeddingProfile(_ profile: VaultEmbeddingProfile, services: PinesAppServices) async {
        do {
            guard let embeddingService = services.vaultEmbeddingService else {
                setIfChanged(\.serviceError, "Vault embedding service is unavailable.")
                return
            }
            guard profile.status != .failed else {
                setIfChanged(\.serviceError, profile.lastError ?? "This vault embedding profile is unavailable.")
                return
            }
            if profile.kind.isCloud && !profile.cloudConsentGranted {
                let approved = await requestCloudVaultEmbeddingApproval(
                    CloudVaultEmbeddingApprovalRequest(
                        profile: profile,
                        reason: "Pines will use this provider for document chunk and search-query embeddings."
                    )
                )
                guard approved else { return }
                _ = try await embeddingService.setActiveProfile(profile, grantConsent: true)
            } else {
                _ = try await embeddingService.setActiveProfile(profile)
            }
            await refreshVaultEmbeddingState(services: services)
            emitHaptic(.primaryAction)
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            emitHaptic(.runFailed)
        }
    }

    func searchVault(_ query: String, services: PinesAppServices) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setIfChanged(\.vaultSearchResults, [])
            return
        }
        do {
            if let retrieval = services.vaultRetrievalService {
                let profile = try await services.vaultEmbeddingService?.activeUsableProfile()
                var queryEmbedding: [Float]?
                if let profile {
                    queryEmbedding = try? await services.vaultEmbeddingService?.embedQuery(trimmed, profile: profile)
                }
                let results = try await services.vaultRepository?.search(
                    query: trimmed,
                    embedding: queryEmbedding,
                    embeddingModelID: profile?.modelID,
                    profileID: queryEmbedding == nil ? nil : profile?.id,
                    limit: 12
                ) ?? []
                setIfChanged(\.vaultSearchResults, results)
                _ = await retrieval.contextMessage(for: trimmed, limit: 1)
            }
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    func loadVaultItemDetails(id: UUID, services: PinesAppServices) async {
        do {
            guard let repository = services.vaultRepository else { return }
            let chunks = try await repository.chunks(documentID: id)
            let storedEmbeddings = try await repository.embeddings(documentID: id)
            let activeProfileID = vaultEmbeddingProfiles.first(where: \.isActive)?.id
            let activeEmbeddingCount = activeProfileID.map { profileID in
                storedEmbeddings.filter { $0.profileID == profileID }.count
            } ?? 0
            guard let index = vaultItems.firstIndex(where: { $0.id == id }) else { return }
            let item = vaultItems[index]
            var items = vaultItems
            items[index] = PinesVaultItemPreview(
                id: item.id,
                title: item.title,
                kind: item.kind,
                detail: item.detail,
                chunks: chunks,
                updatedLabel: item.updatedLabel,
                sensitivity: item.sensitivity,
                linkedThreads: vaultRetrievalEvents.filter { $0.resultCount > 0 }.count,
                activeProfileEmbeddedChunks: activeEmbeddingCount,
                activeProfileTotalChunks: chunks.count
            )
            setIfChanged(\.vaultItems, items)
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
        }
    }

    func reindexVault(services: PinesAppServices) async {
        guard !isVaultReindexing else { return }
        let token = UUID()
        vaultReindexToken = token
        setIfChanged(\.isVaultReindexing, true)
        defer {
            if vaultReindexToken == token {
                vaultReindexToken = nil
            }
            setIfChanged(\.isVaultReindexing, false)
        }

        guard let repository = services.vaultRepository,
              let embeddingService = services.vaultEmbeddingService
        else {
            setIfChanged(\.serviceError, "Vault embedding service is unavailable.")
            return
        }

        guard let profile = await ensureVaultEmbeddingProfile(
            services: services,
            reason: "Pines will send existing vault document chunks to this cloud embedding provider to rebuild your semantic index."
        ) else {
            return
        }

        do {
            let documents = try await repository.listDocuments()
            for document in documents {
                try Task.checkCancellation()
                guard vaultReindexToken == token else {
                    throw CancellationError()
                }
                let chunks = try await repository.chunks(documentID: document.id)
                guard !chunks.isEmpty else { continue }
                var job = VaultEmbeddingJob(
                    profileID: profile.id,
                    documentID: document.id,
                    status: .running,
                    totalChunks: chunks.count,
                    attemptCount: 1
                )
                try await repository.upsertEmbeddingJob(job)
                await refreshVaultEmbeddingState(services: services)
                do {
                    let jobID = job.id
                    let jobCreatedAt = job.createdAt
                    let documentID = document.id
                    let totalChunks = chunks.count
                    let profileID = profile.id
                    let embeddings = try await embeddingService.embed(
                        chunks: chunks,
                        documentID: documentID,
                        profile: profile,
                        progress: { [self] processed in
                            let shouldContinue = await MainActor.run {
                                self.vaultReindexToken == token
                            }
                            guard shouldContinue else {
                                throw CancellationError()
                            }
                            try await repository.upsertEmbeddingJob(
                                VaultEmbeddingJob(
                                    id: jobID,
                                    profileID: profileID,
                                    documentID: documentID,
                                    status: .running,
                                    processedChunks: processed,
                                    totalChunks: totalChunks,
                                    attemptCount: 1,
                                    createdAt: jobCreatedAt,
                                    updatedAt: Date()
                                )
                            )
                            await self.refreshVaultEmbeddingState(services: services)
                        }
                    )
                    try await repository.upsertEmbeddings(
                        VaultEmbeddingBatch(modelID: profile.modelID, embeddings: embeddings),
                        documentID: document.id,
                        embeddingProfile: profile
                    )
                    job.status = .complete
                    job.processedChunks = embeddings.count
                    job.updatedAt = Date()
                    try await repository.upsertEmbeddingJob(job)
                } catch {
                    job.status = .failed
                    job.lastError = error.localizedDescription
                    job.updatedAt = Date()
                    try await repository.upsertEmbeddingJob(job)
                }
            }
            await refreshAll(services: services)
            emitHaptic(.runCompleted)
        } catch is CancellationError {
            if let repository = services.vaultRepository {
                let jobs = (try? await repository.listEmbeddingJobs(limit: 20)) ?? vaultEmbeddingJobs
                for var job in jobs where job.status == .running {
                    job.status = .cancelled
                    job.updatedAt = Date()
                    try? await repository.upsertEmbeddingJob(job)
                }
                await refreshVaultEmbeddingState(services: services)
            }
            emitHaptic(.runCancelled)
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
            emitHaptic(.runFailed)
        }
    }

    func cancelVaultReindex() {
        vaultReindexToken = nil
        if isVaultReindexing {
            emitHaptic(.runCancelled)
        }
    }

    func saveCloudProvider(
        kind: CloudProviderKind,
        displayName: String,
        baseURLString: String,
        apiKey: String,
        enabledForAgents: Bool,
        services: PinesAppServices
    ) async {
        setIfChanged(\.isSavingCloudProvider, true)
        defer { setIfChanged(\.isSavingCloudProvider, false) }

        do {
            guard let service = services.cloudProviderService else {
                serviceError = "Cloud provider service is unavailable."
                return
            }
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDisplayName.isEmpty else {
                serviceError = "Cloud provider display name is required."
                return
            }
            guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                serviceError = "Cloud provider base URL is invalid."
                return
            }
            let providerID = ProviderID(rawValue: trimmedDisplayName.lowercased().replacingOccurrences(of: " ", with: "-"))
            let existing = cloudProviders.first(where: { $0.id == providerID })
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let provider = CloudProviderConfiguration(
                id: providerID,
                kind: kind,
                displayName: trimmedDisplayName,
                baseURL: baseURL,
                defaultModelID: existing?.defaultModelID,
                validationStatus: .unvalidated,
                extraHeadersJSON: existing?.extraHeadersJSON,
                keychainService: existing?.keychainService ?? "com.schtack.pines.cloud",
                keychainAccount: existing?.keychainAccount ?? providerID.rawValue,
                enabledForAgents: kind == .voyageAI ? false : enabledForAgents
            )
            try await service.saveProvider(provider, apiKey: trimmedAPIKey.isEmpty ? nil : trimmedAPIKey)
            upsertCloudProvider(provider)
            await refreshCloudProviders(services: services)
            await refreshVaultEmbeddingState(services: services)
            setIfChanged(\.serviceError, nil)
            Task { [weak self] in
                await self?.refreshCloudModelCatalog(services: services)
            }
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func validateCloudProvider(_ provider: CloudProviderConfiguration, services: PinesAppServices) async {
        validatingCloudProviderIDs.insert(provider.id)
        defer { validatingCloudProviderIDs.remove(provider.id) }

        do {
            guard let service = services.cloudProviderService else {
                serviceError = "Cloud provider service is unavailable."
                return
            }
            _ = try await service.validate(provider)
            await refreshCloudProviders(services: services)
            setIfChanged(\.serviceError, nil)
            Task { [weak self] in
                await self?.refreshCloudModelCatalog(services: services)
            }
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
            if defaultProviderID == provider.id {
                setIfChanged(\.defaultProviderID, nil)
                setIfChanged(\.defaultModelID, nil)
                await saveSettings(services: services)
            }
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func refreshCloudModelCatalog(services: PinesAppServices) async {
        guard !isRefreshingCloudModels else { return }
        setIfChanged(\.isRefreshingCloudModels, true)
        defer { setIfChanged(\.isRefreshingCloudModels, false) }

        var nextCatalog: [ProviderID: [CloudProviderModel]] = [:]
        for provider in cloudProviders {
            do {
                guard let apiKey = try await services.secretStore.read(
                    service: provider.keychainService,
                    account: provider.keychainAccount
                )?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
                    continue
                }
                let inferenceProvider = BYOKCloudInferenceProvider(configuration: provider, secretStore: services.secretStore)
                let models = try await inferenceProvider.listTextModels()
                if !models.isEmpty {
                    nextCatalog[provider.id] = models
                }
            } catch {
                continue
            }
        }
        setIfChanged(\.cloudModelCatalog, nextCatalog)
    }

    func modelPickerSections(services: PinesAppServices) -> [ModelPickerSection] {
        var sections = [ModelPickerSection]()
        let localModels = models
            .map(\.install)
            .filter { $0.state == .installed && $0.modalities.contains(.text) }
            .sorted { lhs, rhs in
                localModelScore(lhs) > localModelScore(rhs)
            }
            .map { install in
                ModelPickerOption(
                    providerID: services.mlxRuntime.localProviderID,
                    providerName: "Local",
                    providerKind: nil,
                    modelID: install.modelID,
                    displayName: Self.localModelDisplayName(install),
                    isLocal: true,
                    rank: localModelScore(install)
                )
            }
        if !localModels.isEmpty {
            sections.append(ModelPickerSection(title: "Local", models: localModels))
        }

        for provider in cloudProviders.sorted(by: { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) {
            let providerModels = (cloudModelCatalog[provider.id] ?? [])
                .map { model in
                    ModelPickerOption(
                        providerID: provider.id,
                        providerName: provider.displayName,
                        providerKind: provider.kind,
                        modelID: model.id,
                        displayName: model.displayName,
                        isLocal: false,
                        rank: model.rank
                    )
                }
            guard !providerModels.isEmpty else { continue }
            sections.append(ModelPickerSection(title: provider.displayName, models: providerModels))
        }

        return sections
    }

    func selectModel(_ option: ModelPickerOption, services: PinesAppServices, createNewChat: Bool = false) async -> UUID? {
        setIfChanged(\.defaultProviderID, option.providerID)
        setIfChanged(\.defaultModelID, option.modelID)
        await recordCloudDefaultModelIfNeeded(option, services: services)
        await saveSettings(services: services)
        emitHaptic(.primaryAction)
        if createNewChat {
            return await createChat(services: services)
        }
        return nil
    }

    func selectModel(_ option: ModelPickerOption, for threadID: UUID, services: PinesAppServices) async {
        setIfChanged(\.defaultProviderID, option.providerID)
        setIfChanged(\.defaultModelID, option.modelID)
        await recordCloudDefaultModelIfNeeded(option, services: services)
        await saveSettings(services: services)

        guard let repository = services.conversationRepository else {
            setChatError("Conversation repository is unavailable.")
            emitHaptic(.runFailed)
            return
        }

        do {
            try await repository.updateConversationModel(
                modelID: option.modelID,
                providerID: option.providerID,
                conversationID: threadID
            )
            if let thread = threads.first(where: { $0.id == threadID }) {
                upsertThreadPreview(
                    PinesThreadPreview(
                        id: thread.id,
                        title: thread.title,
                        modelName: option.displayName,
                        modelID: option.modelID,
                        providerID: option.providerID,
                        lastMessage: thread.lastMessage,
                        messages: thread.messages,
                        status: thread.status,
                        isPinned: thread.isPinned,
                        updatedLabel: RelativeDateTimeFormatter.shortLabel(for: Date()),
                        tokenCount: thread.tokenCount
                    ),
                    moveToFront: true
                )
            }
            clearChatError()
            emitHaptic(.primaryAction)
        } catch {
            setChatError(error.localizedDescription)
            emitHaptic(.runFailed)
        }
    }

    private func recordCloudDefaultModelIfNeeded(_ option: ModelPickerOption, services: PinesAppServices) async {
        guard option.providerID != services.mlxRuntime.localProviderID,
              let repository = services.cloudProviderRepository,
              var provider = cloudProviders.first(where: { $0.id == option.providerID }),
              provider.defaultModelID != option.modelID
        else {
            return
        }
        provider.defaultModelID = option.modelID
        do {
            try await repository.upsertProvider(provider)
            upsertCloudProvider(provider)
        } catch {
            setIfChanged(\.serviceError, error.localizedDescription)
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
                oauthClientID: oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).pinesNilIfEmpty,
                oauthScopes: oauthScopes.trimmingCharacters(in: .whitespacesAndNewlines).pinesNilIfEmpty,
                oauthResource: oauthResource.trimmingCharacters(in: .whitespacesAndNewlines).pinesNilIfEmpty,
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
                    let snapshot = await MainActor.run {
                        (
                            downloads: self?.modelDownloads ?? [],
                            enrichRuntime: self?.shouldEnrichRuntimeModelPreviews ?? false
                        )
                    }
                    let downloads = snapshot.downloads
                    let downloadByRepository = Self.latestDownloadByRepository(downloads)
                    let installByRepository = Dictionary(uniqueKeysWithValues: installs.map { ($0.repository.lowercased(), $0) })
                    await MainActor.run {
                        guard let self else { return }
                        if self.isShowingModelDiscoveryResults {
                            let previews = self.models.map { preview in
                                let key = preview.install.repository.lowercased()
                                if let install = installByRepository[key] {
                                    return Self.modelPreview(
                                        from: install,
                                        runtime: services.mlxRuntime,
                                        download: downloadByRepository[key],
                                        enrichRuntime: snapshot.enrichRuntime
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
                                    download: downloadByRepository[key],
                                    enrichRuntime: snapshot.enrichRuntime
                                )
                            }
                            self.setIfChanged(\.models, Self.downloadingFirst(previews))
                        } else {
                            let previews = installs.map { install in
                                Self.modelPreview(
                                    from: install,
                                    runtime: services.mlxRuntime,
                                    download: downloadByRepository[install.repository.lowercased()],
                                    enrichRuntime: snapshot.enrichRuntime
                                )
                            }
                            self.setIfChanged(\.models, Self.downloadingFirst(previews))
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
                        let previousDownloads = self.modelDownloads
                        self.setIfChanged(\.modelDownloads, downloads)
                        let previousDownloadByRepository = Self.latestDownloadByRepository(previousDownloads)
                        let downloadByRepository = Self.latestDownloadByRepository(downloads)
                        let changedRepositories = Set(previousDownloadByRepository.keys)
                            .union(downloadByRepository.keys)
                            .filter { previousDownloadByRepository[$0] != downloadByRepository[$0] }
                        guard !changedRepositories.isEmpty else { return }

                        let previews = self.models.map { preview in
                            let key = preview.install.repository.lowercased()
                            guard changedRepositories.contains(key) else { return preview }
                            return Self.modelPreview(
                                from: preview.install,
                                runtime: services.mlxRuntime,
                                download: downloadByRepository[key],
                                enrichRuntime: self.shouldEnrichRuntimeModelPreviews
                            )
                        }
                        self.setIfChanged(\.models, Self.downloadingFirst(previews))
                    }
                }
            })
        }

        if let settingsRepository = services.settingsRepository {
            repositoryObservationTasks.append(Task { [weak self] in
                for await settings in settingsRepository.observeSettings() {
                    await MainActor.run {
                        self?.setIfChanged(\.defaultModelID, settings.defaultModelID)
                        self?.setIfChanged(\.defaultProviderID, settings.defaultProviderID)
                        self?.setIfChanged(\.executionMode, settings.executionMode)
                        self?.setIfChanged(\.storeConfiguration, settings.storeConfiguration)
                        self?.setIfChanged(\.cloudMaxCompletionTokens, settings.cloudMaxCompletionTokens)
                        self?.setIfChanged(\.localMaxCompletionTokens, settings.localMaxCompletionTokens)
                        self?.setIfChanged(\.localMaxContextTokens, settings.localMaxContextTokens)
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
                for await records in conversationRepository.observeConversationPreviews() {
                    await MainActor.run {
                        guard let self else { return }
                        self.setIfChanged(\.threads, self.mergeThreadPreviews(records.map(Self.threadPreview(from:))))
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

            repositoryObservationTasks.append(Task { [weak self] in
                for await profiles in vaultRepository.observeEmbeddingProfiles() {
                    await MainActor.run {
                        self?.setIfChanged(\.vaultEmbeddingProfiles, profiles)
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

    func requestCloudContextApproval(_ request: CloudContextApprovalRequest) async -> CloudContextApprovalDecision {
        cloudContextContinuation?.resume(returning: .cancel)
        pendingCloudContextApproval = request
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            cloudContextContinuation = continuation
        }
    }

    func resolvePendingCloudContextApproval(_ decision: CloudContextApprovalDecision) {
        pendingCloudContextApproval = nil
        emitHaptic(decision == .sendWithContext ? .primaryAction : .runCancelled)
        cloudContextContinuation?.resume(returning: decision)
        cloudContextContinuation = nil
    }

    func requestCloudVaultEmbeddingApproval(_ request: CloudVaultEmbeddingApprovalRequest) async -> Bool {
        cloudVaultEmbeddingContinuation?.resume(returning: false)
        pendingCloudVaultEmbeddingApproval = request
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            cloudVaultEmbeddingContinuation = continuation
        }
    }

    func resolvePendingCloudVaultEmbeddingApproval(_ approved: Bool) {
        pendingCloudVaultEmbeddingApproval = nil
        emitHaptic(approved ? .primaryAction : .runCancelled)
        cloudVaultEmbeddingContinuation?.resume(returning: approved)
        cloudVaultEmbeddingContinuation = nil
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
        let requiredInputs = ProviderInputRequirements(messages: messages)
        let settings = try? await services.settingsRepository?.loadSettings()

        if let localModelID = rankedLocalModelID(for: request, requiredInputs: requiredInputs),
           let localInstall = installedModel(for: localModelID) {
            try await services.mlxRuntime.load(
                localInstall,
                profile: localRuntimeProfile(for: localInstall, settings: settings, services: services)
            )
            let sampling = chatSampling(
                for: services.mlxRuntime.localProviderID,
                settings: settings,
                services: services,
                requestedMaxTokens: request.maxTokens,
                temperature: Float(request.temperature ?? 0.6)
            )
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
              let cloudProvider = rankedCloudProvider(for: request, requiredInputs: requiredInputs, requiresTools: !tools.isEmpty)
        else {
            throw InferenceError.providerUnavailable(services.mlxRuntime.localProviderID)
        }
        guard let cloudModelID = cloudProvider.defaultModelID else {
            throw InferenceError.invalidRequest("The selected cloud provider does not define a default model.")
        }
        let sampling = chatSampling(
            for: cloudProvider.id,
            settings: settings,
            services: services,
            requestedMaxTokens: request.maxTokens,
            temperature: Float(request.temperature ?? 0.6)
        )
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

    private func rankedLocalModelID(for request: MCPSamplingRequest, requiredInputs: ProviderInputRequirements) -> ModelID? {
        guard !requiredInputs.requiresPDFs && !requiredInputs.requiresTextDocuments else { return nil }
        let preference = MCPModelPreferenceProfile(json: request.modelPreferences)
        let candidates = models
            .map(\.install)
            .filter { install in
                install.state == .installed
                    && install.modalities.contains(.text)
                    && (!requiredInputs.requiresImages || install.modalities.contains(.vision))
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

    private func providerDisplayName(for providerID: ProviderID, services: PinesAppServices) -> String {
        if providerID == services.mlxRuntime.localProviderID {
            return "Local"
        }
        return cloudProviders.first(where: { $0.id == providerID })?.displayName ?? providerID.rawValue
    }

    private func emptyCloudOutputMessage(
        providerID: ProviderID,
        modelID: ModelID,
        services: PinesAppServices
    ) -> String {
        guard providerID != services.mlxRuntime.localProviderID else {
            return "The selected model finished without producing output."
        }
        let providerName = providerDisplayName(for: providerID, services: services)
        return "\(providerName) returned a successful stream for \(modelID.rawValue), but Pines did not receive visible text. Check the provider event diagnostics above and retry with a text-capable chat model."
    }

    private func messageWithProviderDiagnostics(_ message: String, metadata: [String: String]) -> String {
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

    private func providerKind(for providerID: ProviderID, services: PinesAppServices) -> CloudProviderKind? {
        if providerID == services.mlxRuntime.localProviderID {
            return nil
        }
        return cloudProviders.first(where: { $0.id == providerID })?.kind
    }

    private func displayName(for modelID: ModelID, providerID: ProviderID) -> String {
        if let install = installedModel(for: modelID), install.modelID == modelID {
            return Self.localModelDisplayName(install)
        }
        if let model = cloudModelCatalog[providerID]?.first(where: { $0.id == modelID }) {
            return model.displayName
        }
        return Self.friendlyModelName(modelID.rawValue)
    }

    private func localModelScore(_ install: ModelInstall) -> Double {
        let parameterScale = min(Double(install.parameterCount ?? 0) / 10_000_000_000, 10)
        let byteScale = min(Double(install.estimatedBytes ?? 0) / 10_000_000_000, 10)
        return parameterScale * 10 + byteScale
    }

    private func rankedCloudProvider(for request: MCPSamplingRequest, requiredInputs: ProviderInputRequirements, requiresTools: Bool) -> CloudProviderConfiguration? {
        let preference = MCPModelPreferenceProfile(json: request.modelPreferences)
        let candidates = cloudProviders.filter { provider in
            provider.enabledForAgents
                && provider.capabilities.textGeneration
                && requiredInputs.isSatisfied(by: provider.capabilities)
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

    private func refreshModelPreviews(services: PinesAppServices, enrichRuntime: Bool? = nil) async throws {
        let downloads = try await services.modelDownloadRepository?.listDownloads() ?? []
        setIfChanged(\.modelDownloads, downloads)

        guard let modelRepository = services.modelInstallRepository else {
            setIfChanged(\.models, [])
            return
        }

        let downloadByRepository = Self.latestDownloadByRepository(downloads)
        let shouldEnrichRuntime = enrichRuntime ?? shouldEnrichRuntimeModelPreviews
        let previews = try await modelRepository
            .listInstalledAndCuratedModels()
            .map { install in
                Self.modelPreview(
                    from: install,
                    runtime: services.mlxRuntime,
                    download: downloadByRepository[install.repository.lowercased()],
                    enrichRuntime: shouldEnrichRuntime
                )
            }
        setIfChanged(\.models, Self.downloadingFirst(previews))
    }

    private static func threadPreview(
        from record: ConversationRecord,
        messages: [ChatMessage],
        status: PinesThreadStatus? = nil,
        updatedAt: Date? = nil
    ) -> PinesThreadPreview {
        let lastMessage = previewText(for: messages.last)
        return PinesThreadPreview(
            id: record.id,
            title: record.title,
            modelName: record.defaultModelID.map { friendlyModelName($0.rawValue) } ?? "No model selected",
            modelID: record.defaultModelID ?? ModelID(rawValue: "unselected-local-model"),
            providerID: record.defaultProviderID,
            lastMessage: lastMessage ?? "No messages yet.",
            messages: messages,
            status: record.archived ? .archived : (status ?? .local),
            isPinned: record.pinned,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: updatedAt ?? record.updatedAt),
            tokenCount: threadTokenCount(messages)
        )
    }

    private static func localModelDisplayName(_ install: ModelInstall) -> String {
        friendlyModelName(install.displayName.isEmpty ? install.repository : install.displayName)
    }

    private static func friendlyModelName(_ rawValue: String) -> String {
        var name = rawValue
            .replacingOccurrences(of: "mlx-community/", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "mlx-community", with: "", options: [.caseInsensitive])
        if name.contains("/") {
            name = name.split(separator: "/").last.map(String.init) ?? name
        }
        return name
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-/ ").union(.whitespacesAndNewlines))
    }

    private static func threadPreview(from record: ConversationPreviewRecord) -> PinesThreadPreview {
        let lastMessage = record.lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status: PinesThreadStatus = record.archived ? .archived : .local
        return PinesThreadPreview(
            id: record.id,
            title: record.title,
            modelName: record.defaultModelID.map { friendlyModelName($0.rawValue) } ?? "No model selected",
            modelID: record.defaultModelID ?? ModelID(rawValue: "unselected-local-model"),
            providerID: record.defaultProviderID,
            lastMessage: lastMessage?.isEmpty == false ? lastMessage! : "No messages yet.",
            messages: [],
            status: status,
            isPinned: record.pinned,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            tokenCount: record.tokenCount
        )
    }

    private static func threadPreview(
        from existing: PinesThreadPreview,
        messages: [ChatMessage],
        status: PinesThreadStatus? = nil,
        updatedAt: Date = Date()
    ) -> PinesThreadPreview {
        let lastMessage = previewText(for: messages.last)
        let resolvedStatus = existing.status == .archived ? PinesThreadStatus.archived : (status ?? existing.status)
        return PinesThreadPreview(
            id: existing.id,
            title: existing.title,
            modelName: existing.modelName,
            modelID: existing.modelID,
            providerID: existing.providerID,
            lastMessage: lastMessage ?? "No messages yet.",
            messages: messages,
            status: resolvedStatus,
            isPinned: existing.isPinned,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: updatedAt),
            tokenCount: resolvedStatus == .streaming ? existing.tokenCount : threadTokenCount(messages)
        )
    }

    private static func threadTokenCount(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + max(1, $1.content.split(separator: " ").count) }
    }

    private static func previewText(for message: ChatMessage?) -> String? {
        guard let message else { return nil }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        guard !message.attachments.isEmpty else { return nil }
        return message.attachments.count == 1
            ? "1 attachment"
            : "\(message.attachments.count) attachments"
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
        download: ModelDownloadProgress? = nil,
        enrichRuntime: Bool = true
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
        } else if download?.status == .installed || install.state == .installed {
            readiness = 1
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

        let runtimeProfile = enrichRuntime
            ? runtime.defaultRuntimeProfile(for: install)
            : RuntimeProfile(
                name: "Pending",
                quantization: QuantizationProfile(
                    algorithm: .none,
                    kvCacheStrategy: .none,
                    preset: nil,
                    requestedBackend: nil,
                    activeBackend: nil,
                    activeAttentionPath: nil,
                    activeFallbackReason: "Runtime diagnostics load after startup."
                ),
                promptCacheIdentifier: install.repository
            )
        let contextWindow = enrichRuntime
            ? (runtime.capabilities.maxContextTokens.map { "\($0 / 1000)K" } ?? "Unknown")
            : "Pending"

        return PinesModelPreview(
            id: install.id,
            install: install,
            runtimeProfile: runtimeProfile,
            name: install.displayName,
            family: install.modelType ?? install.modalities.map(\.rawValue).sorted().joined(separator: ", "),
            footprint: install.estimatedBytes.map(Self.byteLabel) ?? download?.totalBytes.map(Self.byteLabel) ?? "Remote",
            contextWindow: contextWindow,
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

    private static func downloadingFirst(_ previews: [PinesModelPreview]) -> [PinesModelPreview] {
        previews.enumerated()
            .sorted { lhs, rhs in
                let lhsActive = lhs.element.isDownloadActive
                let rhsActive = rhs.element.isDownloadActive
                if lhsActive != rhsActive {
                    return lhsActive
                }
                if lhsActive,
                   let lhsUpdated = lhs.element.downloadProgress?.updatedAt,
                   let rhsUpdated = rhs.element.downloadProgress?.updatedAt,
                   lhsUpdated != rhsUpdated {
                    return lhsUpdated > rhsUpdated
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
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
            linkedThreads: 0,
            activeProfileEmbeddedChunks: 0,
            activeProfileTotalChunks: record.chunkCount
        )
    }

    private static func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
