import Foundation

public struct ContextMemoryPlannerRequest: Hashable, Codable, Sendable {
    public var tokenBudget: Int
    public var reservedCompletionTokens: Int
    public var route: ContextPlanRoute
    public var vaultCloudApproval: ContextVaultCloudApproval
    public var pinnedSegments: [ContextSegment]
    public var recentSegments: [ContextSegment]
    public var retrievedVaultSegments: [ContextSegment]
    public var summarySegments: [ContextSegment]
    public var compressedKVPageSegments: [ContextSegment]
    public var liveTokenBudget: Int
    public var summaryBudget: Int
    public var evidenceBudget: Int
    public var pinnedBudget: Int
    public var citationBudget: Int
    public var exactInputTokens: Int?
    public var clippedMessageIDs: [String]
    public var createdAt: Date
    public var strategy: String
    public var planSeed: String?

    public init(
        tokenBudget: Int,
        reservedCompletionTokens: Int = 0,
        route: ContextPlanRoute = .local,
        vaultCloudApproval: ContextVaultCloudApproval = .none,
        pinnedSegments: [ContextSegment] = [],
        recentSegments: [ContextSegment] = [],
        retrievedVaultSegments: [ContextSegment] = [],
        summarySegments: [ContextSegment] = [],
        compressedKVPageSegments: [ContextSegment] = [],
        liveTokenBudget: Int? = nil,
        summaryBudget: Int? = nil,
        evidenceBudget: Int? = nil,
        pinnedBudget: Int? = nil,
        citationBudget: Int = 8,
        exactInputTokens: Int? = nil,
        clippedMessageIDs: [String] = [],
        createdAt: Date = Date(timeIntervalSince1970: 0),
        strategy: String = "context-memory-planner-v1",
        planSeed: String? = nil
    ) {
        let normalizedTokenBudget = max(0, tokenBudget)
        self.tokenBudget = normalizedTokenBudget
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
        self.route = route
        self.vaultCloudApproval = vaultCloudApproval
        self.pinnedSegments = pinnedSegments
        self.recentSegments = recentSegments
        self.retrievedVaultSegments = retrievedVaultSegments
        self.summarySegments = summarySegments
        self.compressedKVPageSegments = compressedKVPageSegments
        self.liveTokenBudget = max(0, liveTokenBudget ?? normalizedTokenBudget)
        self.summaryBudget = max(0, summaryBudget ?? normalizedTokenBudget / 5)
        self.evidenceBudget = max(0, evidenceBudget ?? normalizedTokenBudget / 3)
        self.pinnedBudget = max(0, pinnedBudget ?? normalizedTokenBudget)
        self.citationBudget = max(0, citationBudget)
        self.exactInputTokens = exactInputTokens.map { max(0, $0) }
        self.clippedMessageIDs = clippedMessageIDs
        self.createdAt = createdAt
        self.strategy = strategy
        self.planSeed = planSeed
    }
}

public struct ContextMemoryPlanner: Sendable {
    public init() {}

    public func plan(_ request: ContextMemoryPlannerRequest) -> ContextAssemblyPlan {
        plan(request: request)
    }

