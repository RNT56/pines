import Foundation
import XCTest
import PinesCore
@testable import pines

final class VaultDetailPerformanceTests: XCTestCase {
    func testDocumentDetailQueriesArePagedAndCountWithoutLoadingEmbeddings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "vault-detail-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "store.sqlite"))
        let document = VaultDocumentRecord(title: "Large note", sourceType: "note", chunkCount: 0)
        try await store.upsertDocument(document, localURL: nil, checksum: nil)
        let chunks = (0..<75).map { ordinal in
            VaultChunk(
                id: "chunk-\(ordinal)",
                sourceID: document.id.uuidString,
                ordinal: ordinal,
                text: "Chunk \(ordinal)",
                startOffset: ordinal * 10,
                endOffset: ordinal * 10 + 9,
                checksum: "checksum-\(ordinal)"
            )
        }
        try await store.replaceChunks(chunks, documentID: document.id, embeddingModelID: nil)

        let firstPage = try await store.chunks(documentID: document.id, limit: 32, offset: 0)
        let secondPage = try await store.chunks(documentID: document.id, limit: 32, offset: 32)
        let restoredDocument = try await store.document(id: document.id)
        let embeddingCount = try await store.embeddingCount(documentID: document.id, profileID: "missing")
        let byteCount = try await store.chunkUTF8ByteCount(documentID: document.id)

        XCTAssertEqual(firstPage.map(\.ordinal), Array(0..<32))
        XCTAssertEqual(secondPage.map(\.ordinal), Array(32..<64))
        XCTAssertEqual(restoredDocument?.chunkCount, 75)
        XCTAssertEqual(embeddingCount, 0)
        XCTAssertEqual(byteCount, Int64(chunks.reduce(0) { $0 + $1.text.utf8.count }))
    }

    func testVaultDetailMigrationAddsPagedQueryIndexes() {
        let migration = PinesDatabaseSchema.migrations.first { $0.version == 30 }
        XCTAssertEqual(migration?.name, "vault-detail-queries")
        XCTAssertEqual(migration?.sql.count, 2)
    }

    func testLargeEncryptedSourcesAreRejectedBeforePreviewDecryption() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Pines/App/PinesAppModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("VaultDetailPerformance.authenticatedEncryptionOverheadAllowance"))
        XCTAssertTrue(source.contains("ProviderTransferFileService.shared.inspect(localURL)"))
        XCTAssertTrue(source.contains("guard let data = try? await store.read(metadata)"))
        let inspectRange = try XCTUnwrap(source.range(of: "ProviderTransferFileService.shared.inspect(localURL)"))
        let decryptRange = try XCTUnwrap(source.range(of: "store.read(metadata)"))
        XCTAssertLessThan(inspectRange.lowerBound, decryptRange.lowerBound)
    }
}
