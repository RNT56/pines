import Foundation
import XCTest
import PinesCore
@testable import pines

final class CloudModelCatalogPersistenceTests: XCTestCase {
    func testCatalogSnapshotRoundTripsReplacesAndCascadesWithProvider() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pines-catalog-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try GRDBPinesStore.makeTestingStore(at: directory.appending(path: "store.sqlite"))
        let provider = CloudProviderConfiguration(
            id: "openrouter-test",
            kind: .openRouter,
            displayName: "OpenRouter Test",
            baseURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1")),
            keychainAccount: "openrouter-test"
        )
        try await store.upsertProvider(provider)

        let fetchedAt = Date(timeIntervalSinceReferenceDate: 50_000)
        let first = CloudProviderModelCatalogSnapshot(
            providerID: provider.id,
            models: [
                CloudProviderModel(
                    id: "example/first",
                    displayName: "First",
                    metadata: CloudProviderModelMetadata(
                        inputModalities: ["text", "image"],
                        outputModalities: ["text"],
                        contextLength: 131_072,
                        pricing: CloudProviderModelPricing(
                            prompt: Decimal(string: "0.00000015"),
                            completion: Decimal(string: "0.0000006")
                        )
                    )
                ),
            ],
            fetchedAt: fetchedAt,
            expiresAt: fetchedAt.addingTimeInterval(3_600)
        )
        try await store.upsertModelCatalogSnapshot(first)

        let restoredFirst = try await store.listModelCatalogSnapshots()
        XCTAssertEqual(restoredFirst, [first])

        let replacement = CloudProviderModelCatalogSnapshot(
            providerID: provider.id,
            models: [CloudProviderModel(id: "example/replacement", displayName: "Replacement")],
            fetchedAt: fetchedAt.addingTimeInterval(60),
            expiresAt: fetchedAt.addingTimeInterval(7_200)
        )
        try await store.upsertModelCatalogSnapshot(replacement)
        let restoredReplacement = try await store.listModelCatalogSnapshots()
        XCTAssertEqual(restoredReplacement, [replacement])

        try await store.deleteProvider(id: provider.id)
        let restoredAfterDelete = try await store.listModelCatalogSnapshots()
        XCTAssertTrue(restoredAfterDelete.isEmpty)
    }
}
