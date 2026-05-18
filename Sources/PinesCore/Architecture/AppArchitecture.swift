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
    func createConversation(title: String, defaultModelID: ModelID?, defaultProviderID: ProviderID?) async throws -> ConversationRecord
    func updateConversationTitle(_ title: String, conversationID: UUID) async throws
    func updateConversationModel(modelID: ModelID?, providerID: ProviderID?, conversationID: UUID) async throws
    func setConversationArchived(_ archived: Bool, conversationID: UUID) async throws
    func setConversationPinned(_ pinned: Bool, conversationID: UUID) async throws
    func deleteConversation(id: UUID) async throws
    func messages(in conversationID: UUID) async throws -> [ChatMessage]
    func observeMessages(in conversationID: UUID) -> AsyncStream<[ChatMessage]>
    func appendMessage(_ message: ChatMessage, status: MessageStatus, conversationID: UUID, modelID: ModelID?, providerID: ProviderID?) async throws
    func deleteMessages(after messageID: UUID, in conversationID: UUID) async throws
    func updateMessage(
        id: UUID,
        content: String,
        status: MessageStatus,
        tokenCount: Int?,
        providerMetadata: [String: String]?,
        toolName: String?,
        toolCalls: [ToolCallDelta]?
    ) async throws
    func searchConversations(query: String, limit: Int) async throws -> [ConversationSearchResult]
}

public extension ConversationRepository {
    func updateMessage(id: UUID, content: String, status: MessageStatus, tokenCount: Int?, providerMetadata: [String: String]?) async throws {
        try await updateMessage(
            id: id,
            content: content,
            status: status,
            tokenCount: tokenCount,
            providerMetadata: providerMetadata,
            toolName: nil,
            toolCalls: nil
        )
    }

    func updateMessage(id: UUID, content: String, status: MessageStatus, tokenCount: Int?) async throws {
        try await updateMessage(id: id, content: content, status: status, tokenCount: tokenCount, providerMetadata: nil)
    }

    func searchConversations(query: String, limit: Int) async throws -> [ConversationSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        let tokens = normalizedQuery
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        let conversations = try await listConversations()
        var results = [ConversationSearchResult]()
        for conversation in conversations {
            let messages = try await messages(in: conversation.id)
            for message in messages where message.role != .tool {
                let searchable = message.content.lowercased()
                guard tokens.allSatisfy({ searchable.contains($0) }) else { continue }
                results.append(
                    ConversationSearchResult(
                        conversationID: conversation.id.uuidString,
                        conversationTitle: conversation.title,
                        conversationUpdatedAtISO8601: ConversationSearchResult.iso8601(conversation.updatedAt),
                        messageID: message.id.uuidString,
                        role: message.role.rawValue,
                        createdAtISO8601: ConversationSearchResult.iso8601(message.createdAt),
                        snippet: ConversationSearchResult.snippet(from: message.content, query: normalizedQuery)
                    )
                )
                if results.count >= max(1, limit) {
                    return results
                }
            }
        }
        return results
    }
}

public struct ConversationRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var defaultModelID: ModelID?
    public var defaultProviderID: ProviderID?
    public var archived: Bool
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        defaultModelID: ModelID? = nil,
        defaultProviderID: ProviderID? = nil,
        archived: Bool = false,
        pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.defaultModelID = defaultModelID
        self.defaultProviderID = defaultProviderID
        self.archived = archived
        self.pinned = pinned
    }
}

public struct ConversationPreviewRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var defaultModelID: ModelID?
    public var defaultProviderID: ProviderID?
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
        defaultProviderID: ProviderID? = nil,
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
        self.defaultProviderID = defaultProviderID
        self.archived = archived
        self.pinned = pinned
        self.lastMessage = lastMessage
        self.lastMessageStatus = lastMessageStatus
        self.tokenCount = tokenCount
    }
}

public struct ConversationSearchResult: Identifiable, Hashable, Codable, Sendable {
    public var id: String { messageID }
    public var conversationID: String
    public var conversationTitle: String
    public var conversationUpdatedAtISO8601: String
    public var messageID: String
    public var role: String
    public var createdAtISO8601: String
    public var snippet: String

    public init(
        conversationID: String,
        conversationTitle: String,
        conversationUpdatedAtISO8601: String,
        messageID: String,
        role: String,
        createdAtISO8601: String,
        snippet: String
    ) {
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.conversationUpdatedAtISO8601 = conversationUpdatedAtISO8601
        self.messageID = messageID
        self.role = role
        self.createdAtISO8601 = createdAtISO8601
        self.snippet = snippet
    }

