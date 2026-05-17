import Foundation

public struct VaultChunkEmbedding: Hashable, Codable, Sendable {
    public var chunkID: String
    public var documentID: UUID
    public var modelID: ModelID
    public var vector: [Float]

    public init(chunkID: String, documentID: UUID, modelID: ModelID, vector: [Float]) {
        self.chunkID = chunkID
        self.documentID = documentID
        self.modelID = modelID
        self.vector = vector
    }
}

public struct VaultEmbeddingBatch: Hashable, Codable, Sendable {
    public var modelID: ModelID
    public var embeddings: [VaultChunkEmbedding]

    public init(modelID: ModelID, embeddings: [VaultChunkEmbedding]) {
        self.modelID = modelID
        self.embeddings = embeddings
    }
}

public struct VaultStoredEmbedding: Hashable, Codable, Sendable {
    public var chunkID: String
    public var documentID: UUID
    public var modelID: ModelID
    public var profileID: String?
    public var providerID: ProviderID?
    public var providerKind: VaultEmbeddingProfileKind?
    public var normalized: Bool
    public var sourceChecksum: String?
    public var dimensions: Int
    public var fp16Embedding: Data
    public var turboQuantCode: Data
    public var norm: Double
    public var codecVersion: Int
    public var checksum: String
    public var createdAt: Date

    public init(
        chunkID: String,
        documentID: UUID,
        modelID: ModelID,
        profileID: String? = nil,
        providerID: ProviderID? = nil,
        providerKind: VaultEmbeddingProfileKind? = nil,
        normalized: Bool = true,
        sourceChecksum: String? = nil,
        dimensions: Int,
        fp16Embedding: Data,
        turboQuantCode: Data,
        norm: Double,
        codecVersion: Int,
        checksum: String,
        createdAt: Date
    ) {
        self.chunkID = chunkID
        self.documentID = documentID
        self.modelID = modelID
        self.profileID = profileID
        self.providerID = providerID
        self.providerKind = providerKind
        self.normalized = normalized
        self.sourceChecksum = sourceChecksum
        self.dimensions = dimensions
        self.fp16Embedding = fp16Embedding
        self.turboQuantCode = turboQuantCode
        self.norm = norm
        self.codecVersion = codecVersion
        self.checksum = checksum
        self.createdAt = createdAt
    }
}
