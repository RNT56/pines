import Foundation
import XCTest
import PinesCore
@testable import pines

final class ChatRenderingPerformanceTests: XCTestCase {
    func testCitationMetadataDecodesOffRenderPathAndSurvivesPurge() async throws {
        let expected = [WebSearchCitation(title: "Pines", url: "https://example.com/pines", source: "Example")]
        let raw = String(data: try JSONEncoder().encode(expected), encoding: .utf8) ?? ""

        let first = await PinesChatMetadataCache.shared.webSearchCitations(rawJSON: raw)
        let cached = await PinesChatMetadataCache.shared.webSearchCitations(rawJSON: raw)
        await PinesChatRenderCaches.purge()
        let afterPurge = await PinesChatMetadataCache.shared.webSearchCitations(rawJSON: raw)

        XCTAssertEqual(first, expected)
        XCTAssertEqual(cached, expected)
        XCTAssertEqual(afterPurge, expected)
    }

    func testChatSourceAvoidsForcedReloadAndUnchangedWebViewLoads() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(path: "Pines/Views/Chats/ChatsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("force: false"))
        XCTAssertFalse(source.contains("force: !thread.messages.isEmpty"))
        XCTAssertTrue(source.contains("guard context.coordinator.loadedHTML != html else { return }"))
        XCTAssertTrue(source.contains("PinesChatMetadataCache.shared.webSearchCitations"))
    }

    func testMarkdownDigestsAreNotComputedInViewTaskIdentifiers() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(path: "Pines/Views/Chats/MarkdownMessageView.swift"),
            encoding: .utf8
        )

        let renderIDStart = try XCTUnwrap(source.range(of: "private var renderTaskID"))
        let renderIDEnd = try XCTUnwrap(source.range(of: "var body:", range: renderIDStart.upperBound..<source.endIndex))
        let renderIDBody = source[renderIDStart.lowerBound..<renderIDEnd.lowerBound]
        XCTAssertFalse(renderIDBody.contains("stableMarkdownDigest"))
        XCTAssertFalse(renderIDBody.contains("content: content"))
        XCTAssertTrue(renderIDBody.contains("revision: renderRevision"))
        XCTAssertTrue(source.contains("revision: highlightRevision"))
        XCTAssertTrue(source.contains("cache.totalCostLimit = 12 * 1_024 * 1_024"))
        XCTAssertTrue(source.contains("totalCost > totalCostLimit"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
