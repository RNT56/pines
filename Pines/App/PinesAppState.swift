import Foundation
import SwiftUI
import PinesCore

@MainActor
final class PinesChatState: ObservableObject {
    @Published var threads: [PinesThreadPreview]
    @Published var chatError: String?
    @Published var activeRunID: UUID?

    init(
        threads: [PinesThreadPreview] = [],
        chatError: String? = nil,
        activeRunID: UUID? = nil
    ) {
        self.threads = threads
        self.chatError = chatError
        self.activeRunID = activeRunID
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

@MainActor
final class PinesSettingsState: ObservableObject {
    @Published var settingsSections: [PinesSettingsSection]
    @Published var executionMode: AgentExecutionMode
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
    @Published var openAIReasoningEffort: OpenAIReasoningEffort
    @Published var openAITextVerbosity: OpenAITextVerbosity
    @Published var anthropicEffort: AnthropicEffort
    @Published var geminiThinkingLevel: GeminiThinkingLevel
    @Published var cloudWebSearchMode: CloudWebSearchMode
    @Published var cloudModelCatalog: [ProviderID: [CloudProviderModel]]
    @Published var isRefreshingCloudModels: Bool
    @Published var isSavingCloudProvider: Bool
    @Published var validatingCloudProviderIDs: Set<ProviderID>
    @Published var huggingFaceCredentialStatus: String
    @Published var braveSearchCredentialStatus: String

    init(
        settingsSections: [PinesSettingsSection] = PinesStaticSettings.sections,
        executionMode: AgentExecutionMode = .preferLocal,
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
        openAIReasoningEffort: OpenAIReasoningEffort = AppSettingsSnapshot.defaultOpenAIReasoningEffort,
        openAITextVerbosity: OpenAITextVerbosity = AppSettingsSnapshot.defaultOpenAITextVerbosity,
        anthropicEffort: AnthropicEffort = AppSettingsSnapshot.defaultAnthropicEffort,
        geminiThinkingLevel: GeminiThinkingLevel = AppSettingsSnapshot.defaultGeminiThinkingLevel,
        cloudWebSearchMode: CloudWebSearchMode = AppSettingsSnapshot.defaultCloudWebSearchMode,
        cloudModelCatalog: [ProviderID: [CloudProviderModel]] = [:],
        isRefreshingCloudModels: Bool = false,
        isSavingCloudProvider: Bool = false,
        validatingCloudProviderIDs: Set<ProviderID> = [],
        huggingFaceCredentialStatus: String = "Not configured",
        braveSearchCredentialStatus: String = "Not configured"
    ) {
        self.settingsSections = settingsSections
        self.executionMode = executionMode
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
        self.openAIReasoningEffort = openAIReasoningEffort
        self.openAITextVerbosity = openAITextVerbosity
        self.anthropicEffort = anthropicEffort
        self.geminiThinkingLevel = geminiThinkingLevel
        self.cloudWebSearchMode = cloudWebSearchMode
        self.cloudModelCatalog = cloudModelCatalog
        self.isRefreshingCloudModels = isRefreshingCloudModels
        self.isSavingCloudProvider = isSavingCloudProvider
        self.validatingCloudProviderIDs = validatingCloudProviderIDs
        self.huggingFaceCredentialStatus = huggingFaceCredentialStatus
        self.braveSearchCredentialStatus = braveSearchCredentialStatus
    }
}

@MainActor
final class PinesWorkflowState: ObservableObject {
    @Published var serviceError: String?
    @Published var pendingToolApproval: ToolApprovalRequest?
    @Published var pendingCloudContextApproval: CloudContextApprovalRequest?
    @Published var pendingCloudVaultEmbeddingApproval: CloudVaultEmbeddingApprovalRequest?
    @Published var pendingMCPSamplingRequest: MCPSamplingRequest?
    @Published var pendingMCPSamplingResultReview: MCPSamplingResultReview?
    @Published var mcpSamplingPromptDraft: String
    @Published var hapticSignal: PinesHapticSignal?

    init(
        serviceError: String? = nil,
        pendingToolApproval: ToolApprovalRequest? = nil,
        pendingCloudContextApproval: CloudContextApprovalRequest? = nil,
        pendingCloudVaultEmbeddingApproval: CloudVaultEmbeddingApprovalRequest? = nil,
        pendingMCPSamplingRequest: MCPSamplingRequest? = nil,
        pendingMCPSamplingResultReview: MCPSamplingResultReview? = nil,
        mcpSamplingPromptDraft: String = "",
        hapticSignal: PinesHapticSignal? = nil
    ) {
        self.serviceError = serviceError
        self.pendingToolApproval = pendingToolApproval
        self.pendingCloudContextApproval = pendingCloudContextApproval
        self.pendingCloudVaultEmbeddingApproval = pendingCloudVaultEmbeddingApproval
        self.pendingMCPSamplingRequest = pendingMCPSamplingRequest
        self.pendingMCPSamplingResultReview = pendingMCPSamplingResultReview
        self.mcpSamplingPromptDraft = mcpSamplingPromptDraft
        self.hapticSignal = hapticSignal
    }
}
