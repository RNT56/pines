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
    public var providerKind: CloudProviderKind?
    public var providerBaseURL: URL?
    public var modelID: ModelID
    public var startedAt: Date?
    public var finishedAt: Date?
    public var errorMessage: String?
    public var providerRequestID: String?
    public var providerResponseID: String?
    public var parentResponseID: OpenAIResponseID?
    public var backgroundResponseID: OpenAIResponseID?
    public var batchID: OpenAIBatchID?
    public var realtimeSessionID: OpenAIRealtimeSessionID?
    public var structuredOutputResultID: UUID?
    public var usedResponsesAPI: Bool
    public var responseStorage: OpenAIResponseStorage?
    public var webSearchMode: CloudWebSearchMode?
    public var providerMetadata: [String: String]

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        requestID: UUID,
        status: ChatRunStatus = .queued,
        providerID: ProviderID? = nil,
        providerKind: CloudProviderKind? = nil,
        providerBaseURL: URL? = nil,
        modelID: ModelID,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorMessage: String? = nil,
        providerRequestID: String? = nil,
        providerResponseID: String? = nil,
        parentResponseID: OpenAIResponseID? = nil,
        backgroundResponseID: OpenAIResponseID? = nil,
        batchID: OpenAIBatchID? = nil,
        realtimeSessionID: OpenAIRealtimeSessionID? = nil,
        structuredOutputResultID: UUID? = nil,
        usedResponsesAPI: Bool = false,
        responseStorage: OpenAIResponseStorage? = nil,
        webSearchMode: CloudWebSearchMode? = nil,
        providerMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.conversationID = conversationID
        self.requestID = requestID
        self.status = status
        self.providerID = providerID
        self.providerKind = providerKind
        self.providerBaseURL = providerBaseURL
        self.modelID = modelID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
        self.providerRequestID = providerRequestID
        self.providerResponseID = providerResponseID
        self.parentResponseID = parentResponseID
        self.backgroundResponseID = backgroundResponseID
        self.batchID = batchID
        self.realtimeSessionID = realtimeSessionID
        self.structuredOutputResultID = structuredOutputResultID
        self.usedResponsesAPI = usedResponsesAPI
        self.responseStorage = responseStorage
        self.webSearchMode = webSearchMode
        self.providerMetadata = providerMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID
        case requestID
        case status
        case providerID
        case providerKind
        case providerBaseURL
        case modelID
        case startedAt
        case finishedAt
        case errorMessage
        case providerRequestID
        case providerResponseID
        case parentResponseID
        case backgroundResponseID
        case batchID
        case realtimeSessionID
        case structuredOutputResultID
        case usedResponsesAPI
        case responseStorage
        case webSearchMode
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        status = try container.decodeIfPresent(ChatRunStatus.self, forKey: .status) ?? .queued
        providerID = try container.decodeIfPresent(ProviderID.self, forKey: .providerID)
        providerKind = try container.decodeIfPresent(CloudProviderKind.self, forKey: .providerKind)
        providerBaseURL = try container.decodeIfPresent(URL.self, forKey: .providerBaseURL)
        modelID = try container.decode(ModelID.self, forKey: .modelID)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        providerRequestID = try container.decodeIfPresent(String.self, forKey: .providerRequestID)
        providerResponseID = try container.decodeIfPresent(String.self, forKey: .providerResponseID)
        parentResponseID = try container.decodeIfPresent(OpenAIResponseID.self, forKey: .parentResponseID)
        backgroundResponseID = try container.decodeIfPresent(OpenAIResponseID.self, forKey: .backgroundResponseID)
        batchID = try container.decodeIfPresent(OpenAIBatchID.self, forKey: .batchID)
        realtimeSessionID = try container.decodeIfPresent(OpenAIRealtimeSessionID.self, forKey: .realtimeSessionID)
        structuredOutputResultID = try container.decodeIfPresent(UUID.self, forKey: .structuredOutputResultID)
        usedResponsesAPI = try container.decodeIfPresent(Bool.self, forKey: .usedResponsesAPI) ?? false
        responseStorage = try container.decodeIfPresent(OpenAIResponseStorage.self, forKey: .responseStorage)
        webSearchMode = try container.decodeIfPresent(CloudWebSearchMode.self, forKey: .webSearchMode)
        providerMetadata = try container.decodeIfPresent([String: String].self, forKey: .providerMetadata) ?? [:]
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

public enum OpenAIProviderFilePurpose: String, Hashable, Codable, Sendable, CaseIterable {
    case assistants
    case batch
    case fineTune
    case vision
    case userData
    case evals
    case other
}

public enum OpenAIProviderFileStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case uploaded
    case processed
    case error
    case deleting
    case deleted
}

public struct OpenAIProviderFile: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIProviderFileID
    public var providerID: ProviderID
    public var purpose: OpenAIProviderFilePurpose
    public var fileName: String
    public var contentType: String?
    public var byteCount: Int64
    public var status: OpenAIProviderFileStatus
    public var sha256: String?
    public var localURL: URL?
    public var providerObject: String?
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var expiresAt: Date?
    public var lastError: String?

    public init(
        id: OpenAIProviderFileID,
        providerID: ProviderID,
        purpose: OpenAIProviderFilePurpose,
        fileName: String,
        contentType: String? = nil,
        byteCount: Int64 = 0,
        status: OpenAIProviderFileStatus = .uploaded,
        sha256: String? = nil,
        localURL: URL? = nil,
        providerObject: String? = nil,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.purpose = purpose
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.status = status
        self.sha256 = sha256
        self.localURL = localURL
        self.providerObject = providerObject
        self.providerMetadata = providerMetadata
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastError = lastError
    }
}

public enum OpenAIVectorStoreStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case inProgress
    case completed
    case expired
    case failed
    case cancelled
}

public struct OpenAIVectorStoreFileCounts: Hashable, Codable, Sendable {
    public var inProgress: Int
    public var completed: Int
    public var failed: Int
    public var cancelled: Int
    public var total: Int

