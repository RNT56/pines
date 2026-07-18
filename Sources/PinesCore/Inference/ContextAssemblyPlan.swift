import Foundation

public struct ContextAssemblyPlan: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var strategy: String
    public var tokenBudget: Int
    public var plannedTokens: Int
    public var pinnedPromptTokens: Int
    public var includedRecentMessageCount: Int
    public var clippedMessageCount: Int
    public var droppedMessageCount: Int
    public var exactInputTokens: Int
    public var reservedCompletionTokens: Int
    public var truncationReason: String?
    public var createdAt: Date
    public var pinnedSegments: [ContextSegment]
    public var liveRecentSegments: [ContextSegment]
    public var retrievedSegments: [ContextSegment]
    public var summarizedSegments: [ContextSegment]
    public var compressedKVPageSegments: [ContextSegment]
    public var droppedSegments: [ContextSegment]
    public var retrievalPlan: RetrievalContextPlan?
    public var clippedMessageIDs: [String]
    public var explanation: String

    public var planID: String {
        get { id }
        set { id = newValue }
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        id: String = UUID().uuidString,
        strategy: String,
        tokenBudget: Int? = nil,
        plannedTokens: Int? = nil,
        pinnedPromptTokens: Int = 0,
        includedRecentMessageCount: Int,
        clippedMessageCount: Int = 0,
        droppedMessageCount: Int = 0,
        exactInputTokens: Int,
        reservedCompletionTokens: Int,
        truncationReason: String? = nil,
        createdAt: Date = Date(),
        pinnedSegments: [ContextSegment] = [],
        liveRecentSegments: [ContextSegment] = [],
        retrievedSegments: [ContextSegment] = [],
        summarizedSegments: [ContextSegment] = [],
        compressedKVPageSegments: [ContextSegment] = [],
        droppedSegments: [ContextSegment] = [],
        retrievalPlan: RetrievalContextPlan? = nil,
        clippedMessageIDs: [String] = [],
        explanation: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.strategy = strategy
        // tokenBudget is always the input/prompt budget. Completion reserve is
        // recorded separately so every producer reports the same unit.
        self.tokenBudget = max(0, tokenBudget ?? exactInputTokens)
        self.plannedTokens = max(0, plannedTokens ?? exactInputTokens)
        self.pinnedPromptTokens = max(0, pinnedPromptTokens)
        self.includedRecentMessageCount = max(0, includedRecentMessageCount)
        self.clippedMessageCount = max(0, clippedMessageCount)
        self.droppedMessageCount = max(0, droppedMessageCount)
        self.exactInputTokens = max(0, exactInputTokens)
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
        self.truncationReason = truncationReason
        self.createdAt = createdAt
        self.pinnedSegments = pinnedSegments
        self.liveRecentSegments = liveRecentSegments
        self.retrievedSegments = retrievedSegments
        self.summarizedSegments = summarizedSegments
        self.compressedKVPageSegments = compressedKVPageSegments
        self.droppedSegments = droppedSegments
        self.retrievalPlan = retrievalPlan
        self.clippedMessageIDs = clippedMessageIDs
        self.explanation = explanation
    }

    public static func minimal(
        from summary: ChatContextPackingSummary,
        id: String = UUID().uuidString,
        exactInputTokens: Int? = nil,
        createdAt: Date = Date()
    ) -> ContextAssemblyPlan {
        ContextAssemblyPlan(
            id: id,
            strategy: summary.strategy,
            tokenBudget: summary.inputBudgetTokens,
            plannedTokens: summary.estimatedInputTokens,
            includedRecentMessageCount: summary.includedMessageCount,
            clippedMessageCount: summary.clippedMessageCount,
            droppedMessageCount: summary.droppedMessageCount,
            exactInputTokens: exactInputTokens ?? summary.estimatedInputTokens,
            reservedCompletionTokens: summary.reservedCompletionTokens,
            truncationReason: summary.truncationApplied ? "context_window" : nil,
            createdAt: createdAt,
            explanation: summary.truncationApplied
                ? "MVP 1 context packing metadata recorded existing truncation behavior."
                : "MVP 1 context packing metadata recorded without truncation."
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case planID
        case strategy
        case tokenBudget
        case plannedTokens
        case pinnedPromptTokens
        case includedRecentMessageCount
        case clippedMessageCount
        case droppedMessageCount
        case exactInputTokens
        case reservedCompletionTokens
        case truncationReason
        case createdAt
        case pinnedSegments
        case liveRecentSegments
        case retrievedSegments
        case summarizedSegments
        case compressedKVPageSegments
        case droppedSegments
        case retrievalPlan
        case clippedMessageIDs
        case explanation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPinnedSegments = try container.decodeIfPresent([ContextSegment].self, forKey: .pinnedSegments) ?? []
        let decodedLiveRecentSegments = try container.decodeIfPresent([ContextSegment].self, forKey: .liveRecentSegments) ?? []
        let decodedRetrievedSegments = try container.decodeIfPresent([ContextSegment].self, forKey: .retrievedSegments) ?? []
        let decodedSummarizedSegments = try container.decodeIfPresent([ContextSegment].self, forKey: .summarizedSegments) ?? []
        let decodedCompressedKVPageSegments = try container.decodeIfPresent([ContextSegment].self, forKey: .compressedKVPageSegments) ?? []
        let decodedDroppedSegments = try container.decodeIfPresent([ContextSegment].self, forKey: .droppedSegments) ?? []
        let decodedExactInputTokens = try container.decodeIfPresent(Int.self, forKey: .exactInputTokens) ?? 0
        let decodedReservedCompletionTokens = try container.decodeIfPresent(Int.self, forKey: .reservedCompletionTokens) ?? 0

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.schemaVersion
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .planID)
            ?? UUID().uuidString
        strategy = try container.decodeIfPresent(String.self, forKey: .strategy) ?? "unknown"
        tokenBudget = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .tokenBudget)
                ?? decodedExactInputTokens
        )
        plannedTokens = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .plannedTokens) ?? decodedExactInputTokens
        )
        pinnedPromptTokens = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .pinnedPromptTokens)
                ?? decodedPinnedSegments.reduce(0) {
                    Self.saturatedAdd($0, max(0, $1.estimatedTokens))
                }
        )
        includedRecentMessageCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .includedRecentMessageCount)
                ?? decodedLiveRecentSegments.count
        )
        clippedMessageCount = max(0, try container.decodeIfPresent(Int.self, forKey: .clippedMessageCount) ?? 0)
        droppedMessageCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .droppedMessageCount) ?? decodedDroppedSegments.count
        )
        exactInputTokens = max(0, decodedExactInputTokens)
        reservedCompletionTokens = max(0, decodedReservedCompletionTokens)
        truncationReason = try container.decodeIfPresent(String.self, forKey: .truncationReason)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        pinnedSegments = decodedPinnedSegments
        liveRecentSegments = decodedLiveRecentSegments
        retrievedSegments = decodedRetrievedSegments
        summarizedSegments = decodedSummarizedSegments
        compressedKVPageSegments = decodedCompressedKVPageSegments
        droppedSegments = decodedDroppedSegments
        retrievalPlan = try container.decodeIfPresent(RetrievalContextPlan.self, forKey: .retrievalPlan)
        clippedMessageIDs = try container.decodeIfPresent([String].self, forKey: .clippedMessageIDs) ?? []
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
            ?? truncationReason
            ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(id, forKey: .planID)
        try container.encode(strategy, forKey: .strategy)
        try container.encode(tokenBudget, forKey: .tokenBudget)
        try container.encode(plannedTokens, forKey: .plannedTokens)
        try container.encode(pinnedPromptTokens, forKey: .pinnedPromptTokens)
        try container.encode(includedRecentMessageCount, forKey: .includedRecentMessageCount)
        try container.encode(clippedMessageCount, forKey: .clippedMessageCount)
        try container.encode(droppedMessageCount, forKey: .droppedMessageCount)
        try container.encode(exactInputTokens, forKey: .exactInputTokens)
        try container.encode(reservedCompletionTokens, forKey: .reservedCompletionTokens)
        try container.encodeIfPresent(truncationReason, forKey: .truncationReason)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(pinnedSegments, forKey: .pinnedSegments)
        try container.encode(liveRecentSegments, forKey: .liveRecentSegments)
        try container.encode(retrievedSegments, forKey: .retrievedSegments)
        try container.encode(summarizedSegments, forKey: .summarizedSegments)
        try container.encode(compressedKVPageSegments, forKey: .compressedKVPageSegments)
        try container.encode(droppedSegments, forKey: .droppedSegments)
        try container.encodeIfPresent(retrievalPlan, forKey: .retrievalPlan)
        try container.encode(clippedMessageIDs, forKey: .clippedMessageIDs)
        try container.encode(explanation, forKey: .explanation)
    }

    private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : value
    }
}

