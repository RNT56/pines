import Combine
import PinesCore
import XCTest
@testable import pines

@MainActor
final class ProviderLifecycleSnapshotTests: XCTestCase {
    func testBulkSnapshotApplyPublishesOnceAndDeduplicatesEqualState() {
        let state = PinesProviderLifecycleState()
        var publicationCount = 0
        let cancellable = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { cancellable.cancel() }

        var snapshot = state.snapshot
        snapshot.isRefreshing = true
        snapshot.error = "Loading"
        state.apply(snapshot)

        XCTAssertEqual(publicationCount, 1)
        XCTAssertTrue(state.isRefreshingProviderLifecycle)
        XCTAssertEqual(state.providerLifecycleError, "Loading")

        state.apply(snapshot)
        XCTAssertEqual(publicationCount, 1)
    }

    func testCompatibilityPropertiesUpdateTheSharedSnapshot() {
        let state = PinesProviderLifecycleState()
        state.providerLifecycleError = "Offline"

        XCTAssertEqual(state.snapshot.error, "Offline")
        XCTAssertEqual(state.providerLifecycleError, "Offline")

        state.providerLifecycleError = "Offline"
        XCTAssertEqual(state.snapshot.error, "Offline")
    }

    func testStatusMetadataUpdateDoesNotStrandAnActiveRefresh() {
        let state = PinesProviderLifecycleState()
        let generation = state.beginRefresh()
        state.providerLifecycleError = "A concurrent operation failed"

        var refreshed = state.snapshot
        refreshed.providerArtifacts = [
            ProviderArtifactRecord(
                id: "artifact-refreshed",
                providerID: ProviderID(rawValue: "provider-a"),
                providerKind: .openAI,
                kind: "image",
                createdAt: Date(timeIntervalSinceReferenceDate: 10)
            ),
        ]

        XCTAssertTrue(state.completeRefresh(refreshed, generation: generation))
        XCTAssertFalse(state.isRefreshingProviderLifecycle)
        XCTAssertNil(state.providerLifecycleError)
        XCTAssertEqual(state.providerArtifacts.map(\.id), ["artifact-refreshed"])
    }

    func testIncrementalArtifactUpsertPublishesOnceAndPreservesUnrelatedDomains() {
        let providerID = ProviderID(rawValue: "provider-a")
        let file = ProviderFileRecord(
            id: "file-a",
            providerID: providerID,
            providerKind: .openAI,
            purpose: "assistants",
            fileName: "context.txt",
            status: "processed",
            createdAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let cache = ProviderCacheRecord(
            id: "cache-a",
            providerID: providerID,
            providerKind: .openAI,
            kind: "vector_store",
            status: "completed",
            createdAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        let state = PinesProviderLifecycleState(
            providerFiles: [file],
            providerCaches: [cache],
            providerVectorStores: [cache],
            isRefreshingProviderLifecycle: true,
            providerLifecycleError: "stale error"
        )
        let model = PinesAppModel(providerLifecycleState: state)
        var publicationCount = 0
        let cancellable = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { cancellable.cancel() }

        let older = ProviderArtifactRecord(
            id: "artifact-a",
            providerID: providerID,
            providerKind: .openAI,
            kind: "image",
            createdAt: Date(timeIntervalSinceReferenceDate: 30)
        )
        let newer = ProviderArtifactRecord(
            id: "artifact-b",
            providerID: providerID,
            providerKind: .openAI,
            kind: "image",
            createdAt: Date(timeIntervalSinceReferenceDate: 40)
        )
        model.upsertProviderArtifactRecords([older, newer])

        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(state.providerArtifacts.map(\.id), ["artifact-b", "artifact-a"])
        XCTAssertEqual(state.providerArtifactPreviews.map(\.id), ["artifact-b", "artifact-a"])
        XCTAssertEqual(state.providerFiles, [file])
        XCTAssertEqual(state.providerCaches, [cache])
        XCTAssertEqual(state.providerVectorStores, [cache])
        XCTAssertFalse(state.isRefreshingProviderLifecycle)
        XCTAssertNil(state.providerLifecycleError)
        XCTAssertEqual(state.snapshot.artifactLibraryRevision, 1)
    }

    func testUnrelatedLifecycleMutationDoesNotAdvanceArtifactLibraryRevision() {
        let state = PinesProviderLifecycleState()
        let initialRevision = state.snapshot.artifactLibraryRevision

        state.updateIncrementally { snapshot in
            snapshot.error = "Transfer failed"
        }

        XCTAssertEqual(state.snapshot.artifactLibraryRevision, initialRevision)
    }

    func testStaleFullRefreshCannotOverwriteNewerIncrementalMutation() {
        let providerID = ProviderID(rawValue: "provider-a")
        let original = ProviderArtifactRecord(
            id: "artifact-original",
            providerID: providerID,
            providerKind: .openAI,
            kind: "image",
            createdAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let state = PinesProviderLifecycleState(providerArtifacts: [original])
        let model = PinesAppModel(providerLifecycleState: state)

        let staleGeneration = state.beginRefresh()
        var staleSnapshot = state.snapshot
        staleSnapshot.providerArtifacts = [original]

        let newer = ProviderArtifactRecord(
            id: "artifact-newer",
            providerID: providerID,
            providerKind: .openAI,
            kind: "image",
            createdAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        model.upsertProviderArtifactRecords([newer])

        XCTAssertFalse(state.completeRefresh(staleSnapshot, generation: staleGeneration))
        XCTAssertEqual(state.providerArtifacts.map(\.id), ["artifact-newer", "artifact-original"])
        XCTAssertFalse(state.isRefreshingProviderLifecycle)
    }
}