    public init(inProgress: Int = 0, completed: Int = 0, failed: Int = 0, cancelled: Int = 0, total: Int = 0) {
        self.inProgress = inProgress
        self.completed = completed
        self.failed = failed
        self.cancelled = cancelled
        self.total = total
    }
}

public struct OpenAIVectorStoreExpirationPolicy: Hashable, Codable, Sendable {
    public enum Anchor: String, Hashable, Codable, Sendable, CaseIterable {
        case lastActiveAt
        case createdAt
    }

    public var anchor: Anchor
    public var days: Int

    public init(anchor: Anchor = .lastActiveAt, days: Int) {
        self.anchor = anchor
        self.days = max(1, days)
    }
}

public struct OpenAIVectorStore: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIVectorStoreID
    public var providerID: ProviderID
    public var name: String?
    public var status: OpenAIVectorStoreStatus
    public var fileCounts: OpenAIVectorStoreFileCounts
    public var usageBytes: Int64
    public var expirationPolicy: OpenAIVectorStoreExpirationPolicy?
    public var metadata: [String: String]
    public var createdAt: Date
    public var expiresAt: Date?
    public var lastActiveAt: Date?
    public var lastError: String?

    public init(
        id: OpenAIVectorStoreID,
        providerID: ProviderID,
        name: String? = nil,
        status: OpenAIVectorStoreStatus = .inProgress,
        fileCounts: OpenAIVectorStoreFileCounts = .init(),
        usageBytes: Int64 = 0,
        expirationPolicy: OpenAIVectorStoreExpirationPolicy? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        lastActiveAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.name = name
        self.status = status
        self.fileCounts = fileCounts
        self.usageBytes = usageBytes
        self.expirationPolicy = expirationPolicy
        self.metadata = metadata
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastActiveAt = lastActiveAt
        self.lastError = lastError
    }
}

public enum OpenAIVectorStoreFileStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case inProgress
    case completed
    case failed
    case cancelled
}

public struct OpenAIVectorStoreFile: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIVectorStoreFileID
    public var vectorStoreID: OpenAIVectorStoreID
    public var providerFileID: OpenAIProviderFileID
    public var status: OpenAIVectorStoreFileStatus
    public var usageBytes: Int64
    public var chunkingStrategy: JSONValue?
    public var attributes: [String: String]
    public var createdAt: Date
    public var completedAt: Date?
    public var lastError: String?

    public init(
        id: OpenAIVectorStoreFileID,
        vectorStoreID: OpenAIVectorStoreID,
        providerFileID: OpenAIProviderFileID,
        status: OpenAIVectorStoreFileStatus = .inProgress,
        usageBytes: Int64 = 0,
        chunkingStrategy: JSONValue? = nil,
        attributes: [String: String] = [:],
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.vectorStoreID = vectorStoreID
        self.providerFileID = providerFileID
        self.status = status
        self.usageBytes = usageBytes
        self.chunkingStrategy = chunkingStrategy
        self.attributes = attributes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.lastError = lastError
    }
}

public enum OpenAIHostedToolCallStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case queued
    case inProgress
    case completed
    case failed
    case cancelled
    case requiresAction
}

public struct OpenAIHostedToolCall: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIHostedToolCallID
    public var responseID: OpenAIResponseID?
    public var chatRunID: UUID?
    public var kind: OpenAIHostedToolKind
    public var status: OpenAIHostedToolCallStatus
    public var name: String?
    public var input: JSONValue?
    public var output: JSONValue?
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var completedAt: Date?
    public var lastError: String?

    public init(
        id: OpenAIHostedToolCallID,
        responseID: OpenAIResponseID? = nil,
        chatRunID: UUID? = nil,
        kind: OpenAIHostedToolKind,
        status: OpenAIHostedToolCallStatus = .queued,
        name: String? = nil,
        input: JSONValue? = nil,
        output: JSONValue? = nil,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.responseID = responseID
        self.chatRunID = chatRunID
        self.kind = kind
        self.status = status
        self.name = name
        self.input = input
        self.output = output
        self.providerMetadata = providerMetadata
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.lastError = lastError
    }
}

public enum OpenAIArtifactKind: String, Hashable, Codable, Sendable, CaseIterable {
    case outputText
    case structuredOutput
    case image
    case audio
    case transcript
    case code
    case file
    case toolOutput
}

public struct OpenAIArtifact: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIArtifactID
    public var responseID: OpenAIResponseID?
    public var hostedToolCallID: OpenAIHostedToolCallID?
    public var providerFileID: OpenAIProviderFileID?
    public var kind: OpenAIArtifactKind
    public var fileName: String?
    public var contentType: String?
    public var byteCount: Int64?
    public var text: String?
    public var content: JSONValue?
    public var localURL: URL?
    public var remoteURL: URL?
    public var createdAt: Date

    public init(
        id: OpenAIArtifactID,
        responseID: OpenAIResponseID? = nil,
        hostedToolCallID: OpenAIHostedToolCallID? = nil,
        providerFileID: OpenAIProviderFileID? = nil,
        kind: OpenAIArtifactKind,
        fileName: String? = nil,
        contentType: String? = nil,
        byteCount: Int64? = nil,
        text: String? = nil,
        content: JSONValue? = nil,
        localURL: URL? = nil,
        remoteURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.responseID = responseID
        self.hostedToolCallID = hostedToolCallID
        self.providerFileID = providerFileID
        self.kind = kind
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.text = text
        self.content = content
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.createdAt = createdAt
    }
}

public enum OpenAIBackgroundResponseStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case queued
    case inProgress
    case completed
    case failed
    case cancelled
    case expired
    case requiresAction
}

public extension OpenAIBackgroundResponseStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .expired:
            return true
        case .queued, .inProgress, .requiresAction:
            return false
        }
    }

    init(providerStatus: String) {
        switch providerStatus {
        case "in_progress":
            self = .inProgress
        case "requires_action":
            self = .requiresAction
        default:
            self = OpenAIBackgroundResponseStatus(rawValue: providerStatus) ?? .queued
        }
    }
}

