import Foundation
import XCTest
@testable import pines

final class ProviderTransferFileServiceTests: XCTestCase {
    func testProgressGateBoundsMainActorUpdateFanOut() {
        let gate = ProviderTransferProgressGate()
        let totalBytes = Int64(100 * 1_024 * 1_024)
        var emitted = 0

        for step in 1 ... 10_000 {
            let completed = totalBytes * Int64(step) / 10_000
            if gate.shouldEmit(completedBytes: completed, totalBytes: totalBytes) {
                emitted += 1
            }
        }

        XCTAssertLessThanOrEqual(emitted, 101)
        XCTAssertFalse(gate.shouldEmit(completedBytes: totalBytes, totalBytes: totalBytes))
    }

    func testStagesAndReadsFileWithinOwnedTransferDirectory() async throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let source = temporaryRoot.appending(path: "source.txt")
        let payload = Data(repeating: 0x50, count: 512 * 1_024 + 17)
        try payload.write(to: source)
        let stagingRoot = temporaryRoot.appending(path: "staging", directoryHint: .isDirectory)
        let service = ProviderTransferFileService(rootURL: stagingRoot, copyChunkSize: 64 * 1_024)
        let transferID = UUID()

        let staged = try await service.stage(sourceURL: source, transferID: transferID)

        XCTAssertEqual(staged.byteCount, Int64(payload.count))
        XCTAssertEqual(staged.url.deletingLastPathComponent().lastPathComponent, transferID.uuidString)
        let restored = try await service.readData(from: staged.url)
        let existsBeforeRemoval = await service.fileExists(at: staged.url)
        XCTAssertEqual(restored, payload)
        XCTAssertTrue(existsBeforeRemoval)

        try await service.removeStagedTransfer(containing: staged.url)
        let existsAfterRemoval = await service.fileExists(at: staged.url)
        XCTAssertFalse(existsAfterRemoval)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testReadHonorsMaximumByteLimit() async throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let file = temporaryRoot.appending(path: "bounded.bin")
        try Data(repeating: 0xAA, count: 4_096).write(to: file)
        let service = ProviderTransferFileService(rootURL: temporaryRoot.appending(path: "staging"))

        do {
            _ = try await service.readData(from: file, maximumBytes: 1_024)
            XCTFail("Expected an oversized file to be rejected")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileReadTooLarge)
        }
    }

    func testRejectsNonFileSourcesAndRemovalOutsideOwnedRoot() async throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let stagingRoot = temporaryRoot.appending(path: "staging", directoryHint: .isDirectory)
        let service = ProviderTransferFileService(rootURL: stagingRoot)

        do {
            _ = try await service.stage(sourceURL: temporaryRoot, transferID: UUID())
            XCTFail("Expected a directory source to be rejected")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileReadUnsupportedScheme)
        }

        let outside = temporaryRoot.appending(path: "outside/file.txt")
        do {
            try await service.removeStagedTransfer(containing: outside)
            XCTFail("Expected removal outside the staging root to be rejected")
        } catch let error as CocoaError {
            XCTAssertEqual(error.code, .fileWriteNoPermission)
        }
    }

    func testRemovesOnlyStaleTransferDirectories() async throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let stagingRoot = temporaryRoot.appending(path: "staging", directoryHint: .isDirectory)
        let oldDirectory = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let currentDirectory = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: oldDirectory.path
        )
        let service = ProviderTransferFileService(rootURL: stagingRoot)

        let removed = try await service.removeStaleTransfers(olderThan: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDirectory.path))
    }

    func testInspectsAndStagesTextPagesWithoutJoiningWholeDocument() async throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let service = ProviderTransferFileService(
            rootURL: temporaryRoot.appending(path: "staging"),
            copyChunkSize: 64 * 1_024
        )
        let pages = [
            ["one", "two"],
            ["three", "four"],
            ["five"],
        ]

        let staged = try await service.stageTextPages(
            transferID: UUID(),
            fileName: "vault.txt",
            pageSize: 2
        ) { limit, offset in
            let flattened = pages.flatMap { $0 }
            let start = min(max(0, offset), flattened.count)
            let end = min(flattened.count, start + limit)
            return Array(flattened[start..<end])
        }

        let inspected = try await service.inspect(staged.url)
        let data = try await service.readData(from: staged.url)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "one\n\ntwo\n\nthree\n\nfour\n\nfive")
        XCTAssertEqual(staged.byteCount, Int64(data.count))
        XCTAssertEqual(inspected.byteCount, staged.byteCount)

        try await service.removeStagedTransfer(containing: staged.url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ProviderTransferFileServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
