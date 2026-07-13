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
            ownsTables: [
                "audit_events",
                "mcp_servers",
                "mcp_tools",
                "provider_files",
                "provider_artifacts",
                "provider_caches",
                "provider_batches",
                "provider_live_sessions",
                "provider_structured_outputs",
                "provider_model_capabilities",
                "provider_research_runs",
            ],
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
    func createConversation(title: String, defaultModelID: ModelID?, defaultProviderID: ProviderID?, projectID: UUID?) async throws -> ConversationRecord
    func moveConversation(_ conversationID: UUID, toProject projectID: UUID?) async throws
    func updateConversationTitle(_ title: String, conversationID: UUID) async throws
    func updateConversationModel(modelID: ModelID?, providerID: ProviderID?, conversationID: UUID) async throws
    func setConversationArchived(_ archived: Bool, conversationID: UUID) async throws
    func setConversationPinned(_ pinned: Bool, conversationID: UUID) async throws
    func deleteConversation(id: UUID) async throws
    func messages(in conversationID: UUID) async throws -> [ChatMessage]
    func recentMessages(in conversationID: UUID, limit: Int, requiredMessageIDs: Set<UUID>) async throws -> [ChatMessage]
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
    func createConversation(title: String, defaultModelID: ModelID?, defaultProviderID: ProviderID?, projectID: UUID?) async throws -> ConversationRecord {
        try await createConversation(title: title, defaultModelID: defaultModelID, defaultProviderID: defaultProviderID)
    }

    func moveConversation(_ conversationID: UUID, toProject projectID: UUID?) async throws {}

    func recentMessages(in conversationID: UUID, limit: Int, requiredMessageIDs: Set<UUID>) async throws -> [ChatMessage] {
        let allMessages = try await messages(in: conversationID)
        guard allMessages.count > limit || !requiredMessageIDs.isEmpty else { return allMessages }

        var selectedIDs = Set<UUID>()
        var selected = [ChatMessage]()
        for message in allMessages.reversed() where selected.count < max(1, limit) || requiredMessageIDs.contains(message.id) {
            selectedIDs.insert(message.id)
            selected.append(message)
        }
        for message in allMessages where requiredMessageIDs.contains(message.id) && !selectedIDs.contains(message.id) {
            selectedIDs.insert(message.id)
            selected.append(message)
        }
        return selected.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

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

    @discardableResult
    func repairInterruptedMessages(reason: String) async throws -> Int {
        let conversations = try await listConversations()
        var repairCount = 0
        for conversation in conversations {
            let repairs = InterruptedChatRunRepair.repairs(
                for: try await messages(in: conversation.id),
                reason: reason
            )
            for repair in repairs {
                try await updateMessage(
                    id: repair.messageID,
                    content: repair.content,
                    status: repair.status,
                    tokenCount: nil,
                    providerMetadata: repair.providerMetadata,
                    toolName: repair.toolName,
                    toolCalls: repair.toolCalls
                )
                repairCount += 1
            }
        }
        return repairCount
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

public protocol ProjectRepository: Sendable {
    func listProjects() async throws -> [ProjectRecord]
    func createProject(name: String) async throws -> ProjectRecord
    func updateProjectName(_ name: String, projectID: UUID) async throws
    func setProjectVaultEnabled(_ enabled: Bool, projectID: UUID) async throws
    func deleteProject(id: UUID) async throws
}

public struct ProjectRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var vaultEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        vaultEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.vaultEnabled = vaultEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ConversationRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var defaultModelID: ModelID?
    public var defaultProviderID: ProviderID?
    public var projectID: UUID?
    public var archived: Bool
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        defaultModelID: ModelID? = nil,
        defaultProviderID: ProviderID? = nil,
        projectID: UUID? = nil,
        archived: Bool = false,
        pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.defaultModelID = defaultModelID
        self.defaultProviderID = defaultProviderID
        self.projectID = projectID
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
    public var projectID: UUID?
    public var archived: Bool
    public var pinned: Bool
    public var lastMessage: String?
    public var lastMessageStatus: MessageStatus?
    public var titleSourceMessage: String?
    public var tokenCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        defaultModelID: ModelID? = nil,
        defaultProviderID: ProviderID? = nil,
        projectID: UUID? = nil,
        archived: Bool = false,
        pinned: Bool = false,
        lastMessage: String? = nil,
        lastMessageStatus: MessageStatus? = nil,
        titleSourceMessage: String? = nil,
        tokenCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.defaultModelID = defaultModelID
        self.defaultProviderID = defaultProviderID
        self.projectID = projectID
        self.archived = archived
        self.pinned = pinned
        self.lastMessage = lastMessage
        self.lastMessageStatus = lastMessageStatus
        self.titleSourceMessage = titleSourceMessage
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
    func deleteChunk(id: String, documentID: UUID) async throws
    func moveDocument(_ documentID: UUID, toProject projectID: UUID?) async throws
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

    func deleteChunk(id: String, documentID: UUID) async throws {
        let remaining = try await chunks(documentID: documentID).filter { $0.id != id }
        try await replaceChunks(remaining, documentID: documentID, embeddingModelID: nil)
    }

    func moveDocument(_ documentID: UUID, toProject projectID: UUID?) async throws {}

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
    public var checksum: String?
    public var localURL: URL?
    public var projectID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        sourceType: String,
        updatedAt: Date = Date(),
        chunkCount: Int,
        checksum: String? = nil,
        localURL: URL? = nil,
        projectID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.updatedAt = updatedAt
        self.chunkCount = chunkCount
        self.checksum = checksum
        self.localURL = localURL
        self.projectID = projectID
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
    func listModelCatalogSnapshots() async throws -> [CloudProviderModelCatalogSnapshot]
    func upsertModelCatalogSnapshot(_ snapshot: CloudProviderModelCatalogSnapshot) async throws
    func deleteModelCatalogSnapshot(providerID: ProviderID) async throws
}

public extension CloudProviderRepository {
    func listModelCatalogSnapshots() async throws -> [CloudProviderModelCatalogSnapshot] { [] }
    func upsertModelCatalogSnapshot(_ snapshot: CloudProviderModelCatalogSnapshot) async throws {}
    func deleteModelCatalogSnapshot(providerID: ProviderID) async throws {}
}

public struct ProviderFileRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerID: ProviderID
    public var providerKind: CloudProviderKind
    public var purpose: String
    public var fileName: String
    public var contentType: String?
    public var byteCount: Int64
    public var status: String
    public var sha256: String?
    public var localURL: URL?
    public var providerObject: String?
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var expiresAt: Date?
    public var lastError: String?

    public init(
        id: String,
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        purpose: String,
        fileName: String,
        contentType: String? = nil,
        byteCount: Int64 = 0,
        status: String,
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
        self.providerKind = providerKind
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

public struct ProviderArtifactRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerID: ProviderID?
    public var providerKind: CloudProviderKind
    public var responseID: String?
    public var toolCallID: String?
    public var providerFileID: String?
    public var kind: String
    public var fileName: String?
    public var contentType: String?
    public var byteCount: Int64?
    public var text: String?
    public var content: JSONValue?
    public var localURL: URL?
    public var remoteURL: URL?
    public var createdAt: Date

    public init(
        id: String,
        providerID: ProviderID? = nil,
        providerKind: CloudProviderKind,
        responseID: String? = nil,
        toolCallID: String? = nil,
        providerFileID: String? = nil,
        kind: String,
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
        self.providerID = providerID
        self.providerKind = providerKind
        self.responseID = responseID
        self.toolCallID = toolCallID
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

public struct ProviderCacheRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerID: ProviderID
    public var providerKind: CloudProviderKind
    public var kind: String
    public var name: String?
    public var modelID: ModelID?
    public var status: String
    public var usageBytes: Int64
    public var itemCounts: JSONValue?
    public var configuration: JSONValue?
    public var metadata: [String: String]
    public var createdAt: Date
    public var expiresAt: Date?
    public var lastActiveAt: Date?
    public var lastError: String?

    public init(
        id: String,
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        kind: String,
        name: String? = nil,
        modelID: ModelID? = nil,
        status: String,
        usageBytes: Int64 = 0,
        itemCounts: JSONValue? = nil,
        configuration: JSONValue? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        lastActiveAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.providerKind = providerKind
        self.kind = kind
        self.name = name
        self.modelID = modelID
        self.status = status
        self.usageBytes = usageBytes
        self.itemCounts = itemCounts
        self.configuration = configuration
        self.metadata = metadata
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastActiveAt = lastActiveAt
        self.lastError = lastError
    }
}

public struct ProviderBatchRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerID: ProviderID
    public var providerKind: CloudProviderKind
    public var endpoint: String
    public var status: String
    public var inputFileID: String?
    public var outputFileID: String?
    public var errorFileID: String?
    public var completionWindow: String?
    public var requestCounts: JSONValue?
    public var metadata: [String: String]
    public var createdAt: Date
    public var completedAt: Date?
    public var expiresAt: Date?
    public var lastError: String?

    public init(
        id: String,
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        endpoint: String,
        status: String,
        inputFileID: String? = nil,
        outputFileID: String? = nil,
        errorFileID: String? = nil,
        completionWindow: String? = nil,
        requestCounts: JSONValue? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        expiresAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.providerKind = providerKind
        self.endpoint = endpoint
        self.status = status
        self.inputFileID = inputFileID
        self.outputFileID = outputFileID
        self.errorFileID = errorFileID
        self.completionWindow = completionWindow
        self.requestCounts = requestCounts
        self.metadata = metadata
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.expiresAt = expiresAt
        self.lastError = lastError
    }
}

public struct ProviderLiveSessionRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerID: ProviderID
    public var providerKind: CloudProviderKind
    public var modelID: ModelID
    public var status: String
    public var modalities: [String]
    public var credentialKeychainAccount: String?
    public var expiresAt: Date?
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var closedAt: Date?
    public var lastError: String?

    public init(
        id: String,
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        modelID: ModelID,
        status: String,
        modalities: [String] = [],
        credentialKeychainAccount: String? = nil,
        expiresAt: Date? = nil,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        closedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.providerKind = providerKind
        self.modelID = modelID
        self.status = status
        self.modalities = modalities
        self.credentialKeychainAccount = credentialKeychainAccount
        self.expiresAt = expiresAt
        self.providerMetadata = providerMetadata
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.lastError = lastError
    }
}