public enum OpenAIRunKind: String, Hashable, Codable, Sendable, CaseIterable {
    case chat
    case backgroundResponse
    case deepResearch
    case batch
    case realtime
}

public struct OpenAIBackgroundResponse: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIResponseID
    public var providerID: ProviderID
    public var modelID: ModelID
    public var status: OpenAIBackgroundResponseStatus
    public var conversationID: UUID?
    public var chatRunID: UUID?
    public var previousResponseID: OpenAIResponseID?
    public var outputItems: JSONValue?
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var completedAt: Date?
    public var lastPolledAt: Date?
    public var expiresAt: Date?
    public var lastError: String?

    public init(
        id: OpenAIResponseID,
        providerID: ProviderID,
        modelID: ModelID,
        status: OpenAIBackgroundResponseStatus = .queued,
        conversationID: UUID? = nil,
        chatRunID: UUID? = nil,
        previousResponseID: OpenAIResponseID? = nil,
        outputItems: JSONValue? = nil,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        lastPolledAt: Date? = nil,
        expiresAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.status = status
        self.conversationID = conversationID
        self.chatRunID = chatRunID
        self.previousResponseID = previousResponseID
        self.outputItems = outputItems
        self.providerMetadata = providerMetadata
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.lastPolledAt = lastPolledAt
        self.expiresAt = expiresAt
        self.lastError = lastError
    }
}

public enum OpenAIDeepResearchDepth: String, Hashable, Codable, Sendable, CaseIterable {
    case quick
    case standard
    case deep
}

public enum OpenAIDeepResearchSourceScope: String, Hashable, Codable, Sendable, CaseIterable {
    case webOnly
    case webAndProviderFiles
    case webAndVaultExport
    case webAndMCP
}

public enum OpenAIDeepResearchReportFormat: String, Hashable, Codable, Sendable, CaseIterable {
    case memo
    case brief
    case citationFirst
    case tableHeavy
    case markdown
}

public struct OpenAIDeepResearchSourcePolicy: Hashable, Codable, Sendable {
    public var scope: OpenAIDeepResearchSourceScope
    public var vectorStoreIDs: [OpenAIVectorStoreID]
    public var providerFileIDs: [OpenAIProviderFileID]
    public var vaultDocumentIDs: [UUID]
    public var allowedDomains: [String]
    public var blockedDomains: [String]
    public var webSearchReturnTokenBudget: Int?
    public var mcpServerLabel: String?
    public var mcpServerURL: URL?
    public var requireMCPApproval: String

    public init(
        scope: OpenAIDeepResearchSourceScope = .webOnly,
        vectorStoreIDs: [OpenAIVectorStoreID] = [],
        providerFileIDs: [OpenAIProviderFileID] = [],
        vaultDocumentIDs: [UUID] = [],
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        webSearchReturnTokenBudget: Int? = nil,
        mcpServerLabel: String? = nil,
        mcpServerURL: URL? = nil,
        requireMCPApproval: String = "always"
    ) {
        self.scope = scope
        self.vectorStoreIDs = vectorStoreIDs
        self.providerFileIDs = providerFileIDs
        self.vaultDocumentIDs = vaultDocumentIDs
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.webSearchReturnTokenBudget = webSearchReturnTokenBudget
        self.mcpServerLabel = mcpServerLabel
        self.mcpServerURL = mcpServerURL
        self.requireMCPApproval = requireMCPApproval
    }
}

public extension OpenAIDeepResearchSourcePolicy {
    static func webOnly(
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        webSearchReturnTokenBudget: Int? = nil
    ) -> Self {
        Self(
            scope: .webOnly,
            allowedDomains: allowedDomains,
            blockedDomains: blockedDomains,
            webSearchReturnTokenBudget: webSearchReturnTokenBudget
        )
    }

    static func webAndFiles(
        vectorStoreIDs: [OpenAIVectorStoreID] = [],
        providerFileIDs: [OpenAIProviderFileID] = [],
        vaultDocumentIDs: [UUID] = [],
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        webSearchReturnTokenBudget: Int? = nil
    ) -> Self {
        Self(
            scope: .webAndProviderFiles,
            vectorStoreIDs: vectorStoreIDs,
            providerFileIDs: providerFileIDs,
            vaultDocumentIDs: vaultDocumentIDs,
            allowedDomains: allowedDomains,
            blockedDomains: blockedDomains,
            webSearchReturnTokenBudget: webSearchReturnTokenBudget
        )
    }

    static func webAndMCP(
        serverLabel: String,
        serverURL: URL,
        requireApproval: String = "always",
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        webSearchReturnTokenBudget: Int? = nil
    ) -> Self {
        Self(
            scope: .webAndMCP,
            allowedDomains: allowedDomains,
            blockedDomains: blockedDomains,
            webSearchReturnTokenBudget: webSearchReturnTokenBudget,
            mcpServerLabel: serverLabel,
            mcpServerURL: serverURL,
            requireMCPApproval: requireApproval
        )
    }
}

public struct OpenAIDeepResearchRequest: Hashable, Codable, Sendable {
    public var id: UUID
    public var providerID: ProviderID
    public var modelID: ModelID
    public var title: String
    public var prompt: String
    public var depth: OpenAIDeepResearchDepth
    public var sourcePolicy: OpenAIDeepResearchSourcePolicy
    public var reportFormat: OpenAIDeepResearchReportFormat
    public var includeCodeInterpreter: Bool
    public var serviceTier: OpenAIServiceTier
    public var responseOutputTokenBudget: Int?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        modelID: ModelID = "gpt-5.5-pro",
        title: String,
        prompt: String,
        depth: OpenAIDeepResearchDepth = .standard,
        sourcePolicy: OpenAIDeepResearchSourcePolicy = .init(),
        reportFormat: OpenAIDeepResearchReportFormat = .memo,
        includeCodeInterpreter: Bool = true,
        serviceTier: OpenAIServiceTier = .auto,
        responseOutputTokenBudget: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.title = title
        self.prompt = prompt
        self.depth = depth
        self.sourcePolicy = sourcePolicy
        self.reportFormat = reportFormat
        self.includeCodeInterpreter = includeCodeInterpreter
        self.serviceTier = serviceTier
        self.responseOutputTokenBudget = responseOutputTokenBudget
        self.metadata = metadata
    }
}

