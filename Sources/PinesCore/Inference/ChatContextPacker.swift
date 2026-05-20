import Foundation

public enum ChatContextMetadataKeys {
    public static let strategy = "chat.context.strategy"
    public static let estimatedInputTokens = "chat.context.estimated_input_tokens"
    public static let inputBudgetTokens = "chat.context.input_budget_tokens"
    public static let contextWindowTokens = "chat.context.window_tokens"
    public static let reservedCompletionTokens = "chat.context.reserved_completion_tokens"
    public static let originalMessageCount = "chat.context.original_message_count"
    public static let includedMessageCount = "chat.context.included_message_count"
    public static let droppedMessageCount = "chat.context.dropped_message_count"
    public static let clippedMessageCount = "chat.context.clipped_message_count"
    public static let truncationApplied = "chat.context.truncation_applied"
    public static let budgetSource = "chat.context.budget_source"
    public static let exactInputTokens = "chat.context.exact_input_tokens"
}

public struct ChatContextPackingPolicy: Hashable, Sendable {
    public var maxContextTokens: Int?
    public var reservedCompletionTokens: Int
    public var defaultContextTokens: Int
    public var safetyMarginTokens: Int
    public var charactersPerToken: Int
    public var perMessageOverheadTokens: Int
    public var attachmentOverheadTokens: Int
    public var minimumMessageTokens: Int
    public var maximumMessages: Int
    public var anchorMessageID: UUID?
    public var strategy: String

    public init(
        maxContextTokens: Int?,
        reservedCompletionTokens: Int,
        defaultContextTokens: Int = 65_536,
        safetyMarginTokens: Int = 384,
        charactersPerToken: Int = 3,
        perMessageOverheadTokens: Int = 16,
        attachmentOverheadTokens: Int = 256,
        minimumMessageTokens: Int = 64,
        maximumMessages: Int = 192,
        anchorMessageID: UUID? = nil,
        strategy: String = "anchored-recent-conservative-estimate-v1"
    ) {
        self.maxContextTokens = maxContextTokens
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
        self.defaultContextTokens = max(1_024, defaultContextTokens)
        self.safetyMarginTokens = max(0, safetyMarginTokens)
        self.charactersPerToken = max(1, charactersPerToken)
        self.perMessageOverheadTokens = max(0, perMessageOverheadTokens)
        self.attachmentOverheadTokens = max(0, attachmentOverheadTokens)
        self.minimumMessageTokens = max(1, minimumMessageTokens)
        self.maximumMessages = max(1, maximumMessages)
        self.anchorMessageID = anchorMessageID
        self.strategy = strategy
    }
}

public struct ChatContextPackingSummary: Hashable, Sendable {
    public var estimatedInputTokens: Int
    public var inputBudgetTokens: Int
    public var contextWindowTokens: Int
    public var reservedCompletionTokens: Int
    public var originalMessageCount: Int
    public var includedMessageCount: Int
    public var droppedMessageCount: Int
    public var clippedMessageCount: Int
    public var budgetSource: String
    public var strategy: String

    public var truncationApplied: Bool {
        droppedMessageCount > 0 || clippedMessageCount > 0
    }

    public var providerMetadata: [String: String] {
        [
            ChatContextMetadataKeys.strategy: strategy,
            ChatContextMetadataKeys.estimatedInputTokens: String(estimatedInputTokens),
            ChatContextMetadataKeys.inputBudgetTokens: String(inputBudgetTokens),
            ChatContextMetadataKeys.contextWindowTokens: String(contextWindowTokens),
            ChatContextMetadataKeys.reservedCompletionTokens: String(reservedCompletionTokens),
            ChatContextMetadataKeys.originalMessageCount: String(originalMessageCount),
            ChatContextMetadataKeys.includedMessageCount: String(includedMessageCount),
            ChatContextMetadataKeys.droppedMessageCount: String(droppedMessageCount),
            ChatContextMetadataKeys.clippedMessageCount: String(clippedMessageCount),
            ChatContextMetadataKeys.truncationApplied: String(truncationApplied),
            ChatContextMetadataKeys.budgetSource: budgetSource,
        ]
    }
}

public struct ChatContextPackingResult: Hashable, Sendable {
    public var messages: [ChatMessage]
    public var summary: ChatContextPackingSummary
}

public enum ChatContextPacker {
    private enum ClipMode {
        case preserveEdges
        case suffix
    }

    private struct IndexedMessage {
        var index: Int
        var message: ChatMessage
    }

    public static func estimatedTokens(
        for message: ChatMessage,
        policy: ChatContextPackingPolicy
    ) -> Int {
        let contentTokens = (message.content.unicodeScalars.count + policy.charactersPerToken - 1) / policy.charactersPerToken
        return max(
            1,
            contentTokens
                + policy.perMessageOverheadTokens
                + message.attachments.count * policy.attachmentOverheadTokens
        )
    }