    public func plan(request: ContextMemoryPlannerRequest) -> ContextAssemblyPlan {
        var droppedSegments = [ContextSegment]()
        var notes = [String]()

        let pinnedSegments = request.pinnedSegments.map {
            normalize($0, storageState: .pinnedPrompt, canSummarize: false, canEvictKV: false)
        }
        let pinnedTokens = pinnedSegments.reduce(0) { $0 + $1.estimatedTokens }
        if pinnedTokens > request.tokenBudget {
            notes.append("Pinned prompt exceeds token budget and was retained.")
        }

        var apparentTokens = pinnedTokens
        var semanticPromptTokens = pinnedTokens

        let compressedKVPageSegments = selectCompressedKVPages(
            from: request.compressedKVPageSegments,
            request: request,
            apparentTokens: &apparentTokens,
            droppedSegments: &droppedSegments,
            notes: &notes
        )

        let liveRecentSegments = selectBudgeted(
            from: request.recentSegments.map {
                normalize($0, storageState: .liveRecent, canSummarize: true, canEvictKV: true)
            },
            budget: min(request.liveTokenBudget, remainingTokens(request.tokenBudget, apparentTokens)),
            apparentTokens: &apparentTokens,
            semanticPromptTokens: &semanticPromptTokens,
            droppedSegments: &droppedSegments,
            exhaustedReason: "live recent budget exhausted"
        )

        let summarizedSegments = selectSummaries(
            from: request.summarySegments,
            request: request,
            apparentTokens: &apparentTokens,
            semanticPromptTokens: &semanticPromptTokens,
            droppedSegments: &droppedSegments
        )

        let retrievedSegments = selectRetrievedVault(
            from: request.retrievedVaultSegments,
            request: request,
            apparentTokens: &apparentTokens,
            semanticPromptTokens: &semanticPromptTokens,
            droppedSegments: &droppedSegments,
            notes: &notes
        )

        let selectedVaultChunks = retrievedSegments.compactMap { segment in
            segment.provenance.chunkID
        }
        let explanation = Self.explanation(notes: notes, droppedCount: droppedSegments.count)
        let planID = request.planSeed ?? Self.stablePlanID(
            request: request,
            pinnedSegments: pinnedSegments,
            liveRecentSegments: liveRecentSegments,
            retrievedSegments: retrievedSegments,
            summarizedSegments: summarizedSegments,
            compressedKVPageSegments: compressedKVPageSegments,
            droppedSegments: droppedSegments
        )

        return ContextAssemblyPlan(
            id: planID,
            strategy: request.strategy,
            tokenBudget: request.tokenBudget,
            plannedTokens: apparentTokens,
            pinnedPromptTokens: pinnedTokens,
            includedRecentMessageCount: liveRecentSegments.count,
            clippedMessageCount: request.clippedMessageIDs.count,
            droppedMessageCount: droppedSegments.count,
            exactInputTokens: request.exactInputTokens ?? semanticPromptTokens,
            reservedCompletionTokens: request.reservedCompletionTokens,
            truncationReason: droppedSegments.isEmpty ? nil : "context_memory_budget",
            createdAt: request.createdAt,
            pinnedSegments: pinnedSegments,
            liveRecentSegments: liveRecentSegments,
            retrievedSegments: retrievedSegments,
            summarizedSegments: summarizedSegments,
            compressedKVPageSegments: compressedKVPageSegments,
            droppedSegments: droppedSegments,
            retrievalPlan: RetrievalContextPlan(
                selectedVaultChunks: selectedVaultChunks,
                liveTokenBudget: request.liveTokenBudget,
                summaryBudget: request.summaryBudget,
                evidenceBudget: request.evidenceBudget,
                pinnedBudget: request.pinnedBudget,
                citationBudget: request.citationBudget
            ),
            clippedMessageIDs: request.clippedMessageIDs,
            explanation: explanation
        )
    }

    private func selectCompressedKVPages(
        from segments: [ContextSegment],
        request: ContextMemoryPlannerRequest,
        apparentTokens: inout Int,
        droppedSegments: inout [ContextSegment],
        notes: inout [String]
    ) -> [ContextSegment] {
        var selected = [ContextSegment]()
        for segment in Self.sorted(segments.map({
            normalize($0, storageState: .compressedKVPage, canSummarize: false, canEvictKV: true)
        })) {
            guard segment.provenance.kvPageValidation?.isValid == true else {
                droppedSegments.append(drop(segment, reason: "compressed KV page requires exact-prefix validity"))
                notes.append("Invalid compressed KV pages were dropped; semantic retrieval cannot restore KV state.")
                continue
            }
            let remaining = remainingTokens(request.tokenBudget, apparentTokens)
            guard segment.estimatedTokens <= remaining else {
                droppedSegments.append(drop(segment, reason: "compressed KV page budget exhausted"))
                continue
            }
            selected.append(segment)
            apparentTokens += segment.estimatedTokens
        }
        return selected
    }