public struct OpenAIDeepResearchRun: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var request: OpenAIDeepResearchRequest
    public var responseID: OpenAIResponseID?
    public var status: OpenAIBackgroundResponseStatus
    public var finalReportArtifactID: OpenAIArtifactID?
    public var citationCount: Int
    public var toolCallCount: Int
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        request: OpenAIDeepResearchRequest,
        responseID: OpenAIResponseID? = nil,
        status: OpenAIBackgroundResponseStatus = .queued,
        finalReportArtifactID: OpenAIArtifactID? = nil,
        citationCount: Int = 0,
        toolCallCount: Int = 0,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.request = request
        self.responseID = responseID
        self.status = status
        self.finalReportArtifactID = finalReportArtifactID
        self.citationCount = citationCount
        self.toolCallCount = toolCallCount
        self.providerMetadata = providerMetadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.lastError = lastError
    }
}

public enum OpenAIRealtimeSessionStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case created
    case active
    case closing
    case closed
    case failed
    case expired
}

public enum OpenAIRealtimeModality: String, Hashable, Codable, Sendable, CaseIterable {
    case text
    case audio
    case image
}

public struct OpenAIRealtimeSession: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIRealtimeSessionID
    public var providerID: ProviderID
    public var modelID: ModelID
    public var status: OpenAIRealtimeSessionStatus
    public var modalities: [OpenAIRealtimeModality]
    public var voice: String?
    public var inputAudioFormat: String?
    public var outputAudioFormat: String?
    public var credentialKeychainAccount: String?
    public var expiresAt: Date?
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var closedAt: Date?
    public var lastError: String?

    public init(
        id: OpenAIRealtimeSessionID,
        providerID: ProviderID,
        modelID: ModelID,
        status: OpenAIRealtimeSessionStatus = .created,
        modalities: [OpenAIRealtimeModality] = [.text],
        voice: String? = nil,
        inputAudioFormat: String? = nil,
        outputAudioFormat: String? = nil,
        credentialKeychainAccount: String? = nil,
        expiresAt: Date? = nil,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        closedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.status = status
        self.modalities = modalities
        self.voice = voice
        self.inputAudioFormat = inputAudioFormat
        self.outputAudioFormat = outputAudioFormat
        self.credentialKeychainAccount = credentialKeychainAccount
        self.expiresAt = expiresAt
        self.providerMetadata = providerMetadata
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.lastError = lastError
    }
}

public enum OpenAIBatchEndpoint: String, Hashable, Codable, Sendable, CaseIterable {
    case responses = "/v1/responses"
    case chatCompletions = "/v1/chat/completions"
    case embeddings = "/v1/embeddings"
    case completions = "/v1/completions"
}

public enum OpenAIBatchJobStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case validating
    case failed
    case inProgress
    case finalizing
    case completed
    case expired
    case cancelling
    case cancelled
}

public struct OpenAIBatchRequestCounts: Hashable, Codable, Sendable {
    public var total: Int
    public var completed: Int
    public var failed: Int

    public init(total: Int = 0, completed: Int = 0, failed: Int = 0) {
        self.total = total
        self.completed = completed
        self.failed = failed
    }
}

public struct OpenAIBatchJob: Identifiable, Hashable, Codable, Sendable {
    public var id: OpenAIBatchID
    public var providerID: ProviderID
    public var endpoint: OpenAIBatchEndpoint
    public var status: OpenAIBatchJobStatus
    public var inputFileID: OpenAIProviderFileID
    public var outputFileID: OpenAIProviderFileID?
    public var errorFileID: OpenAIProviderFileID?
    public var completionWindow: String
    public var requestCounts: OpenAIBatchRequestCounts
    public var metadata: [String: String]
    public var createdAt: Date
    public var inProgressAt: Date?
    public var finalizingAt: Date?
    public var completedAt: Date?
    public var failedAt: Date?
    public var expiredAt: Date?
    public var cancelledAt: Date?
    public var expiresAt: Date?
    public var lastError: String?

    public init(
        id: OpenAIBatchID,
        providerID: ProviderID,
        endpoint: OpenAIBatchEndpoint,
        status: OpenAIBatchJobStatus = .validating,
        inputFileID: OpenAIProviderFileID,
        outputFileID: OpenAIProviderFileID? = nil,
        errorFileID: OpenAIProviderFileID? = nil,
        completionWindow: String = "24h",
        requestCounts: OpenAIBatchRequestCounts = .init(),
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        inProgressAt: Date? = nil,
        finalizingAt: Date? = nil,
        completedAt: Date? = nil,
        failedAt: Date? = nil,
        expiredAt: Date? = nil,
        cancelledAt: Date? = nil,
        expiresAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.endpoint = endpoint
        self.status = status
        self.inputFileID = inputFileID
        self.outputFileID = outputFileID
        self.errorFileID = errorFileID
        self.completionWindow = completionWindow
        self.requestCounts = requestCounts
        self.metadata = metadata
        self.createdAt = createdAt
        self.inProgressAt = inProgressAt
        self.finalizingAt = finalizingAt
        self.completedAt = completedAt
        self.failedAt = failedAt
        self.expiredAt = expiredAt
        self.cancelledAt = cancelledAt
        self.expiresAt = expiresAt
        self.lastError = lastError
    }
}

public enum OpenAIStructuredOutputResultStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case parsed
    case refused
    case incomplete
    case invalid
}

