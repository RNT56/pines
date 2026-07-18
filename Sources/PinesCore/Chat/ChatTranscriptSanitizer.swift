import Foundation

public enum ChatTranscriptMetadataKeys {
    public static let persistedMessageStatus = "pines.message.status"
    public static let contextOnly = "pines.context.only"
    public static let contextParentMessageID = "pines.context.parent_message_id"
    public static let contextSequence = "pines.context.sequence"
    public static let originalMessageCount = "chat.transcript.original_message_count"
    public static let includedMessageCount = "chat.transcript.included_message_count"
    public static let droppedMessageCount = "chat.transcript.dropped_message_count"
    public static let droppedIncompleteAssistantCount = "chat.transcript.dropped_incomplete_assistant_count"
    public static let droppedIncompleteToolCount = "chat.transcript.dropped_incomplete_tool_count"
    public static let droppedEmptyAssistantCount = "chat.transcript.dropped_empty_assistant_count"
    public static let droppedEmptyToolCount = "chat.transcript.dropped_empty_tool_count"
    public static let droppedOrphanToolCount = "chat.transcript.dropped_orphan_tool_count"
    public static let droppedOrphanContextCount = "chat.transcript.dropped_orphan_context_count"
    public static let repairedAssistantToolCallCount = "chat.transcript.repaired_assistant_tool_call_count"
    public static let interruptedRunRepairReason = "chat.repair.interrupted_run.reason"
    public static let interruptedRunOriginalStatus = "chat.repair.interrupted_run.original_status"
}

public struct ChatTranscriptSanitizingSummary: Hashable, Sendable {
    public var originalMessageCount: Int
    public var includedMessageCount: Int
    public var droppedMessageCount: Int
    public var droppedIncompleteAssistantCount: Int
    public var droppedIncompleteToolCount: Int
    public var droppedEmptyAssistantCount: Int
    public var droppedEmptyToolCount: Int
    public var droppedOrphanToolCount: Int
    public var droppedOrphanContextCount: Int
    public var repairedAssistantToolCallCount: Int

    public init(
        originalMessageCount: Int,
        includedMessageCount: Int,
        droppedMessageCount: Int,
        droppedIncompleteAssistantCount: Int,
        droppedIncompleteToolCount: Int = 0,
        droppedEmptyAssistantCount: Int,
        droppedEmptyToolCount: Int,
        droppedOrphanToolCount: Int = 0,
        droppedOrphanContextCount: Int = 0,
        repairedAssistantToolCallCount: Int = 0
    ) {
        self.originalMessageCount = originalMessageCount
        self.includedMessageCount = includedMessageCount
        self.droppedMessageCount = droppedMessageCount
        self.droppedIncompleteAssistantCount = droppedIncompleteAssistantCount
        self.droppedIncompleteToolCount = droppedIncompleteToolCount
        self.droppedEmptyAssistantCount = droppedEmptyAssistantCount
        self.droppedEmptyToolCount = droppedEmptyToolCount
        self.droppedOrphanToolCount = droppedOrphanToolCount
        self.droppedOrphanContextCount = droppedOrphanContextCount
        self.repairedAssistantToolCallCount = repairedAssistantToolCallCount
    }