public struct ProviderStructuredOutputRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var providerID: ProviderID?
    public var providerKind: CloudProviderKind
    public var responseID: String?
    public var messageID: UUID?
    public var schemaName: String?
    public var schema: JSONValue?
    public var content: JSONValue?
    public var refusal: String?
    public var incompleteReason: String?
    public var validationErrors: [String]
    public var status: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID? = nil,
        providerKind: CloudProviderKind,
        responseID: String? = nil,
        messageID: UUID? = nil,
        schemaName: String? = nil,
        schema: JSONValue? = nil,
        content: JSONValue? = nil,
        refusal: String? = nil,
        incompleteReason: String? = nil,
        validationErrors: [String] = [],
        status: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.providerKind = providerKind
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
}

public struct ProviderResearchRunRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerID: ProviderID
    public var providerKind: CloudProviderKind
    public var modelID: ModelID
    public var title: String
    public var prompt: String
    public var depth: String
    public var sourcePolicy: JSONValue
    public var reportFormat: String
    public var includeCodeInterpreter: Bool
    public var serviceTier: String
    public var responseID: String?
    public var status: String
    public var finalReportArtifactID: String?
    public var citationCount: Int
    public var toolCallCount: Int
    public var providerMetadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var lastError: String?

    public init(
        id: String,
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        modelID: ModelID,
        title: String,
        prompt: String,
        depth: String,
        sourcePolicy: JSONValue,
        reportFormat: String,
        includeCodeInterpreter: Bool = true,
        serviceTier: String,
        responseID: String? = nil,
        status: String,
        finalReportArtifactID: String? = nil,
        citationCount: Int = 0,
        toolCallCount: Int = 0,
        providerMetadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.providerKind = providerKind
        self.modelID = modelID
        self.title = title
        self.prompt = prompt
        self.depth = depth
        self.sourcePolicy = sourcePolicy
        self.reportFormat = reportFormat
        self.includeCodeInterpreter = includeCodeInterpreter
        self.serviceTier = serviceTier
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

public struct ProviderModelCapabilityRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(providerID.rawValue)::\(modelID.rawValue)" }
    public var providerID: ProviderID
    public var providerKind: CloudProviderKind
    public var modelID: ModelID
    public var capabilities: ProviderCapabilities
    public var contextWindowTokens: Int?
    public var inputModalities: [String]
    public var outputModalities: [String]
    public var metadata: [String: String]
    public var fetchedAt: Date
    public var expiresAt: Date?

    public init(
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        modelID: ModelID,
        capabilities: ProviderCapabilities,
        contextWindowTokens: Int? = nil,
        inputModalities: [String] = [],
        outputModalities: [String] = [],
        metadata: [String: String] = [:],
        fetchedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.providerID = providerID
        self.providerKind = providerKind
        self.modelID = modelID
        self.capabilities = capabilities
        self.contextWindowTokens = contextWindowTokens
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.metadata = metadata
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
    }
}