public struct OpenAIStructuredOutputResult: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var responseID: OpenAIResponseID?
    public var messageID: UUID?
    public var schemaName: String?
    public var schema: JSONValue?
    public var content: JSONValue?
    public var refusal: String?
    public var incompleteReason: String?
    public var validationErrors: [String]
    public var status: OpenAIStructuredOutputResultStatus
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        responseID: OpenAIResponseID? = nil,
        messageID: UUID? = nil,
        schemaName: String? = nil,
        schema: JSONValue? = nil,
        content: JSONValue? = nil,
        refusal: String? = nil,
        incompleteReason: String? = nil,
        validationErrors: [String] = [],
        status: OpenAIStructuredOutputResultStatus = .parsed,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.responseID = responseID
        self.messageID = messageID
        self.schemaName = schemaName
        self.schema = schema
        self.content = content
        self.refusal = refusal
        self.incompleteReason = incompleteReason
        self.validationErrors = validationErrors
        self.status = status
        self.createdAt = createdAt
    }

    public init(
        id: UUID = UUID(),
        messageID: UUID? = nil,
        schemaName: String? = nil,
        schema: JSONValue? = nil,
        content: JSONValue? = nil,
        refusal: String? = nil,
        providerMetadata: [String: String],
        createdAt: Date = Date()
    ) {
        let responseID = providerMetadata[CloudProviderMetadataKeys.openAIResponseID].map(OpenAIResponseID.init(rawValue:))
        let incompleteReason = providerMetadata[CloudProviderMetadataKeys.openAIResponseIncompleteReason]
        let validationErrors: [String]
        if let content, let schema {
            validationErrors = Self.localValidationErrors(content: content, schema: schema)
        } else {
            validationErrors = []
        }
        let status: OpenAIStructuredOutputResultStatus
        if refusal?.isEmpty == false {
            status = .refused
        } else if incompleteReason?.isEmpty == false {
            status = .incomplete
        } else if !validationErrors.isEmpty {
            status = .invalid
        } else {
            status = .parsed
        }
        self.init(
            id: id,
            responseID: responseID,
            messageID: messageID,
            schemaName: schemaName,
            schema: schema,
            content: content,
            refusal: refusal,
            incompleteReason: incompleteReason,
            validationErrors: validationErrors,
            status: status,
            createdAt: createdAt
        )
    }

    public func locallyValidated() -> OpenAIStructuredOutputResult {
        guard let content, let schema else {
            return self
        }
        let errors = Self.localValidationErrors(content: content, schema: schema)
        var result = self
        result.validationErrors = errors
        if !errors.isEmpty {
            result.status = .invalid
        } else if result.status == .invalid {
            result.status = .parsed
        }
        return result
    }

    public static func localValidationErrors(content: JSONValue, schema: JSONValue) -> [String] {
        var errors = [String]()
        validate(content, schema: schema, path: "$", errors: &errors)
        return errors
    }

    private static func validate(_ value: JSONValue, schema: JSONValue, path: String, errors: inout [String]) {
        guard case let .object(schemaObject) = schema else {
            return
        }
        if let allowed = allowedTypes(from: schemaObject["type"]),
           !allowed.contains(jsonSchemaType(of: value)) {
            errors.append("\(path) expected \(allowed.sorted().joined(separator: " or ")), got \(jsonSchemaType(of: value))")
            return
        }
        if let enumValues = schemaObject["enum"],
           case let .array(candidates) = enumValues,
           !candidates.contains(value) {
            errors.append("\(path) did not match an allowed enum value")
        }
        if case let .object(object) = value {
            validateObject(object, schema: schemaObject, path: path, errors: &errors)
        }
        if case let .array(array) = value,
           let itemSchema = schemaObject["items"] {
            for (index, item) in array.enumerated() {
                validate(item, schema: itemSchema, path: "\(path)[\(index)]", errors: &errors)
            }
        }
    }

    private static func validateObject(_ object: [String: JSONValue], schema: [String: JSONValue], path: String, errors: inout [String]) {
        let required = stringArray(from: schema["required"])
        for key in required where object[key] == nil {
            errors.append("\(path).\(key) is required")
        }
        let properties = schema["properties"]?.objectValue ?? [:]
        for (key, propertySchema) in properties {
            guard let child = object[key] else { continue }
            validate(child, schema: propertySchema, path: "\(path).\(key)", errors: &errors)
        }
        if schema["additionalProperties"]?.boolValue == false {
            let allowedKeys = Set(properties.keys)
            for key in object.keys where !allowedKeys.contains(key) {
                errors.append("\(path).\(key) is not allowed")
            }
        }
    }

    private static func allowedTypes(from typeValue: JSONValue?) -> Set<String>? {
        switch typeValue {
        case let .string(value):
            return [value]
        case let .array(values):
            let strings = values.compactMap(\.stringValue)
            return strings.isEmpty ? nil : Set(strings)
        case .object, .number, .bool, .null, .none:
            return nil
        }
    }

    private static func stringArray(from value: JSONValue?) -> [String] {
        guard case let .array(values) = value else { return [] }
        return values.compactMap(\.stringValue)
    }

    private static func jsonSchemaType(of value: JSONValue) -> String {
        switch value {
        case .object:
            return "object"
        case .array:
            return "array"
        case .string:
            return "string"
        case .number:
            return "number"
        case .bool:
            return "boolean"
        case .null:
            return "null"
        }
    }
}

public enum ProviderContextCacheStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case creating
    case active
    case expired
    case failed
    case deleting
    case deleted
}

public struct ProviderContextCache: Identifiable, Hashable, Codable, Sendable {
    public var id: ProviderContextCacheID
    public var providerID: ProviderID
    public var modelID: ModelID
    public var name: String?
    public var status: ProviderContextCacheStatus
    public var displayName: String?
    public var contentTokenCount: Int?
    public var ttlSeconds: Int?
    public var expiresAt: Date?
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date?
    public var lastError: String?

