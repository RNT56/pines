import Foundation
import XCTest
import PinesCore
@testable import pines

final class ProviderArtifactPaginationTests: XCTestCase {
    func testRecentArtifactsUseStableCreatedAtAndIDCursor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "provider-artifact-page-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "store.sqlite"))
        let timestamp = Date(timeIntervalSinceReferenceDate: 100_000)
        let records = [
            artifact(id: "a", createdAt: timestamp.addingTimeInterval(-1)),
            artifact(id: "b", createdAt: timestamp),
            artifact(id: "c", createdAt: timestamp),
            artifact(id: "d", createdAt: timestamp.addingTimeInterval(1)),
        ]
        for record in records {
            try await store.upsertProviderArtifact(record)
        }

        let firstPage = try await store.listRecentProviderArtifacts(limit: 2, before: nil)
        XCTAssertEqual(firstPage.map(\.id), ["d", "c"])

        let cursorRecord = try XCTUnwrap(firstPage.last)
        let cursor = ProviderArtifactCursor(createdAt: cursorRecord.createdAt, id: cursorRecord.id)
        let secondPage = try await store.listRecentProviderArtifacts(limit: 2, before: cursor)
        XCTAssertEqual(secondPage.map(\.id), ["b", "a"])

        let restored = try await store.providerArtifact(id: "b")
        let missing = try await store.providerArtifact(id: "missing")
        XCTAssertEqual(restored?.id, "b")
        XCTAssertNil(missing)
    }

    func testPaginationMigrationAddsCreatedAtIndex() {
        let migration = PinesDatabaseSchema.migrations.first { $0.version == 29 }
        XCTAssertEqual(migration?.name, "provider-artifact-pagination")
        XCTAssertTrue(migration?.sql.contains(where: { $0.contains("idx_provider_artifacts_created") }) == true)
    }

    func testProviderLifecycleRepositoryLimitsAreAppliedBeforeMaterialization() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "provider-lifecycle-limit-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "store.sqlite"))
        let providerID = ProviderID(rawValue: "provider-a")
        let timestamp = Date(timeIntervalSinceReferenceDate: 200_000)

        for id in ["a", "b", "c"] {
            try await store.upsertProviderFile(
                ProviderFileRecord(
                    id: id,
                    providerID: providerID,
                    providerKind: .openAI,
                    purpose: "assistants",
                    fileName: "\(id).txt",
                    status: "processed",
                    createdAt: timestamp
                )
            )
        }
        let repository: any ProviderFileRepository = store
        let limited = try await repository.listProviderFiles(providerID: nil, limit: 2)

        XCTAssertEqual(limited.map(\.id), ["c", "b"])
    }

    func testProviderLifecycleBoundedListMigrationAddsHotPathIndexes() {
        let migration = PinesDatabaseSchema.migrations.first { $0.version == 31 }
        XCTAssertEqual(migration?.name, "provider-lifecycle-bounded-lists")
        XCTAssertTrue(migration?.sql.contains(where: { $0.contains("idx_provider_files_recent") }) == true)
        XCTAssertTrue(migration?.sql.contains(where: { $0.contains("idx_provider_transfers_recent") }) == true)
        XCTAssertTrue(migration?.sql.contains(where: { $0.contains("idx_provider_research_runs_recent") }) == true)
    }

    private func artifact(id: String, createdAt: Date) -> ProviderArtifactRecord {
        ProviderArtifactRecord(
            id: id,
            providerKind: .openAI,
            kind: "image",
            fileName: "\(id).png",
            createdAt: createdAt
        )
    }
}