public protocol ProviderFileRepository: Sendable {
    func listProviderFiles(providerID: ProviderID?) async throws -> [ProviderFileRecord]
    func upsertProviderFile(_ file: ProviderFileRecord) async throws
    func deleteProviderFile(id: String) async throws
}

public protocol ProviderArtifactRepository: Sendable {
    func listProviderArtifacts(responseID: String?) async throws -> [ProviderArtifactRecord]
    func upsertProviderArtifact(_ artifact: ProviderArtifactRecord) async throws
    func deleteProviderArtifact(id: String) async throws
}

public protocol ProviderCacheRepository: Sendable {
    func listProviderCaches(providerID: ProviderID?, kind: String?) async throws -> [ProviderCacheRecord]
    func upsertProviderCache(_ cache: ProviderCacheRecord) async throws
    func deleteProviderCache(id: String) async throws
}

public protocol ProviderBatchRepository: Sendable {
    func listProviderBatches(providerID: ProviderID?) async throws -> [ProviderBatchRecord]
    func upsertProviderBatch(_ batch: ProviderBatchRecord) async throws
    func deleteProviderBatch(id: String) async throws
}

public protocol ProviderLiveSessionRepository: Sendable {
    func listProviderLiveSessions(providerID: ProviderID?) async throws -> [ProviderLiveSessionRecord]
    func upsertProviderLiveSession(_ session: ProviderLiveSessionRecord) async throws
    func deleteProviderLiveSession(id: String) async throws
}