    public init(
        id: ProviderContextCacheID,
        providerID: ProviderID,
        modelID: ModelID,
        name: String? = nil,
        status: ProviderContextCacheStatus = .creating,
        displayName: String? = nil,
        contentTokenCount: Int? = nil,
        ttlSeconds: Int? = nil,
        expiresAt: Date? = nil,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.name = name
        self.status = status
        self.displayName = displayName
        self.contentTokenCount = contentTokenCount
        self.ttlSeconds = ttlSeconds
        self.expiresAt = expiresAt
        self.providerMetadata = providerMetadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastError = lastError
    }
}

public typealias ProviderFilePurpose = OpenAIProviderFilePurpose
public typealias ProviderFileStatus = OpenAIProviderFileStatus
public typealias ProviderFile = OpenAIProviderFile
public typealias ProviderDataStoreStatus = OpenAIVectorStoreStatus
public typealias ProviderDataStoreFileCounts = OpenAIVectorStoreFileCounts
public typealias ProviderDataStoreExpirationPolicy = OpenAIVectorStoreExpirationPolicy
public typealias ProviderDataStore = OpenAIVectorStore
public typealias ProviderDataStoreFileStatus = OpenAIVectorStoreFileStatus
public typealias ProviderDataStoreFile = OpenAIVectorStoreFile
public typealias ProviderHostedToolCallStatus = OpenAIHostedToolCallStatus
public typealias ProviderHostedToolCall = OpenAIHostedToolCall
public typealias ProviderArtifactKind = OpenAIArtifactKind
public typealias ProviderArtifact = OpenAIArtifact
public typealias ProviderBackgroundRunStatus = OpenAIBackgroundResponseStatus
public typealias ProviderBackgroundRun = OpenAIBackgroundResponse
public typealias ProviderLiveSessionStatus = OpenAIRealtimeSessionStatus
public typealias ProviderLiveModality = OpenAIRealtimeModality
public typealias ProviderLiveSession = OpenAIRealtimeSession
public typealias ProviderBatchEndpoint = OpenAIBatchEndpoint
public typealias ProviderBatchJobStatus = OpenAIBatchJobStatus
public typealias ProviderBatchRequestCounts = OpenAIBatchRequestCounts
public typealias ProviderBatchJob = OpenAIBatchJob
public typealias StructuredOutputResultStatus = OpenAIStructuredOutputResultStatus
public typealias StructuredOutputResult = OpenAIStructuredOutputResult

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

public struct VaultSearchOptions: Hashable, Codable, Sendable {
    public var lexicalCandidateCount: Int
    public var semanticBatchSize: Int
    public var semanticRerankCount: Int
    public var timeoutMilliseconds: Int?