public enum ContextSegmentSource: String, Hashable, Codable, Sendable, CaseIterable {
    case systemPrompt
    case chatMessage
    case toolSchema
    case userPreference
    case vaultChunk
    case mcpResource
    case mcpServerPrompt
    case attachmentManifest
    case referenceData
    case summary
    case compressedKVPage
    case toolOutput
    case activeTask
    case unknown
}

public enum ContextSegmentRole: String, Hashable, Codable, Sendable, CaseIterable {
    case systemInstruction
    case userPreference
    case toolSchema
    case recentUserMessage
    case recentAssistantMessage
    case olderChat
    case vaultEvidence
    case referenceEvidence
    case attachmentReference
    case toolOutput
    case summary
    case snapshotReference
    case activeTask
}

public enum ContextStorageState: String, Hashable, Codable, Sendable, CaseIterable {
    case pinnedPrompt
    case liveRecent
    case retrievedVault
    case retrievedReference
    case summary
    case dropped
    case compressedKVPage

    public var isSemanticMemory: Bool {
        self != .compressedKVPage
    }

    public var isKVState: Bool {
        self == .compressedKVPage
    }

    public var requiresExactPrefixValidation: Bool {
        self == .compressedKVPage
    }

    public var requiresCloudApprovalWhenCloudRouted: Bool {
        self == .retrievedVault
    }

