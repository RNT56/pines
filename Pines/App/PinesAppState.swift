import Foundation
import SwiftUI
import PinesCore

struct PinesLiveChatMessageSnapshot: Hashable {
    var id: UUID
    var content: String
    var tokenCount: Int
    var providerMetadata: [String: String]
    var toolCalls: [ToolCallDelta]

    func merged(into message: ChatMessage) -> ChatMessage {
        var copy = message
        copy.content = content
        copy.providerMetadata = providerMetadata
        copy.toolCalls = toolCalls
        return copy
    }
}

@MainActor
final class PinesLiveChatMessage: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var snapshot: PinesLiveChatMessageSnapshot

    init(message: ChatMessage, tokenCount: Int = 0) {
        id = message.id
        snapshot = PinesLiveChatMessageSnapshot(
            id: message.id,
            content: message.content,
            tokenCount: tokenCount,
            providerMetadata: message.providerMetadata,
            toolCalls: message.toolCalls
        )
    }

    func update(
        content: String? = nil,
        tokenCount: Int? = nil,
        providerMetadata: [String: String]? = nil,
        toolCalls: [ToolCallDelta]? = nil
    ) {
        var next = snapshot
        if let content {
            next.content = content
        }
        if let tokenCount {
            next.tokenCount = tokenCount
        }
        if let providerMetadata {
            next.providerMetadata = providerMetadata
        }
        if let toolCalls {
            next.toolCalls = toolCalls
        }
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class PinesChatState: ObservableObject {
    @Published var threads: [PinesThreadPreview]
    @Published var projects: [PinesProjectPreview]
    @Published var selectedProjectID: UUID?
    @Published var chatError: String?
    @Published var activeRunID: UUID?
    private var liveMessages: [UUID: PinesLiveChatMessage]

    init(
        threads: [PinesThreadPreview] = [],
        projects: [PinesProjectPreview] = [],
        selectedProjectID: UUID? = nil,
        chatError: String? = nil,
        activeRunID: UUID? = nil
    ) {
        self.threads = threads
        self.projects = projects
        self.selectedProjectID = selectedProjectID
        self.chatError = chatError
        self.activeRunID = activeRunID
        liveMessages = [:]
    }

    func liveMessage(for id: UUID) -> PinesLiveChatMessage? {
        liveMessages[id]
    }

    func beginLiveMessage(_ message: ChatMessage) {
        liveMessages[message.id] = PinesLiveChatMessage(message: message)
    }

    func updateLiveMessage(
        id: UUID,
        content: String? = nil,
        tokenCount: Int? = nil,
        providerMetadata: [String: String]? = nil,
        toolCalls: [ToolCallDelta]? = nil
    ) {
        liveMessages[id]?.update(
            content: content,
            tokenCount: tokenCount,
            providerMetadata: providerMetadata,
            toolCalls: toolCalls
        )
    }

    func removeLiveMessage(id: UUID) {
        liveMessages[id] = nil
    }

    func removeAllLiveMessages() {
        liveMessages.removeAll()
    }
}

@MainActor
final class PinesModelState: ObservableObject {
    @Published var models: [PinesModelPreview]
    @Published var modelDownloads: [ModelDownloadProgress]
    @Published var isSearchingModels: Bool
    @Published var modelSearchError: String?
    @Published var defaultProviderID: ProviderID?
    @Published var defaultModelID: ModelID?

    init(
        models: [PinesModelPreview] = [],
        modelDownloads: [ModelDownloadProgress] = [],
        isSearchingModels: Bool = false,
        modelSearchError: String? = nil,
        defaultProviderID: ProviderID? = nil,
        defaultModelID: ModelID? = nil
    ) {
        self.models = models
        self.modelDownloads = modelDownloads
        self.isSearchingModels = isSearchingModels
        self.modelSearchError = modelSearchError
        self.defaultProviderID = defaultProviderID
        self.defaultModelID = defaultModelID
    }
}

@MainActor
final class PinesVaultState: ObservableObject {
    @Published var vaultItems: [PinesVaultItemPreview]
    @Published var selectedItemDetail: PinesVaultItemDetail?
    @Published var vaultEmbeddingProfiles: [VaultEmbeddingProfile]
    @Published var vaultEmbeddingJobs: [VaultEmbeddingJob]
    @Published var vaultRetrievalEvents: [VaultRetrievalEvent]
    @Published var vaultSearchResults: [VaultSearchResult]
    @Published var isVaultSearchPresented: Bool
    @Published var isVaultReindexing: Bool

    init(
        vaultItems: [PinesVaultItemPreview] = [],
        selectedItemDetail: PinesVaultItemDetail? = nil,
        vaultEmbeddingProfiles: [VaultEmbeddingProfile] = [],
        vaultEmbeddingJobs: [VaultEmbeddingJob] = [],
        vaultRetrievalEvents: [VaultRetrievalEvent] = [],
        vaultSearchResults: [VaultSearchResult] = [],
        isVaultSearchPresented: Bool = false,
        isVaultReindexing: Bool = false
    ) {
        self.vaultItems = vaultItems
        self.selectedItemDetail = selectedItemDetail
        self.vaultEmbeddingProfiles = vaultEmbeddingProfiles
        self.vaultEmbeddingJobs = vaultEmbeddingJobs
        self.vaultRetrievalEvents = vaultRetrievalEvents
        self.vaultSearchResults = vaultSearchResults
        self.isVaultSearchPresented = isVaultSearchPresented
        self.isVaultReindexing = isVaultReindexing
    }
}

enum PinesCloudKitSyncPhase: Equatable {
    case idle
    case syncing
    case succeeded
    case failed
}

struct PinesCloudKitSyncStatus: Equatable {
    var phase: PinesCloudKitSyncPhase = .idle
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?
    var trigger: String?
}

@MainActor
final class PinesSettingsState: ObservableObject {
    @Published var settingsSections: [PinesSettingsSection]
    @Published var securityConfiguration: SecurityConfiguration
    @Published var executionMode: AgentExecutionMode
    @Published var cloudAccessMode: CloudAccessMode
    @Published var proEntitlementStatus: ProEntitlementStatus
    @Published var managedCloudConsent: ManagedCloudConsent
    @Published var storeConfiguration: LocalStoreConfiguration
    @Published var selectedThemeTemplate: PinesThemeTemplate
    @Published var interfaceMode: PinesInterfaceMode
    @Published var auditEvents: [AuditEvent]
    @Published var cloudProviders: [CloudProviderConfiguration]
    @Published var mcpServers: [MCPServerConfiguration]
    @Published var mcpTools: [MCPToolRecord]
    @Published var mcpResources: [MCPResourceRecord]
    @Published var mcpResourceTemplates: [MCPResourceTemplateRecord]
    @Published var mcpPrompts: [MCPPromptRecord]
    @Published var cloudMaxCompletionTokens: Int
    @Published var localMaxCompletionTokens: Int
    @Published var localMaxContextTokens: Int
    @Published var localTurboQuantMode: TurboQuantUserMode
    @Published var openAIReasoningEffort: OpenAIReasoningEffort
    @Published var openAITextVerbosity: OpenAITextVerbosity
    @Published var anthropicEffort: AnthropicEffort
    @Published var anthropicThinkingMode: AnthropicThinkingMode
    @Published var anthropicThinkingBudgetTokens: Int
    @Published var anthropicPromptCachingEnabled: Bool
    @Published var anthropicPromptCacheTTL: AnthropicPromptCacheTTL
    @Published var anthropicCitationsEnabled: Bool
    @Published var anthropicTokenCountPreflightEnabled: Bool
    @Published var geminiThinkingLevel: GeminiThinkingLevel
    @Published var cloudWebSearchMode: CloudWebSearchMode
    @Published var openRouterProviderPreferences: OpenRouterProviderPreferences
    @Published var cloudModelCatalog: [ProviderID: [CloudProviderModel]]
    @Published var isRefreshingCloudModels: Bool
    @Published var isSavingCloudProvider: Bool
    @Published var validatingCloudProviderIDs: Set<ProviderID>
    @Published var cloudKitSyncStatus: PinesCloudKitSyncStatus
    @Published var cloudKitConflicts: [CloudKitConflictRecord]
    @Published var openRouterSpendReport: OpenRouterSpendReport
    @Published var huggingFaceCredentialStatus: String
    @Published var braveSearchCredentialStatus: String

    init(
        settingsSections: [PinesSettingsSection] = PinesStaticSettings.sections,
        securityConfiguration: SecurityConfiguration = .init(),
        executionMode: AgentExecutionMode = .preferLocal,
        cloudAccessMode: CloudAccessMode = AppSettingsSnapshot.defaultCloudAccessMode,
        proEntitlementStatus: ProEntitlementStatus = AppSettingsSnapshot.defaultProEntitlementStatus,
        managedCloudConsent: ManagedCloudConsent = AppSettingsSnapshot.defaultManagedCloudConsent,
        storeConfiguration: LocalStoreConfiguration = .init(),
        selectedThemeTemplate: PinesThemeTemplate = .evergreen,
        interfaceMode: PinesInterfaceMode = .system,
        auditEvents: [AuditEvent] = [],
        cloudProviders: [CloudProviderConfiguration] = [],
        mcpServers: [MCPServerConfiguration] = [],
        mcpTools: [MCPToolRecord] = [],
        mcpResources: [MCPResourceRecord] = [],
        mcpResourceTemplates: [MCPResourceTemplateRecord] = [],
        mcpPrompts: [MCPPromptRecord] = [],
        cloudMaxCompletionTokens: Int = AppSettingsSnapshot.defaultCloudMaxCompletionTokens,
        localMaxCompletionTokens: Int = AppSettingsSnapshot.defaultLocalMaxCompletionTokens,
        localMaxContextTokens: Int = AppSettingsSnapshot.defaultLocalMaxContextTokens,
        localTurboQuantMode: TurboQuantUserMode = AppSettingsSnapshot.defaultLocalTurboQuantMode,
        openAIReasoningEffort: OpenAIReasoningEffort = AppSettingsSnapshot.defaultOpenAIReasoningEffort,
        openAITextVerbosity: OpenAITextVerbosity = AppSettingsSnapshot.defaultOpenAITextVerbosity,
        anthropicEffort: AnthropicEffort = AppSettingsSnapshot.defaultAnthropicEffort,
        anthropicThinkingMode: AnthropicThinkingMode = AppSettingsSnapshot.defaultAnthropicThinkingMode,
        anthropicThinkingBudgetTokens: Int = AppSettingsSnapshot.defaultAnthropicThinkingBudgetTokens,
        anthropicPromptCachingEnabled: Bool = false,
        anthropicPromptCacheTTL: AnthropicPromptCacheTTL = .fiveMinutes,
        anthropicCitationsEnabled: Bool = true,
        anthropicTokenCountPreflightEnabled: Bool = false,
        geminiThinkingLevel: GeminiThinkingLevel = AppSettingsSnapshot.defaultGeminiThinkingLevel,
        cloudWebSearchMode: CloudWebSearchMode = AppSettingsSnapshot.defaultCloudWebSearchMode,
        openRouterProviderPreferences: OpenRouterProviderPreferences = AppSettingsSnapshot.defaultOpenRouterProviderPreferences,
        cloudModelCatalog: [ProviderID: [CloudProviderModel]] = [:],
        isRefreshingCloudModels: Bool = false,
        isSavingCloudProvider: Bool = false,
        validatingCloudProviderIDs: Set<ProviderID> = [],
        cloudKitSyncStatus: PinesCloudKitSyncStatus = .init(),
        cloudKitConflicts: [CloudKitConflictRecord] = [],
        openRouterSpendReport: OpenRouterSpendReport = .init(window: .month),
        huggingFaceCredentialStatus: String = "Not configured",
        braveSearchCredentialStatus: String = "Not configured"
    ) {
        self.settingsSections = settingsSections
        self.securityConfiguration = securityConfiguration
        self.executionMode = executionMode
        self.cloudAccessMode = cloudAccessMode
        self.proEntitlementStatus = proEntitlementStatus
        self.managedCloudConsent = managedCloudConsent
        self.storeConfiguration = storeConfiguration
        self.selectedThemeTemplate = selectedThemeTemplate
        self.interfaceMode = interfaceMode
        self.auditEvents = auditEvents
        self.cloudProviders = cloudProviders
        self.mcpServers = mcpServers
        self.mcpTools = mcpTools
        self.mcpResources = mcpResources
        self.mcpResourceTemplates = mcpResourceTemplates
        self.mcpPrompts = mcpPrompts
        self.cloudMaxCompletionTokens = cloudMaxCompletionTokens
        self.localMaxCompletionTokens = localMaxCompletionTokens
        self.localMaxContextTokens = localMaxContextTokens
        self.localTurboQuantMode = localTurboQuantMode
        self.openAIReasoningEffort = openAIReasoningEffort
        self.openAITextVerbosity = openAITextVerbosity
        self.anthropicEffort = anthropicEffort
        self.anthropicThinkingMode = anthropicThinkingMode
        self.anthropicThinkingBudgetTokens = AppSettingsSnapshot.normalizedAnthropicThinkingBudgetTokens(anthropicThinkingBudgetTokens)
        self.anthropicPromptCachingEnabled = anthropicPromptCachingEnabled
        self.anthropicPromptCacheTTL = anthropicPromptCacheTTL
        self.anthropicCitationsEnabled = anthropicCitationsEnabled
        self.anthropicTokenCountPreflightEnabled = anthropicTokenCountPreflightEnabled
        self.geminiThinkingLevel = geminiThinkingLevel
        self.cloudWebSearchMode = cloudWebSearchMode
        self.openRouterProviderPreferences = openRouterProviderPreferences
        self.cloudModelCatalog = cloudModelCatalog
        self.isRefreshingCloudModels = isRefreshingCloudModels
        self.isSavingCloudProvider = isSavingCloudProvider
        self.validatingCloudProviderIDs = validatingCloudProviderIDs
        self.cloudKitSyncStatus = cloudKitSyncStatus
        self.cloudKitConflicts = cloudKitConflicts
        self.openRouterSpendReport = openRouterSpendReport
        self.huggingFaceCredentialStatus = huggingFaceCredentialStatus
        self.braveSearchCredentialStatus = braveSearchCredentialStatus
    }
}

struct PinesProviderLifecycleSnapshot: Equatable {
    var artifactLibraryRevision: UInt64 = 0
    var providerTransfers: [ProviderTransferRecord] = []
    var providerFiles: [ProviderFileRecord] = []
    var providerFilePreviews: [PinesProviderFilePreview] = []
    var providerArtifacts: [ProviderArtifactRecord] = []
    var providerArtifactPreviews: [PinesProviderArtifactPreview] = []
    var providerCaches: [ProviderCacheRecord] = []
    var providerCachePreviews: [PinesProviderCachePreview] = []
    var providerVectorStores: [ProviderCacheRecord] = []
    var providerVectorStorePreviews: [PinesProviderCachePreview] = []
    var providerBatches: [ProviderBatchRecord] = []
    var providerBatchPreviews: [PinesProviderBatchPreview] = []
    var providerLiveSessions: [ProviderLiveSessionRecord] = []
    var providerLiveSessionPreviews: [PinesProviderLiveSessionPreview] = []
    var providerStructuredOutputs: [ProviderStructuredOutputRecord] = []
    var providerStructuredOutputPreviews: [PinesProviderStructuredOutputPreview] = []
    var providerModelCapabilities: [ProviderModelCapabilityRecord] = []
    var providerModelCapabilityPreviews: [PinesProviderModelCapabilityPreview] = []
    var providerResearchRuns: [ProviderResearchRunRecord] = []
    var providerResearchRunPreviews: [PinesProviderResearchRunPreview] = []
    var isRefreshing: Bool = false
    var error: String?
}

@MainActor
final class PinesProviderLifecycleState: ObservableObject {
    @Published private(set) var snapshot: PinesProviderLifecycleSnapshot
    private var refreshGeneration: UInt64 = 0

    var providerTransfers: [ProviderTransferRecord] {
        get { snapshot.providerTransfers }
        set { update(\.providerTransfers, to: newValue) }
    }
    var providerFiles: [ProviderFileRecord] {
        get { snapshot.providerFiles }
        set { update(\.providerFiles, to: newValue) }
    }
    var providerFilePreviews: [PinesProviderFilePreview] {
        get { snapshot.providerFilePreviews }
        set { update(\.providerFilePreviews, to: newValue) }
    }
    var providerArtifacts: [ProviderArtifactRecord] {
        get { snapshot.providerArtifacts }
        set { update(\.providerArtifacts, to: newValue) }
    }
    var providerArtifactPreviews: [PinesProviderArtifactPreview] {
        get { snapshot.providerArtifactPreviews }
        set { update(\.providerArtifactPreviews, to: newValue) }
    }
    var providerCaches: [ProviderCacheRecord] {
        get { snapshot.providerCaches }
        set { update(\.providerCaches, to: newValue) }
    }
    var providerCachePreviews: [PinesProviderCachePreview] {
        get { snapshot.providerCachePreviews }
        set { update(\.providerCachePreviews, to: newValue) }
    }
    var providerVectorStores: [ProviderCacheRecord] {
        get { snapshot.providerVectorStores }
        set { update(\.providerVectorStores, to: newValue) }
    }
    var providerVectorStorePreviews: [PinesProviderCachePreview] {
        get { snapshot.providerVectorStorePreviews }
        set { update(\.providerVectorStorePreviews, to: newValue) }
    }
    var providerBatches: [ProviderBatchRecord] {
        get { snapshot.providerBatches }
        set { update(\.providerBatches, to: newValue) }
    }
    var providerBatchPreviews: [PinesProviderBatchPreview] {
        get { snapshot.providerBatchPreviews }
        set { update(\.providerBatchPreviews, to: newValue) }
    }
    var providerLiveSessions: [ProviderLiveSessionRecord] {
        get { snapshot.providerLiveSessions }
        set { update(\.providerLiveSessions, to: newValue) }
    }
    var providerLiveSessionPreviews: [PinesProviderLiveSessionPreview] {
        get { snapshot.providerLiveSessionPreviews }
        set { update(\.providerLiveSessionPreviews, to: newValue) }
    }
    var providerStructuredOutputs: [ProviderStructuredOutputRecord] {
        get { snapshot.providerStructuredOutputs }
        set { update(\.providerStructuredOutputs, to: newValue) }
    }
    var providerStructuredOutputPreviews: [PinesProviderStructuredOutputPreview] {
        get { snapshot.providerStructuredOutputPreviews }
        set { update(\.providerStructuredOutputPreviews, to: newValue) }
    }
    var providerModelCapabilities: [ProviderModelCapabilityRecord] {
        get { snapshot.providerModelCapabilities }
        set { update(\.providerModelCapabilities, to: newValue) }
    }
    var providerModelCapabilityPreviews: [PinesProviderModelCapabilityPreview] {
        get { snapshot.providerModelCapabilityPreviews }
        set { update(\.providerModelCapabilityPreviews, to: newValue) }
    }
    var providerResearchRuns: [ProviderResearchRunRecord] {
        get { snapshot.providerResearchRuns }
        set { update(\.providerResearchRuns, to: newValue) }
    }
    var providerResearchRunPreviews: [PinesProviderResearchRunPreview] {
        get { snapshot.providerResearchRunPreviews }
        set { update(\.providerResearchRunPreviews, to: newValue) }
    }
    var isRefreshingProviderLifecycle: Bool {
        get { snapshot.isRefreshing }
        set { update(\.isRefreshing, to: newValue, invalidatesRefresh: false) }
    }
    var providerLifecycleError: String? {
        get { snapshot.error }
        set { update(\.error, to: newValue, invalidatesRefresh: false) }
    }

    init(
        providerTransfers: [ProviderTransferRecord] = [],
        providerFiles: [ProviderFileRecord] = [],
        providerFilePreviews: [PinesProviderFilePreview] = [],
        providerArtifacts: [ProviderArtifactRecord] = [],
        providerArtifactPreviews: [PinesProviderArtifactPreview] = [],
        providerCaches: [ProviderCacheRecord] = [],
        providerCachePreviews: [PinesProviderCachePreview] = [],
        providerVectorStores: [ProviderCacheRecord] = [],
        providerVectorStorePreviews: [PinesProviderCachePreview] = [],
        providerBatches: [ProviderBatchRecord] = [],
        providerBatchPreviews: [PinesProviderBatchPreview] = [],
        providerLiveSessions: [ProviderLiveSessionRecord] = [],
        providerLiveSessionPreviews: [PinesProviderLiveSessionPreview] = [],
        providerStructuredOutputs: [ProviderStructuredOutputRecord] = [],
        providerStructuredOutputPreviews: [PinesProviderStructuredOutputPreview] = [],
        providerModelCapabilities: [ProviderModelCapabilityRecord] = [],
        providerModelCapabilityPreviews: [PinesProviderModelCapabilityPreview] = [],
        providerResearchRuns: [ProviderResearchRunRecord] = [],
        providerResearchRunPreviews: [PinesProviderResearchRunPreview] = [],
        isRefreshingProviderLifecycle: Bool = false,
        providerLifecycleError: String? = nil
    ) {
        snapshot = PinesProviderLifecycleSnapshot(
            providerTransfers: providerTransfers,
            providerFiles: providerFiles,
            providerFilePreviews: providerFilePreviews,
            providerArtifacts: providerArtifacts,
            providerArtifactPreviews: providerArtifactPreviews,
            providerCaches: providerCaches,
            providerCachePreviews: providerCachePreviews,
            providerVectorStores: providerVectorStores,
            providerVectorStorePreviews: providerVectorStorePreviews,
            providerBatches: providerBatches,
            providerBatchPreviews: providerBatchPreviews,
            providerLiveSessions: providerLiveSessions,
            providerLiveSessionPreviews: providerLiveSessionPreviews,
            providerStructuredOutputs: providerStructuredOutputs,
            providerStructuredOutputPreviews: providerStructuredOutputPreviews,
            providerModelCapabilities: providerModelCapabilities,
            providerModelCapabilityPreviews: providerModelCapabilityPreviews,
            providerResearchRuns: providerResearchRuns,
            providerResearchRunPreviews: providerResearchRunPreviews,
            isRefreshing: isRefreshingProviderLifecycle,
            error: providerLifecycleError
        )
    }

    func apply(_ newSnapshot: PinesProviderLifecycleSnapshot) {
        var updatedSnapshot = newSnapshot
        if snapshot.providerArtifacts != newSnapshot.providerArtifacts
            || snapshot.providerResearchRuns != newSnapshot.providerResearchRuns {
            updatedSnapshot.artifactLibraryRevision = snapshot.artifactLibraryRevision &+ 1
        } else {
            updatedSnapshot.artifactLibraryRevision = snapshot.artifactLibraryRevision
        }
        guard snapshot != updatedSnapshot else { return }
        snapshot = updatedSnapshot
    }

    /// Starts a repository-wide refresh and returns the generation that is
    /// allowed to publish its result. Any later targeted mutation invalidates
    /// this generation so stale repository reads cannot replace newer state.
    @discardableResult
    func beginRefresh() -> UInt64 {
        refreshGeneration &+= 1
        var loadingSnapshot = snapshot
        loadingSnapshot.isRefreshing = true
        loadingSnapshot.error = nil
        apply(loadingSnapshot)
        return refreshGeneration
    }

    /// Publishes a repository-wide refresh only when no newer refresh or
    /// targeted mutation has superseded it.
    @discardableResult
    func completeRefresh(
        _ refreshedSnapshot: PinesProviderLifecycleSnapshot,
        generation: UInt64
    ) -> Bool {
        guard refreshGeneration == generation else { return false }
        var completedSnapshot = refreshedSnapshot
        completedSnapshot.isRefreshing = false
        completedSnapshot.error = nil
        apply(completedSnapshot)
        return true
    }

    /// Publishes a refresh failure only while that refresh is still current.
    @discardableResult
    func failRefresh(_ error: String, generation: UInt64) -> Bool {
        guard refreshGeneration == generation else { return false }
        var failedSnapshot = snapshot
        failedSnapshot.isRefreshing = false
        failedSnapshot.error = error
        apply(failedSnapshot)
        return true
    }

    /// Applies a focused lifecycle mutation in one publication. Incrementing
    /// the generation first also prevents an older full refresh from restoring
    /// the pre-mutation value after this method returns.
    func updateIncrementally(
        _ mutation: (inout PinesProviderLifecycleSnapshot) -> Void
    ) {
        refreshGeneration &+= 1
        var updatedSnapshot = snapshot
        updatedSnapshot.isRefreshing = false
        updatedSnapshot.error = nil
        mutation(&updatedSnapshot)
        apply(updatedSnapshot)
    }

    private func update<Value: Equatable>(
        _ keyPath: WritableKeyPath<PinesProviderLifecycleSnapshot, Value>,
        to value: Value,
        invalidatesRefresh: Bool = true
    ) {
        guard snapshot[keyPath: keyPath] != value else { return }
        if invalidatesRefresh {
            refreshGeneration &+= 1
        }
        var updated = snapshot
        updated[keyPath: keyPath] = value
        apply(updated)
    }
}

@MainActor
final class PinesWorkflowState: ObservableObject {
    @Published var serviceError: String?
    @Published var pendingToolApproval: ToolApprovalRequest?
    @Published var pendingHostedToolApproval: HostedToolApprovalRequest?
    @Published var pendingCloudContextApproval: CloudContextApprovalRequest?
    @Published var pendingCloudVaultEmbeddingApproval: CloudVaultEmbeddingApprovalRequest?
    @Published var pendingMCPSamplingRequest: MCPSamplingRequest?
    @Published var pendingMCPSamplingResultReview: MCPSamplingResultReview?
    @Published var mcpSamplingPromptDraft: String
    @Published var hapticSignal: PinesHapticSignal?
    @Published var isErasingAllData: Bool

    init(
        serviceError: String? = nil,
        pendingToolApproval: ToolApprovalRequest? = nil,
        pendingHostedToolApproval: HostedToolApprovalRequest? = nil,
        pendingCloudContextApproval: CloudContextApprovalRequest? = nil,
        pendingCloudVaultEmbeddingApproval: CloudVaultEmbeddingApprovalRequest? = nil,
        pendingMCPSamplingRequest: MCPSamplingRequest? = nil,
        pendingMCPSamplingResultReview: MCPSamplingResultReview? = nil,
        mcpSamplingPromptDraft: String = "",
        hapticSignal: PinesHapticSignal? = nil,
        isErasingAllData: Bool = false
    ) {
        self.serviceError = serviceError
        self.pendingToolApproval = pendingToolApproval
        self.pendingHostedToolApproval = pendingHostedToolApproval
        self.pendingCloudContextApproval = pendingCloudContextApproval
        self.pendingCloudVaultEmbeddingApproval = pendingCloudVaultEmbeddingApproval
        self.pendingMCPSamplingRequest = pendingMCPSamplingRequest
        self.pendingMCPSamplingResultReview = pendingMCPSamplingResultReview
        self.mcpSamplingPromptDraft = mcpSamplingPromptDraft
        self.hapticSignal = hapticSignal
        self.isErasingAllData = isErasingAllData
    }
}
