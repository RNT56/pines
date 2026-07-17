import Foundation
import XCTest
@testable import pines

final class ProviderMultipartBodyFileBuilderTests: XCTestCase {
    func testBuildStreamsSourceIntoFileBackedMultipartBody() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "provider-multipart-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appending(path: "source.bin")
        let source = Data(repeating: 0xA5, count: 2 * 1_024 * 1_024 + 17)
        try source.write(to: sourceURL)
        let bodyRoot = root.appending(path: "bodies", directoryHint: .isDirectory)
        let builder = ProviderMultipartBodyFileBuilder(rootURL: bodyRoot, copyChunkSize: 64 * 1_024)

        let body = try await builder.build(
            boundary: "PinesBoundary",
            fields: ["purpose": "assistants"],
            fileName: "source.bin",
            contentType: "application/octet-stream",
            sourceURL: sourceURL
        )

        let values = try body.url.resourceValues(forKeys: [.fileSizeKey])
        XCTAssertEqual(body.byteCount, Int64(values.fileSize ?? -1))
        XCTAssertGreaterThan(body.byteCount, Int64(source.count))

        let encoded = try Data(contentsOf: body.url)
        XCTAssertTrue(encoded.starts(with: Data("--PinesBoundary\r\n".utf8)))
        XCTAssertNotNil(encoded.range(of: Data("name=\"purpose\"\r\n\r\nassistants".utf8)))
        XCTAssertNotNil(encoded.range(of: source))
        let suffix = Data("\r\n--PinesBoundary--\r\n".utf8)
        XCTAssertEqual(encoded.suffix(suffix.count), suffix)

        await builder.remove(body)
        XCTAssertFalse(FileManager.default.fileExists(atPath: body.url.path))
    }

    func testHeaderTokensCannotInjectMultipartHeaders() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "provider-multipart-header-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appending(path: "source.txt")
        try Data("safe".utf8).write(to: sourceURL)
        let builder = ProviderMultipartBodyFileBuilder(rootURL: root.appending(path: "bodies"))

        let body = try await builder.build(
            boundary: "Boundary",
            fields: [:],
            fileFieldName: "file\r\nInjected: yes",
            fileName: "bad\"\r\nInjected: yes.txt",
            contentType: "text/plain\r\nInjected: yes",
            sourceURL: sourceURL
        )
        let encoded = try String(contentsOf: body.url, encoding: .utf8)

        XCTAssertFalse(encoded.contains("\r\nInjected: yes"))
        XCTAssertTrue(encoded.contains("name=\"file__Injected: yes\""))
        await builder.remove(body)
    }

    func testPurgeRemovesOnlyBodiesOlderThanCutoff() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "provider-multipart-purge-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appending(path: "old.multipart")
        let current = root.appending(path: "current.multipart")
        try Data("old".utf8).write(to: old)
        try Data("current".utf8).write(to: current)
        let cutoff = Date().addingTimeInterval(-60)
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(-60)],
            ofItemAtPath: old.path
        )
        let builder = ProviderMultipartBodyFileBuilder(rootURL: root)

        let removed = try await builder.purge(olderThan: cutoff)

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
    }
}
