import Foundation
import PinesCore
import Testing

@Suite("TurboQuant KV snapshot store")
struct TurboQuantKVSnapshotStoreTests {
    @Test func validSnapshotRestoreRequiresExplicitGate() async throws {
        let store = TurboQuantKVSnapshotStore(policy: .init(quotaBytes: 4_096))
        let manifest = Self.manifest(blobByteCount: 64)
        _ = try await store.store(Self.request(manifest: manifest))

        let disabled = await store.restoreDecision(
            conversationID: manifest.conversationID,
            expectedIdentity: manifest.identity
        )
        #expect(disabled == .rejected(.restoreDisabled("compatibility-pair pending")))

        let enabled = await store.restoreDecision(
            conversationID: manifest.conversationID,
            expectedIdentity: manifest.identity,
            restoreGate: .enabled()
        )
        #expect(enabled == .accepted(manifest))

        let attempts = await store.allRestoreAttempts()
        #expect(attempts.map(\.result).contains(.disabled))
        #expect(attempts.map(\.result).contains(.accepted))
    }

    @Test func prefixMismatchRejectsWithoutQuarantine() async throws {
        let store = TurboQuantKVSnapshotStore(policy: .init(quotaBytes: 4_096))
        let manifest = Self.manifest(blobByteCount: 64)
        _ = try await store.store(Self.request(manifest: manifest))
        var expected = manifest.identity
        expected.tokenPrefixHash = "new-prefix"

        let decision = await store.restoreDecision(
            conversationID: manifest.conversationID,
            expectedIdentity: expected,
            restoreGate: .enabled()
        )

        #expect(decision == .rejected(.tokenPrefixHashMismatch(expected: "new-prefix", actual: manifest.tokenPrefixHash)))
        #expect(await store.allQuarantines().isEmpty)
    }

    @Test func partialWriteQuarantinesAndDoesNotBecomeActive() async throws {
        let store = TurboQuantKVSnapshotStore(policy: .init(quotaBytes: 4_096))
        let manifest = Self.manifest(blobByteCount: 64)

        let outcome = try await store.store(
            Self.request(
                manifest: manifest,
                encryptedBlob: Data(repeating: 0x0f, count: 16),
                writeCompletedAtomically: false
            )
        )

        #expect(outcome.disposition == .quarantined)
        #expect(outcome.quarantine?.reason == "partial_write")
        #expect(await store.allManifests().isEmpty)
        #expect(await store.allQuarantines().count == 1)
    }

    @Test func corruptedBlobQuarantinesOnRestore() async throws {
        let store = TurboQuantKVSnapshotStore(policy: .init(quotaBytes: 4_096))
        let manifest = Self.manifest(blobByteCount: 64)
        _ = try await store.store(Self.request(manifest: manifest))
        await store.simulateBlobCorruption(snapshotID: manifest.snapshotID, bytes: Data(repeating: 0xaa, count: 64))

        let decision = await store.restoreDecision(
            conversationID: manifest.conversationID,
            expectedIdentity: manifest.identity,
            restoreGate: .enabled()
        )
        let quarantines = await store.allQuarantines()

        #expect(quarantines.first?.stage == .integrity)
        #expect(quarantines.first?.snapshotID == manifest.snapshotID)
        if case .quarantined(let quarantine) = decision {
            #expect(quarantine.snapshotID == manifest.snapshotID)
        } else {
            Issue.record("Expected corrupted snapshot to quarantine.")
        }
    }