    private func selectBudgeted(
        from segments: [ContextSegment],
        budget: Int,
        apparentTokens: inout Int,
        semanticPromptTokens: inout Int,
        droppedSegments: inout [ContextSegment],
        exhaustedReason: String
    ) -> [ContextSegment] {
        var selected = [ContextSegment]()
        var categoryBudget = max(0, budget)
        for segment in Self.sorted(segments) {
            guard segment.estimatedTokens <= categoryBudget else {
                droppedSegments.append(drop(segment, reason: exhaustedReason))
                continue
            }
            selected.append(segment)
            categoryBudget -= segment.estimatedTokens
            apparentTokens += segment.estimatedTokens
            semanticPromptTokens += segment.estimatedTokens
        }
        return selected
    }

    private func selectSummaries(
        from segments: [ContextSegment],
        request: ContextMemoryPlannerRequest,
        apparentTokens: inout Int,
        semanticPromptTokens: inout Int,
        droppedSegments: inout [ContextSegment]
    ) -> [ContextSegment] {
        var selected = [ContextSegment]()
        var categoryBudget = min(request.summaryBudget, remainingTokens(request.tokenBudget, apparentTokens))
        for segment in Self.sorted(segments.map({
            normalize($0, storageState: .summary, canSummarize: false, canEvictKV: false)
        })) {
            guard segment.provenance.hasSourceReference else {
                droppedSegments.append(drop(segment, reason: "summary segment missing provenance"))
                continue
            }
            guard segment.estimatedTokens <= categoryBudget else {
                droppedSegments.append(drop(segment, reason: "summary budget exhausted"))
                continue
            }
            selected.append(segment)
            categoryBudget -= segment.estimatedTokens
            apparentTokens += segment.estimatedTokens
            semanticPromptTokens += segment.estimatedTokens
        }
        return selected
    }

    private func selectRetrievedVault(
        from segments: [ContextSegment],
        request: ContextMemoryPlannerRequest,
        apparentTokens: inout Int,
        semanticPromptTokens: inout Int,
        droppedSegments: inout [ContextSegment],
        notes: inout [String]
    ) -> [ContextSegment] {
        var selected = [ContextSegment]()
        var categoryBudget = min(request.evidenceBudget, remainingTokens(request.tokenBudget, apparentTokens))
        var citationBudget = request.citationBudget

        for original in Self.sorted(segments) {
            if original.storageState == .compressedKVPage || original.source == .compressedKVPage {
                let normalized = normalize(original, storageState: .compressedKVPage, canSummarize: false, canEvictKV: true)
                droppedSegments.append(drop(normalized, reason: "compressed KV page is not semantic retrieval content"))
                notes.append("Compressed KV pages remained distinct from semantic retrieval.")
                continue
            }

            let segment = normalize(original, storageState: .retrievedVault, canSummarize: true, canEvictKV: false)
            if request.route == ContextPlanRoute.cloud && !request.vaultCloudApproval.allows(segment.provenance) {
                droppedSegments.append(drop(segment, reason: "vault content requires cloud approval"))
                notes.append("Cloud route excluded unapproved vault content.")
                continue
            }
            guard segment.provenance.hasCitationProvenance else {
                droppedSegments.append(drop(segment, reason: "retrieved vault segment missing source provenance"))
                continue
            }
            guard citationBudget > 0 else {
                droppedSegments.append(drop(segment, reason: "citation budget exhausted"))
                continue
            }
            guard segment.estimatedTokens <= categoryBudget else {
                droppedSegments.append(drop(segment, reason: "retrieval budget exhausted"))
                continue
            }
            selected.append(segment)
            citationBudget -= 1
            categoryBudget -= segment.estimatedTokens
            apparentTokens += segment.estimatedTokens
            semanticPromptTokens += segment.estimatedTokens
        }
        return selected
    }

