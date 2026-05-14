import Foundation

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct ModelID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public enum ChatRole: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public enum AttachmentKind: String, Codable, Sendable, CaseIterable {
    case image
    case document
    case webCapture
    case audio
    case video
}

public struct ChatAttachment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: AttachmentKind
    public var fileName: String
    public var contentType: String
    public var localURL: URL?
    public var byteCount: Int

    public init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        fileName: String,
        contentType: String,
        localURL: URL? = nil,
        byteCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.contentType = contentType
        self.localURL = localURL
        self.byteCount = byteCount
    }
}

public struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var content: String
    public var attachments: [ChatAttachment]
    public var createdAt: Date
    public var toolCallID: String?

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        toolCallID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
        self.toolCallID = toolCallID
    }
}

public struct ProviderCapabilities: Hashable, Codable, Sendable {
    public var local: Bool
    public var streaming: Bool
    public var textGeneration: Bool
    public var vision: Bool
    public var embeddings: Bool
    public var toolCalling: Bool
    public var jsonMode: Bool
    public var maxContextTokens: Int?

    public init(
        local: Bool,
        streaming: Bool = true,
        textGeneration: Bool = true,
        vision: Bool = false,
        embeddings: Bool = false,
        toolCalling: Bool = false,
        jsonMode: Bool = false,
        maxContextTokens: Int? = nil
    ) {
        self.local = local
        self.streaming = streaming
        self.textGeneration = textGeneration
        self.vision = vision
        self.embeddings = embeddings
        self.toolCalling = toolCalling
        self.jsonMode = jsonMode
        self.maxContextTokens = maxContextTokens
    }
}

public struct ChatSampling: Hashable, Codable, Sendable {
    public var maxTokens: Int?
    public var temperature: Float
    public var topP: Float
    public var topK: Int
    public var minP: Float
    public var repetitionPenalty: Float?

    public init(
        maxTokens: Int? = 1024,
        temperature: Float = 0.6,
        topP: Float = 1,
        topK: Int = 0,
        minP: Float = 0,
        repetitionPenalty: Float? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.repetitionPenalty = repetitionPenalty
    }
}

public struct ChatRequest: Hashable, Codable, Sendable {
    public var id: UUID
    public var modelID: ModelID
    public var messages: [ChatMessage]
    public var sampling: ChatSampling
    public var allowsTools: Bool
    public var vaultContextIDs: [UUID]

    public init(
        id: UUID = UUID(),
        modelID: ModelID,
        messages: [ChatMessage],
        sampling: ChatSampling = .init(),
        allowsTools: Bool = false,
        vaultContextIDs: [UUID] = []
    ) {
        self.id = id
        self.modelID = modelID
        self.messages = messages
        self.sampling = sampling
        self.allowsTools = allowsTools
        self.vaultContextIDs = vaultContextIDs
    }
}

public struct TokenDelta: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case token
        case toolCall
        case finish
        case metrics
    }

    public var kind: Kind
    public var text: String
    public var tokenCount: Int
    public var metadata: [String: String]

    public init(
        kind: Kind = .token,
        text: String,
        tokenCount: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.text = text
        self.tokenCount = tokenCount
        self.metadata = metadata
    }
}

public struct EmbeddingRequest: Hashable, Codable, Sendable {
    public var modelID: ModelID
    public var inputs: [String]
    public var normalize: Bool

    public init(modelID: ModelID, inputs: [String], normalize: Bool = true) {
        self.modelID = modelID
        self.inputs = inputs
        self.normalize = normalize
    }
}

public struct EmbeddingResult: Hashable, Codable, Sendable {
    public var modelID: ModelID
    public var vectors: [[Float]]
    public var dimensions: Int

    public init(modelID: ModelID, vectors: [[Float]]) {
        self.modelID = modelID
        self.vectors = vectors
        self.dimensions = vectors.first?.count ?? 0
    }
}

public enum InferenceError: Error, Equatable, Sendable {
    case providerUnavailable(ProviderID)
    case modelNotLoaded(ModelID)
    case unsupportedCapability(String)
    case cloudNotAllowed
    case invalidRequest(String)
    case cancelled
}

public protocol InferenceProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }

    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<TokenDelta, Error>
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult
}
