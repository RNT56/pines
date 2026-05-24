import Foundation

public struct InterruptedChatMessageRepair: Hashable, Sendable {
    public var messageID: UUID
    public var content: String
    public var status: MessageStatus
    public var providerMetadata: [String: String]
    public var toolName: String?
    public var toolCalls: [ToolCallDelta]

    public init(
        messageID: UUID,
        content: String,
        status: MessageStatus,
        providerMetadata: [String: String],
        toolName: String?,
        toolCalls: [ToolCallDelta]
    ) {
        self.messageID = messageID
        self.content = content
        self.status = status
        self.providerMetadata = providerMetadata
        self.toolName = toolName
        self.toolCalls = toolCalls
    }
}

public enum InterruptedChatRunRepair {
    public static let defaultInterruptedAssistantMessage = "The previous generation was interrupted before it completed."

    public static func repairs(
        for messages: [ChatMessage],
        reason: String
    ) -> [InterruptedChatMessageRepair] {
        messages.compactMap { repair(for: $0, reason: reason) }
    }

    public static func repair(
        for message: ChatMessage,
        reason: String
    ) -> InterruptedChatMessageRepair? {
        guard message.role == .assistant || message.role == .tool else { return nil }
        guard let status = message.persistedMessageStatus,
              status == .pending || status == .streaming
        else { return nil }

        var repaired = message.strippingTranscriptInternalMetadata()
        let trimmed = repaired.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            repaired.content = defaultInterruptedAssistantMessage
        }
        repaired.providerMetadata[ChatTranscriptMetadataKeys.interruptedRunRepairReason] = reason
        repaired.providerMetadata[ChatTranscriptMetadataKeys.interruptedRunOriginalStatus] = status.rawValue

        return InterruptedChatMessageRepair(
            messageID: repaired.id,
            content: repaired.content,
            status: .failed,
            providerMetadata: repaired.providerMetadata,
            toolName: repaired.toolName,
            toolCalls: repaired.toolCalls
        )
    }
}
