import Foundation
import XCTest
import PinesCore
@testable import pines

final class ProductionUXPersistenceTests: XCTestCase {
    func testProviderTransferPersistsAndActiveTransferBecomesInterrupted() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let provider = CloudProviderConfiguration(
            id: ProviderID(rawValue: "openai-test"),
            kind: .openAI,
            displayName: "OpenAI Test",
            baseURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1")),
            keychainAccount: "openai-test"
        )
        try await store.upsertProvider(provider)
        let transfer = ProviderTransferRecord(
            providerID: provider.id,
            providerKind: .openAI,
            source: .localFile,
            sourceReference: "brief.pdf",
            stagedLocalURL: directory.appending(path: "brief.pdf"),
            fileName: "brief.pdf",
            contentType: "application/pdf",
            purpose: "assistants",
            status: .transferring,
            completedBytes: 128,
            totalBytes: 1_024
        )
        try await store.upsertProviderTransfer(transfer)

        var transfers = try await store.listProviderTransfers(providerID: nil)
        let restored = try XCTUnwrap(transfers.first)
        XCTAssertEqual(restored, transfer)

        let interruptedAt = Date(timeIntervalSinceReferenceDate: 75_000)
        try await store.markActiveProviderTransfersInterrupted(at: interruptedAt)
        transfers = try await store.listProviderTransfers(providerID: transfer.providerID)
        let interrupted = try XCTUnwrap(transfers.first)
        XCTAssertEqual(interrupted.status, .interrupted)
        XCTAssertTrue(interrupted.status.canRetry)
        XCTAssertEqual(interrupted.updatedAt, interruptedAt)
        XCTAssertTrue(interrupted.lastError?.contains("Retry") == true)
    }

    func testOpenRouterSpendUsesPersistedReceiptMetadataWithoutEstimation() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let conversation = try await store.createConversation(
            title: "Spend",
            defaultModelID: nil,
            defaultProviderID: nil
        )
        let now = Date(timeIntervalSinceReferenceDate: 90_000)
        try await store.appendMessage(
            ChatMessage(
                role: .assistant,
                content: "Reported",
                createdAt: now.addingTimeInterval(-60),
                providerMetadata: [
                    CloudProviderMetadataKeys.openRouterCostCredits: "0.004",
                    CloudProviderMetadataKeys.openRouterUpstreamInferenceCost: "0.003",
                    CloudProviderMetadataKeys.openRouterPromptTokens: "100",
                    CloudProviderMetadataKeys.openRouterCompletionTokens: "20",
                    CloudProviderMetadataKeys.openRouterWebSearchRequests: "2",
                    CloudProviderMetadataKeys.openRouterSelectedProvider: "Anthropic",
                ]
            ),
            status: .complete,
            conversationID: conversation.id,
            modelID: ModelID(rawValue: "openrouter/auto"),
            providerID: nil
        )
        try await store.appendMessage(
            ChatMessage(
                role: .assistant,
                content: "Missing provider cost",
                createdAt: now.addingTimeInterval(-30),
                providerMetadata: [
                    CloudProviderMetadataKeys.openRouterPromptTokens: "50",
                    CloudProviderMetadataKeys.openRouterCompletionTokens: "10",
                    CloudProviderMetadataKeys.openRouterProvider: "OpenAI",
                ]
            ),
            status: .complete,
            conversationID: conversation.id,
            modelID: ModelID(rawValue: "openrouter/auto"),
            providerID: nil
        )

        let report = try await store.openRouterSpendReport(window: .day, now: now)
        XCTAssertEqual(report.runCount, 2)
        XCTAssertEqual(report.reportedCostRunCount, 1)
        XCTAssertEqual(report.missingCostRunCount, 1)
        XCTAssertEqual(report.reportedCostCredits, 0.004, accuracy: 0.000_001)
        XCTAssertEqual(report.upstreamCostCredits, 0.003, accuracy: 0.000_001)
        XCTAssertEqual(report.promptTokens, 150)
        XCTAssertEqual(report.completionTokens, 30)
        XCTAssertEqual(report.webSearchRunCount, 1)
        XCTAssertEqual(report.byUpstreamProvider.map(\.providerName).sorted(), ["Anthropic", "OpenAI"])
    }

    func testCloudKitConversationConflictRequiresExplicitResolution() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let conversation = try await store.createConversation(
            title: "This device",
            defaultModelID: nil,
            defaultProviderID: nil
        )
        let cloudVersion = CloudKitConversationSnapshot(
            id: conversation.id,
            title: "From iCloud",
            updatedAt: Date().addingTimeInterval(60),
            deletedAt: nil,
            defaultModelID: nil,
            defaultProviderID: nil,
            projectID: nil,
            archived: false,
            pinned: false
        )

        try await store.applyCloudKitSnapshot(CloudKitRemoteSnapshot(conversations: [cloudVersion]))
        var unresolvedConflicts = try await store.listCloudKitConflicts(unresolvedOnly: true)
        var conflict = try XCTUnwrap(unresolvedConflicts.first)
        XCTAssertEqual(conflict.entityID, conversation.id)
        var restoredConversation = try await store.listConversations().first
        XCTAssertEqual(restoredConversation?.title, "This device")

        try await store.resolveCloudKitConflict(id: conflict.id, resolution: .keepDevice, at: Date())
        unresolvedConflicts = try await store.listCloudKitConflicts(unresolvedOnly: true)
        XCTAssertTrue(unresolvedConflicts.isEmpty)
        restoredConversation = try await store.listConversations().first
        XCTAssertEqual(restoredConversation?.title, "This device")

        try await store.applyCloudKitSnapshot(CloudKitRemoteSnapshot(conversations: [cloudVersion]))
        unresolvedConflicts = try await store.listCloudKitConflicts(unresolvedOnly: true)
        conflict = try XCTUnwrap(unresolvedConflicts.first)
        try await store.resolveCloudKitConflict(id: conflict.id, resolution: .useICloud, at: Date())
        unresolvedConflicts = try await store.listCloudKitConflicts(unresolvedOnly: true)
        XCTAssertTrue(unresolvedConflicts.isEmpty)
        restoredConversation = try await store.listConversations().first
        XCTAssertEqual(restoredConversation?.title, "From iCloud")

        try await store.updateConversationTitle("Edited after sync", conversationID: conversation.id)
        try await store.applyCloudKitSnapshot(
            CloudKitRemoteSnapshot(
                deletedRecords: [
                    CloudKitDeletedRecord(
                        recordType: "Conversation",
                        recordName: conversation.id.uuidString,
                        deletedAt: Date().addingTimeInterval(120)
                    ),
                ]
            )
        )
        unresolvedConflicts = try await store.listCloudKitConflicts(unresolvedOnly: true)
        conflict = try XCTUnwrap(unresolvedConflicts.first)
        XCTAssertTrue(conflict.iCloudSummary.contains("deleted"))
        restoredConversation = try await store.listConversations().first
        XCTAssertEqual(restoredConversation?.title, "Edited after sync")
    }

    func testHiddenAgentContextDoesNotLeakIntoConversationPreviewOrTokenCount() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let conversation = try await store.createConversation(
            title: "Context protocol",
            defaultModelID: nil,
            defaultProviderID: nil
        )
        let base = Date(timeIntervalSinceReferenceDate: 110_000)
        let visibleAnswer = ChatMessage(
            role: .assistant,
            content: "Visible answer",
            createdAt: base.addingTimeInterval(1)
        )
        try await store.appendMessage(
            ChatMessage(role: .user, content: "Question", createdAt: base),
            status: .complete,
            conversationID: conversation.id,
            modelID: nil,
            providerID: nil
        )
        try await store.appendMessage(
            visibleAnswer,
            status: .complete,
            conversationID: conversation.id,
            modelID: nil,
            providerID: nil
        )
        try await store.appendMessage(
            ChatMessage(
                role: .tool,
                content: "hidden secret output",
                createdAt: base.addingTimeInterval(2),
                toolCallID: "call-1",
                toolName: "lookup"
            ).asContextOnly(parentMessageID: visibleAnswer.id),
            status: .complete,
            conversationID: conversation.id,
            modelID: nil,
            providerID: nil
        )

        let previews = try await store.listConversationPreviews()
        let preview = try XCTUnwrap(previews.first { $0.id == conversation.id })
        XCTAssertEqual(preview.lastMessage, "Visible answer")
        XCTAssertEqual(preview.tokenCount, 3)
        let hiddenMatches = try await store.searchConversations(query: "secret", limit: 10)
        XCTAssertTrue(hiddenMatches.isEmpty)
    }

    func testProjectScopedVaultSearchCannotReturnAnotherProjectsChunks() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let selectedProject = try await store.createProject(name: "Selected")
        let otherProject = try await store.createProject(name: "Other")
        let selectedDocument = VaultDocumentRecord(
            title: "Selected notes",
            sourceType: "note",
            chunkCount: 0,
            projectID: selectedProject.id
        )
        let otherDocument = VaultDocumentRecord(
            title: "Other notes",
            sourceType: "note",
            chunkCount: 0,
            projectID: otherProject.id
        )
        try await store.upsertDocument(selectedDocument, localURL: nil, checksum: nil)
        try await store.upsertDocument(otherDocument, localURL: nil, checksum: nil)
        try await store.replaceChunks(
            [
                VaultChunk(
                    id: "selected-chunk",
                    sourceID: selectedDocument.id.uuidString,
                    ordinal: 0,
                    text: "orchid selected evidence",
                    startOffset: 0,
                    endOffset: 24,
                    checksum: "selected-checksum"
                ),
            ],
            documentID: selectedDocument.id,
            embeddingModelID: nil
        )
        try await store.replaceChunks(
            [
                VaultChunk(
                    id: "other-chunk",
                    sourceID: otherDocument.id.uuidString,
                    ordinal: 0,
                    text: "orchid other evidence",
                    startOffset: 0,
                    endOffset: 21,
                    checksum: "other-checksum"
                ),
            ],
            documentID: otherDocument.id,
            embeddingModelID: nil
        )

        let results = try await store.search(
            query: "orchid",
            embedding: nil,
            embeddingModelID: nil,
            profileID: nil,
            projectID: selectedProject.id,
            limit: 10
        )
        XCTAssertEqual(results.map(\.document.id), [selectedDocument.id])
        XCTAssertTrue(results.allSatisfy { $0.document.projectID == selectedProject.id })
    }

    private func makeStore() throws -> (GRDBPinesStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pines-production-ux-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "store.sqlite")), directory)
    }
}
