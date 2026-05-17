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

public enum LocalProviderMetadataKeys {
    public static let turboQuantRequestedBackend = "local.turboquant.requested_backend"
    public static let turboQuantActiveBackend = "local.turboquant.active_backend"
    public static let turboQuantAttentionPath = "local.turboquant.attention_path"
    public static let turboQuantKernelProfile = "local.turboquant.kernel_profile"
    public static let turboQuantSelfTestStatus = "local.turboquant.self_test_status"
    public static let turboQuantFallbackReason = "local.turboquant.fallback_reason"
    public static let turboQuantLastUnsupportedShape = "local.turboquant.last_unsupported_shape"
    public static let turboQuantRawFallbackAllocated = "local.turboquant.raw_fallback_allocated"
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
    public var providerMetadata: [String: String]

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolCalls: [ToolCallDelta] = [],
        providerMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolCalls = toolCalls
        self.providerMetadata = providerMetadata
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
        case providerMetadata
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
        providerMetadata = try container.decodeIfPresent([String: String].self, forKey: .providerMetadata) ?? [:]
    }
}

public struct ProviderCapabilities: Hashable, Codable, Sendable {
    public var local: Bool
    public var streaming: Bool
    public var textGeneration: Bool
    public var vision: Bool
    public var imageInputs: Bool
    public var pdfInputs: Bool
    public var textDocumentInputs: Bool
    public var embeddings: Bool
    public var toolCalling: Bool
    public var jsonMode: Bool
    public var maxContextTokens: Int?

    public init(
        local: Bool,
        streaming: Bool = true,
        textGeneration: Bool = true,
        vision: Bool = false,
        imageInputs: Bool = false,
        pdfInputs: Bool = false,
        textDocumentInputs: Bool = false,
        embeddings: Bool = false,
        toolCalling: Bool = false,
        jsonMode: Bool = false,
        maxContextTokens: Int? = nil
    ) {
        self.local = local
        self.streaming = streaming
        self.textGeneration = textGeneration
        self.vision = vision
        self.imageInputs = imageInputs
        self.pdfInputs = pdfInputs
        self.textDocumentInputs = textDocumentInputs
        self.embeddings = embeddings
        self.toolCalling = toolCalling
        self.jsonMode = jsonMode
        self.maxContextTokens = maxContextTokens
    }

    enum CodingKeys: String, CodingKey {
        case local
        case streaming
        case textGeneration
        case vision
        case imageInputs
        case pdfInputs
        case textDocumentInputs
        case embeddings
        case toolCalling
        case jsonMode
        case maxContextTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        local = try container.decode(Bool.self, forKey: .local)
        streaming = try container.decodeIfPresent(Bool.self, forKey: .streaming) ?? true
        textGeneration = try container.decodeIfPresent(Bool.self, forKey: .textGeneration) ?? true
        vision = try container.decodeIfPresent(Bool.self, forKey: .vision) ?? false
        imageInputs = try container.decodeIfPresent(Bool.self, forKey: .imageInputs) ?? false
        pdfInputs = try container.decodeIfPresent(Bool.self, forKey: .pdfInputs) ?? false
        textDocumentInputs = try container.decodeIfPresent(Bool.self, forKey: .textDocumentInputs) ?? false
        embeddings = try container.decodeIfPresent(Bool.self, forKey: .embeddings) ?? false
        toolCalling = try container.decodeIfPresent(Bool.self, forKey: .toolCalling) ?? false
        jsonMode = try container.decodeIfPresent(Bool.self, forKey: .jsonMode) ?? false
        maxContextTokens = try container.decodeIfPresent(Int.self, forKey: .maxContextTokens)
    }
}

public struct ProviderInputRequirements: Hashable, Codable, Sendable {
    public var requiresImages: Bool
    public var requiresPDFs: Bool
    public var requiresTextDocuments: Bool

