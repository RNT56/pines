import Foundation
import PinesCore
import Testing

@Suite("TurboQuant Wave 4 context memory planner")
struct TurboQuantWave4ContextMemoryTests {
    @Test func pinnedPromptCannotBeDroppedEvenWhenOverBudget() throws {
        let pinned = Self.segment(
            1,
            source: .systemPrompt,
            role: .systemInstruction,
            tokens: 120,
            storageState: .pinnedPrompt,
            priority: 1_000,
            provenance: ContextSegmentProvenance(sourceID: "system-prompt")
        )
        let recent = Self.segment(
            2,
            source: .chatMessage,
            role: .recentUserMessage,
            tokens: 20,
            storageState: .liveRecent,
            recencyScore: 1,
            provenance: ContextSegmentProvenance(messageID: Self.uuid(102))
        )

        let plan = ContextMemoryPlanner().plan(
            request: ContextMemoryPlannerRequest(
                tokenBudget: 40,
                pinnedSegments: [pinned],
                recentSegments: [recent]
            )
        )

        #expect(plan.pinnedSegments.map(\.id) == [pinned.id])
        #expect(plan.pinnedSegments.first?.canSummarize == false)
        #expect(plan.pinnedSegments.first?.canEvictKV == false)
        #expect(!plan.droppedSegments.contains { $0.id == pinned.id })
        #expect(plan.droppedSegments.contains { $0.id == recent.id && $0.dropReason == "live recent budget exhausted" })
        #expect(plan.plannedTokens > plan.tokenBudget)
        #expect(plan.explanation.contains("Pinned prompt exceeds token budget"))
    }

    @Test func cloudRouteExcludesVaultContentWithoutApproval() throws {
        let documentID = Self.uuid(201)
        let chunkID = Self.uuid(202)
        let vault = Self.vaultSegment(
            3,
            documentID: documentID,
            chunkID: chunkID,
            privacyBoundary: .localOnly,
            retrievalScore: 0.95
        )

        let blockedPlan = ContextMemoryPlanner().plan(
            request: ContextMemoryPlannerRequest(
                tokenBudget: 400,
                route: .cloud,
                retrievedVaultSegments: [vault],
                evidenceBudget: 200,
                citationBudget: 2
            )
        )

        #expect(blockedPlan.retrievedSegments.isEmpty)
        let dropped = try #require(blockedPlan.droppedSegments.first { $0.id == vault.id })
        #expect(dropped.dropReason == "vault content requires cloud approval")
        #expect(blockedPlan.explanation.contains("Cloud route excluded unapproved vault content"))

        let approvedPlan = ContextMemoryPlanner().plan(
            request: ContextMemoryPlannerRequest(
                tokenBudget: 400,
                route: .cloud,
                vaultCloudApproval: ContextVaultCloudApproval(approvedDocumentIDs: [documentID]),
                retrievedVaultSegments: [vault],
                evidenceBudget: 200,
                citationBudget: 2
            )
        )

        #expect(approvedPlan.retrievedSegments.map(\.id) == [vault.id])
        #expect(approvedPlan.retrievalPlan?.selectedVaultChunks == [chunkID])
    }

    @Test func compressedKVPagesRequireExactPrefixValidity() throws {
        let invalidKV = Self.kvSegment(4, exactPrefixMatch: false)
        let validKV = Self.kvSegment(5, exactPrefixMatch: true)

        let plan = ContextMemoryPlanner().plan(
            request: ContextMemoryPlannerRequest(
                tokenBudget: 256,
                compressedKVPageSegments: [invalidKV, validKV]
            )
        )

        #expect(plan.compressedKVPageSegments.map(\.id) == [validKV.id])
        #expect(plan.retrievedSegments.isEmpty)
        let dropped = try #require(plan.droppedSegments.first { $0.id == invalidKV.id })
        #expect(dropped.dropReason == "compressed KV page requires exact-prefix validity")
        #expect(dropped.validationErrors.isEmpty)
    }