    private func normalize(
        _ segment: ContextSegment,
        storageState: ContextStorageState,
        canSummarize: Bool,
        canEvictKV: Bool
    ) -> ContextSegment {
        var normalized = segment
        normalized.storageState = storageState
        normalized.canSummarize = canSummarize
        normalized.canEvictKV = canEvictKV
        normalized.dropReason = nil
        return normalized
    }

    private func drop(_ segment: ContextSegment, reason: String) -> ContextSegment {
        var dropped = segment
        dropped.storageState = .dropped
        dropped.dropReason = reason
        return dropped
    }

    private func remainingTokens(_ tokenBudget: Int, _ usedTokens: Int) -> Int {
        max(0, tokenBudget - usedTokens)
    }

    private static func sorted(_ segments: [ContextSegment]) -> [ContextSegment] {
        segments.sorted { lhs, rhs in
            let lhsScore = score(lhs)
            let rhsScore = score(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.estimatedTokens != rhs.estimatedTokens {
                return lhs.estimatedTokens < rhs.estimatedTokens
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func score(_ segment: ContextSegment) -> Double {
        roleWeight(segment.role)
            + segment.priority
            + segment.recencyScore * 0.25
            + (segment.retrievalScore ?? 0) * 0.35
            + storageWeight(segment.storageState)
            - Double(segment.estimatedTokens) * 0.0001
    }

    private static func roleWeight(_ role: ContextSegmentRole) -> Double {
        switch role {
        case .systemInstruction:
            return 100
        case .userPreference, .toolSchema, .activeTask:
            return 80
        case .recentUserMessage:
            return 60
        case .recentAssistantMessage:
            return 55
        case .toolOutput:
            return 45
        case .vaultEvidence:
            return 40
        case .summary:
            return 35
        case .olderChat:
            return 20
        case .snapshotReference:
            return 10
        }
    }

    private static func storageWeight(_ storageState: ContextStorageState) -> Double {
        switch storageState {
        case .pinnedPrompt:
            return 1_000
        case .liveRecent:
            return 100
        case .retrievedVault:
            return 80
        case .summary:
            return 60
        case .compressedKVPage:
            return 40
        case .dropped:
            return 0
        }
    }

    private static func explanation(notes: [String], droppedCount: Int) -> String {
        var uniqueNotes = [String]()
        var seen = Set<String>()
        for note in notes where seen.insert(note).inserted {
            uniqueNotes.append(note)
        }
        if droppedCount > 0 {
            uniqueNotes.append("\(droppedCount) segment(s) dropped by storage, privacy, or budget rules.")
        }
        if uniqueNotes.isEmpty {
            return "Context assembled within budget."
        }
        return uniqueNotes.joined(separator: " ")
    }

    private static func stablePlanID(
        request: ContextMemoryPlannerRequest,
        pinnedSegments: [ContextSegment],
        liveRecentSegments: [ContextSegment],
        retrievedSegments: [ContextSegment],
        summarizedSegments: [ContextSegment],
        compressedKVPageSegments: [ContextSegment],
        droppedSegments: [ContextSegment]
    ) -> String {
        var parts: [String] = []
        parts.append(request.strategy)
        parts.append(String(request.tokenBudget))
        parts.append(String(request.reservedCompletionTokens))
        parts.append(request.route.rawValue)
        parts.append(String(request.liveTokenBudget))
        parts.append(String(request.summaryBudget))
        parts.append(String(request.evidenceBudget))
        parts.append(String(request.pinnedBudget))
        parts.append(String(request.citationBudget))

        for segment in pinnedSegments
            + liveRecentSegments
            + retrievedSegments
            + summarizedSegments
            + compressedKVPageSegments
            + droppedSegments {
            parts.append(segment.id.uuidString)
            parts.append(segment.storageState.rawValue)
            parts.append(String(segment.estimatedTokens))
            parts.append(segment.dropReason ?? "")
        }
        return "context-plan-\(stableHexDigest(parts.joined(separator: "|")))"
    }

    private static func stableHexDigest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
