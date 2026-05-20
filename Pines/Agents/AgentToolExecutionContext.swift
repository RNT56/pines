import Foundation
import PinesCore

struct AgentToolRunContext: Sendable {
    let attachmentsByID: [UUID: ChatAttachment]
    let allowedVaultDocumentIDs: Set<UUID>?
    let allowsConversationSearch: Bool

    init(
        messages: [ChatMessage],
        allowedVaultDocumentIDs: Set<UUID>? = nil,
        allowsConversationSearch: Bool = true
    ) {
        let latestUserAttachments = messages
            .last(where: { $0.role == .user })?
            .attachments ?? []
        attachmentsByID = Dictionary(uniqueKeysWithValues: latestUserAttachments.map { ($0.id, $0) })
        self.allowedVaultDocumentIDs = allowedVaultDocumentIDs
        self.allowsConversationSearch = allowsConversationSearch
    }
}

enum AgentToolExecutionContext {
    @TaskLocal static var current = AgentToolRunContext(messages: [])
}
