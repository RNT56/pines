import Foundation

public enum PinesFeature: String, Codable, CaseIterable, Sendable {
    case chats
    case models
    case vault
    case agents
    case settings
}

public enum ServiceReadiness: String, Codable, Sendable {
    case unavailable
    case booting
    case ready
    case degraded
    case requiresUserAction
}

public struct ServiceHealth: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public var name: String
    public var readiness: ServiceReadiness
    public var summary: String
    public var updatedAt: Date

    public init(
        name: String,
        readiness: ServiceReadiness,
        summary: String,
        updatedAt: Date = Date()
    ) {
        self.name = name
        self.readiness = readiness
        self.summary = summary
        self.updatedAt = updatedAt
    }
}

public struct FeatureModuleDescriptor: Identifiable, Hashable, Codable, Sendable {
    public var id: PinesFeature { feature }
    public var feature: PinesFeature
    public var displayName: String
    public var ownsTables: [String]
    public var ownsPermissions: [String]
    public var serviceDependencies: [String]

    public init(
        feature: PinesFeature,
        displayName: String,
        ownsTables: [String],
        ownsPermissions: [String] = [],
        serviceDependencies: [String] = []
    ) {
        self.feature = feature
        self.displayName = displayName
        self.ownsTables = ownsTables
        self.ownsPermissions = ownsPermissions
        self.serviceDependencies = serviceDependencies
    }
}

public enum PinesArchitecture {
    public static let modules: [FeatureModuleDescriptor] = [
        FeatureModuleDescriptor(
            feature: .chats,
            displayName: "Chats",
            ownsTables: ["conversations", "messages", "messages_fts", "attachments"],
            serviceDependencies: ["InferenceRuntime", "AuditLog"]
        ),
        FeatureModuleDescriptor(
            feature: .models,
            displayName: "Models",
            ownsTables: ["model_installs"],
            serviceDependencies: ["ModelCatalog", "DownloadManager", "MLXRuntime"]
        ),
        FeatureModuleDescriptor(
            feature: .vault,
            displayName: "Vault",
            ownsTables: ["vault_documents", "vault_chunks", "vault_chunks_fts", "attachments"],
            ownsPermissions: ["Files", "Photos", "Camera"],
            serviceDependencies: ["EmbeddingRuntime", "OCR", "AuditLog"]
        ),
        FeatureModuleDescriptor(
            feature: .agents,
            displayName: "Agents",
            ownsTables: ["audit_events", "mcp_servers", "mcp_tools"],
            ownsPermissions: ["Network", "Browser", "Cloud BYOK"],
            serviceDependencies: ["ToolRegistry", "ExecutionRouter", "SecretStore"]
        ),
        FeatureModuleDescriptor(
            feature: .settings,
            displayName: "Settings",
            ownsTables: [],
            serviceDependencies: ["SecretStore", "ThemeStore", "CloudSyncSettings"]
        ),
    ]
}

public protocol ConversationRepository: Sendable {
    func listConversations() async throws -> [ConversationRecord]
    func listConversationPreviews() async throws -> [ConversationPreviewRecord]
    func observeConversations() -> AsyncStream<[ConversationRecord]>
    func observeConversationPreviews() -> AsyncStream<[ConversationPreviewRecord]>
    func createConversation(title: String, defaultModelID: ModelID?) async throws -> ConversationRecord
    func updateConversationTitle(_ title: String, conversationID: UUID) async throws
    func setConversationArchived(_ archived: Bool, conversationID: UUID) async throws
    func deleteConversation(id: UUID) async throws
    func messages(in conversationID: UUID) async throws -> [ChatMessage]
    func observeMessages(in conversationID: UUID) -> AsyncStream<[ChatMessage]>
    func appendMessage(_ message: ChatMessage, status: MessageStatus, conversationID: UUID, modelID: ModelID?, providerID: ProviderID?) async throws
    func updateMessage(id: UUID, content: String, status: MessageStatus, tokenCount: Int?) async throws
}

public struct ConversationRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var defaultModelID: ModelID?
    public var archived: Bool
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        defaultModelID: ModelID? = nil,
        archived: Bool = false,
        pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.defaultModelID = defaultModelID
        self.archived = archived
        self.pinned = pinned
    }
}

