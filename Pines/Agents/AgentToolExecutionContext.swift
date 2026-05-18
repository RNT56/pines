import Foundation
import PinesCore

struct AgentToolRunContext: Sendable {
    let attachmentsByID: [UUID: ChatAttachment]

    init(messages: [ChatMessage]) {
        let latestUserAttachments = messages
            .last(where: { $0.role == .user })?
            .attachments ?? []
        attachmentsByID = Dictionary(uniqueKeysWithValues: latestUserAttachments.map { ($0.id, $0) })
    }
}

enum AgentToolExecutionContext {
    @TaskLocal static var current = AgentToolRunContext(messages: [])
}
