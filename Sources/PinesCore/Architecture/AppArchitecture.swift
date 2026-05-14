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
            ownsTables: ["audit_events"],
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
    func messages(in conversationID: UUID) async throws -> [ChatMessage]
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

public protocol ModelInstallRepository: Sendable {
    func listInstalledAndCuratedModels() async throws -> [ModelInstall]
    func updateInstallState(_ state: ModelInstallState, for repository: String) async throws
}

public protocol VaultRepository: Sendable {
    func listDocuments() async throws -> [VaultDocumentRecord]
    func chunks(documentID: UUID) async throws -> [VaultChunk]
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