    public init(
        lexicalCandidateCount: Int = 64,
        semanticBatchSize: Int = 256,
        semanticRerankCount: Int = 64,
        timeoutMilliseconds: Int? = nil
    ) {
        self.lexicalCandidateCount = max(1, lexicalCandidateCount)
        self.semanticBatchSize = max(32, semanticBatchSize)
        self.semanticRerankCount = max(1, semanticRerankCount)
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    public static let `default` = VaultSearchOptions()
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
    /// Legacy or explicitly local transcript rows (most commonly a prior
    /// local agent tool exchange) that would cross the cloud boundary for this
    /// turn. Optional preserves decoding compatibility with older requests.
    public var localTranscriptMessageCount: Int?
    public var estimatedContextBytes: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        modelID: ModelID,
        documentIDs: [UUID],
        mcpResourceIDs: [String],
        localTranscriptMessageCount: Int? = nil,
        estimatedContextBytes: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.documentIDs = documentIDs
        self.mcpResourceIDs = mcpResourceIDs
        self.localTranscriptMessageCount = localTranscriptMessageCount.map { max(0, $0) }
        self.estimatedContextBytes = max(0, estimatedContextBytes)
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
    public static let defaultCloudMaxCompletionTokens = 16_384
    public static let defaultLocalMaxCompletionTokens = 1_024
    public static let defaultLocalMaxContextTokens = 65_536
    public static let minCompletionTokens = 128
    public static let maxCompletionTokens = 128_000
    public static let minLocalContextTokens = 1_024
    public static let maxLocalContextTokens = 262_144
    public static let defaultOpenAIReasoningEffort: OpenAIReasoningEffort = .low
    public static let defaultOpenAITextVerbosity: OpenAITextVerbosity = .low
    public static let defaultAnthropicEffort: AnthropicEffort = .medium
    public static let defaultAnthropicThinkingMode: AnthropicThinkingMode = .adaptive
    public static let defaultAnthropicThinkingBudgetTokens = 4096
    public static let defaultGeminiThinkingLevel: GeminiThinkingLevel = .medium
    public static let defaultCloudWebSearchMode: CloudWebSearchMode = .off
    public static let defaultOpenRouterProviderPreferences = OpenRouterProviderPreferences()
    public static let defaultCloudAccessMode: CloudAccessMode = .byok
    public static let defaultProEntitlementStatus: ProEntitlementStatus = .inactive
    public static let defaultManagedCloudConsent: ManagedCloudConsent = .notAsked
    public static let defaultLocalTurboQuantMode: TurboQuantUserMode = .balanced

    public var securityConfiguration: SecurityConfiguration
    public var executionMode: AgentExecutionMode
    public var cloudAccessMode: CloudAccessMode
    public var proEntitlementStatus: ProEntitlementStatus
    public var managedCloudConsent: ManagedCloudConsent
    public var storeConfiguration: LocalStoreConfiguration
    public var defaultProviderID: ProviderID?
    public var defaultModelID: ModelID?
    public var embeddingModelID: ModelID?
    public var cloudMaxCompletionTokens: Int
    public var localMaxCompletionTokens: Int
    public var localMaxContextTokens: Int
    public var localTurboQuantMode: TurboQuantUserMode
    public var openAIReasoningEffort: OpenAIReasoningEffort
    public var openAITextVerbosity: OpenAITextVerbosity
    public var anthropicEffort: AnthropicEffort
    public var anthropicThinkingMode: AnthropicThinkingMode
    public var anthropicThinkingBudgetTokens: Int
    public var anthropicPromptCachingEnabled: Bool
    public var anthropicPromptCacheTTL: AnthropicPromptCacheTTL
    public var anthropicCitationsEnabled: Bool
    public var anthropicTokenCountPreflightEnabled: Bool
    public var geminiThinkingLevel: GeminiThinkingLevel
    public var cloudWebSearchMode: CloudWebSearchMode
    public var openRouterProviderPreferences: OpenRouterProviderPreferences
    public var requireToolApproval: Bool
    public var braveSearchEnabled: Bool
    public var onboardingCompleted: Bool
    public var themeTemplate: String
    public var interfaceMode: String

    private enum CodingKeys: String, CodingKey {
        case securityConfiguration
        case executionMode
        case cloudAccessMode
        case proEntitlementStatus
        case managedCloudConsent
        case storeConfiguration
        case defaultProviderID
        case defaultModelID
        case embeddingModelID
        case cloudMaxCompletionTokens
        case localMaxCompletionTokens
        case localMaxContextTokens
        case localTurboQuantMode
        case openAIReasoningEffort
        case openAITextVerbosity
        case anthropicEffort
        case anthropicThinkingMode
        case anthropicThinkingBudgetTokens
        case anthropicPromptCachingEnabled
        case anthropicPromptCacheTTL
        case anthropicCitationsEnabled
        case anthropicTokenCountPreflightEnabled
        case geminiThinkingLevel
        case cloudWebSearchMode
        case openRouterProviderPreferences
        case requireToolApproval
        case braveSearchEnabled
        case onboardingCompleted
        case themeTemplate
        case interfaceMode
    }

    public init(
        securityConfiguration: SecurityConfiguration = .init(),
        executionMode: AgentExecutionMode = .preferLocal,
        cloudAccessMode: CloudAccessMode = Self.defaultCloudAccessMode,
        proEntitlementStatus: ProEntitlementStatus = Self.defaultProEntitlementStatus,
        managedCloudConsent: ManagedCloudConsent = Self.defaultManagedCloudConsent,
        storeConfiguration: LocalStoreConfiguration = .init(),
        defaultProviderID: ProviderID? = nil,
        defaultModelID: ModelID? = nil,
        embeddingModelID: ModelID? = nil,
        cloudMaxCompletionTokens: Int = Self.defaultCloudMaxCompletionTokens,
        localMaxCompletionTokens: Int = Self.defaultLocalMaxCompletionTokens,
        localMaxContextTokens: Int = Self.defaultLocalMaxContextTokens,
        localTurboQuantMode: TurboQuantUserMode = Self.defaultLocalTurboQuantMode,
        openAIReasoningEffort: OpenAIReasoningEffort = Self.defaultOpenAIReasoningEffort,
        openAITextVerbosity: OpenAITextVerbosity = Self.defaultOpenAITextVerbosity,
        anthropicEffort: AnthropicEffort = Self.defaultAnthropicEffort,
        anthropicThinkingMode: AnthropicThinkingMode = Self.defaultAnthropicThinkingMode,
        anthropicThinkingBudgetTokens: Int = Self.defaultAnthropicThinkingBudgetTokens,
        anthropicPromptCachingEnabled: Bool = false,
        anthropicPromptCacheTTL: AnthropicPromptCacheTTL = .fiveMinutes,
        anthropicCitationsEnabled: Bool = true,
        anthropicTokenCountPreflightEnabled: Bool = false,
        geminiThinkingLevel: GeminiThinkingLevel = Self.defaultGeminiThinkingLevel,
        cloudWebSearchMode: CloudWebSearchMode = Self.defaultCloudWebSearchMode,
        openRouterProviderPreferences: OpenRouterProviderPreferences = Self.defaultOpenRouterProviderPreferences,
        requireToolApproval: Bool = true,
        braveSearchEnabled: Bool = false,
        onboardingCompleted: Bool = false,
        themeTemplate: String = "evergreen",
        interfaceMode: String = "system"
    ) {
        self.securityConfiguration = securityConfiguration
        self.executionMode = executionMode
        self.cloudAccessMode = cloudAccessMode
        self.proEntitlementStatus = proEntitlementStatus
        self.managedCloudConsent = managedCloudConsent
        self.storeConfiguration = storeConfiguration
        self.defaultProviderID = defaultProviderID
        self.defaultModelID = defaultModelID
        self.embeddingModelID = embeddingModelID
        self.cloudMaxCompletionTokens = Self.normalizedCompletionTokens(cloudMaxCompletionTokens)
        self.localMaxCompletionTokens = Self.normalizedCompletionTokens(localMaxCompletionTokens)
        self.localMaxContextTokens = Self.normalizedLocalContextTokens(localMaxContextTokens)
        self.localTurboQuantMode = localTurboQuantMode
        self.openAIReasoningEffort = openAIReasoningEffort
        self.openAITextVerbosity = openAITextVerbosity
        self.anthropicEffort = anthropicEffort
        self.anthropicThinkingMode = anthropicThinkingMode
        self.anthropicThinkingBudgetTokens = Self.normalizedAnthropicThinkingBudgetTokens(anthropicThinkingBudgetTokens)
        self.anthropicPromptCachingEnabled = anthropicPromptCachingEnabled
        self.anthropicPromptCacheTTL = anthropicPromptCacheTTL
        self.anthropicCitationsEnabled = anthropicCitationsEnabled
        self.anthropicTokenCountPreflightEnabled = anthropicTokenCountPreflightEnabled
        self.geminiThinkingLevel = geminiThinkingLevel
        self.cloudWebSearchMode = cloudWebSearchMode
        self.openRouterProviderPreferences = openRouterProviderPreferences
        self.requireToolApproval = requireToolApproval
        self.braveSearchEnabled = braveSearchEnabled
        self.onboardingCompleted = onboardingCompleted
        self.themeTemplate = themeTemplate
        self.interfaceMode = interfaceMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityConfiguration = try container.decodeIfPresent(SecurityConfiguration.self, forKey: .securityConfiguration) ?? .init()
        executionMode = try container.decodeIfPresent(AgentExecutionMode.self, forKey: .executionMode) ?? .preferLocal
        cloudAccessMode = try container.decodeIfPresent(CloudAccessMode.self, forKey: .cloudAccessMode) ?? Self.defaultCloudAccessMode
        proEntitlementStatus = try container.decodeIfPresent(ProEntitlementStatus.self, forKey: .proEntitlementStatus) ?? Self.defaultProEntitlementStatus
        managedCloudConsent = try container.decodeIfPresent(ManagedCloudConsent.self, forKey: .managedCloudConsent) ?? Self.defaultManagedCloudConsent
        storeConfiguration = try container.decodeIfPresent(LocalStoreConfiguration.self, forKey: .storeConfiguration) ?? .init()
        defaultProviderID = try container.decodeIfPresent(ProviderID.self, forKey: .defaultProviderID)
        defaultModelID = try container.decodeIfPresent(ModelID.self, forKey: .defaultModelID)
        embeddingModelID = try container.decodeIfPresent(ModelID.self, forKey: .embeddingModelID)
        cloudMaxCompletionTokens = Self.normalizedCompletionTokens(
            try container.decodeIfPresent(Int.self, forKey: .cloudMaxCompletionTokens) ?? Self.defaultCloudMaxCompletionTokens
        )
        localMaxCompletionTokens = Self.normalizedCompletionTokens(
            try container.decodeIfPresent(Int.self, forKey: .localMaxCompletionTokens) ?? Self.defaultLocalMaxCompletionTokens
        )
        localMaxContextTokens = Self.normalizedLocalContextTokens(
            try container.decodeIfPresent(Int.self, forKey: .localMaxContextTokens) ?? Self.defaultLocalMaxContextTokens
        )
        localTurboQuantMode = try container.decodeIfPresent(TurboQuantUserMode.self, forKey: .localTurboQuantMode) ?? Self.defaultLocalTurboQuantMode
        openAIReasoningEffort = try container.decodeIfPresent(OpenAIReasoningEffort.self, forKey: .openAIReasoningEffort) ?? Self.defaultOpenAIReasoningEffort
        openAITextVerbosity = try container.decodeIfPresent(OpenAITextVerbosity.self, forKey: .openAITextVerbosity) ?? Self.defaultOpenAITextVerbosity
        anthropicEffort = try container.decodeIfPresent(AnthropicEffort.self, forKey: .anthropicEffort) ?? Self.defaultAnthropicEffort
        anthropicThinkingMode = try container.decodeIfPresent(AnthropicThinkingMode.self, forKey: .anthropicThinkingMode) ?? Self.defaultAnthropicThinkingMode
        anthropicThinkingBudgetTokens = Self.normalizedAnthropicThinkingBudgetTokens(
            try container.decodeIfPresent(Int.self, forKey: .anthropicThinkingBudgetTokens) ?? Self.defaultAnthropicThinkingBudgetTokens
        )
        anthropicPromptCachingEnabled = try container.decodeIfPresent(Bool.self, forKey: .anthropicPromptCachingEnabled) ?? false
        anthropicPromptCacheTTL = try container.decodeIfPresent(AnthropicPromptCacheTTL.self, forKey: .anthropicPromptCacheTTL) ?? .fiveMinutes
        anthropicCitationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .anthropicCitationsEnabled) ?? true
        anthropicTokenCountPreflightEnabled = try container.decodeIfPresent(Bool.self, forKey: .anthropicTokenCountPreflightEnabled) ?? false
        geminiThinkingLevel = try container.decodeIfPresent(GeminiThinkingLevel.self, forKey: .geminiThinkingLevel) ?? Self.defaultGeminiThinkingLevel
        cloudWebSearchMode = try container.decodeIfPresent(CloudWebSearchMode.self, forKey: .cloudWebSearchMode) ?? Self.defaultCloudWebSearchMode
        openRouterProviderPreferences = try container.decodeIfPresent(
            OpenRouterProviderPreferences.self,
            forKey: .openRouterProviderPreferences
        ) ?? Self.defaultOpenRouterProviderPreferences
        requireToolApproval = try container.decodeIfPresent(Bool.self, forKey: .requireToolApproval) ?? true
        braveSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .braveSearchEnabled) ?? false
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        themeTemplate = try container.decodeIfPresent(String.self, forKey: .themeTemplate) ?? "evergreen"
        interfaceMode = try container.decodeIfPresent(String.self, forKey: .interfaceMode) ?? "system"
    }

    public static func normalizedCompletionTokens(_ value: Int) -> Int {
        min(max(value, minCompletionTokens), maxCompletionTokens)
    }

    public static func normalizedLocalContextTokens(_ value: Int) -> Int {
        min(max(value, minLocalContextTokens), maxLocalContextTokens)
    }

    public static func normalizedAnthropicThinkingBudgetTokens(_ value: Int) -> Int {
        min(max(value, 1_024), 128_000)
    }
}

public struct SecurityConfiguration: Hashable, Codable, Sendable {
    public static let currentEncryptedStoreVersion = 1

    public var appLockEnabled: Bool
    public var encryptedStoreVersion: Int
    public var cloudKitE2EEnabled: Bool
    public var securityResetCompletedAt: Date?

    public init(
        appLockEnabled: Bool = false,
        encryptedStoreVersion: Int = Self.currentEncryptedStoreVersion,
        cloudKitE2EEnabled: Bool = true,
        securityResetCompletedAt: Date? = nil
    ) {
        self.appLockEnabled = appLockEnabled
        self.encryptedStoreVersion = max(0, encryptedStoreVersion)
        self.cloudKitE2EEnabled = cloudKitE2EEnabled
        self.securityResetCompletedAt = securityResetCompletedAt
    }
}
