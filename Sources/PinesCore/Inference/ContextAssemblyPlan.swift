import Foundation

public struct ContextAssemblyPlan: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var strategy: String
    public var pinnedPromptTokens: Int
    public var includedRecentMessageCount: Int
    public var clippedMessageCount: Int
    public var droppedMessageCount: Int
    public var exactInputTokens: Int
    public var reservedCompletionTokens: Int
    public var truncationReason: String?
    public var createdAt: Date

    public init(
        schemaVersion: Int = Self.schemaVersion,
        id: String = UUID().uuidString,
        strategy: String,
        pinnedPromptTokens: Int = 0,
        includedRecentMessageCount: Int,
        clippedMessageCount: Int = 0,
        droppedMessageCount: Int = 0,
        exactInputTokens: Int,
        reservedCompletionTokens: Int,
        truncationReason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.strategy = strategy
        self.pinnedPromptTokens = max(0, pinnedPromptTokens)
        self.includedRecentMessageCount = max(0, includedRecentMessageCount)
        self.clippedMessageCount = max(0, clippedMessageCount)
        self.droppedMessageCount = max(0, droppedMessageCount)
        self.exactInputTokens = max(0, exactInputTokens)
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
        self.truncationReason = truncationReason
        self.createdAt = createdAt
    }
}