public protocol ProviderStructuredOutputRepository: Sendable {
    func listProviderStructuredOutputs(responseID: String?) async throws -> [ProviderStructuredOutputRecord]
    func upsertProviderStructuredOutput(_ output: ProviderStructuredOutputRecord) async throws
    func deleteProviderStructuredOutput(id: UUID) async throws
}

public protocol ProviderModelCapabilityRepository: Sendable {
    func listProviderModelCapabilities(providerID: ProviderID?) async throws -> [ProviderModelCapabilityRecord]
    func upsertProviderModelCapability(_ capability: ProviderModelCapabilityRecord) async throws
    func deleteProviderModelCapability(providerID: ProviderID, modelID: ModelID) async throws
}

public protocol ProviderResearchRunRepository: Sendable {
    func listProviderResearchRuns(providerID: ProviderID?, status: String?) async throws -> [ProviderResearchRunRecord]
    func upsertProviderResearchRun(_ run: ProviderResearchRunRecord) async throws
    func deleteProviderResearchRun(id: String) async throws
}

public extension ProviderFileRepository {
    func listProviderFiles(providerID: ProviderID?) async throws -> [ProviderFileRecord] { [] }
    func upsertProviderFile(_ file: ProviderFileRecord) async throws {}
    func deleteProviderFile(id: String) async throws {}
}

public extension ProviderArtifactRepository {
    func listProviderArtifacts(responseID: String?) async throws -> [ProviderArtifactRecord] { [] }
    func upsertProviderArtifact(_ artifact: ProviderArtifactRecord) async throws {}
    func deleteProviderArtifact(id: String) async throws {}
}

public extension ProviderCacheRepository {
    func listProviderCaches(providerID: ProviderID?, kind: String?) async throws -> [ProviderCacheRecord] { [] }
    func upsertProviderCache(_ cache: ProviderCacheRecord) async throws {}
    func deleteProviderCache(id: String) async throws {}
}

public extension ProviderBatchRepository {
    func listProviderBatches(providerID: ProviderID?) async throws -> [ProviderBatchRecord] { [] }
    func upsertProviderBatch(_ batch: ProviderBatchRecord) async throws {}
    func deleteProviderBatch(id: String) async throws {}
}

public extension ProviderLiveSessionRepository {
    func listProviderLiveSessions(providerID: ProviderID?) async throws -> [ProviderLiveSessionRecord] { [] }
    func upsertProviderLiveSession(_ session: ProviderLiveSessionRecord) async throws {}
    func deleteProviderLiveSession(id: String) async throws {}
}

public extension ProviderStructuredOutputRepository {
    func listProviderStructuredOutputs(responseID: String?) async throws -> [ProviderStructuredOutputRecord] { [] }
    func upsertProviderStructuredOutput(_ output: ProviderStructuredOutputRecord) async throws {}
    func deleteProviderStructuredOutput(id: UUID) async throws {}
}

public extension ProviderModelCapabilityRepository {
    func listProviderModelCapabilities(providerID: ProviderID?) async throws -> [ProviderModelCapabilityRecord] { [] }
    func upsertProviderModelCapability(_ capability: ProviderModelCapabilityRecord) async throws {}
    func deleteProviderModelCapability(providerID: ProviderID, modelID: ModelID) async throws {}
}

public extension ProviderResearchRunRepository {
    func listProviderResearchRuns(providerID: ProviderID?, status: String?) async throws -> [ProviderResearchRunRecord] { [] }
    func upsertProviderResearchRun(_ run: ProviderResearchRunRecord) async throws {}
    func deleteProviderResearchRun(id: String) async throws {}
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

public protocol AppDataResetRepository: Sendable {
    func deleteAllUserRecords() async throws
}