    public var providerMetadata: [String: String] {
        [
            ChatTranscriptMetadataKeys.originalMessageCount: String(originalMessageCount),
            ChatTranscriptMetadataKeys.includedMessageCount: String(includedMessageCount),
            ChatTranscriptMetadataKeys.droppedMessageCount: String(droppedMessageCount),
            ChatTranscriptMetadataKeys.droppedIncompleteAssistantCount: String(droppedIncompleteAssistantCount),
            ChatTranscriptMetadataKeys.droppedIncompleteToolCount: String(droppedIncompleteToolCount),
            ChatTranscriptMetadataKeys.droppedEmptyAssistantCount: String(droppedEmptyAssistantCount),
            ChatTranscriptMetadataKeys.droppedEmptyToolCount: String(droppedEmptyToolCount),
            ChatTranscriptMetadataKeys.droppedOrphanToolCount: String(droppedOrphanToolCount),
            ChatTranscriptMetadataKeys.droppedOrphanContextCount: String(droppedOrphanContextCount),
            ChatTranscriptMetadataKeys.repairedAssistantToolCallCount: String(repairedAssistantToolCallCount),
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
        let visibleMessages = messages.filter { !$0.isContextOnly }
        // A malformed imported transcript must be repairable, not capable of
        // trapping the process because two rows reused an ID. The earliest
        // visible row is the durable parent for context-link validation.
        let visibleMessageByID = visibleMessages.reduce(into: [UUID: ChatMessage]()) { result, message in
            if result[message.id] == nil {
                result[message.id] = message
            }
        }
        let linkedContext = Dictionary(grouping: messages.filter(\.isContextOnly)) { message in
            message.contextParentMessageID
        }

        var reordered = [ChatMessage]()
        var emittedContextIDs = Set<UUID>()
        var handledVisibleParentIDs = Set<UUID>()
        for message in visibleMessages {
            // Only the earliest visible row with a reused imported ID may own
            // linked hidden context. A later forged duplicate must not be able
            // to revive context whose canonical parent failed or was cancelled.
            let isCanonicalParent = handledVisibleParentIDs.insert(message.id).inserted
            if isCanonicalParent,
               message.role == .assistant,
               message.persistedMessageStatus == .complete,
               let linked = linkedContext[message.id] {
                for contextMessage in linked.sorted(by: Self.messageOrder) {
                    guard emittedContextIDs.insert(contextMessage.id).inserted else { continue }
                    reordered.append(contextMessage)
                }
            }
            reordered.append(message)
        }

        let orphanContextCount = messages.lazy.filter { message in
            guard message.isContextOnly else { return false }
            guard let parentID = message.contextParentMessageID,
                  let parent = visibleMessageByID[parentID]
            else { return true }
            return parent.role != .assistant
                || parent.persistedMessageStatus != .complete
                || !emittedContextIDs.contains(message.id)
        }.count

        var rowSanitized = [ChatMessage]()
        var droppedIncompleteAssistantCount = 0
        var droppedIncompleteToolCount = 0
        var droppedEmptyAssistantCount = 0
        var droppedEmptyToolCount = 0

        for message in reordered {
            let contentIsEmpty = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let status = message.persistedMessageStatus

            switch message.role {
            case .system, .user:
                // Imported/provider-authored rows can carry protocol fields
                // that are illegal for these roles. Never forward them merely
                // because `ChatMessage` is a common transport model.
                guard !contentIsEmpty || !message.attachments.isEmpty else {
                    continue
                }
                var normalized = message.strippingTranscriptInternalMetadata()
                normalized.toolCalls = []
                normalized.toolCallID = nil
                normalized.toolName = nil
                rowSanitized.append(normalized)
            case .assistant:
                if let status, status != .complete {
                    droppedIncompleteAssistantCount += 1
                    continue
                }
                guard !contentIsEmpty || !message.toolCalls.isEmpty else {
                    droppedEmptyAssistantCount += 1
                    continue
                }
                var normalized = message.strippingTranscriptInternalMetadata()
                normalized.toolCallID = nil
                normalized.toolName = nil
                rowSanitized.append(normalized)
            case .tool:
                if let status, status != .complete {
                    droppedIncompleteToolCount += 1
                    continue
                }
                guard !contentIsEmpty else {
                    droppedEmptyToolCount += 1
                    continue
                }
                var normalized = message.strippingTranscriptInternalMetadata()
                normalized.toolCalls = []
                rowSanitized.append(normalized)
            }
        }

        let protocolResult = repairToolProtocol(in: rowSanitized)
        let sanitized = protocolResult.messages
        let dropped = max(0, messages.count - sanitized.count)
        return ChatTranscriptSanitizingResult(
            messages: sanitized,
            summary: ChatTranscriptSanitizingSummary(
                originalMessageCount: messages.count,
                includedMessageCount: sanitized.count,
                droppedMessageCount: dropped,
                droppedIncompleteAssistantCount: droppedIncompleteAssistantCount,
                droppedIncompleteToolCount: droppedIncompleteToolCount,
                droppedEmptyAssistantCount: droppedEmptyAssistantCount,
                droppedEmptyToolCount: droppedEmptyToolCount,
                droppedOrphanToolCount: protocolResult.droppedOrphanToolCount,
                droppedOrphanContextCount: orphanContextCount,
                repairedAssistantToolCallCount: protocolResult.repairedAssistantToolCallCount
            )
        )
    }

    private static func messageOrder(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        if let lhsSequence = lhs.providerMetadata[ChatTranscriptMetadataKeys.contextSequence].flatMap(Int.init),
           let rhsSequence = rhs.providerMetadata[ChatTranscriptMetadataKeys.contextSequence].flatMap(Int.init),
           lhsSequence != rhsSequence {
            return lhsSequence < rhsSequence
        }
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    private static func repairToolProtocol(
        in messages: [ChatMessage]
    ) -> (messages: [ChatMessage], droppedOrphanToolCount: Int, repairedAssistantToolCallCount: Int) {
        var result = [ChatMessage]()
        var droppedOrphanToolCount = 0
        var repairedAssistantToolCallCount = 0
        var index = 0

        while index < messages.count {
            let message = messages[index]
            guard message.role == .assistant, !message.toolCalls.isEmpty else {
                if message.role == .tool {
                    droppedOrphanToolCount += 1
                } else {
                    result.append(message)
                }
                index += 1
                continue
            }

            var followingTools = [ChatMessage]()
            var nextIndex = index + 1
            while nextIndex < messages.count, messages[nextIndex].role == .tool {
                followingTools.append(messages[nextIndex])
                nextIndex += 1
            }

            let callsAreStructurallyValid = message.toolCalls.allSatisfy { call in
                call.isComplete
                    && !call.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !call.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && isValidJSON(call.argumentsFragment)
            }
            let callsByID = Dictionary(
                message.toolCalls.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let expectedIDs = Set(callsByID.keys)
            var seenIDs = Set<String>()
            let matchingTools = followingTools.compactMap { toolMessage -> ChatMessage? in
                guard let toolCallID = toolMessage.toolCallID,
                      let expectedCall = callsByID[toolCallID],
                      !toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      toolMessage.toolName.map({ $0 == expectedCall.name }) ?? true,
                      seenIDs.insert(toolCallID).inserted
                else { return nil }
                var normalized = toolMessage
                normalized.toolName = expectedCall.name
                return normalized
            }
            let hasCompletePairing = callsAreStructurallyValid
                && !expectedIDs.isEmpty
                && expectedIDs.count == message.toolCalls.count
                && seenIDs == expectedIDs

            if hasCompletePairing {
                result.append(message)
                result.append(contentsOf: matchingTools)
                droppedOrphanToolCount += followingTools.count - matchingTools.count
            } else {
                var repaired = message
                repaired.toolCalls = []
                if !repaired.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(repaired)
                }
                repairedAssistantToolCallCount += 1
                droppedOrphanToolCount += followingTools.count
            }
            index = nextIndex
        }

        return (result, droppedOrphanToolCount, repairedAssistantToolCallCount)
    }

    private static func isValidJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8), !data.isEmpty else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return object is [String: Any]
    }
}