public struct ConversationPreviewRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var defaultModelID: ModelID?
    public var archived: Bool
    public var pinned: Bool
    public var lastMessage: String?
    public var lastMessageStatus: MessageStatus?
    public var tokenCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        defaultModelID: ModelID? = nil,
        archived: Bool = false,
        pinned: Bool = false,
        lastMessage: String? = nil,
        lastMessageStatus: MessageStatus? = nil,
        tokenCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.defaultModelID = defaultModelID
        self.archived = archived
        self.pinned = pinned
        self.lastMessage = lastMessage
        self.lastMessageStatus = lastMessageStatus
        self.tokenCount = tokenCount
    }
}

public protocol ModelInstallRepository: Sendable {
    func listInstalledAndCuratedModels() async throws -> [ModelInstall]
    func observeInstalledAndCuratedModels() -> AsyncStream<[ModelInstall]>
    func upsertInstall(_ install: ModelInstall) async throws
    func updateInstallState(_ state: ModelInstallState, for repository: String) async throws
    func deleteInstall(repository: String) async throws
}

public protocol VaultRepository: Sendable {
    func listDocuments() async throws -> [VaultDocumentRecord]
    func observeDocuments() -> AsyncStream<[VaultDocumentRecord]>
    func upsertDocument(_ document: VaultDocumentRecord, localURL: URL?, checksum: String?) async throws
    func deleteDocument(id: UUID) async throws
    func chunks(documentID: UUID) async throws -> [VaultChunk]
    func embeddings(documentID: UUID) async throws -> [VaultStoredEmbedding]
    func replaceChunks(_ chunks: [VaultChunk], documentID: UUID, embeddingModelID: ModelID?) async throws
    func replaceChunks(_ chunks: [VaultChunk], embeddings: VaultEmbeddingBatch?, documentID: UUID, embeddingModelID: ModelID?) async throws
    func search(query: String, embedding: [Float]?, limit: Int) async throws -> [VaultSearchResult]
    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, limit: Int) async throws -> [VaultSearchResult]
}

public extension VaultRepository {
    func embeddings(documentID: UUID) async throws -> [VaultStoredEmbedding] {
        []
    }

    func replaceChunks(
        _ chunks: [VaultChunk],
        embeddings: VaultEmbeddingBatch?,
        documentID: UUID,
        embeddingModelID: ModelID?
    ) async throws {
        try await replaceChunks(chunks, documentID: documentID, embeddingModelID: embeddingModelID)
    }

    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, limit: limit)
    }
}

public struct VaultDocumentRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceType: String
    public var updatedAt: Date
    public var chunkCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        sourceType: String,
        updatedAt: Date = Date(),
        chunkCount: Int
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.updatedAt = updatedAt
        self.chunkCount = chunkCount
    }
}

public protocol SettingsRepository: Sendable {
    func loadSettings() async throws -> AppSettingsSnapshot
    func observeSettings() -> AsyncStream<AppSettingsSnapshot>
    func saveSettings(_ settings: AppSettingsSnapshot) async throws
}

public protocol CloudProviderRepository: Sendable {
    func listProviders() async throws -> [CloudProviderConfiguration]
    func observeProviders() -> AsyncStream<[CloudProviderConfiguration]>
    func upsertProvider(_ provider: CloudProviderConfiguration) async throws
    func deleteProvider(id: ProviderID) async throws
}

public typealias RemoteMCPServerRepository = MCPServerRepository

public protocol ModelDownloadRepository: Sendable {
    func listDownloads() async throws -> [ModelDownloadProgress]
    func observeDownloads() -> AsyncStream<[ModelDownloadProgress]>
    func upsertDownload(_ progress: ModelDownloadProgress) async throws
    func deleteDownload(id: UUID) async throws
}

public protocol AuditEventRepository: Sendable {
    func append(_ event: AuditEvent) async throws
    func list(category: AuditCategory?, limit: Int) async throws -> [AuditEvent]
    func observeRecent(limit: Int) -> AsyncStream<[AuditEvent]>
}
