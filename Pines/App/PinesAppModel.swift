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
    @Published var pendingToolApproval: ToolApprovalRequest?
    @Published var modelDownloads: [ModelDownloadProgress] = []
    @Published var isSearchingModels = false
    @Published var modelSearchError: String?
    @Published var defaultModelID: ModelID?
    @Published var huggingFaceCredentialStatus = "Not configured"
    @Published var braveSearchCredentialStatus = "Not configured"
    private var currentRunTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<ToolApprovalStatus, Never>?

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

    func bootstrap(services: PinesAppServices) async {
        await refreshAll(services: services)
        observeRepositories(services: services)
    }

    func refreshAll(services: PinesAppServices) async {
        do {
            if let settingsRepository = services.settingsRepository {
                let settings = try await settingsRepository.loadSettings()
                executionMode = settings.executionMode
                storeConfiguration = settings.storeConfiguration
                defaultModelID = settings.defaultModelID
                selectedThemeTemplate = PinesThemeTemplate(rawValue: settings.themeTemplate) ?? selectedThemeTemplate
                interfaceMode = PinesInterfaceMode(rawValue: settings.interfaceMode) ?? interfaceMode
            }

            let downloads = try await services.modelDownloadRepository?.listDownloads() ?? []
            modelDownloads = downloads

            if let modelRepository = services.modelInstallRepository {
                let downloadByRepository = Self.latestDownloadByRepository(downloads)
                models = try await modelRepository
                    .listInstalledAndCuratedModels()
                    .map { install in
                        Self.modelPreview(
                            from: install,
                            runtime: services.mlxRuntime,
                            download: downloadByRepository[install.repository.lowercased()]
                        )
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
                threads = previews
            }

            if let vaultRepository = services.vaultRepository {
                vaultItems = try await vaultRepository.listDocuments().map(Self.vaultPreview(from:))
            }

            if let auditRepository = services.auditRepository {
                auditEvents = try await auditRepository.list(category: nil, limit: 30)
            }

            if let cloudProviderRepository = services.cloudProviderRepository {
                cloudProviders = try await cloudProviderRepository.listProviders()
            }

            if let mcpServerRepository = services.mcpServerRepository {
                mcpServers = try await mcpServerRepository.listMCPServers()
                mcpTools = try await mcpServerRepository.listMCPTools(serverID: nil)
            }

            await refreshCredentialStatuses(services: services)
            serviceError = nil
        } catch {
            serviceError = error.localizedDescription
        }
    }

    func createChat(services: PinesAppServices) async -> UUID? {
        do {
            guard let repository = services.conversationRepository else {
                serviceError = "Conversation repository is unavailable."
                return nil
            }
            let modelID = defaultModelID
                ?? models.first(where: { $0.install.state == .installed })?.install.modelID
                ?? models.first?.install.modelID
            let conversation = try await repository.createConversation(title: "New chat", defaultModelID: modelID)
            await refreshAll(services: services)
            return conversation.id
        } catch {
            serviceError = error.localizedDescription
            return nil
        }
    }

    func startSending(_ draft: String, in threadID: UUID?, services: PinesAppServices) {
        currentRunTask?.cancel()
        currentRunTask = Task { [weak self] in
            await self?.sendMessage(draft, in: threadID, services: services)
        }
    }

    func stopCurrentRun() {
        currentRunTask?.cancel()
        currentRunTask = nil
        activeRunID = nil
        resolvePendingToolApproval(.denied)
    }

    func retryLastUserMessage(in thread: PinesThreadPreview, services: PinesAppServices) {
        guard let lastUser = thread.messages.last(where: { $0.role == .user }) else { return }
        startSending(lastUser.content, in: thread.id, services: services)
    }

    private func sendMessage(_ draft: String, in threadID: UUID?, services: PinesAppServices) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            guard let repository = services.conversationRepository else {
                serviceError = "Conversation repository is unavailable."
                return
            }

            let conversationID: UUID
            if let threadID {
                conversationID = threadID
            } else if let created = await createChat(services: services) {
                conversationID = created
            } else {
                return
            }

            let modelID = defaultModelID
                ?? threads.first(where: { $0.id == conversationID })?.modelID
                ?? models.first(where: { $0.install.state == .installed })?.install.modelID
                ?? models.first?.install.modelID
                ?? ModelID(rawValue: "mlx-community/Llama-3.2-1B-Instruct-4bit")
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
                selectedProvider = services.mlxRuntime
                selectedProviderID = services.mlxRuntime.localProviderID
                selectedModelID = modelID
            case let .cloud(providerID):
                guard let cloudCandidate else {
                    serviceError = "No enabled cloud provider is configured for agents."
                    return
                }
                selectedProvider = cloudCandidate.1
                selectedProviderID = providerID
                selectedModelID = cloudCandidate.0.defaultModelID ?? modelID
            case let .denied(reason):
                serviceError = "\(reason)"
                return
            }

            let userMessage = ChatMessage(role: .user, content: trimmed)
            try await repository.appendMessage(userMessage, status: .complete, conversationID: conversationID, modelID: selectedModelID, providerID: nil)

            let assistantMessage = ChatMessage(role: .assistant, content: "")
            try await repository.appendMessage(assistantMessage, status: .streaming, conversationID: conversationID, modelID: selectedModelID, providerID: selectedProviderID)

            activeRunID = assistantMessage.id
            await refreshAll(services: services)

            let messages = try await repository.messages(in: conversationID)
            let vaultContext = await vaultContextMessage(for: trimmed, services: services)
            var requestMessages = messages
            if let vaultContext {
                requestMessages.insert(vaultContext.message, at: 0)
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
            var accumulated = ""
            var tokenCount = 0
            let generationStartedAt = Date()

            for try await event in stream {
                guard !Task.isCancelled else { throw InferenceError.cancelled }
                switch event {
                case let .token(delta):
                    accumulated += delta.text
                    tokenCount += max(delta.tokenCount, 1)
                    try await repository.updateMessage(id: assistantMessage.id, content: accumulated, status: .streaming, tokenCount: tokenCount)
                case let .finish(finish):
                    let status: MessageStatus = finish.reason == .cancelled ? .cancelled : .complete
                    try await repository.updateMessage(id: assistantMessage.id, content: accumulated, status: status, tokenCount: tokenCount)
                case let .failure(failure):
                    try await repository.updateMessage(id: assistantMessage.id, content: failure.message, status: .failed, tokenCount: tokenCount)
                case let .metrics(metrics):
                    services.runtimeMetrics.recordGenerationMetrics(metrics, modelID: selectedModelID)
                case .toolCall:
                    break
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
        } catch {
            activeRunID = nil
            currentRunTask = nil
            serviceError = error.localizedDescription
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

    func saveSettings(services: PinesAppServices) async {
        do {
            let snapshot = AppSettingsSnapshot(
                executionMode: executionMode,
                storeConfiguration: storeConfiguration,
                defaultModelID: defaultModelID ?? models.first(where: { $0.install.state == .installed })?.install.modelID,
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
                serviceError = "Model lifecycle service is unavailable."
                return
            }
            try await lifecycle.install(repository: repository)
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
            await refreshAll(services: services)
        }
    }

    func deleteModel(repository: String, services: PinesAppServices) async {
        do {
            guard let lifecycle = services.modelLifecycleService else {
                serviceError = "Model lifecycle service is unavailable."
                return
            }
            try await lifecycle.delete(repository: repository)
            if defaultModelID?.rawValue.lowercased() == repository.lowercased() {
                defaultModelID = nil
                await saveSettings(services: services)
            }
            await refreshAll(services: services)
        } catch {
            serviceError = error.localizedDescription
            await refreshAll(services: services)
        }
    }

    func selectDefaultModel(_ model: PinesModelPreview, services: PinesAppServices) async {
        defaultModelID = model.install.modelID
        await saveSettings(services: services)
    }

    func searchModels(
        query: String,
        task: HubTask? = nil,
        verification: ModelVerificationState? = nil,
        installState: ModelInstallState? = nil,
        services: PinesAppServices
    ) async {
        isSearchingModels = true
        modelSearchError = nil
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, task == nil, verification == nil, installState == nil {
                await refreshAll(services: services)
            } else {
                let token = try await services.huggingFaceCredentialService.readToken()
                let filters = ModelSearchFilters(query: query, task: task, limit: 30)
                let remoteModels = try await services.modelCatalog.search(filters: filters, accessToken: token)
                let installed = try await services.modelInstallRepository?.listInstalledAndCuratedModels() ?? []
                let installedByRepository = Dictionary(uniqueKeysWithValues: installed.map { ($0.repository.lowercased(), $0) })
                let downloadByRepository = Self.latestDownloadByRepository(modelDownloads)
                let previews = remoteModels.compactMap { summary -> PinesModelPreview? in
                    let install = installedByRepository[summary.repository.lowercased()]
                        ?? Self.install(from: summary)
                    guard verification == nil || install.verification == verification else { return nil }
                    guard installState == nil || install.state == installState else { return nil }
                    return Self.modelPreview(
                        from: install,
                        runtime: services.mlxRuntime,
                        download: downloadByRepository[install.repository.lowercased()]
                    )
                }
                models = previews
            }
            isSearchingModels = false
            serviceError = nil
        } catch {
            isSearchingModels = false
            modelSearchError = error.localizedDescription
            serviceError = error.localizedDescription
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
            modelSearchError = nil
        } catch {
            modelSearchError = error.localizedDescription
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
                oauthResource: oauthResource.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
        if let modelRepository = services.modelInstallRepository {
            Task { [weak self] in
                for await installs in modelRepository.observeInstalledAndCuratedModels() {
                    let downloads = await MainActor.run { self?.modelDownloads ?? [] }
                    let downloadByRepository = Self.latestDownloadByRepository(downloads)
                    await MainActor.run {
                        self?.models = installs.map { install in
                            Self.modelPreview(
                                from: install,
                                runtime: services.mlxRuntime,
                                download: downloadByRepository[install.repository.lowercased()]
                            )
                        }
                    }
                }
            }
        }

        if let downloadRepository = services.modelDownloadRepository {
            Task { [weak self] in
                for await downloads in downloadRepository.observeDownloads() {
                    await MainActor.run {
                        guard let self else { return }
                        self.modelDownloads = downloads
                        let downloadByRepository = Self.latestDownloadByRepository(downloads)
                        self.models = self.models.map { preview in
                            Self.modelPreview(
                                from: preview.install,
                                runtime: services.mlxRuntime,
                                download: downloadByRepository[preview.install.repository.lowercased()]
                            )
                        }
                    }
                }
            }
        }

        if let settingsRepository = services.settingsRepository {
            Task { [weak self] in
                for await settings in settingsRepository.observeSettings() {
                    await MainActor.run {
                        self?.defaultModelID = settings.defaultModelID
                        self?.executionMode = settings.executionMode
                        self?.storeConfiguration = settings.storeConfiguration
                        if let theme = PinesThemeTemplate(rawValue: settings.themeTemplate) {
                            self?.selectedThemeTemplate = theme
                        }
                        if let mode = PinesInterfaceMode(rawValue: settings.interfaceMode) {
                            self?.interfaceMode = mode
                        }
                    }
                }
            }
        }

        if let conversationRepository = services.conversationRepository {
            Task { [weak self] in
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
                        self?.threads = previews
                    }
                }
            }
        }

        if let vaultRepository = services.vaultRepository {
            Task { [weak self] in
                for await documents in vaultRepository.observeDocuments() {
                    await MainActor.run {
                        self?.vaultItems = documents.map(Self.vaultPreview(from:))
                    }
                }
            }
        }

        if let auditRepository = services.auditRepository {
            Task { [weak self] in
                for await events in auditRepository.observeRecent(limit: 30) {
                    await MainActor.run {
                        self?.auditEvents = events
                    }
                }
            }
        }

        if let cloudProviderRepository = services.cloudProviderRepository {
            Task { [weak self] in
                for await providers in cloudProviderRepository.observeProviders() {
                    await MainActor.run {
                        self?.cloudProviders = providers
                    }
                }
            }
        }

        if let mcpServerRepository = services.mcpServerRepository {
            Task { [weak self] in
                for await servers in mcpServerRepository.observeMCPServers() {
                    await MainActor.run {
                        self?.mcpServers = servers
                    }
                }
            }
            Task { [weak self] in
                for await tools in mcpServerRepository.observeMCPTools() {
                    await MainActor.run {
                        self?.mcpTools = tools
                    }
                }
            }
        }
    }

    func requestToolApproval(_ request: ToolApprovalRequest) async -> ToolApprovalStatus {
        pendingToolApproval = request
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    func resolvePendingToolApproval(_ status: ToolApprovalStatus) {
        pendingToolApproval = nil
        approvalContinuation?.resume(returning: status)
        approvalContinuation = nil
    }

    private func refreshCredentialStatuses(services: PinesAppServices) async {
        huggingFaceCredentialStatus = (try? await services.huggingFaceCredentialService.readToken())?.isEmpty == false
            ? "Configured"
            : "Not configured"
        braveSearchCredentialStatus = (try? await services.secretStore.read(
            service: BraveSearchTool.keychainService,
            account: BraveSearchTool.keychainAccount
        ))?.isEmpty == false ? "Configured" : "Not configured"
    }

    private static func threadPreview(from record: ConversationRecord, messages: [ChatMessage]) -> PinesThreadPreview {
        let lastMessage = messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return PinesThreadPreview(
            id: record.id,
            title: record.title,
            modelName: record.defaultModelID?.rawValue.components(separatedBy: "/").last ?? "Local model",
            modelID: record.defaultModelID ?? ModelID(rawValue: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
            lastMessage: lastMessage?.isEmpty == false ? lastMessage! : "No messages yet.",
            messages: messages,
            status: record.archived ? .archived : .local,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            tokenCount: messages.reduce(0) { $0 + max(1, $1.content.split(separator: " ").count) }
        )
    }

    private static func install(from summary: RemoteModelSummary) -> ModelInstall {
        let modalities: Set<ModelModality>
        switch summary.task {
        case .imageTextToText:
            modalities = [.text, .vision]
        case .featureExtraction, .sentenceSimilarity:
            modalities = [.embeddings]
        case .textGeneration, .none:
            modalities = [.text]
        }

        return ModelInstall(
            modelID: ModelID(rawValue: summary.repository),
            displayName: summary.repository.components(separatedBy: "/").last ?? summary.repository,
            repository: summary.repository,
            modalities: modalities,
            verification: CuratedModelManifest.default.contains(repository: summary.repository) ? .verified : .installable,
            state: .remote
        )
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
        if let download {
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
            subtitle: "Templates, light and dark mode, density, and motion.",
            systemImage: "paintpalette",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20010")!,
                    title: "Theme template",
                    detail: "Evergreen",
                    systemImage: "swatchpalette"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20011")!,
                    title: "Mode",
                    detail: "System",
                    systemImage: "circle.lefthalf.filled"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20001")!,
            title: "Inference",
            subtitle: "Runtime, memory, and model defaults.",
            systemImage: "cpu",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21001")!,
                    title: "Default model",
                    detail: "Qwen3 8B",
                    systemImage: "sparkles"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21002")!,
                    title: "Context budget",
                    detail: "32K tokens",
                    systemImage: "text.line.first.and.arrowtriangle.forward"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20002")!,
            title: "Privacy",
            subtitle: "Vault, sync, and key isolation.",
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
                    title: "Cloud sync",
                    detail: "Private database",
                    systemImage: "icloud"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20003")!,
            title: "Tools",
            subtitle: "Agent actions and approvals.",
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
                    title: "Workspace access",
                    detail: "Selected folders",
                    systemImage: "folder.badge.gearshape"
                )
            ]
        )
    ]

}
