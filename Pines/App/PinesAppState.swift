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
    @Published var vaultEmbeddingProfiles: [VaultEmbeddingProfile]
    @Published var vaultEmbeddingJobs: [VaultEmbeddingJob]
    @Published var vaultRetrievalEvents: [VaultRetrievalEvent]
    @Published var vaultSearchResults: [VaultSearchResult]
    @Published var isVaultSearchPresented: Bool
    @Published var isVaultReindexing: Bool

    init(
        vaultItems: [PinesVaultItemPreview] = [],
        vaultEmbeddingProfiles: [VaultEmbeddingProfile] = [],
        vaultEmbeddingJobs: [VaultEmbeddingJob] = [],
        vaultRetrievalEvents: [VaultRetrievalEvent] = [],
        vaultSearchResults: [VaultSearchResult] = [],
        isVaultSearchPresented: Bool = false,
        isVaultReindexing: Bool = false
    ) {
        self.vaultItems = vaultItems
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

@MainActor
final class PinesProviderLifecycleState: ObservableObject {
    @Published var providerTransfers: [ProviderTransferRecord]
    @Published var providerFiles: [ProviderFileRecord]
    @Published var providerFilePreviews: [PinesProviderFilePreview]
    @Published var providerArtifacts: [ProviderArtifactRecord]
    @Published var providerArtifactPreviews: [PinesProviderArtifactPreview]
    @Published var providerCaches: [ProviderCacheRecord]
    @Published var providerCachePreviews: [PinesProviderCachePreview]
    @Published var providerVectorStores: [ProviderCacheRecord]
    @Published var providerVectorStorePreviews: [PinesProviderCachePreview]
    @Published var providerBatches: [ProviderBatchRecord]
    @Published var providerBatchPreviews: [PinesProviderBatchPreview]
    @Published var providerLiveSessions: [ProviderLiveSessionRecord]
    @Published var providerLiveSessionPreviews: [PinesProviderLiveSessionPreview]
    @Published var providerStructuredOutputs: [ProviderStructuredOutputRecord]
    @Published var providerStructuredOutputPreviews: [PinesProviderStructuredOutputPreview]
    @Published var providerModelCapabilities: [ProviderModelCapabilityRecord]
    @Published var providerModelCapabilityPreviews: [PinesProviderModelCapabilityPreview]
    @Published var providerResearchRuns: [ProviderResearchRunRecord]
    @Published var providerResearchRunPreviews: [PinesProviderResearchRunPreview]
    @Published var isRefreshingProviderLifecycle: Bool
    @Published var providerLifecycleError: String?

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
        self.providerTransfers = providerTransfers
        self.providerFiles = providerFiles
        self.providerFilePreviews = providerFilePreviews
        self.providerArtifacts = providerArtifacts
        self.providerArtifactPreviews = providerArtifactPreviews
        self.providerCaches = providerCaches
        self.providerCachePreviews = providerCachePreviews
        self.providerVectorStores = providerVectorStores
        self.providerVectorStorePreviews = providerVectorStorePreviews
        self.providerBatches = providerBatches
        self.providerBatchPreviews = providerBatchPreviews
        self.providerLiveSessions = providerLiveSessions
        self.providerLiveSessionPreviews = providerLiveSessionPreviews
        self.providerStructuredOutputs = providerStructuredOutputs
        self.providerStructuredOutputPreviews = providerStructuredOutputPreviews
        self.providerModelCapabilities = providerModelCapabilities
        self.providerModelCapabilityPreviews = providerModelCapabilityPreviews
        self.providerResearchRuns = providerResearchRuns
        self.providerResearchRunPreviews = providerResearchRunPreviews
        self.isRefreshingProviderLifecycle = isRefreshingProviderLifecycle
        self.providerLifecycleError = providerLifecycleError
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
