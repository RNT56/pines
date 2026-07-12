import Foundation
import XCTest
import PinesCore
@testable import pines

final class MCPToolAnnotationPersistenceTests: XCTestCase {
    func testToolSafetyAnnotationsSurviveDiscoveryPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pines-mcp-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "store.sqlite"))
        let serverID = MCPServerID(rawValue: "safety-test")
        try await store.upsertMCPServer(
            MCPServerConfiguration(
                id: serverID,
                displayName: "Safety Test",
                endpointURL: URL(string: "https://example.com/mcp")!,
                keychainAccount: "safety-test"
            )
        )
        let annotations = MCPToolAnnotations(
            title: "Delete item",
            readOnlyHint: false,
            destructiveHint: true,
            idempotentHint: false,
            openWorldHint: true
        )
        try await store.replaceMCPTools(
            [
                MCPToolRecord(
                    serverID: serverID,
                    originalName: "delete_item",
                    namespacedName: "mcp.safety-test.delete-item",
                    displayName: "Delete item",
                    description: "Deletes a remote item.",
                    inputSchema: .objectSchema(),
                    annotations: annotations
                ),
            ],
            serverID: serverID
        )

        let restored = try await store.listMCPTools(serverID: serverID)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].annotations, annotations)
        XCTAssertEqual(restored[0].annotations?.sideEffectLevel, .sensitive)
    }
}
