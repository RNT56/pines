import Foundation

public enum WatchChatProtocolVersion {
    public static let current = 1
}

public enum WatchChatMessageKind: String, Codable, Sendable {
    case phoneStatus
    case listConversations
    case loadConversation
    case createConversation
    case renameConversation
    case archiveConversation
    case deleteConversation
    case sendMessage
    case cancelRun
    case snapshot
    case runUpdate
    case error
}

public enum WatchChatRole: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public enum WatchChatRunStatus: String, Codable, Sendable, CaseIterable {
    case accepted
    case streaming
    case completed
    case failed
    case cancelled
}

public struct WatchChatEnvelope: Codable, Sendable {
    public var version: Int
    public var kind: WatchChatMessageKind
    public var requestID: UUID
    public var sequence: Int?
    public var sentAt: Date
    public var payload: Data?

    public init(
        version: Int = WatchChatProtocolVersion.current,
        kind: WatchChatMessageKind,
        requestID: UUID = UUID(),
        sequence: Int? = nil,
        sentAt: Date = Date(),
        payload: Data? = nil
    ) {
        self.version = version
        self.kind = kind
        self.requestID = requestID
        self.sequence = sequence
        self.sentAt = sentAt
        self.payload = payload
    }
}

public enum WatchChatCodec {
    public static let envelopeKey = "pines.watch.envelope"

    public static func message<Payload: Encodable>(
        kind: WatchChatMessageKind,
        requestID: UUID = UUID(),
        sequence: Int? = nil,
        payload: Payload
    ) throws -> [String: Any] {
        let payloadData = try JSONEncoder.watchChat.encode(payload)
        return try message(kind: kind, requestID: requestID, sequence: sequence, payloadData: payloadData)
    }

    public static func message(
        kind: WatchChatMessageKind,
        requestID: UUID = UUID(),
        sequence: Int? = nil
    ) throws -> [String: Any] {
        try message(kind: kind, requestID: requestID, sequence: sequence, payloadData: nil)
    }

    public static func message(
        kind: WatchChatMessageKind,
        requestID: UUID,
        sequence: Int?,
        payloadData: Data?
    ) throws -> [String: Any] {
        let envelope = WatchChatEnvelope(
            kind: kind,
            requestID: requestID,
            sequence: sequence,
            payload: payloadData
        )
        return [envelopeKey: try JSONEncoder.watchChat.encode(envelope)]
    }

    public static func envelope(from message: [String: Any]) throws -> WatchChatEnvelope {
        try envelope(from: envelopeData(from: message))
    }

    public static func envelopeData(from message: [String: Any]) throws -> Data {
        guard let data = message[envelopeKey] as? Data else {
            throw WatchChatProtocolError.missingEnvelope
        }
        return data
    }

    public static func envelope(from data: Data) throws -> WatchChatEnvelope {
        let envelope = try JSONDecoder.watchChat.decode(WatchChatEnvelope.self, from: data)
        guard envelope.version == WatchChatProtocolVersion.current else {
            throw WatchChatProtocolError.unsupportedVersion(envelope.version)
        }
        return envelope
    }

    public static func decode<Payload: Decodable>(_ type: Payload.Type, from envelope: WatchChatEnvelope) throws -> Payload {
        guard let payload = envelope.payload else {
            throw WatchChatProtocolError.missingPayload
        }
        return try JSONDecoder.watchChat.decode(type, from: payload)
    }
}

public enum WatchChatProtocolError: LocalizedError, Sendable {
    case missingEnvelope
    case missingPayload
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .missingEnvelope:
            "The watch message did not contain a Pines envelope."
        case .missingPayload:
            "The watch message did not contain the expected payload."
        case let .unsupportedVersion(version):
            "Unsupported watch protocol version \(version)."
        }
    }
}

public struct WatchPhoneStatus: Codable, Hashable, Sendable {
    public var reachable: Bool
    public var runtimeReady: Bool
    public var paired: Bool
    public var watchAppInstalled: Bool
    public var summary: String

