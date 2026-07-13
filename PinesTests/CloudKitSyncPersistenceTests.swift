import Foundation
import XCTest
import PinesCore
@testable import pines

final class CloudKitSyncPersistenceTests: XCTestCase {
    func testProjectAssignmentsRoundTripAndDeleteAcrossCloudKitSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pines-cloudkit-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "source.sqlite"))
        let target = try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "target.sqlite"))

        let project = try await source.createProject(name: "Synced project")
        let conversation = try await source.createConversation(
            title: "Project chat",
            defaultModelID: nil,
            defaultProviderID: nil,
            projectID: project.id
        )
        let document = VaultDocumentRecord(
            title: "Project note",
            sourceType: "note",
            chunkCount: 0,
            projectID: project.id
        )
        try await source.upsertDocument(document, localURL: nil, checksum: "test")

        let initial = try await source.cloudKitLocalSnapshot(
            includeVault: true,
            includeEmbeddings: false,
            includeClean: true
        )
        XCTAssertEqual(initial.projects.map(\.id), [project.id])
        XCTAssertEqual(initial.conversations.first(where: { $0.id == conversation.id })?.projectID, project.id)
        XCTAssertEqual(initial.documents.first(where: { $0.id == document.id })?.projectID, project.id)

        try await target.applyCloudKitSnapshot(Self.remoteSnapshot(from: initial))
        let targetProjectIDs = try await target.listProjects().map(\.id)
        let targetConversation = try await target.listConversations().first(where: { $0.id == conversation.id })
        let targetDocument = try await target.listDocuments().first(where: { $0.id == document.id })
        XCTAssertEqual(targetProjectIDs, [project.id])
        XCTAssertEqual(
            targetConversation?.projectID,
            project.id
        )
        XCTAssertEqual(
            targetDocument?.projectID,
            project.id
        )

        try await source.deleteProject(id: project.id)
        let deletion = try await source.cloudKitLocalSnapshot(
            includeVault: true,
            includeEmbeddings: false,
            includeClean: false
        )
        XCTAssertNotNil(deletion.projects.first(where: { $0.id == project.id })?.deletedAt)

        try await target.applyCloudKitSnapshot(Self.remoteSnapshot(from: deletion))
        let remainingProjects = try await target.listProjects()
        let unlinkedConversation = try await target.listConversations().first(where: { $0.id == conversation.id })
        let unlinkedDocument = try await target.listDocuments().first(where: { $0.id == document.id })
        XCTAssertTrue(remainingProjects.isEmpty)
        XCTAssertNil(unlinkedConversation?.projectID)
        XCTAssertNil(unlinkedDocument?.projectID)
    }

    private static func remoteSnapshot(from local: CloudKitLocalSnapshot) -> CloudKitRemoteSnapshot {
        CloudKitRemoteSnapshot(
            settings: local.settings,
            projects: local.projects,
            conversations: local.conversations,
            messages: local.messages,
            documents: local.documents,
            chunks: local.chunks,
            embeddings: local.embeddings,
            deletedRecords: [],
            serverChangeTokenData: nil
        )
    }
}