    public init(
        requiresImages: Bool = false,
        requiresPDFs: Bool = false,
        requiresTextDocuments: Bool = false
    ) {
        self.requiresImages = requiresImages
        self.requiresPDFs = requiresPDFs
        self.requiresTextDocuments = requiresTextDocuments
    }

    public init(messages: [ChatMessage]) {
        self.init()
        for attachment in messages.flatMap(\.attachments) {
            switch attachment.cloudInputKind {
            case .image:
                requiresImages = true
            case .pdf:
                requiresPDFs = true
            case .textDocument:
                requiresTextDocuments = true
            case .unsupported:
                if attachment.kind == .image {
                    requiresImages = true
                } else if attachment.kind == .document {
                    requiresTextDocuments = true
                }
            }
        }
    }

    public var isEmpty: Bool {
        !requiresImages && !requiresPDFs && !requiresTextDocuments
    }

    public func isSatisfied(by capabilities: ProviderCapabilities) -> Bool {
        if requiresImages && !(capabilities.imageInputs || capabilities.vision) { return false }
        if requiresPDFs && !capabilities.pdfInputs { return false }
        if requiresTextDocuments && !capabilities.textDocumentInputs { return false }
        return true
    }
}

public enum CloudAttachmentInputKind: Hashable, Codable, Sendable {
    case image
    case pdf
    case textDocument
    case unsupported
}

public extension ChatAttachment {
    var normalizedContentType: String {
        let rawValue = contentType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !rawValue.isEmpty {
            return rawValue
        }
        let extensionValue = [localURL?.pathExtension, URL(fileURLWithPath: fileName).pathExtension]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty }
        switch extensionValue {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "heics":
            return "image/heic-sequence"
        case "heifs":
            return "image/heif-sequence"
        case "pdf":
            return "application/pdf"
        case "md", "markdown":
            return "text/markdown"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "txt", "text":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }

    var cloudInputKind: CloudAttachmentInputKind {
        switch normalizedContentType {
        case "image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif", "image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence":
            return .image
        case "application/pdf":
            return .pdf
        case "text/plain", "text/markdown", "text/x-markdown", "application/json", "text/csv":
            return .textDocument
        default:
            switch kind {
            case .image:
                return .image
            default:
                return .unsupported
            }
        }
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
    public var providerMetadata: [String: String]

    public init(reason: InferenceFinishReason, message: String? = nil, providerMetadata: [String: String] = [:]) {
        self.reason = reason
        self.message = message
        self.providerMetadata = providerMetadata
    }

    enum CodingKeys: String, CodingKey {
        case reason
        case message
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decode(InferenceFinishReason.self, forKey: .reason)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        providerMetadata = try container.decodeIfPresent([String: String].self, forKey: .providerMetadata) ?? [:]
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
    public var dimensions: Int?
    public var inputType: EmbeddingInputType?

    public init(
        modelID: ModelID,
        inputs: [String],
        normalize: Bool = true,
        dimensions: Int? = nil,
        inputType: EmbeddingInputType? = nil
    ) {
        self.modelID = modelID
        self.inputs = inputs
        self.normalize = normalize
        self.dimensions = dimensions
        self.inputType = inputType
    }
}

public enum EmbeddingInputType: String, Hashable, Codable, Sendable, CaseIterable {
    case document
    case query
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

extension InferenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .providerUnavailable(providerID):
            "Provider \(providerID.rawValue) is unavailable."
        case let .modelNotLoaded(modelID):
            "Model \(modelID.rawValue) is not loaded."
        case let .unsupportedCapability(message):
            message
        case .cloudNotAllowed:
            "Cloud inference is not allowed for this request."
        case let .invalidRequest(message):
            message
        case .cancelled:
            "The inference request was cancelled."
        }
    }
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
                            var metadata = finish.providerMetadata
                            metadata["reason"] = finish.reason.rawValue
                            continuation.yield(
                                TokenDelta(
                                    kind: .finish,
                                    text: finish.message ?? "",
                                    metadata: metadata
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
