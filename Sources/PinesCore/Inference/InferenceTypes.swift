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
    public var toolName: String?
    public var toolCalls: [ToolCallDelta]

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolCalls: [ToolCallDelta] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
        case createdAt
        case toolCallID
        case toolName
        case toolCalls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolCalls = try container.decodeIfPresent([ToolCallDelta].self, forKey: .toolCalls) ?? []
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
    public var availableTools: [AnyToolSpec]
    public var vaultContextIDs: [UUID]

    public init(
        id: UUID = UUID(),
        modelID: ModelID,
        messages: [ChatMessage],
        sampling: ChatSampling = .init(),
        allowsTools: Bool = false,
        availableTools: [AnyToolSpec] = [],
        vaultContextIDs: [UUID] = []
    ) {
        self.id = id
        self.modelID = modelID
        self.messages = messages
        self.sampling = sampling
        self.allowsTools = allowsTools
        self.availableTools = availableTools
        self.vaultContextIDs = vaultContextIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case modelID
        case messages
        case sampling
        case allowsTools
        case availableTools
        case vaultContextIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        modelID = try container.decode(ModelID.self, forKey: .modelID)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        sampling = try container.decodeIfPresent(ChatSampling.self, forKey: .sampling) ?? .init()
        allowsTools = try container.decodeIfPresent(Bool.self, forKey: .allowsTools) ?? false
        availableTools = try container.decodeIfPresent([AnyToolSpec].self, forKey: .availableTools) ?? []
        vaultContextIDs = try container.decodeIfPresent([UUID].self, forKey: .vaultContextIDs) ?? []
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

public struct ToolCallDelta: Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var argumentsFragment: String
    public var isComplete: Bool

    public init(
        id: String,
        name: String,
        argumentsFragment: String = "",
        isComplete: Bool = false
    ) {
        self.id = id
        self.name = name
        self.argumentsFragment = argumentsFragment
        self.isComplete = isComplete
    }
}

public enum InferenceFinishReason: String, Hashable, Codable, Sendable {
    case stop
    case length
    case cancelled
    case toolCall
    case error
}

public struct InferenceFinish: Hashable, Codable, Sendable {
    public var reason: InferenceFinishReason
    public var message: String?

    public init(reason: InferenceFinishReason, message: String? = nil) {
        self.reason = reason
        self.message = message
    }
}

public struct InferenceMetrics: Hashable, Codable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var promptTokensPerSecond: Double?
    public var completionTokensPerSecond: Double?
    public var latencyMilliseconds: Int?

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        promptTokensPerSecond: Double? = nil,
        completionTokensPerSecond: Double? = nil,
        latencyMilliseconds: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.promptTokensPerSecond = promptTokensPerSecond
        self.completionTokensPerSecond = completionTokensPerSecond
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public struct InferenceStreamFailure: Hashable, Codable, Sendable {
    public var code: String
    public var message: String
    public var recoverable: Bool

    public init(code: String, message: String, recoverable: Bool = false) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
    }
}

public enum InferenceStreamEvent: Hashable, Codable, Sendable {
    case token(TokenDelta)
    case toolCall(ToolCallDelta)
    case finish(InferenceFinish)
    case metrics(InferenceMetrics)
    case failure(InferenceStreamFailure)
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

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<TokenDelta, Error>
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult
}

public extension InferenceProvider {
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<TokenDelta, Error> {
        let eventStream = try await streamEvents(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in eventStream {
                        switch event {
                        case let .token(delta):
                            continuation.yield(delta)
                        case let .toolCall(delta):
                            continuation.yield(
                                TokenDelta(
                                    kind: .toolCall,
                                    text: delta.argumentsFragment,
                                    tokenCount: 0,
                                    metadata: [
                                        "id": delta.id,
                                        "name": delta.name,
                                        "complete": String(delta.isComplete),
                                    ]
                                )
                            )
                        case let .finish(finish):
                            continuation.yield(
                                TokenDelta(
                                    kind: .finish,
                                    text: finish.message ?? "",
                                    metadata: ["reason": finish.reason.rawValue]
                                )
                            )
                            continuation.finish()
                            return
                        case let .metrics(metrics):
                            continuation.yield(
                                TokenDelta(
                                    kind: .metrics,
                                    text: "",
                                    tokenCount: metrics.completionTokens,
                                    metadata: [
                                        "promptTokens": String(metrics.promptTokens),
                                        "completionTokens": String(metrics.completionTokens),
                                    ]
                                )
                            )
                        case let .failure(failure):
                            continuation.yield(
                                TokenDelta(
                                    kind: .finish,
                                    text: failure.message,
                                    metadata: [
                                        "reason": InferenceFinishReason.error.rawValue,
                                        "code": failure.code,
                                        "recoverable": String(failure.recoverable),
                                    ]
                                )
                            )
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