    public init(
        reachable: Bool,
        runtimeReady: Bool,
        paired: Bool = true,
        watchAppInstalled: Bool = true,
        summary: String
    ) {
        self.reachable = reachable
        self.runtimeReady = runtimeReady
        self.paired = paired
        self.watchAppInstalled = watchAppInstalled
        self.summary = summary
    }
}

public struct WatchConversationSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var lastMessage: String
    public var updatedAt: Date
    public var modelName: String
    public var archived: Bool

    public init(
        id: UUID,
        title: String,
        lastMessage: String,
        updatedAt: Date,
        modelName: String,
        archived: Bool
    ) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
        self.modelName = modelName
        self.archived = archived
    }
}

public struct WatchChatMessage: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var role: WatchChatRole
    public var content: String
    public var createdAt: Date
    public var isStreaming: Bool

    public init(
        id: UUID,
        role: WatchChatRole,
        content: String,
        createdAt: Date,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}

public struct WatchChatSnapshot: Codable, Hashable, Sendable {
    public var conversations: [WatchConversationSummary]
    public var selectedConversationID: UUID?
    public var messages: [WatchChatMessage]
    public var activeRunID: UUID?
    public var status: WatchPhoneStatus

    public init(
        conversations: [WatchConversationSummary],
        selectedConversationID: UUID?,
        messages: [WatchChatMessage],
        activeRunID: UUID?,
        status: WatchPhoneStatus
    ) {
        self.conversations = conversations
        self.selectedConversationID = selectedConversationID
        self.messages = messages
        self.activeRunID = activeRunID
        self.status = status
    }
}

public struct WatchLoadConversationRequest: Codable, Hashable, Sendable {
    public var conversationID: UUID

    public init(conversationID: UUID) {
        self.conversationID = conversationID
    }
}

public struct WatchRenameConversationRequest: Codable, Hashable, Sendable {
    public var conversationID: UUID
    public var title: String

    public init(conversationID: UUID, title: String) {
        self.conversationID = conversationID
        self.title = title
    }
}

public struct WatchArchiveConversationRequest: Codable, Hashable, Sendable {
    public var conversationID: UUID
    public var archived: Bool

    public init(conversationID: UUID, archived: Bool) {
        self.conversationID = conversationID
        self.archived = archived
    }
}

public struct WatchDeleteConversationRequest: Codable, Hashable, Sendable {
    public var conversationID: UUID

    public init(conversationID: UUID) {
        self.conversationID = conversationID
    }
}

public struct WatchSendMessageRequest: Codable, Hashable, Sendable {
    public var conversationID: UUID?
    public var text: String
    public var clientMessageID: UUID

    public init(conversationID: UUID?, text: String, clientMessageID: UUID = UUID()) {
        self.conversationID = conversationID
        self.text = text
        self.clientMessageID = clientMessageID
    }
}

public struct WatchCancelRunRequest: Codable, Hashable, Sendable {
    public var runID: UUID

    public init(runID: UUID) {
        self.runID = runID
    }
}

public struct WatchChatRunUpdate: Codable, Hashable, Sendable {
    public var runID: UUID
    public var conversationID: UUID
    public var assistantMessageID: UUID?
    public var status: WatchChatRunStatus
    public var text: String
    public var tokenCount: Int
    public var errorMessage: String?

    public init(
        runID: UUID,
        conversationID: UUID,
        assistantMessageID: UUID?,
        status: WatchChatRunStatus,
        text: String,
        tokenCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.runID = runID
        self.conversationID = conversationID
        self.assistantMessageID = assistantMessageID
        self.status = status
        self.text = text
        self.tokenCount = tokenCount
        self.errorMessage = errorMessage
    }
}

public struct WatchChatErrorPayload: Codable, Hashable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

private extension JSONEncoder {
    static var watchChat: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var watchChat: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