    @Test func quotaEvictsOldUnpinnedSnapshots() async throws {
        let store = TurboQuantKVSnapshotStore(policy: .init(quotaBytes: 10))
        let first = Self.manifest(
            snapshotID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            blobByteCount: 4,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let second = Self.manifest(
            snapshotID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            blobByteCount: 4,
            createdAt: Date(timeIntervalSinceReferenceDate: 2)
        )
        let third = Self.manifest(
            snapshotID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            blobByteCount: 4,
            createdAt: Date(timeIntervalSinceReferenceDate: 3)
        )

        _ = try await store.store(Self.request(manifest: first, encryptedBlob: Self.blob(byteCount: 4, seed: 1)))
        _ = try await store.store(Self.request(manifest: second, encryptedBlob: Self.blob(byteCount: 4, seed: 2)))
        let outcome = try await store.store(Self.request(manifest: third, encryptedBlob: Self.blob(byteCount: 4, seed: 3)))

        let activeManifests = await store.allManifests()
        let activeIDs = Set(activeManifests.map(\.snapshotID))
        #expect(outcome.evictedSnapshotIDs == [first.snapshotID])
        #expect(!activeIDs.contains(first.snapshotID))
        #expect(activeIDs.contains(second.snapshotID))
        #expect(activeIDs.contains(third.snapshotID))
    }

    @Test func modelDeletionAndDataErasureDeleteSnapshots() async throws {
        let store = TurboQuantKVSnapshotStore(policy: .init(quotaBytes: 4_096))
        let first = Self.manifest(modelID: "model-a", blobByteCount: 64)
        let second = Self.manifest(
            snapshotID: UUID(uuidString: "00000000-0000-4000-8000-000000000222")!,
            modelID: "model-b",
            blobByteCount: 64
        )
        _ = try await store.store(Self.request(manifest: first))
        _ = try await store.store(Self.request(manifest: second))

        let deletedForModel = await store.deleteSnapshots(modelID: "model-a")
        #expect(deletedForModel == [first.snapshotID])
        let remainingManifests = await store.allManifests()
        let remainingAfterModelDeletion = remainingManifests.map(\.snapshotID)
        #expect(remainingAfterModelDeletion == [second.snapshotID])

        let deletedForErasure = await store.deleteAllSnapshots(reason: "data_erasure")
        #expect(deletedForErasure == [second.snapshotID])
        #expect(await store.allManifests().isEmpty)
        let quarantines = await store.allQuarantines()
        #expect(quarantines.contains { $0.stage == .deletion && $0.reason == "data_erasure" })
    }

    private static func request(
        manifest: TurboQuantKVSnapshotManifest,
        encryptedBlob: Data? = nil,
        writeCompletedAtomically: Bool = true
    ) -> TurboQuantKVSnapshotWriteRequest {
        TurboQuantKVSnapshotWriteRequest(
            manifest: manifest,
            encryptedBlob: encryptedBlob ?? blob(byteCount: Int(manifest.blobByteCount), seed: 7),
            writeCompletedAtomically: writeCompletedAtomically,
            createdAt: manifest.createdAt
        )
    }

    private static func manifest(
        snapshotID: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000111")!,
        conversationID: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000999")!,
        modelID: String = "mlx-community/test-model",
        blobByteCount: Int64,
        createdAt: Date = Date(timeIntervalSinceReferenceDate: 10)
    ) -> TurboQuantKVSnapshotManifest {
        TurboQuantKVSnapshotManifest(
            snapshotID: snapshotID,
            conversationID: conversationID,
            modelID: modelID,
            modelRevision: "rev-a",
            tokenizerHash: "tokenizer-hash",
            profileHash: "profile-hash",
            turboQuantLayoutVersion: 4,
            ropeConfigHash: "rope-hash",
            tokenPrefixHash: "prefix-hash",
            fallbackContractHash: "fallback-hash",
            logicalLength: 128,
            pinnedPrefixLength: 32,
            compressedKeyBytes: max(1, blobByteCount / 2),
            compressedValueBytes: max(1, blobByteCount / 2),
            blobByteCount: blobByteCount,
            encryptionKeyID: "blob-aes-gcm-v1",
            createdAt: createdAt
        )
    }

    private static func blob(byteCount: Int, seed: UInt8) -> Data {
        Data((0..<byteCount).map { UInt8((Int(seed) + $0) % 255) })
    }
}