    public var canBeDroppedWithReason: Bool {
        self != .pinnedPrompt
    }

    public var requiresDropReasonWhenDropped: Bool {
        self != .pinnedPrompt
    }
}

public enum ContextPrivacyBoundary: String, Hashable, Codable, Sendable, CaseIterable {
    case localOnly
    case approvedForCloud
    case cloudProvider
    case publicWeb
    case unknown
}

public struct ContextCitationProvenance: Hashable, Codable, Sendable {
    public var citationID: String
    public var title: String?
    public var uri: String?
    public var documentID: UUID?
    public var chunkID: UUID?

    public var isUsable: Bool {
        !citationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || uri?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || documentID != nil
            || chunkID != nil
    }

    public init(
        citationID: String = "",
        title: String? = nil,
        uri: String? = nil,
        documentID: UUID? = nil,
        chunkID: UUID? = nil
    ) {
        self.citationID = citationID
        self.title = title
        self.uri = uri
        self.documentID = documentID
        self.chunkID = chunkID
    }
}

public struct ContextKVPageValidation: Hashable, Codable, Sendable {
    public var modelID: String
    public var tokenizerID: String
    public var profileID: String
    public var ropeConfigHash: String
    public var prefixHash: String
    public var expectedPrefixHash: String
    public var prefixTokenCount: Int
    public var exactPrefixMatch: Bool

    public var isValid: Bool {
        exactPrefixMatch
            && prefixTokenCount > 0
            && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !tokenizerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ropeConfigHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prefixHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && prefixHash == expectedPrefixHash
    }

    public init(
        modelID: String,
        tokenizerID: String,
        profileID: String,
        ropeConfigHash: String,
        prefixHash: String,
        expectedPrefixHash: String,
        prefixTokenCount: Int,
        exactPrefixMatch: Bool
    ) {
        self.modelID = modelID
        self.tokenizerID = tokenizerID
        self.profileID = profileID
        self.ropeConfigHash = ropeConfigHash
        self.prefixHash = prefixHash
        self.expectedPrefixHash = expectedPrefixHash
        self.prefixTokenCount = max(0, prefixTokenCount)
        self.exactPrefixMatch = exactPrefixMatch
    }
}

public struct ContextSegmentProvenance: Hashable, Codable, Sendable {
    public var sourceID: String?
    public var messageID: UUID?
    public var documentID: UUID?
    public var chunkID: UUID?
    public var summaryID: UUID?
    public var snapshotID: String?
    public var title: String?
    public var sourceURI: String?
    public var privacyBoundary: ContextPrivacyBoundary
    public var citation: ContextCitationProvenance?
    public var kvPageValidation: ContextKVPageValidation?
    public var notes: String?

