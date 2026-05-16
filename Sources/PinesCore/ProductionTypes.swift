import Foundation

public enum SyncState: String, Hashable, Codable, Sendable, CaseIterable {
    case local
    case pendingUpload
    case synced
    case conflicted
    case deleted
}

public enum MessageStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case pending
    case streaming
    case complete
    case failed
    case cancelled
}

public enum ChatRunStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case queued
    case routing
    case streaming
    case waitingForToolApproval
    case completed
    case failed
    case cancelled
}

public struct ChatRun: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var conversationID: UUID
    public var requestID: UUID
    public var status: ChatRunStatus
    public var providerID: ProviderID?
    public var modelID: ModelID
    public var startedAt: Date?
    public var finishedAt: Date?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        requestID: UUID,
        status: ChatRunStatus = .queued,
        providerID: ProviderID? = nil,
        modelID: ModelID,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.requestID = requestID
        self.status = status
        self.providerID = providerID
        self.modelID = modelID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
    }
}

public enum ModelDownloadStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case queued
    case downloading
    case verifying
    case installing
    case installed
    case failed
    case cancelled
}

public struct ModelDownloadProgress: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var repository: String
    public var revision: String?
    public var status: ModelDownloadStatus
    public var bytesReceived: Int64
    public var totalBytes: Int64?
    public var currentFile: String?
    public var checksum: String?
    public var localURL: URL?
    public var errorMessage: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        repository: String,
        revision: String? = nil,
        status: ModelDownloadStatus = .queued,
        bytesReceived: Int64 = 0,
        totalBytes: Int64? = nil,
        currentFile: String? = nil,
        checksum: String? = nil,
        localURL: URL? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.repository = repository
        self.revision = revision
        self.status = status
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.currentFile = currentFile
        self.checksum = checksum
        self.localURL = localURL
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

public enum ProviderValidationStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case unvalidated
    case valid
    case invalid
    case rateLimited
}

public struct ProviderValidationResult: Hashable, Codable, Sendable {
    public var providerID: ProviderID
    public var status: ProviderValidationStatus
    public var message: String
    public var validatedAt: Date
    public var availableModels: [ModelID]

    public init(
        providerID: ProviderID,
        status: ProviderValidationStatus,
        message: String,
        validatedAt: Date = Date(),
        availableModels: [ModelID] = []
    ) {
        self.providerID = providerID
        self.status = status
        self.message = message
        self.validatedAt = validatedAt
        self.availableModels = availableModels
    }
}

public enum VaultImportStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case queued
    case extracting
    case chunking
    case embedding
    case indexed
    case failed
    case cancelled
}

public struct VaultImportJob: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var documentID: UUID?
    public var sourceURL: URL?
    public var fileName: String
    public var status: VaultImportStatus
    public var progress: Double
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        documentID: UUID? = nil,
        sourceURL: URL? = nil,
        fileName: String,
        status: VaultImportStatus = .queued,
        progress: Double = 0,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VaultSearchResult: Identifiable, Hashable, Codable, Sendable {
    public var id: String { chunk.id }
    public var document: VaultDocumentRecord
    public var chunk: VaultChunk
    public var score: Double
    public var snippet: String

    public init(document: VaultDocumentRecord, chunk: VaultChunk, score: Double, snippet: String) {
        self.document = document
        self.chunk = chunk
        self.score = score
        self.snippet = snippet
    }
}

public enum AgentRunStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case queued
    case thinking
    case callingTool
    case waitingForApproval
    case completed
    case failed
    case cancelled
}

public struct AgentRunState: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var status: AgentRunStatus
    public var stepIndex: Int
    public var toolCallCount: Int
    public var startedAt: Date
    public var updatedAt: Date
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        status: AgentRunStatus = .queued,
        stepIndex: Int = 0,
        toolCallCount: Int = 0,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.status = status
        self.stepIndex = stepIndex
        self.toolCallCount = toolCallCount
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }
}

public enum ToolApprovalStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case pending
    case approved
    case denied
    case expired
}

public struct ToolApprovalRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var invocation: ToolInvocation
    public var status: ToolApprovalStatus
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        invocation: ToolInvocation,
        status: ToolApprovalStatus = .pending,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.invocation = invocation
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

public enum CloudContextApprovalDecision: String, Hashable, Codable, Sendable, CaseIterable {
    case sendWithContext
    case sendWithoutContext
    case cancel
}

public struct CloudContextApprovalRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var providerID: ProviderID
    public var modelID: ModelID
    public var documentIDs: [UUID]
    public var mcpResourceIDs: [String]
    public var estimatedContextBytes: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        modelID: ModelID,
        documentIDs: [UUID],
        mcpResourceIDs: [String],
        estimatedContextBytes: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.documentIDs = documentIDs
        self.mcpResourceIDs = mcpResourceIDs
        self.estimatedContextBytes = estimatedContextBytes
        self.createdAt = createdAt
    }
}

public enum BrowserActionKind: String, Hashable, Codable, Sendable, CaseIterable {
    case observe
    case navigate
    case click
    case typeText
    case submit
    case screenshot
    case stop
}

public struct BrowserAction: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: BrowserActionKind
    public var url: URL?
    public var selector: String?
    public var text: String?
    public var requiresApproval: Bool

    public init(
        id: UUID = UUID(),
        kind: BrowserActionKind,
        url: URL? = nil,
        selector: String? = nil,
        text: String? = nil,
        requiresApproval: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.selector = selector
        self.text = text
        self.requiresApproval = requiresApproval
    }
}

public struct AppSettingsSnapshot: Hashable, Codable, Sendable {
    public var executionMode: AgentExecutionMode
    public var storeConfiguration: LocalStoreConfiguration
    public var defaultProviderID: ProviderID?
    public var defaultModelID: ModelID?
    public var embeddingModelID: ModelID?
    public var requireToolApproval: Bool
    public var braveSearchEnabled: Bool
    public var onboardingCompleted: Bool
    public var themeTemplate: String
    public var interfaceMode: String

    public init(
        executionMode: AgentExecutionMode = .preferLocal,
        storeConfiguration: LocalStoreConfiguration = .init(),
        defaultProviderID: ProviderID? = nil,
        defaultModelID: ModelID? = nil,
        embeddingModelID: ModelID? = nil,
        requireToolApproval: Bool = true,
        braveSearchEnabled: Bool = false,
        onboardingCompleted: Bool = false,
        themeTemplate: String = "evergreen",
        interfaceMode: String = "system"
    ) {
        self.executionMode = executionMode
        self.storeConfiguration = storeConfiguration
        self.defaultProviderID = defaultProviderID
        self.defaultModelID = defaultModelID
        self.embeddingModelID = embeddingModelID
        self.requireToolApproval = requireToolApproval
        self.braveSearchEnabled = braveSearchEnabled
        self.onboardingCompleted = onboardingCompleted
        self.themeTemplate = themeTemplate
        self.interfaceMode = interfaceMode
    }
}
