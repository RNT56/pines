import Foundation

public enum ChatTranscriptMetadataKeys {
    public static let persistedMessageStatus = "pines.message.status"
    public static let originalMessageCount = "chat.transcript.original_message_count"
    public static let includedMessageCount = "chat.transcript.included_message_count"
    public static let droppedMessageCount = "chat.transcript.dropped_message_count"
    public static let droppedIncompleteAssistantCount = "chat.transcript.dropped_incomplete_assistant_count"
    public static let droppedEmptyAssistantCount = "chat.transcript.dropped_empty_assistant_count"
    public static let droppedEmptyToolCount = "chat.transcript.dropped_empty_tool_count"
    public static let interruptedRunRepairReason = "chat.repair.interrupted_run.reason"
    public static let interruptedRunOriginalStatus = "chat.repair.interrupted_run.original_status"
}

public struct ChatTranscriptSanitizingSummary: Hashable, Sendable {
    public var originalMessageCount: Int
    public var includedMessageCount: Int
    public var droppedMessageCount: Int
    public var droppedIncompleteAssistantCount: Int
    public var droppedEmptyAssistantCount: Int
    public var droppedEmptyToolCount: Int

    public init(
        originalMessageCount: Int,
        includedMessageCount: Int,
        droppedMessageCount: Int,
        droppedIncompleteAssistantCount: Int,
        droppedEmptyAssistantCount: Int,
        droppedEmptyToolCount: Int
    ) {
        self.originalMessageCount = originalMessageCount
        self.includedMessageCount = includedMessageCount
        self.droppedMessageCount = droppedMessageCount
        self.droppedIncompleteAssistantCount = droppedIncompleteAssistantCount
        self.droppedEmptyAssistantCount = droppedEmptyAssistantCount
        self.droppedEmptyToolCount = droppedEmptyToolCount
    }

    public var providerMetadata: [String: String] {
        [
            ChatTranscriptMetadataKeys.originalMessageCount: String(originalMessageCount),
            ChatTranscriptMetadataKeys.includedMessageCount: String(includedMessageCount),
            ChatTranscriptMetadataKeys.droppedMessageCount: String(droppedMessageCount),
            ChatTranscriptMetadataKeys.droppedIncompleteAssistantCount: String(droppedIncompleteAssistantCount),
            ChatTranscriptMetadataKeys.droppedEmptyAssistantCount: String(droppedEmptyAssistantCount),
            ChatTranscriptMetadataKeys.droppedEmptyToolCount: String(droppedEmptyToolCount),
        ]
    }
}

public struct ChatTranscriptSanitizingResult: Hashable, Sendable {
    public var messages: [ChatMessage]
    public var summary: ChatTranscriptSanitizingSummary

    public init(messages: [ChatMessage], summary: ChatTranscriptSanitizingSummary) {
        self.messages = messages
        self.summary = summary
    }
}

public enum ChatTranscriptSanitizer {
    public static func messagesForProviderRequest(
        _ messages: [ChatMessage],
        requiredUserMessageIDs: Set<UUID> = []
    ) -> ChatTranscriptSanitizingResult {
        var sanitized = [ChatMessage]()
        var droppedIncompleteAssistantCount = 0
        var droppedEmptyAssistantCount = 0
        var droppedEmptyToolCount = 0

        for message in messages {
            let contentIsEmpty = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let status = message.persistedMessageStatus

            switch message.role {
            case .system, .user:
                if message.role == .user,
                   requiredUserMessageIDs.contains(message.id),
                   contentIsEmpty,
                   message.attachments.isEmpty {
                    continue
                }
                sanitized.append(message.strippingTranscriptInternalMetadata())
            case .assistant:
                if let status, status != .complete {
                    droppedIncompleteAssistantCount += 1
                    continue
                }
                guard !contentIsEmpty || !message.toolCalls.isEmpty else {
                    droppedEmptyAssistantCount += 1
                    continue
                }
                sanitized.append(message.strippingTranscriptInternalMetadata())
            case .tool:
                if let status, status != .complete {
                    droppedIncompleteAssistantCount += 1
                    continue
                }
                guard !contentIsEmpty else {
                    droppedEmptyToolCount += 1
                    continue
                }
                sanitized.append(message.strippingTranscriptInternalMetadata())
            }
        }

        let dropped = messages.count - sanitized.count
        return ChatTranscriptSanitizingResult(
            messages: sanitized,
            summary: ChatTranscriptSanitizingSummary(
                originalMessageCount: messages.count,
                includedMessageCount: sanitized.count,
                droppedMessageCount: dropped,
                droppedIncompleteAssistantCount: droppedIncompleteAssistantCount,
                droppedEmptyAssistantCount: droppedEmptyAssistantCount,
                droppedEmptyToolCount: droppedEmptyToolCount
            )
        )
    }
}

public extension ChatMessage {
    var persistedMessageStatus: MessageStatus? {
        providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus].flatMap(MessageStatus.init(rawValue:))
    }

    func withPersistedMessageStatus(_ status: MessageStatus) -> ChatMessage {
        var message = self
        message.providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus] = status.rawValue
        return message
    }

    func strippingTranscriptInternalMetadata() -> ChatMessage {
        guard providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus] != nil else {
            return self
        }
        var message = self
        message.providerMetadata.removeValue(forKey: ChatTranscriptMetadataKeys.persistedMessageStatus)
        return message
    }
}