    @Test func compressedKVPageIsNeverTreatedAsSemanticRetrieval() throws {
        let kvAsRetrieval = Self.kvSegment(6, exactPrefixMatch: true)

        let plan = ContextMemoryPlanner().plan(
            request: ContextMemoryPlannerRequest(
                tokenBudget: 256,
                retrievedVaultSegments: [kvAsRetrieval],
                evidenceBudget: 256,
                citationBudget: 1
            )
        )

        #expect(plan.retrievedSegments.isEmpty)
        #expect(plan.compressedKVPageSegments.isEmpty)
        let dropped = try #require(plan.droppedSegments.first { $0.id == kvAsRetrieval.id })
        #expect(dropped.dropReason == "compressed KV page is not semantic retrieval content")
    }

    @Test func retrievalSummaryAndCitationBudgetsAreRecordedAndEnforced() throws {
        let includedVault = Self.vaultSegment(
            7,
            documentID: Self.uuid(301),
            chunkID: Self.uuid(302),
            privacyBoundary: .localOnly,
            retrievalScore: 0.99
        )
        let citationDroppedVault = Self.vaultSegment(
            8,
            documentID: Self.uuid(303),
            chunkID: Self.uuid(304),
            privacyBoundary: .localOnly,
            retrievalScore: 0.98
        )
        let summary = Self.segment(
            9,
            source: .summary,
            role: .summary,
            tokens: 24,
            storageState: .summary,
            provenance: ContextSegmentProvenance(
                sourceID: "rolling-summary",
                summaryID: Self.uuid(305),
                title: "Earlier project constraints"
            )
        )

        let plan = ContextMemoryPlanner().plan(
            request: ContextMemoryPlannerRequest(
                tokenBudget: 256,
                retrievedVaultSegments: [citationDroppedVault, includedVault],
                summarySegments: [summary],
                summaryBudget: 64,
                evidenceBudget: 200,
                citationBudget: 1
            )
        )

        #expect(plan.summarizedSegments.map(\.id) == [summary.id])
        #expect(plan.summarizedSegments.first?.provenance.summaryID == Self.uuid(305))
        #expect(plan.retrievedSegments.map(\.id) == [includedVault.id])
        let dropped = try #require(plan.droppedSegments.first { $0.id == citationDroppedVault.id })
        #expect(dropped.dropReason == "citation budget exhausted")
        #expect(plan.retrievalPlan?.summaryBudget == 64)
        #expect(plan.retrievalPlan?.evidenceBudget == 200)
        #expect(plan.retrievalPlan?.citationBudget == 1)
    }

    @Test func plannerOutputIsDeterministicForSameInputs() throws {
        let request = ContextMemoryPlannerRequest(
            tokenBudget: 512,
            reservedCompletionTokens: 64,
            pinnedSegments: [
                Self.segment(
                    10,
                    source: .systemPrompt,
                    role: .systemInstruction,
                    tokens: 48,
                    storageState: .pinnedPrompt,
                    provenance: ContextSegmentProvenance(sourceID: "system-prompt")
                ),
            ],
            recentSegments: [
                Self.segment(
                    12,
                    source: .chatMessage,
                    role: .recentAssistantMessage,
                    tokens: 80,
                    storageState: .liveRecent,
                    recencyScore: 0.7,
                    provenance: ContextSegmentProvenance(messageID: Self.uuid(402))
                ),
                Self.segment(
                    11,
                    source: .chatMessage,
                    role: .recentUserMessage,
                    tokens: 72,
                    storageState: .liveRecent,
                    recencyScore: 0.9,
                    provenance: ContextSegmentProvenance(messageID: Self.uuid(401))
                ),
            ],
            retrievedVaultSegments: [
                Self.vaultSegment(
                    13,
                    documentID: Self.uuid(403),
                    chunkID: Self.uuid(404),
                    privacyBoundary: .localOnly,
                    retrievalScore: 0.8
                ),
            ],
            summarySegments: [
                Self.segment(
                    14,
                    source: .summary,
                    role: .summary,
                    tokens: 32,
                    storageState: .summary,
                    provenance: ContextSegmentProvenance(summaryID: Self.uuid(405), title: "prior work")
                ),
            ],
            liveTokenBudget: 200,
            summaryBudget: 64,
            evidenceBudget: 128,
            citationBudget: 4,
            createdAt: Date(timeIntervalSince1970: 123)
        )

        let first = ContextMemoryPlanner().plan(request: request)
        let second = ContextMemoryPlanner().plan(request: request)

        #expect(first == second)
        #expect(first.id == second.id)
        #expect(first.liveRecentSegments.map(\.id) == [Self.uuid(11), Self.uuid(12)])
    }