    public var hasSourceReference: Bool {
        sourceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || messageID != nil
            || documentID != nil
            || chunkID != nil
            || summaryID != nil
            || snapshotID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || sourceURI?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public var hasCitationProvenance: Bool {
        citation?.isUsable == true
            || documentID != nil
            || chunkID != nil
            || title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || sourceURI?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public init(
        sourceID: String? = nil,
        messageID: UUID? = nil,
        documentID: UUID? = nil,
        chunkID: UUID? = nil,
        summaryID: UUID? = nil,
        snapshotID: String? = nil,
        title: String? = nil,
        sourceURI: String? = nil,
        privacyBoundary: ContextPrivacyBoundary = .localOnly,
        citation: ContextCitationProvenance? = nil,
        kvPageValidation: ContextKVPageValidation? = nil,
        notes: String? = nil
    ) {
        self.sourceID = sourceID
        self.messageID = messageID
        self.documentID = documentID
        self.chunkID = chunkID
        self.summaryID = summaryID
        self.snapshotID = snapshotID
        self.title = title
        self.sourceURI = sourceURI
        self.privacyBoundary = privacyBoundary
        self.citation = citation
        self.kvPageValidation = kvPageValidation
        self.notes = notes
    }
}

public struct ContextSegment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var source: ContextSegmentSource
    public var role: ContextSegmentRole
    public var estimatedTokens: Int
    public var exactTokenRange: Range<Int>?
    public var priority: Double
    public var recencyScore: Double
    public var retrievalScore: Double?
    public var lastAttentionMass: Double?
    public var storageState: ContextStorageState
    public var canSummarize: Bool
    public var canEvictKV: Bool
    public var provenance: ContextSegmentProvenance
    public var dropReason: String?

    public var validationErrors: [String] {
        var errors = [String]()
        if storageState == .pinnedPrompt && (canSummarize || canEvictKV) {
            errors.append("pinned prompt must not be summarizable or KV-evictable")
        }
        if storageState == .compressedKVPage && provenance.kvPageValidation?.isValid != true {
            errors.append("compressed KV page requires exact-prefix validation")
        }
        if storageState == .retrievedVault && !provenance.hasCitationProvenance {
            errors.append("retrieved vault segment requires source provenance")
        }
        if storageState == .retrievedReference && !provenance.hasSourceReference {
            errors.append("retrieved reference segment requires source provenance")
        }
        if storageState == .dropped && dropReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append("dropped segment requires dropReason")
        }
        return errors
    }

    public init(
        id: UUID = UUID(),
        source: ContextSegmentSource,
        role: ContextSegmentRole,
        estimatedTokens: Int,
        exactTokenRange: Range<Int>? = nil,
        priority: Double = 0,
        recencyScore: Double = 0,
        retrievalScore: Double? = nil,
        lastAttentionMass: Double? = nil,
        storageState: ContextStorageState,
        canSummarize: Bool = true,
        canEvictKV: Bool = true,
        provenance: ContextSegmentProvenance = ContextSegmentProvenance(),
        dropReason: String? = nil
    ) {
        self.id = id
        self.source = source
        self.role = role
        self.estimatedTokens = max(0, estimatedTokens)
        self.exactTokenRange = exactTokenRange
        self.priority = Self.finite(priority)
        self.recencyScore = Self.finite(recencyScore)
        self.retrievalScore = retrievalScore.map(Self.finite)
        self.lastAttentionMass = lastAttentionMass.map(Self.finite)
        self.storageState = storageState
        self.canSummarize = canSummarize
        self.canEvictKV = canEvictKV
        self.provenance = provenance
        self.dropReason = dropReason
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}

public struct RetrievalContextPlan: Hashable, Codable, Sendable {
    public var selectedVaultChunks: [UUID]
    public var liveTokenBudget: Int
    public var summaryBudget: Int
    public var evidenceBudget: Int
    public var pinnedBudget: Int
    public var citationBudget: Int

    public init(
        selectedVaultChunks: [UUID] = [],
        liveTokenBudget: Int,
        summaryBudget: Int,
        evidenceBudget: Int,
        pinnedBudget: Int,
        citationBudget: Int
    ) {
        self.selectedVaultChunks = selectedVaultChunks
        self.liveTokenBudget = max(0, liveTokenBudget)
        self.summaryBudget = max(0, summaryBudget)
        self.evidenceBudget = max(0, evidenceBudget)
        self.pinnedBudget = max(0, pinnedBudget)
        self.citationBudget = max(0, citationBudget)
    }
}

public enum ContextPlanRoute: String, Hashable, Codable, Sendable, CaseIterable {
    case local
    case cloud
}

public struct ContextVaultCloudApproval: Hashable, Codable, Sendable {
    public static let none = ContextVaultCloudApproval()

    public var allowsAllVaultContent: Bool
    public var approvedDocumentIDs: [UUID]
    public var approvedChunkIDs: [UUID]

    public init(
        allowsAllVaultContent: Bool = false,
        approvedDocumentIDs: [UUID] = [],
        approvedChunkIDs: [UUID] = []
    ) {
        self.allowsAllVaultContent = allowsAllVaultContent
        self.approvedDocumentIDs = approvedDocumentIDs
        self.approvedChunkIDs = approvedChunkIDs
    }

    public func allows(_ provenance: ContextSegmentProvenance) -> Bool {
        if allowsAllVaultContent || provenance.privacyBoundary == .approvedForCloud {
            return true
        }
        if let documentID = provenance.documentID, approvedDocumentIDs.contains(documentID) {
            return true
        }
        if let chunkID = provenance.chunkID, approvedChunkIDs.contains(chunkID) {
            return true
        }
        return false
    }
}