    public static func pack(
        _ messages: [ChatMessage],
        policy: ChatContextPackingPolicy
    ) -> ChatContextPackingResult {
        guard !messages.isEmpty else {
            return ChatContextPackingResult(
                messages: [],
                summary: ChatContextPackingSummary(
                    estimatedInputTokens: 0,
                    inputBudgetTokens: inputBudget(for: policy).budget,
                    contextWindowTokens: inputBudget(for: policy).contextWindow,
                    reservedCompletionTokens: policy.reservedCompletionTokens,
                    originalMessageCount: 0,
                    includedMessageCount: 0,
                    droppedMessageCount: 0,
                    clippedMessageCount: 0,
                    budgetSource: inputBudget(for: policy).source,
                    strategy: policy.strategy
                )
            )
        }

        let budget = inputBudget(for: policy)
        let anchorIndex = policy.anchorMessageID.flatMap { id in
            messages.firstIndex { $0.id == id }
        } ?? messages.lastIndex { $0.role == .user }
        let lastAllowedIndex = anchorIndex ?? messages.index(before: messages.endIndex)
        let indexedMessages = messages.enumerated().map { IndexedMessage(index: $0.offset, message: $0.element) }
        let systemMessages = indexedMessages.filter { $0.message.role == .system }
        let historyMessages = indexedMessages.filter { item in
            item.index <= lastAllowedIndex
                && (anchorIndex.map { item.index != $0 } ?? true)
                && item.message.role != .system
        }
        let droppedAfterAnchor = indexedMessages.filter { item in
            item.index > lastAllowedIndex && item.message.role != .system
        }.count

        var selected = [Int: ChatMessage]()
        var usedTokens = 0
        var clippedMessages = 0

        func remainingTokens() -> Int {
            max(0, budget.budget - usedTokens)
        }

        func addMessage(_ item: IndexedMessage, tokenBudget: Int, clipMode: ClipMode) {
            guard tokenBudget >= policy.minimumMessageTokens || !item.message.attachments.isEmpty else { return }
            let originalEstimate = estimatedTokens(for: item.message, policy: policy)
            if originalEstimate <= tokenBudget {
                selected[item.index] = item.message
                usedTokens += originalEstimate
                return
            }

            let fixedTokens = policy.perMessageOverheadTokens + item.message.attachments.count * policy.attachmentOverheadTokens
            let availableContentTokens = max(0, tokenBudget - fixedTokens)
            let maxCharacters = availableContentTokens * policy.charactersPerToken
            var clipped = item.message
            clipped.content = clippedContent(item.message.content, maxCharacters: maxCharacters, mode: clipMode)
            guard !clipped.content.isEmpty || !clipped.attachments.isEmpty else { return }

            let clippedEstimate = estimatedTokens(for: clipped, policy: policy)
            guard clippedEstimate <= tokenBudget || selected.isEmpty else { return }
            selected[item.index] = clipped
            usedTokens += min(clippedEstimate, tokenBudget)
            clippedMessages += 1
        }

        if let anchorIndex {
            let anchor = IndexedMessage(index: anchorIndex, message: messages[anchorIndex])
            let anchorBudget = min(budget.budget, max(policy.minimumMessageTokens, budget.budget * 2 / 3))
            addMessage(anchor, tokenBudget: anchorBudget, clipMode: .preserveEdges)
        }

        for item in systemMessages where selected.count < policy.maximumMessages {
            guard remainingTokens() > 0 else { break }
            addMessage(item, tokenBudget: remainingTokens(), clipMode: .preserveEdges)
        }

        for item in historyMessages.reversed() where selected.count < policy.maximumMessages {
            guard remainingTokens() > 0 else { break }
            addMessage(item, tokenBudget: remainingTokens(), clipMode: .suffix)
        }

        let packed = selected
            .sorted { $0.key < $1.key }
            .map(\.value)
        let estimatedInputTokens = packed.reduce(0) { $0 + estimatedTokens(for: $1, policy: policy) }
        let droppedByBudget = max(0, messages.count - packed.count - droppedAfterAnchor)
        let summary = ChatContextPackingSummary(
            estimatedInputTokens: estimatedInputTokens,
            inputBudgetTokens: budget.budget,
            contextWindowTokens: budget.contextWindow,
            reservedCompletionTokens: policy.reservedCompletionTokens,
            originalMessageCount: messages.count,
            includedMessageCount: packed.count,
            droppedMessageCount: droppedAfterAnchor + droppedByBudget,
            clippedMessageCount: clippedMessages,
            budgetSource: budget.source,
            strategy: policy.strategy
        )
        return ChatContextPackingResult(messages: packed, summary: summary)
    }

    private static func inputBudget(for policy: ChatContextPackingPolicy) -> (budget: Int, contextWindow: Int, source: String) {
        let contextWindow = max(1, policy.maxContextTokens ?? policy.defaultContextTokens)
        let source = policy.maxContextTokens == nil ? "default" : "provider"
        let safety = min(policy.safetyMarginTokens, max(0, contextWindow - 1))
        let budget = max(policy.minimumMessageTokens, contextWindow - policy.reservedCompletionTokens - safety)
        return (budget, contextWindow, source)
    }

    private static func clippedContent(_ content: String, maxCharacters: Int, mode: ClipMode) -> String {
        guard maxCharacters > 0 else { return "" }
        guard content.count > maxCharacters else { return content }

        switch mode {
        case .preserveEdges:
            return clippedPreservingEdges(content, maxCharacters: maxCharacters)
        case .suffix:
            return clippedSuffix(content, maxCharacters: maxCharacters)
        }
    }

    private static func clippedPreservingEdges(_ content: String, maxCharacters: Int) -> String {
        let marker = "\n\n[... trimmed content to fit model context ...]\n\n"
        guard maxCharacters > marker.count + 16 else {
            return String(content.prefix(maxCharacters))
        }
        let edgeBudget = maxCharacters - marker.count
        let prefixCount = max(1, edgeBudget / 2)
        let suffixCount = max(1, edgeBudget - prefixCount)
        return String(content.prefix(prefixCount)) + marker + String(content.suffix(suffixCount))
    }

    private static func clippedSuffix(_ content: String, maxCharacters: Int) -> String {
        let marker = "[... earlier content trimmed to fit model context ...]\n\n"
        guard maxCharacters > marker.count + 16 else {
            return String(content.suffix(maxCharacters))
        }
        return marker + String(content.suffix(maxCharacters - marker.count))
    }
}
