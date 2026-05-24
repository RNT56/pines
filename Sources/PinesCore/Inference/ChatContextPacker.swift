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
    public static let rollingSummaryApplied = "chat.context.rolling_summary_applied"
    public static let rollingSummaryEstimatedTokens = "chat.context.rolling_summary_estimated_tokens"
    public static let rollingSummaryMessageCount = "chat.context.rolling_summary_message_count"
    public static let handoffStrategy = "chat.context.handoff_strategy"
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
    public var rollingSummaryEnabled: Bool
    public var rollingSummaryBudgetTokens: Int
    public var rollingSummaryMaxMessages: Int

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
        strategy: String = "anchored-recent-conservative-estimate-v1",
        rollingSummaryEnabled: Bool = true,
        rollingSummaryBudgetTokens: Int = 1_024,
        rollingSummaryMaxMessages: Int = 64
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
        self.rollingSummaryEnabled = rollingSummaryEnabled
        self.rollingSummaryBudgetTokens = max(self.minimumMessageTokens, rollingSummaryBudgetTokens)
        self.rollingSummaryMaxMessages = max(1, rollingSummaryMaxMessages)
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
    public var rollingSummaryApplied: Bool
    public var rollingSummaryEstimatedTokens: Int
    public var rollingSummaryMessageCount: Int
    public var budgetSource: String
    public var strategy: String

    public var truncationApplied: Bool {
        droppedMessageCount > 0 || clippedMessageCount > 0 || rollingSummaryApplied
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
            ChatContextMetadataKeys.rollingSummaryApplied: String(rollingSummaryApplied),
            ChatContextMetadataKeys.rollingSummaryEstimatedTokens: String(rollingSummaryEstimatedTokens),
            ChatContextMetadataKeys.rollingSummaryMessageCount: String(rollingSummaryMessageCount),
            ChatContextMetadataKeys.handoffStrategy: rollingSummaryApplied ? "deterministic-rolling-handoff-v1" : "none",
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
                    rollingSummaryApplied: false,
                    rollingSummaryEstimatedTokens: 0,
                    rollingSummaryMessageCount: 0,
                    budgetSource: inputBudget(for: policy).source,
                    strategy: policy.strategy
                )
            )
        }

        var budget = inputBudget(for: policy)
        let totalInputBudgetTokens = budget.budget
        let totalEstimatedTokens = messages.reduce(0) { $0 + estimatedTokens(for: $1, policy: policy) }
        let shouldReserveRollingSummary = policy.rollingSummaryEnabled
            && (totalEstimatedTokens > budget.budget || messages.count > policy.maximumMessages)
        let reservedRollingSummaryBudget = shouldReserveRollingSummary
            ? min(policy.rollingSummaryBudgetTokens, max(policy.minimumMessageTokens, budget.budget / 4))
            : 0
        if reservedRollingSummaryBudget > 0 {
            budget.budget = max(policy.minimumMessageTokens, budget.budget - reservedRollingSummaryBudget)
        }
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

        var packed = selected
            .sorted { $0.key < $1.key }
            .map(\.value)
        var rollingSummaryApplied = false
        var rollingSummaryEstimatedTokens = 0
        var rollingSummaryMessageCount = 0
        if reservedRollingSummaryBudget > 0 {
            let selectedIndexes = Set(selected.keys)
            let summarizedItems = indexedMessages.filter { item in
                item.index <= lastAllowedIndex
                    && item.message.role != .system
                    && !selectedIndexes.contains(item.index)
            }
            if let summaryMessage = rollingSummaryMessage(
                from: summarizedItems,
                tokenBudget: reservedRollingSummaryBudget,
                policy: policy
            ) {
                rollingSummaryEstimatedTokens = estimatedTokens(for: summaryMessage, policy: policy)
                rollingSummaryMessageCount = summarizedItems.count
                rollingSummaryApplied = true
                let insertIndex = packed.lastIndex { $0.role == .system }
                    .map { packed.index(after: $0) }
                    ?? packed.startIndex
                packed.insert(summaryMessage, at: insertIndex)
            }
        }
        let estimatedInputTokens = packed.reduce(0) { $0 + estimatedTokens(for: $1, policy: policy) }
        let droppedByBudget = max(0, messages.count - selected.count - droppedAfterAnchor)
        let summary = ChatContextPackingSummary(
            estimatedInputTokens: estimatedInputTokens,
            inputBudgetTokens: totalInputBudgetTokens,
            contextWindowTokens: budget.contextWindow,
            reservedCompletionTokens: policy.reservedCompletionTokens,
            originalMessageCount: messages.count,
            includedMessageCount: packed.count,
            droppedMessageCount: droppedAfterAnchor + droppedByBudget,
            clippedMessageCount: clippedMessages,
            rollingSummaryApplied: rollingSummaryApplied,
            rollingSummaryEstimatedTokens: rollingSummaryEstimatedTokens,
            rollingSummaryMessageCount: rollingSummaryMessageCount,
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

    private static func rollingSummaryMessage(
        from items: [IndexedMessage],
        tokenBudget: Int,
        policy: ChatContextPackingPolicy
    ) -> ChatMessage? {
        guard tokenBudget >= policy.minimumMessageTokens, !items.isEmpty else { return nil }
        let fixedTokens = policy.perMessageOverheadTokens
        let maxCharacters = max(0, (tokenBudget - fixedTokens) * policy.charactersPerToken)
        guard maxCharacters > 128 else { return nil }

        let summarizedItems = Array(items.suffix(policy.rollingSummaryMaxMessages))
        var lines = [
            "Earlier conversation handoff summary.",
            "Use this as compressed context for turns that no longer fit verbatim.",
            "Preserve decisions, constraints, open questions, tool outcomes, attachments, and user preferences from these earlier turns.",
            "Source message count: \(items.count).",
        ]
        if summarizedItems.count < items.count {
            lines.append("Oldest omitted source messages: \(items.count - summarizedItems.count).")
        }
        lines.append("Compressed source turns:")

        for item in summarizedItems {
            lines.append("- \(handoffRoleName(item.message.role)): \(handoffExcerpt(for: item.message, policy: policy))")
        }

        var content = lines.joined(separator: "\n")
        if content.count > maxCharacters {
            content = clippedPreservingEdges(content, maxCharacters: maxCharacters)
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return ChatMessage(
            role: .system,
            content: content,
            providerMetadata: [
                ChatContextMetadataKeys.handoffStrategy: "deterministic-rolling-handoff-v1",
                ChatContextMetadataKeys.rollingSummaryMessageCount: String(items.count),
            ]
        )
    }

    private static func handoffRoleName(_ role: ChatRole) -> String {
        switch role {
        case .system:
            return "System"
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .tool:
            return "Tool"
        }
    }

    private static func handoffExcerpt(
        for message: ChatMessage,
        policy: ChatContextPackingPolicy
    ) -> String {
        var parts = [String]()
        let normalized = message.content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        let maxCharacters = max(96, policy.charactersPerToken * 96)
        if normalized.count > maxCharacters {
            parts.append(String(normalized.prefix(maxCharacters)) + " ...")
        } else if !normalized.isEmpty {
            parts.append(normalized)
        }
        if !message.attachments.isEmpty {
            let attachmentSummary = message.attachments
                .prefix(4)
                .map { "\($0.kind.rawValue):\($0.fileName)" }
                .joined(separator: ", ")
            parts.append("[attachments: \(attachmentSummary)]")
        }
        if !message.toolCalls.isEmpty {
            let toolSummary = message.toolCalls
                .prefix(4)
                .map(\.name)
                .joined(separator: ", ")
            parts.append("[tool calls: \(toolSummary)]")
        }
        if let toolName = message.toolName {
            parts.append("[tool result: \(toolName)]")
        }
        return parts.isEmpty ? "[empty message]" : parts.joined(separator: " ")
    }
}