    @Test func minimalWave2ContextPlanDecodesWithEmptyFullPlannerFields() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "id": "wave2-plan",
          "strategy": "mlx-current-history-v1",
          "pinnedPromptTokens": 32,
          "includedRecentMessageCount": 4,
          "clippedMessageCount": 1,
          "droppedMessageCount": 2,
          "exactInputTokens": 512,
          "reservedCompletionTokens": 128,
          "truncationReason": "context_window"
        }
        """

        let decoded = try JSONDecoder().decode(ContextAssemblyPlan.self, from: Data(legacyJSON.utf8))

        #expect(decoded.id == "wave2-plan")
        #expect(decoded.planID == "wave2-plan")
        #expect(decoded.strategy == "mlx-current-history-v1")
        #expect(decoded.tokenBudget == 512)
        #expect(decoded.plannedTokens == 512)
        #expect(decoded.pinnedSegments.isEmpty)
        #expect(decoded.liveRecentSegments.isEmpty)
        #expect(decoded.retrievedSegments.isEmpty)
        #expect(decoded.summarizedSegments.isEmpty)
        #expect(decoded.compressedKVPageSegments.isEmpty)
        #expect(decoded.droppedSegments.isEmpty)

        let roundTripped = try JSONDecoder().decode(ContextAssemblyPlan.self, from: JSONEncoder().encode(decoded))
        #expect(roundTripped == decoded)
    }

    private static func segment(
        _ id: Int,
        source: ContextSegmentSource,
        role: ContextSegmentRole,
        tokens: Int,
        storageState: ContextStorageState,
        priority: Double = 0,
        recencyScore: Double = 0,
        retrievalScore: Double? = nil,
        provenance: ContextSegmentProvenance
    ) -> ContextSegment {
        ContextSegment(
            id: uuid(id),
            source: source,
            role: role,
            estimatedTokens: tokens,
            priority: priority,
            recencyScore: recencyScore,
            retrievalScore: retrievalScore,
            storageState: storageState,
            provenance: provenance
        )
    }

    private static func vaultSegment(
        _ id: Int,
        documentID: UUID,
        chunkID: UUID,
        privacyBoundary: ContextPrivacyBoundary,
        retrievalScore: Double
    ) -> ContextSegment {
        segment(
            id,
            source: .vaultChunk,
            role: .vaultEvidence,
            tokens: 64,
            storageState: .retrievedVault,
            retrievalScore: retrievalScore,
            provenance: ContextSegmentProvenance(
                documentID: documentID,
                chunkID: chunkID,
                title: "Vault note \(id)",
                privacyBoundary: privacyBoundary,
                citation: ContextCitationProvenance(
                    citationID: "vault-\(id)",
                    title: "Vault note \(id)",
                    documentID: documentID,
                    chunkID: chunkID
                )
            )
        )
    }

    private static func kvSegment(_ id: Int, exactPrefixMatch: Bool) -> ContextSegment {
        segment(
            id,
            source: .compressedKVPage,
            role: .snapshotReference,
            tokens: 64,
            storageState: .compressedKVPage,
            provenance: ContextSegmentProvenance(
                snapshotID: "kv-\(id)",
                kvPageValidation: ContextKVPageValidation(
                    modelID: "model-a",
                    tokenizerID: "tokenizer-a",
                    profileID: "profile-a",
                    ropeConfigHash: "rope-a",
                    prefixHash: "prefix-a",
                    expectedPrefixHash: "prefix-a",
                    prefixTokenCount: 64,
                    exactPrefixMatch: exactPrefixMatch
                )
            )
        )
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