    public static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public static func snippet(from content: String, query: String, radius: Int = 180) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let matchRange = tokens
            .compactMap { lower.range(of: $0.lowercased()) }
            .first

        guard let matchRange else {
            return String(trimmed.prefix(radius * 2))
        }

        let lowerBoundDistance = trimmed.distance(from: trimmed.startIndex, to: matchRange.lowerBound)
        let startOffset = max(0, lowerBoundDistance - radius)
        let start = trimmed.index(trimmed.startIndex, offsetBy: startOffset)
        let remaining = trimmed.distance(from: start, to: trimmed.endIndex)
        let end = trimmed.index(start, offsetBy: min(radius * 2, remaining))
        let prefix = start == trimmed.startIndex ? "" : "..."
        let suffix = end == trimmed.endIndex ? "" : "..."
        return prefix + String(trimmed[start..<end]) + suffix
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
    func listEmbeddingProfiles() async throws -> [VaultEmbeddingProfile]
    func observeEmbeddingProfiles() -> AsyncStream<[VaultEmbeddingProfile]>
    func activeEmbeddingProfile() async throws -> VaultEmbeddingProfile?
    func upsertEmbeddingProfile(_ profile: VaultEmbeddingProfile) async throws
    func setActiveEmbeddingProfile(id: String?) async throws
    func updateEmbeddingProfileConsent(id: String, granted: Bool) async throws
    func upsertEmbeddingJob(_ job: VaultEmbeddingJob) async throws
    func listEmbeddingJobs(limit: Int) async throws -> [VaultEmbeddingJob]
    func recordRetrievalEvent(_ event: VaultRetrievalEvent) async throws
    func listRetrievalEvents(limit: Int) async throws -> [VaultRetrievalEvent]
    func replaceChunks(_ chunks: [VaultChunk], documentID: UUID, embeddingModelID: ModelID?) async throws
    func replaceChunks(_ chunks: [VaultChunk], embeddings: VaultEmbeddingBatch?, documentID: UUID, embeddingModelID: ModelID?) async throws
    func replaceChunks(_ chunks: [VaultChunk], embeddings: VaultEmbeddingBatch?, documentID: UUID, embeddingProfile: VaultEmbeddingProfile?) async throws
    func upsertEmbeddings(_ embeddings: VaultEmbeddingBatch, documentID: UUID, embeddingProfile: VaultEmbeddingProfile) async throws
    func search(query: String, embedding: [Float]?, limit: Int) async throws -> [VaultSearchResult]
    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, limit: Int) async throws -> [VaultSearchResult]
    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, profileID: String?, limit: Int) async throws -> [VaultSearchResult]
}

public extension VaultRepository {
    func embeddings(documentID: UUID) async throws -> [VaultStoredEmbedding] {
        []
    }

    func listEmbeddingProfiles() async throws -> [VaultEmbeddingProfile] {
        []
    }

    func observeEmbeddingProfiles() -> AsyncStream<[VaultEmbeddingProfile]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func activeEmbeddingProfile() async throws -> VaultEmbeddingProfile? {
        nil
    }

    func upsertEmbeddingProfile(_ profile: VaultEmbeddingProfile) async throws {}

    func setActiveEmbeddingProfile(id: String?) async throws {}

    func updateEmbeddingProfileConsent(id: String, granted: Bool) async throws {}

    func upsertEmbeddingJob(_ job: VaultEmbeddingJob) async throws {}

    func listEmbeddingJobs(limit: Int) async throws -> [VaultEmbeddingJob] {
        []
    }

    func recordRetrievalEvent(_ event: VaultRetrievalEvent) async throws {}

    func listRetrievalEvents(limit: Int) async throws -> [VaultRetrievalEvent] {
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

    func replaceChunks(
        _ chunks: [VaultChunk],
        embeddings: VaultEmbeddingBatch?,
        documentID: UUID,
        embeddingProfile: VaultEmbeddingProfile?
    ) async throws {
        try await replaceChunks(chunks, embeddings: embeddings, documentID: documentID, embeddingModelID: embeddingProfile?.modelID)
    }

    func upsertEmbeddings(_ embeddings: VaultEmbeddingBatch, documentID: UUID, embeddingProfile: VaultEmbeddingProfile) async throws {
        let chunks = try await chunks(documentID: documentID)
        try await replaceChunks(chunks, embeddings: embeddings, documentID: documentID, embeddingProfile: embeddingProfile)
    }

    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, limit: limit)
    }

    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, profileID: String?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, embeddingModelID: embeddingModelID, limit: limit)
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