public extension ChatMessage {
    var isContextOnly: Bool {
        providerMetadata[ChatTranscriptMetadataKeys.contextOnly] == "true"
    }

    var contextParentMessageID: UUID? {
        providerMetadata[ChatTranscriptMetadataKeys.contextParentMessageID].flatMap(UUID.init(uuidString:))
    }

    func asContextOnly(parentMessageID: UUID) -> ChatMessage {
        var message = self
        message.providerMetadata[ChatTranscriptMetadataKeys.contextOnly] = "true"
        message.providerMetadata[ChatTranscriptMetadataKeys.contextParentMessageID] = parentMessageID.uuidString
        return message
    }

    var persistedMessageStatus: MessageStatus? {
        providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus].flatMap(MessageStatus.init(rawValue:))
    }

    func withPersistedMessageStatus(_ status: MessageStatus) -> ChatMessage {
        var message = self
        message.providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus] = status.rawValue
        return message
    }

    func strippingTranscriptInternalMetadata() -> ChatMessage {
        var message = self
        message.providerMetadata.removeValue(forKey: ChatTranscriptMetadataKeys.persistedMessageStatus)
        message.providerMetadata.removeValue(forKey: ChatTranscriptMetadataKeys.contextOnly)
        message.providerMetadata.removeValue(forKey: ChatTranscriptMetadataKeys.contextParentMessageID)
        message.providerMetadata.removeValue(forKey: ChatTranscriptMetadataKeys.contextSequence)
        return message
    }
}
