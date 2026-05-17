import Foundation

public enum VaultEmbeddingProfileKind: String, Hashable, Codable, Sendable, CaseIterable {
    case localMLX
    case openAI
    case openAICompatible
    case gemini
    case openRouter
    case voyageAI
    case custom

    public var isCloud: Bool {
        self != .localMLX
    }

    public var supportsProviderBackedEmbeddings: Bool {
        switch self {
        case .localMLX, .openAI, .openAICompatible, .gemini, .openRouter, .voyageAI, .custom:
            true
        }
    }

    public init?(cloudProviderKind: CloudProviderKind) {
        switch cloudProviderKind {
        case .openAI:
            self = .openAI
        case .openAICompatible:
            self = .openAICompatible
        case .gemini:
            self = .gemini
        case .openRouter:
            self = .openRouter
        case .voyageAI:
            self = .voyageAI
        case .custom:
            self = .custom
        case .anthropic:
            return nil
        }
    }
}

public enum VaultEmbeddingProfileStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case available
    case needsConsent
    case indexing
    case ready
    case failed
}

public enum VaultEmbeddingJobStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case queued
    case running
    case complete
    case failed
    case cancelled
}

public struct VaultEmbeddingProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var kind: VaultEmbeddingProfileKind
    public var providerID: ProviderID?
    public var displayName: String
    public var modelID: ModelID
    public var dimensions: Int
    public var documentTask: String?
    public var queryTask: String?
    public var normalized: Bool
    public var cloudConsentGranted: Bool
    public var isActive: Bool
    public var status: VaultEmbeddingProfileStatus
    public var lastError: String?
    public var embeddedChunkCount: Int
    public var totalChunkCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        kind: VaultEmbeddingProfileKind,
        providerID: ProviderID? = nil,
        displayName: String,
        modelID: ModelID,
        dimensions: Int,
        documentTask: String? = nil,
        queryTask: String? = nil,
        normalized: Bool = true,
        cloudConsentGranted: Bool = false,
        isActive: Bool = false,
        status: VaultEmbeddingProfileStatus = .available,
        lastError: String? = nil,
        embeddedChunkCount: Int = 0,
        totalChunkCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.providerID = providerID
        self.displayName = displayName
        self.modelID = modelID
        self.dimensions = dimensions
        self.documentTask = documentTask
        self.queryTask = queryTask
        self.normalized = normalized
        self.cloudConsentGranted = cloudConsentGranted
        self.isActive = isActive
        self.status = status
        self.lastError = lastError
        self.embeddedChunkCount = embeddedChunkCount
        self.totalChunkCount = totalChunkCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var canUseWithoutPrompt: Bool {
        !kind.isCloud || cloudConsentGranted
    }

    public static func local(modelID: ModelID, displayName: String, isActive: Bool = false) -> VaultEmbeddingProfile {
        VaultEmbeddingProfile(
            id: stableID(kind: .localMLX, providerID: nil, modelID: modelID, dimensions: 0),
            kind: .localMLX,
            providerID: ProviderID(rawValue: "mlx-local"),
            displayName: displayName,
            modelID: modelID,
            dimensions: 0,
            cloudConsentGranted: true,
            isActive: isActive
        )
    }

    public static func cloud(
        provider: CloudProviderConfiguration,
        modelID: ModelID? = nil,
        dimensions: Int? = nil,
        isActive: Bool = false,
        consentGranted: Bool = false
    ) -> VaultEmbeddingProfile? {
        guard let kind = VaultEmbeddingProfileKind(cloudProviderKind: provider.kind) else {
            return nil
        }
        let defaults = VaultEmbeddingDefaults.defaults(for: provider.kind)
        let resolvedModelID = modelID ?? defaults.modelID
        let resolvedDimensions = dimensions ?? defaults.dimensions
        return VaultEmbeddingProfile(
            id: stableID(kind: kind, providerID: provider.id, modelID: resolvedModelID, dimensions: resolvedDimensions),
            kind: kind,
            providerID: provider.id,
            displayName: "\(provider.displayName) Embeddings",
            modelID: resolvedModelID,
            dimensions: resolvedDimensions,
            documentTask: defaults.documentTask,
            queryTask: defaults.queryTask,
            normalized: true,
            cloudConsentGranted: consentGranted,
            isActive: isActive,
            status: consentGranted ? .available : .needsConsent
        )
    }

    public static func stableID(
        kind: VaultEmbeddingProfileKind,
        providerID: ProviderID?,
        modelID: ModelID,
        dimensions: Int
    ) -> String {
        [
            kind.rawValue,
            providerID?.rawValue ?? "local",
            modelID.rawValue,
            dimensions > 0 ? "\(dimensions)" : "native",
        ]
        .joined(separator: "::")
    }
}

public enum VaultEmbeddingDefaults {
    public struct ProviderDefaults: Hashable, Codable, Sendable {
        public var modelID: ModelID
        public var dimensions: Int
        public var documentTask: String?
        public var queryTask: String?

        public init(modelID: ModelID, dimensions: Int, documentTask: String? = nil, queryTask: String? = nil) {
            self.modelID = modelID
            self.dimensions = dimensions
            self.documentTask = documentTask
            self.queryTask = queryTask
        }
    }

    public static func defaults(for kind: CloudProviderKind) -> ProviderDefaults {
        switch kind {
        case .openAI, .openAICompatible, .custom:
            ProviderDefaults(modelID: "text-embedding-3-small", dimensions: 1536)
        case .gemini:
            ProviderDefaults(
                modelID: "gemini-embedding-2",
                dimensions: 768,
                documentTask: "title: none | text: {content}",
                queryTask: "task: search result | query: {content}"
            )
        case .openRouter:
            ProviderDefaults(
                modelID: "openai/text-embedding-3-small",
                dimensions: 1536,
                documentTask: "search_document",
                queryTask: "search_query"
            )
        case .voyageAI:
            ProviderDefaults(
                modelID: "voyage-4-lite",
                dimensions: 1024,
                documentTask: "document",
                queryTask: "query"
            )
        case .anthropic:
            ProviderDefaults(modelID: "", dimensions: 0)
        }
    }
}

public struct VaultEmbeddingJob: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var profileID: String
    public var documentID: UUID?
    public var status: VaultEmbeddingJobStatus
    public var processedChunks: Int
    public var totalChunks: Int
    public var attemptCount: Int
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        profileID: String,
        documentID: UUID? = nil,
        status: VaultEmbeddingJobStatus = .queued,
        processedChunks: Int = 0,
        totalChunks: Int = 0,
        attemptCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.documentID = documentID
        self.status = status
        self.processedChunks = processedChunks
        self.totalChunks = totalChunks
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VaultRetrievalEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var profileID: String?
    public var providerID: ProviderID?
    public var queryHash: String
    public var usedVectorSearch: Bool
    public var resultCount: Int
    public var elapsedSeconds: Double
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        profileID: String? = nil,
        providerID: ProviderID? = nil,
        queryHash: String,
        usedVectorSearch: Bool,
        resultCount: Int,
        elapsedSeconds: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.providerID = providerID
        self.queryHash = queryHash
        self.usedVectorSearch = usedVectorSearch
        self.resultCount = resultCount
        self.elapsedSeconds = elapsedSeconds
        self.createdAt = createdAt
    }
}
