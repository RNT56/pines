import Foundation
import PinesCore
import Testing

@Suite("Snapshot security policy")
struct SnapshotSecurityPolicyTests {
    @Test func defaultsAreEncryptedLocalOnlyAndDeletionScoped() throws {
        let policy = SnapshotSecurityPolicy.deviceDefault(deviceClass: .a17Pro)

        try policy.validateForLocalSnapshotStore()
        #expect(policy.encryptedAtRest)
        #expect(policy.keySource == SnapshotSecurityPolicy.keychainLocalKeySource)
        #expect(!policy.cloudSyncAllowed)
        #expect(policy.atomicWriteRequired)
        #expect(policy.partialWriteQuarantine)
        #expect(policy.deleteOnModelDeletion)
        #expect(policy.deleteOnDataErasure)
        #expect(policy.quotaBytes == 512 * 1_024 * 1_024)
    }

    @Test func policyRejectsCloudSyncAndNonLocalKeysFailClosed() {
        var cloudSync = SnapshotSecurityPolicy.deviceDefault()
        cloudSync.cloudSyncAllowed = true
        #expect(throws: TurboQuantKVSnapshotValidationFailure.securityPolicyRejected("snapshots must be excluded from cloud sync")) {
            try cloudSync.validateForLocalSnapshotStore()
        }

        var wrongKey = SnapshotSecurityPolicy.deviceDefault()
        wrongKey.keySource = "cloud-synchronizable-key"
        #expect(throws: TurboQuantKVSnapshotValidationFailure.securityPolicyRejected("snapshots must use a Keychain-backed local key")) {
            try wrongKey.validateForLocalSnapshotStore()
        }
    }

    @Test func unsupportedPolicySchemaFailsClosed() {
        let policy = SnapshotSecurityPolicy(schemaVersion: 999)

        #expect(throws: TurboQuantKVSnapshotValidationFailure.unsupportedSchema(name: "SnapshotSecurityPolicy", version: 999)) {
            try policy.validateForLocalSnapshotStore()
        }
    }

    @Test func manifestIdentityValidationRejectsMismatchBeforeRestore() throws {
        let manifest = Self.manifest()
        var expected = manifest.identity
        expected.tokenPrefixHash = "different-prefix"

        #expect(throws: TurboQuantKVSnapshotValidationFailure.tokenPrefixHashMismatch(expected: "different-prefix", actual: "prefix-hash")) {
            try manifest.validateForRestore(
                expectedIdentity: expected,
                policy: .deviceDefault(),
                restoreGate: .enabled()
            )
        }
    }

    @Test func restoreIsDisabledByDefaultWhileCompatibilityPairIsPending() throws {
        let manifest = Self.manifest()

        #expect(throws: TurboQuantKVSnapshotValidationFailure.restoreDisabled("compatibility-pair pending")) {
            try manifest.validateForRestore(expectedIdentity: manifest.identity)
        }
    }

    @Test func manifestAndPolicyRoundTripCodable() throws {
        try roundTrip(SnapshotSecurityPolicy.deviceDefault(deviceClass: .mSeriesTabletPro))
        try roundTrip(Self.manifest())
    }

    private static func manifest() -> TurboQuantKVSnapshotManifest {
        TurboQuantKVSnapshotManifest(
            snapshotID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            conversationID: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
            modelID: "mlx-community/test-model",
            modelRevision: "rev-a",
            tokenizerHash: "tokenizer-hash",
            profileHash: "profile-hash",
            turboQuantLayoutVersion: 4,
            ropeConfigHash: "rope-hash",
            tokenPrefixHash: "prefix-hash",
            fallbackContractHash: "fallback-hash",
            logicalLength: 128,
            pinnedPrefixLength: 32,
            compressedKeyBytes: 256,
            compressedValueBytes: 256,
            blobByteCount: 512,
            encryptionKeyID: "blob-aes-gcm-v1",
            createdAt: Date(timeIntervalSinceReferenceDate: 10)
        )
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        #expect(decoded == value)
    }
}
