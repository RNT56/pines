import CryptoKit
import CryptoKit
import Foundation

public struct TurboQuantKVSnapshotIdentity: Hashable, Codable, Sendable {
    public var modelID: String
    public var modelRevision: String?
    public var tokenizerHash: String
    public var profileHash: String
    public var ropeConfigHash: String
    public var tokenPrefixHash: String
    public var fallbackContractHash: String?
    public var turboQuantLayoutVersion: Int
    public var logicalLength: Int
    public var pinnedPrefixLength: Int

    public init(
        modelID: String,
        modelRevision: String? = nil,
        tokenizerHash: String,
        profileHash: String,
        ropeConfigHash: String,
        tokenPrefixHash: String,
        fallbackContractHash: String? = nil,
        turboQuantLayoutVersion: Int = 4,
        logicalLength: Int = 0,
        pinnedPrefixLength: Int = 0
    ) {
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.tokenizerHash = tokenizerHash
        self.profileHash = profileHash
        self.ropeConfigHash = ropeConfigHash
        self.tokenPrefixHash = tokenPrefixHash
        self.fallbackContractHash = fallbackContractHash
        self.turboQuantLayoutVersion = turboQuantLayoutVersion
        self.logicalLength = logicalLength
        self.pinnedPrefixLength = pinnedPrefixLength
    }

    public func validateMatches(_ expected: Self) throws {
        guard modelID == expected.modelID else {
            throw TurboQuantKVSnapshotValidationFailure.modelIDMismatch(expected: expected.modelID, actual: modelID)
        }
        guard modelRevision == expected.modelRevision else {
            throw TurboQuantKVSnapshotValidationFailure.modelRevisionMismatch(expected: expected.modelRevision, actual: modelRevision)
        }
        guard tokenizerHash == expected.tokenizerHash else {
            throw TurboQuantKVSnapshotValidationFailure.tokenizerHashMismatch(expected: expected.tokenizerHash, actual: tokenizerHash)
        }
        guard profileHash == expected.profileHash else {
            throw TurboQuantKVSnapshotValidationFailure.profileHashMismatch(expected: expected.profileHash, actual: profileHash)
        }
        guard turboQuantLayoutVersion == expected.turboQuantLayoutVersion else {
            throw TurboQuantKVSnapshotValidationFailure.layoutVersionMismatch(
                expected: expected.turboQuantLayoutVersion,
                actual: turboQuantLayoutVersion
            )
        }
        guard ropeConfigHash == expected.ropeConfigHash else {
            throw TurboQuantKVSnapshotValidationFailure.ropeConfigHashMismatch(expected: expected.ropeConfigHash, actual: ropeConfigHash)
        }
        guard tokenPrefixHash == expected.tokenPrefixHash else {
            throw TurboQuantKVSnapshotValidationFailure.tokenPrefixHashMismatch(expected: expected.tokenPrefixHash, actual: tokenPrefixHash)
        }
        guard fallbackContractHash == expected.fallbackContractHash else {
            throw TurboQuantKVSnapshotValidationFailure.fallbackContractHashMismatch(
                expected: expected.fallbackContractHash,
                actual: fallbackContractHash
            )
        }
        guard logicalLength == expected.logicalLength else {
            throw TurboQuantKVSnapshotValidationFailure.logicalLengthMismatch(expected: expected.logicalLength, actual: logicalLength)
        }
        guard pinnedPrefixLength == expected.pinnedPrefixLength else {
            throw TurboQuantKVSnapshotValidationFailure.pinnedPrefixLengthMismatch(
                expected: expected.pinnedPrefixLength,
                actual: pinnedPrefixLength
            )
        }
    }
}

public struct TurboQuantKVSnapshotManifest: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var snapshotID: UUID
    public var conversationID: UUID
    public var modelID: String
    public var modelRevision: String?
    public var tokenizerHash: String
    public var profileHash: String
    public var turboQuantLayoutVersion: Int
    public var ropeConfigHash: String
    public var tokenPrefixHash: String
    public var fallbackContractHash: String?
    public var logicalLength: Int
    public var pinnedPrefixLength: Int
    public var compressedKeyBytes: Int64
    public var compressedValueBytes: Int64
    public var blobByteCount: Int64
    public var encryptionKeyID: String
    public var createdAt: Date

    public var id: UUID { snapshotID }

    public var identity: TurboQuantKVSnapshotIdentity {
        TurboQuantKVSnapshotIdentity(
            modelID: modelID,
            modelRevision: modelRevision,
            tokenizerHash: tokenizerHash,
            profileHash: profileHash,
            ropeConfigHash: ropeConfigHash,
            tokenPrefixHash: tokenPrefixHash,
            fallbackContractHash: fallbackContractHash,
            turboQuantLayoutVersion: turboQuantLayoutVersion,
            logicalLength: logicalLength,
            pinnedPrefixLength: pinnedPrefixLength
        )
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        snapshotID: UUID = UUID(),
        conversationID: UUID,
        identity: TurboQuantKVSnapshotIdentity,
        turboQuantLayoutVersion: Int,
        logicalLength: Int,
        pinnedPrefixLength: Int,
        compressedKeyBytes: Int64,
        compressedValueBytes: Int64,
        blobByteCount: Int64,
        encryptionKeyID: String,
        createdAt: Date = Date()
    ) {
        self.init(
            schemaVersion: schemaVersion,
            snapshotID: snapshotID,
            conversationID: conversationID,
            modelID: identity.modelID,
            modelRevision: identity.modelRevision,
            tokenizerHash: identity.tokenizerHash,
            profileHash: identity.profileHash,
            turboQuantLayoutVersion: turboQuantLayoutVersion,
            ropeConfigHash: identity.ropeConfigHash,
            tokenPrefixHash: identity.tokenPrefixHash,
            fallbackContractHash: identity.fallbackContractHash,
            logicalLength: logicalLength,
            pinnedPrefixLength: pinnedPrefixLength,
            compressedKeyBytes: compressedKeyBytes,
            compressedValueBytes: compressedValueBytes,
            blobByteCount: blobByteCount,
            encryptionKeyID: encryptionKeyID,
            createdAt: createdAt
        )
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        snapshotID: UUID = UUID(),
        conversationID: UUID,
        modelID: String,
        modelRevision: String? = nil,
        tokenizerHash: String,
        profileHash: String,
        turboQuantLayoutVersion: Int,
        ropeConfigHash: String,
        tokenPrefixHash: String,
        fallbackContractHash: String? = nil,
        logicalLength: Int,
        pinnedPrefixLength: Int,
        compressedKeyBytes: Int64,
        compressedValueBytes: Int64,
        blobByteCount: Int64,
        encryptionKeyID: String,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.conversationID = conversationID
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.tokenizerHash = tokenizerHash
        self.profileHash = profileHash
        self.turboQuantLayoutVersion = turboQuantLayoutVersion
        self.ropeConfigHash = ropeConfigHash
        self.tokenPrefixHash = tokenPrefixHash
        self.fallbackContractHash = fallbackContractHash
        self.logicalLength = logicalLength
        self.pinnedPrefixLength = pinnedPrefixLength
        self.compressedKeyBytes = compressedKeyBytes
        self.compressedValueBytes = compressedValueBytes
        self.blobByteCount = blobByteCount
        self.encryptionKeyID = encryptionKeyID
        self.createdAt = createdAt
    }

    public func validationErrors(expectedIdentity: TurboQuantKVSnapshotIdentity? = nil) -> [String] {
        var errors: [String] = []
        if schemaVersion != Self.schemaVersion {
            errors.append("unsupported snapshot schema \(schemaVersion)")
        }
        if turboQuantLayoutVersion <= 0 {
            errors.append("unsupported TurboQuant layout \(turboQuantLayoutVersion)")
        }
        if logicalLength < 0 {
            errors.append("logicalLength must be non-negative")
        }
        if pinnedPrefixLength < 0 || pinnedPrefixLength > logicalLength {
            errors.append("pinnedPrefixLength must be between 0 and logicalLength")
        }
        if compressedKeyBytes <= 0 || compressedValueBytes <= 0 || blobByteCount <= 0 {
            errors.append("snapshot byte counts must be positive")
        }
        if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("modelID is required")
        }
        if tokenizerHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("tokenizerHash is required")
        }
        if profileHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("profileHash is required")
        }
        if ropeConfigHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("ropeConfigHash is required")
        }
        if tokenPrefixHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("tokenPrefixHash is required")
        }
        if encryptionKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("encryptionKeyID is required")
        }
        if let expectedIdentity {
            if modelID != expectedIdentity.modelID { errors.append("modelID mismatch") }
            if modelRevision != expectedIdentity.modelRevision { errors.append("modelRevision mismatch") }
            if tokenizerHash != expectedIdentity.tokenizerHash { errors.append("tokenizerHash mismatch") }
            if profileHash != expectedIdentity.profileHash { errors.append("profileHash mismatch") }
            if turboQuantLayoutVersion != expectedIdentity.turboQuantLayoutVersion { errors.append("turboQuantLayoutVersion mismatch") }
            if ropeConfigHash != expectedIdentity.ropeConfigHash { errors.append("ropeConfigHash mismatch") }
            if tokenPrefixHash != expectedIdentity.tokenPrefixHash { errors.append("tokenPrefixHash mismatch") }
            if fallbackContractHash != expectedIdentity.fallbackContractHash { errors.append("fallbackContractHash mismatch") }
            if logicalLength != expectedIdentity.logicalLength { errors.append("logicalLength mismatch") }
            if pinnedPrefixLength != expectedIdentity.pinnedPrefixLength { errors.append("pinnedPrefixLength mismatch") }
        }
        return errors
    }

    public func validateForStorage(policy: SnapshotSecurityPolicy = .deviceDefault()) throws {
        try validateSchema()
        try policy.validateForLocalSnapshotStore()
        if let error = validationErrors().first {
            throw TurboQuantKVSnapshotValidationFailure.securityPolicyRejected(error)
        }
    }

    public func validateForRestore(
        expectedIdentity: TurboQuantKVSnapshotIdentity,
        policy: SnapshotSecurityPolicy = .deviceDefault(),
        restoreGate: TurboQuantKVSnapshotRestoreGate = .pendingCompatibilityPair
    ) throws {
        try validateForStorage(policy: policy)
        guard restoreGate.restoreEnabled else {
            throw TurboQuantKVSnapshotValidationFailure.restoreDisabled(restoreGate.reason)
        }
        try identity.validateMatches(expectedIdentity)
    }

    public func validateSchema() throws {
        guard schemaVersion == Self.schemaVersion,
              schemaVersion == TurboQuantSchemaRegistry.kvSnapshotManifest.version
        else {
            throw TurboQuantKVSnapshotValidationFailure.unsupportedSchema(
                name: TurboQuantSchemaName.kvSnapshotManifest.rawValue,
                version: schemaVersion
            )
        }
    }
}

public struct SnapshotSecurityPolicy: Hashable, Codable, Sendable {
    public static let schemaVersion = 1
    public static let keychainLocalKeySource = "keychain-backed-local-key"
    public static let evictionPolicyV1 = "quarantine-invalid-oldest-lru-largest"

    public var schemaVersion: Int
    public var encryptedAtRest: Bool
    public var keySource: String
    public var cloudSyncAllowed: Bool
    public var atomicWriteRequired: Bool
    public var partialWriteQuarantine: Bool
    public var quotaBytes: Int64
    public var evictionPolicy: String
    public var deleteOnModelDeletion: Bool
    public var deleteOnDataErasure: Bool

    public var isLocalOnlyByDefault: Bool {
        encryptedAtRest && !cloudSyncAllowed
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        encryptedAtRest: Bool = true,
        keySource: String = Self.keychainLocalKeySource,
        cloudSyncAllowed: Bool = false,
        atomicWriteRequired: Bool = true,
        partialWriteQuarantine: Bool = true,
        quotaBytes: Int64 = Self.defaultQuotaBytes(for: nil),
        evictionPolicy: String = Self.evictionPolicyV1,
        deleteOnModelDeletion: Bool = true,
        deleteOnDataErasure: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.encryptedAtRest = encryptedAtRest
        self.keySource = keySource
        self.cloudSyncAllowed = cloudSyncAllowed
        self.atomicWriteRequired = atomicWriteRequired
        self.partialWriteQuarantine = partialWriteQuarantine
        self.quotaBytes = quotaBytes
        self.evictionPolicy = evictionPolicy
        self.deleteOnModelDeletion = deleteOnModelDeletion
        self.deleteOnDataErasure = deleteOnDataErasure
    }

    public static let localDefault = SnapshotSecurityPolicy()

    public static func deviceDefault(deviceClass: DevicePerformanceClass? = nil) -> Self {
        Self(quotaBytes: defaultQuotaBytes(for: deviceClass))
    }

    public static func defaultQuotaBytes(for deviceClass: DevicePerformanceClass?) -> Int64 {
        switch deviceClass {
        case .a16Compact:
            256 * 1_024 * 1_024
        case .a17Pro, .a18Standard, .a18Pro, .a19Standard:
            512 * 1_024 * 1_024
        case .a19ProThin, .a19ProSustained, .mSeriesTabletBalanced:
            1_024 * 1_024 * 1_024
        case .mSeriesTabletPro, .mSeriesTabletMax, .futureVerified:
            2 * 1_024 * 1_024 * 1_024
        case nil:
            512 * 1_024 * 1_024
        }
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if schemaVersion != Self.schemaVersion {
            errors.append("unsupported snapshot security policy schema \(schemaVersion)")
        }
        if !encryptedAtRest {
            errors.append("snapshots must be encrypted at rest")
        }
        if keySource != Self.keychainLocalKeySource {
            errors.append("snapshots must use a Keychain-backed local key")
        }
        if cloudSyncAllowed {
            errors.append("snapshots must be excluded from cloud sync")
        }
        if !atomicWriteRequired {
            errors.append("atomic snapshot writes are required")
        }
        if !partialWriteQuarantine {
            errors.append("partial snapshot writes must quarantine")
        }
        if quotaBytes <= 0 {
            errors.append("snapshot quota must be positive")
        }
        if evictionPolicy != Self.evictionPolicyV1 {
            errors.append("unsupported snapshot eviction policy")
        }
        if !deleteOnModelDeletion {
            errors.append("snapshots must delete on model deletion")
        }
        if !deleteOnDataErasure {
            errors.append("snapshots must delete on user data erasure")
        }
        return errors
    }

    public func validateForLocalSnapshotStore() throws {
        guard schemaVersion == Self.schemaVersion,
              schemaVersion == TurboQuantSchemaRegistry.snapshotSecurityPolicy.version
        else {
            throw TurboQuantKVSnapshotValidationFailure.unsupportedSchema(
                name: TurboQuantSchemaName.snapshotSecurityPolicy.rawValue,
                version: schemaVersion
            )
        }
        if let error = validationErrors.first {
            throw TurboQuantKVSnapshotValidationFailure.securityPolicyRejected(error)
        }
    }
}

public struct TurboQuantKVSnapshotRestoreGate: Hashable, Codable, Sendable {
    public var restoreEnabled: Bool
    public var reason: String

    public init(restoreEnabled: Bool, reason: String) {
        self.restoreEnabled = restoreEnabled
        self.reason = reason
    }

    public static let pendingCompatibilityPair = Self(
        restoreEnabled: false,
        reason: "compatibility-pair pending"
    )

    public static func enabled(reason: String = "compatibility-pair validated") -> Self {
        Self(restoreEnabled: true, reason: reason)
    }
}

public enum TurboQuantKVSnapshotState: String, Hashable, Codable, Sendable, CaseIterable {
    case active
    case stale
    case invalidated
    case quarantined
    case deleted

    var evictionRank: Int {
        switch self {
        case .quarantined:
            0
        case .invalidated:
            1
        case .stale:
            2
        case .active:
            3
        case .deleted:
            4
        }
    }
}

public enum TurboQuantKVSnapshotRestoreOutcome: String, Hashable, Codable, Sendable, CaseIterable {
    case restored
    case rejected
    case quarantined
    case rePrefillRequired
}

public enum TurboQuantKVSnapshotRestoreResult: String, Hashable, Codable, Sendable, CaseIterable {
    case accepted
    case missing
    case rejected
    case quarantined
    case disabled
}

public struct TurboQuantKVSnapshotRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID { manifest.snapshotID }
    public var manifest: TurboQuantKVSnapshotManifest
    public var encryptedBlob: Data
    public var state: TurboQuantKVSnapshotState
    public var lastUsedAt: Date?

    public init(
        manifest: TurboQuantKVSnapshotManifest,
        encryptedBlob: Data,
        state: TurboQuantKVSnapshotState = .active,
        lastUsedAt: Date? = nil
    ) {
        self.manifest = manifest
        self.encryptedBlob = encryptedBlob
        self.state = state
        self.lastUsedAt = lastUsedAt
    }
}

public struct TurboQuantKVSnapshotBlob: Hashable, Codable, Sendable {
    public static let sqlCipherStorageLocation = "sqlcipher-local"

    public var snapshotID: UUID
    public var encryptedByteCount: Int64
    public var integrityChecksum: String
    public var encryptionKeyID: String
    public var storageLocation: String
    public var relativePath: String?
    public var cloudSyncAllowed: Bool
    public var excludedFromBackup: Bool
    public var createdAt: Date
    public var lastVerifiedAt: Date?

    public init(
        snapshotID: UUID,
        encryptedByteCount: Int64,
        integrityChecksum: String,
        encryptionKeyID: String,
        storageLocation: String = Self.sqlCipherStorageLocation,
        relativePath: String? = nil,
        cloudSyncAllowed: Bool = false,
        excludedFromBackup: Bool = true,
        createdAt: Date = Date(),
        lastVerifiedAt: Date? = nil
    ) {
        self.snapshotID = snapshotID
        self.encryptedByteCount = encryptedByteCount
        self.integrityChecksum = integrityChecksum
        self.encryptionKeyID = encryptionKeyID
        self.storageLocation = storageLocation
        self.relativePath = relativePath
        self.cloudSyncAllowed = cloudSyncAllowed
        self.excludedFromBackup = excludedFromBackup
        self.createdAt = createdAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    public static func checksum(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func validate(encryptedBytes: Data, manifest: TurboQuantKVSnapshotManifest) throws {
        guard encryptionKeyID == manifest.encryptionKeyID else {
            throw TurboQuantKVSnapshotValidationFailure.securityPolicyRejected("blob key ID does not match manifest key ID")
        }
        guard Int64(encryptedBytes.count) == manifest.blobByteCount,
              encryptedByteCount == manifest.blobByteCount
        else {
            throw TurboQuantKVSnapshotValidationFailure.blobByteCountMismatch(
                expected: manifest.blobByteCount,
                actual: Int64(encryptedBytes.count)
            )
        }
        guard integrityChecksum == Self.checksum(for: encryptedBytes) else {
            throw TurboQuantKVSnapshotValidationFailure.checksumMismatch(snapshotID: snapshotID)
        }
        guard !cloudSyncAllowed, excludedFromBackup else {
            throw TurboQuantKVSnapshotValidationFailure.securityPolicyRejected("snapshot blob must remain local-only and backup-excluded")
        }
    }
}

public struct TurboQuantKVSnapshotReference: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var conversationID: UUID
    public var snapshotID: UUID
    public var pinned: Bool
    public var state: TurboQuantKVSnapshotState
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        snapshotID: UUID,
        pinned: Bool = false,
        state: TurboQuantKVSnapshotState = .active,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.snapshotID = snapshotID
        self.pinned = pinned
        self.state = state
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct TurboQuantKVSnapshotRestoreAttempt: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var id: UUID
    public var schemaVersion: Int
    public var snapshotID: UUID?
    public var conversationID: UUID
    public var attemptedAt: Date
    public var result: TurboQuantKVSnapshotRestoreResult
    public var failureReason: String?
    public var expectedIdentity: TurboQuantKVSnapshotIdentity?

    public var outcome: TurboQuantKVSnapshotRestoreOutcome {
        switch result {
        case .accepted:
            .restored
        case .quarantined:
            .quarantined
        case .missing:
            .rePrefillRequired
        case .rejected, .disabled:
            .rejected
        }
    }

    public var reason: String? { failureReason }

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = Self.schemaVersion,
        snapshotID: UUID? = nil,
        conversationID: UUID,
        attemptedAt: Date = Date(),
        result: TurboQuantKVSnapshotRestoreResult,
        failureReason: String? = nil,
        expectedIdentity: TurboQuantKVSnapshotIdentity? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.conversationID = conversationID
        self.attemptedAt = attemptedAt
        self.result = result
        self.failureReason = failureReason
        self.expectedIdentity = expectedIdentity
    }

    public init(
        id: UUID = UUID(),
        snapshotID: UUID?,
        conversationID: UUID,
        attemptedAt: Date = Date(),
        outcome: TurboQuantKVSnapshotRestoreOutcome,
        reason: String? = nil
    ) {
        self.init(
            id: id,
            snapshotID: snapshotID,
            conversationID: conversationID,
            attemptedAt: attemptedAt,
            result: Self.result(for: outcome),
            failureReason: reason
        )
    }

    private static func result(for outcome: TurboQuantKVSnapshotRestoreOutcome) -> TurboQuantKVSnapshotRestoreResult {
        switch outcome {
        case .restored:
            .accepted
        case .rejected:
            .rejected
        case .quarantined:
            .quarantined
        case .rePrefillRequired:
            .missing
        }
    }
}

public enum TurboQuantKVSnapshotQuarantineStage: String, Hashable, Codable, Sendable, CaseIterable {
    case write
    case restore
    case integrity
    case quota
    case deletion
}

public struct TurboQuantKVSnapshotQuarantine: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var id: UUID
    public var schemaVersion: Int
    public var snapshotID: UUID?
    public var conversationID: UUID?
    public var stage: TurboQuantKVSnapshotQuarantineStage
    public var reason: String
    public var blobByteCount: Int64
    public var quarantinedAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = Self.schemaVersion,
        snapshotID: UUID? = nil,
        conversationID: UUID? = nil,
        stage: TurboQuantKVSnapshotQuarantineStage,
        reason: String,
        blobByteCount: Int64 = 0,
        quarantinedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.conversationID = conversationID
        self.stage = stage
        self.reason = reason
        self.blobByteCount = max(0, blobByteCount)
        self.quarantinedAt = quarantinedAt
        self.resolvedAt = resolvedAt
    }

    public init(
        id: UUID = UUID(),
        snapshotID: UUID,
        quarantinedAt: Date = Date(),
        reason: String
    ) {
        self.init(
            id: id,
            snapshotID: snapshotID,
            stage: .restore,
            reason: reason,
            quarantinedAt: quarantinedAt
        )
    }
}

public struct TurboQuantKVSnapshotWriteRequest: Hashable, Sendable {
    public var manifest: TurboQuantKVSnapshotManifest
    public var encryptedBlob: Data
    public var writeCompletedAtomically: Bool
    public var pinned: Bool
    public var createdAt: Date

    public init(
        manifest: TurboQuantKVSnapshotManifest,
        encryptedBlob: Data,
        writeCompletedAtomically: Bool = true,
        pinned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.manifest = manifest
        self.encryptedBlob = encryptedBlob
        self.writeCompletedAtomically = writeCompletedAtomically
        self.pinned = pinned
        self.createdAt = createdAt
    }
}

public enum TurboQuantKVSnapshotWriteDisposition: String, Hashable, Codable, Sendable, CaseIterable {
    case committed
    case quarantined
}

public struct TurboQuantKVSnapshotWriteOutcome: Hashable, Sendable {
    public var disposition: TurboQuantKVSnapshotWriteDisposition
    public var manifest: TurboQuantKVSnapshotManifest
    public var blob: TurboQuantKVSnapshotBlob?
    public var quarantine: TurboQuantKVSnapshotQuarantine?
    public var evictedSnapshotIDs: [UUID]

    public init(
        disposition: TurboQuantKVSnapshotWriteDisposition,
        manifest: TurboQuantKVSnapshotManifest,
        blob: TurboQuantKVSnapshotBlob? = nil,
        quarantine: TurboQuantKVSnapshotQuarantine? = nil,
        evictedSnapshotIDs: [UUID] = []
    ) {
        self.disposition = disposition
        self.manifest = manifest
        self.blob = blob
        self.quarantine = quarantine
        self.evictedSnapshotIDs = evictedSnapshotIDs
    }
}

public enum TurboQuantKVSnapshotRestoreDecision: Hashable, Sendable {
    case accepted(TurboQuantKVSnapshotManifest)
    case missing
    case rejected(TurboQuantKVSnapshotValidationFailure)
    case quarantined(TurboQuantKVSnapshotQuarantine)
}

public protocol TurboQuantKVSnapshotRepository: Sendable {
    func commitKVSnapshot(_ request: TurboQuantKVSnapshotWriteRequest, policy: SnapshotSecurityPolicy) async throws -> TurboQuantKVSnapshotWriteOutcome
    func latestKVSnapshotManifest(conversationID: UUID) async throws -> TurboQuantKVSnapshotManifest?
    func listKVSnapshotManifests(conversationID: UUID?) async throws -> [TurboQuantKVSnapshotManifest]
    func recordKVSnapshotRestoreAttempt(_ attempt: TurboQuantKVSnapshotRestoreAttempt) async throws
    func quarantineKVSnapshot(_ quarantine: TurboQuantKVSnapshotQuarantine) async throws
    func deleteKVSnapshots(modelID: String) async throws -> [UUID]
    func deleteAllKVSnapshots(reason: String) async throws
}

public struct TurboQuantSnapshotLocalCipher: Sendable {
    public var keyID: String
    private var key: SymmetricKey

    public init(keyID: String, keyMaterial: Data) {
        self.keyID = keyID
        precondition(!keyMaterial.isEmpty, "TurboQuant snapshot encryption requires non-empty key material")
        self.key = SymmetricKey(data: SHA256.hash(data: keyMaterial))
    }

    public func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw TurboQuantKVSnapshotStoreFailure.encryptionFailed
        }
        return combined
    }

    public func open(_ sealed: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
}

public enum TurboQuantKVSnapshotStoreFailure: Error, Hashable, Codable, Sendable, CustomStringConvertible {
    case invalidPolicy([String])
    case invalidManifest([String])
    case encryptionKeyMismatch
    case encryptionFailed

    public var description: String {
        switch self {
        case .invalidPolicy(let errors):
            "Invalid snapshot security policy: \(errors.joined(separator: "; "))"
        case .invalidManifest(let errors):
            "Invalid KV snapshot manifest: \(errors.joined(separator: "; "))"
        case .encryptionKeyMismatch:
            "Snapshot manifest encryption key does not match the local cipher key."
        case .encryptionFailed:
            "Snapshot encryption failed."
        }
    }
}

public actor TurboQuantKVSnapshotStore {
    private var records: [UUID: TurboQuantKVSnapshotRecord] = [:]
    private var references: [UUID: TurboQuantKVSnapshotReference] = [:]
    private var blobMetadata: [UUID: TurboQuantKVSnapshotBlob] = [:]
    private var attempts: [TurboQuantKVSnapshotRestoreAttempt] = []
    private var quarantines: [TurboQuantKVSnapshotQuarantine] = []
    private var policy: SnapshotSecurityPolicy

    public init(policy: SnapshotSecurityPolicy = .localDefault) {
        self.policy = policy
    }

    public func currentPolicy() -> SnapshotSecurityPolicy { policy }

    public func updatePolicy(_ policy: SnapshotSecurityPolicy) throws {
        let errors = policy.validationErrors
        guard errors.isEmpty else {
            throw TurboQuantKVSnapshotStoreFailure.invalidPolicy(errors)
        }
        self.policy = policy
    }

    @discardableResult
    public func store(_ request: TurboQuantKVSnapshotWriteRequest) throws -> TurboQuantKVSnapshotWriteOutcome {
        try request.manifest.validateForStorage(policy: policy)

        if !request.writeCompletedAtomically {
            return quarantineWrite(
                manifest: request.manifest,
                encryptedByteCount: Int64(request.encryptedBlob.count),
                stage: .write,
                reason: "partial_write"
            )
        }

        guard Int64(request.encryptedBlob.count) == request.manifest.blobByteCount else {
            return quarantineWrite(
                manifest: request.manifest,
                encryptedByteCount: Int64(request.encryptedBlob.count),
                stage: .write,
                reason: "blob_byte_count_mismatch"
            )
        }

        guard request.manifest.blobByteCount <= policy.quotaBytes else {
            return quarantineWrite(
                manifest: request.manifest,
                encryptedByteCount: Int64(request.encryptedBlob.count),
                stage: .quota,
                reason: "snapshot_exceeds_quota"
            )
        }

        let blob = TurboQuantKVSnapshotBlob(
            snapshotID: request.manifest.snapshotID,
            encryptedByteCount: request.manifest.blobByteCount,
            integrityChecksum: TurboQuantKVSnapshotBlob.checksum(for: request.encryptedBlob),
            encryptionKeyID: request.manifest.encryptionKeyID,
            createdAt: request.createdAt
        )
        try blob.validate(encryptedBytes: request.encryptedBlob, manifest: request.manifest)

        let reference = TurboQuantKVSnapshotReference(
            conversationID: request.manifest.conversationID,
            snapshotID: request.manifest.snapshotID,
            pinned: request.pinned,
            createdAt: request.createdAt
        )
        records[request.manifest.snapshotID] = TurboQuantKVSnapshotRecord(
            manifest: request.manifest,
            encryptedBlob: request.encryptedBlob,
            state: .active
        )
        references[request.manifest.snapshotID] = reference
        blobMetadata[request.manifest.snapshotID] = blob

        let evicted = enforceQuota(protecting: request.manifest.snapshotID)
        if activeByteCount > policy.quotaBytes {
            let quarantine = quarantineSnapshot(
                snapshotID: request.manifest.snapshotID,
                conversationID: request.manifest.conversationID,
                stage: .quota,
                reason: "quota_cannot_be_enforced_without_eviction_of_pinned_snapshot",
                blobByteCount: request.manifest.blobByteCount,
                quarantinedAt: request.createdAt
            )
            return TurboQuantKVSnapshotWriteOutcome(
                disposition: .quarantined,
                manifest: request.manifest,
                blob: blob,
                quarantine: quarantine,
                evictedSnapshotIDs: evicted
            )
        }

        return TurboQuantKVSnapshotWriteOutcome(
            disposition: .committed,
            manifest: request.manifest,
            blob: blob,
            evictedSnapshotIDs: evicted
        )
    }

    @discardableResult
    public func store(
        manifest: TurboQuantKVSnapshotManifest,
        plaintextBlob: Data,
        cipher: TurboQuantSnapshotLocalCipher
    ) throws -> TurboQuantKVSnapshotRecord {
        guard manifest.encryptionKeyID == cipher.keyID else {
            throw TurboQuantKVSnapshotStoreFailure.encryptionKeyMismatch
        }
        let encrypted = try cipher.seal(plaintextBlob)
        guard encrypted != plaintextBlob else {
            throw TurboQuantKVSnapshotStoreFailure.encryptionFailed
        }
        var storedManifest = manifest
        storedManifest.blobByteCount = Int64(encrypted.count)
        _ = try store(
            TurboQuantKVSnapshotWriteRequest(
                manifest: storedManifest,
                encryptedBlob: encrypted,
                writeCompletedAtomically: true,
                createdAt: manifest.createdAt
            )
        )
        guard let record = records[storedManifest.snapshotID] else {
            throw TurboQuantKVSnapshotStoreFailure.invalidManifest(["snapshot was not committed"])
        }
        return record
    }

    public func latest(
        conversationID: UUID,
        expectedIdentity: TurboQuantKVSnapshotIdentity
    ) -> TurboQuantKVSnapshotRecord? {
        records.values
            .filter { record in
                record.state == .active
                    && record.manifest.conversationID == conversationID
                    && record.manifest.validationErrors(expectedIdentity: expectedIdentity).isEmpty
            }
            .sorted {
                if $0.manifest.createdAt == $1.manifest.createdAt {
                    return $0.manifest.snapshotID.uuidString < $1.manifest.snapshotID.uuidString
                }
                return $0.manifest.createdAt > $1.manifest.createdAt
            }
            .first
    }

    public func restoreDecision(
        conversationID: UUID,
        expectedIdentity: TurboQuantKVSnapshotIdentity,
        restoreGate: TurboQuantKVSnapshotRestoreGate = .pendingCompatibilityPair,
        attemptedAt: Date = Date()
    ) -> TurboQuantKVSnapshotRestoreDecision {
        guard restoreGate.restoreEnabled else {
            let failure = TurboQuantKVSnapshotValidationFailure.restoreDisabled(restoreGate.reason)
            recordAttempt(
                snapshotID: nil,
                conversationID: conversationID,
                attemptedAt: attemptedAt,
                result: .disabled,
                failureReason: failure.errorDescription,
                expectedIdentity: expectedIdentity
            )
            return .rejected(failure)
        }

        let candidates = records.values
            .filter({ $0.manifest.conversationID == conversationID && $0.state == .active })
            .sorted(by: { $0.manifest.createdAt > $1.manifest.createdAt })
        guard !candidates.isEmpty else {
            recordAttempt(
                snapshotID: nil,
                conversationID: conversationID,
                attemptedAt: attemptedAt,
                result: .missing,
                failureReason: "missing_snapshot",
                expectedIdentity: expectedIdentity
            )
            return .missing
        }

        var lastFailure: (TurboQuantKVSnapshotManifest, TurboQuantKVSnapshotValidationFailure)?
        var lastQuarantine: TurboQuantKVSnapshotQuarantine?

        for record in candidates {
            do {
                try record.manifest.validateForRestore(
                    expectedIdentity: expectedIdentity,
                    policy: policy,
                    restoreGate: restoreGate
                )
                guard let blob = blobMetadata[record.manifest.snapshotID] else {
                    throw TurboQuantKVSnapshotValidationFailure.missingBlob(record.manifest.snapshotID)
                }
                try blob.validate(encryptedBytes: record.encryptedBlob, manifest: record.manifest)

                var updated = record
                updated.lastUsedAt = attemptedAt
                records[record.manifest.snapshotID] = updated
                if var reference = references[record.manifest.snapshotID] {
                    reference.lastUsedAt = attemptedAt
                    references[record.manifest.snapshotID] = reference
                }
                recordAttempt(
                    snapshotID: record.manifest.snapshotID,
                    conversationID: conversationID,
                    attemptedAt: attemptedAt,
                    result: .accepted,
                    failureReason: nil,
                    expectedIdentity: expectedIdentity
                )
                return .accepted(record.manifest)
            } catch let failure as TurboQuantKVSnapshotValidationFailure {
                lastFailure = (record.manifest, failure)
                if case .checksumMismatch = failure {
                    let quarantine = quarantineSnapshot(
                        snapshotID: record.manifest.snapshotID,
                        conversationID: record.manifest.conversationID,
                        stage: .integrity,
                        reason: failure.errorDescription ?? "checksum_mismatch",
                        blobByteCount: record.manifest.blobByteCount,
                        quarantinedAt: attemptedAt
                    )
                    lastQuarantine = quarantine ?? lastQuarantine
                    recordAttempt(
                        snapshotID: record.manifest.snapshotID,
                        conversationID: conversationID,
                        attemptedAt: attemptedAt,
                        result: .quarantined,
                        failureReason: failure.errorDescription,
                        expectedIdentity: expectedIdentity
                    )
                    continue
                }
                recordAttempt(
                    snapshotID: record.manifest.snapshotID,
                    conversationID: conversationID,
                    attemptedAt: attemptedAt,
                    result: .rejected,
                    failureReason: failure.errorDescription,
                    expectedIdentity: expectedIdentity
                )
                continue
            } catch {
                let failure = TurboQuantKVSnapshotValidationFailure.securityPolicyRejected(error.localizedDescription)
                lastFailure = (record.manifest, failure)
                recordAttempt(
                    snapshotID: record.manifest.snapshotID,
                    conversationID: conversationID,
                    attemptedAt: attemptedAt,
                    result: .rejected,
                    failureReason: failure.errorDescription,
                    expectedIdentity: expectedIdentity
                )
                continue
            }
        }

        if let lastQuarantine {
            return .quarantined(lastQuarantine)
        }
        if let lastFailure {
            return .rejected(lastFailure.1)
        }

        recordAttempt(
            snapshotID: nil,
            conversationID: conversationID,
            attemptedAt: attemptedAt,
            result: .missing,
            failureReason: "missing_snapshot",
            expectedIdentity: expectedIdentity
        )
        return .missing
    }

    public func simulateBlobCorruption(snapshotID: UUID, bytes: Data) {
        guard var record = records[snapshotID] else { return }
        record.encryptedBlob = bytes
        records[snapshotID] = record
    }

    @discardableResult
    public func recordRestoreAttempt(
        snapshotID: UUID?,
        conversationID: UUID,
        outcome: TurboQuantKVSnapshotRestoreOutcome,
        reason: String? = nil
    ) -> TurboQuantKVSnapshotRestoreAttempt {
        let attempt = TurboQuantKVSnapshotRestoreAttempt(
            snapshotID: snapshotID,
            conversationID: conversationID,
            outcome: outcome,
            reason: reason
        )
        attempts.append(attempt)
        return attempt
    }

    @discardableResult
    public func quarantine(snapshotID: UUID, reason: String) -> TurboQuantKVSnapshotQuarantine? {
        quarantineSnapshot(
            snapshotID: snapshotID,
            conversationID: records[snapshotID]?.manifest.conversationID,
            stage: .restore,
            reason: reason,
            blobByteCount: Int64(records[snapshotID]?.encryptedBlob.count ?? 0),
            quarantinedAt: Date()
        )
    }

    @discardableResult
    public func deleteSnapshots(modelID: String) -> [UUID] {
        let deleted = records.values
            .filter { $0.manifest.modelID == modelID }
            .map(\.manifest.snapshotID)
        for snapshotID in deleted {
            records.removeValue(forKey: snapshotID)
            references.removeValue(forKey: snapshotID)
            blobMetadata.removeValue(forKey: snapshotID)
        }
        return deleted
    }

    @discardableResult
    public func deleteAllSnapshots(reason: String = "data_erasure") -> [UUID] {
        let deleted = records.keys.sorted { $0.uuidString < $1.uuidString }
        records.removeAll()
        references.removeAll()
        blobMetadata.removeAll()
        quarantines.append(TurboQuantKVSnapshotQuarantine(stage: .deletion, reason: reason))
        return deleted
    }

    public func eraseAllSnapshots() {
        records.removeAll()
        references.removeAll()
        blobMetadata.removeAll()
        attempts.removeAll()
        quarantines.removeAll()
    }

    public func allRecords() -> [TurboQuantKVSnapshotRecord] {
        records.values.sorted { $0.manifest.createdAt < $1.manifest.createdAt }
    }

    public func allManifests(includeInactive: Bool = false) -> [TurboQuantKVSnapshotManifest] {
        records.values
            .filter { includeInactive || $0.state == .active }
            .map(\.manifest)
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func allAttempts() -> [TurboQuantKVSnapshotRestoreAttempt] { attempts }

    public func allRestoreAttempts() -> [TurboQuantKVSnapshotRestoreAttempt] {
        attempts.sorted { $0.attemptedAt > $1.attemptedAt }
    }

    public func allQuarantines() -> [TurboQuantKVSnapshotQuarantine] {
        quarantines.sorted { $0.quarantinedAt > $1.quarantinedAt }
    }

    private func quarantineWrite(
        manifest: TurboQuantKVSnapshotManifest,
        encryptedByteCount: Int64,
        stage: TurboQuantKVSnapshotQuarantineStage,
        reason: String
    ) -> TurboQuantKVSnapshotWriteOutcome {
        let quarantine = TurboQuantKVSnapshotQuarantine(
            snapshotID: manifest.snapshotID,
            conversationID: manifest.conversationID,
            stage: stage,
            reason: reason,
            blobByteCount: encryptedByteCount,
            quarantinedAt: manifest.createdAt
        )
        quarantines.append(quarantine)
        return TurboQuantKVSnapshotWriteOutcome(
            disposition: .quarantined,
            manifest: manifest,
            quarantine: quarantine
        )
    }

    @discardableResult
    private func quarantineSnapshot(
        snapshotID: UUID,
        conversationID: UUID?,
        stage: TurboQuantKVSnapshotQuarantineStage,
        reason: String,
        blobByteCount: Int64,
        quarantinedAt: Date
    ) -> TurboQuantKVSnapshotQuarantine? {
        guard var record = records[snapshotID] else { return nil }
        record.state = .quarantined
        records[snapshotID] = record
        if var reference = references[snapshotID] {
            reference.state = .quarantined
            references[snapshotID] = reference
        }
        let quarantine = TurboQuantKVSnapshotQuarantine(
            snapshotID: snapshotID,
            conversationID: conversationID,
            stage: stage,
            reason: reason,
            blobByteCount: blobByteCount,
            quarantinedAt: quarantinedAt
        )
        quarantines.append(quarantine)
        return quarantine
    }

    private func recordAttempt(
        snapshotID: UUID?,
        conversationID: UUID,
        attemptedAt: Date,
        result: TurboQuantKVSnapshotRestoreResult,
        failureReason: String?,
        expectedIdentity: TurboQuantKVSnapshotIdentity?
    ) {
        attempts.append(
            TurboQuantKVSnapshotRestoreAttempt(
                snapshotID: snapshotID,
                conversationID: conversationID,
                attemptedAt: attemptedAt,
                result: result,
                failureReason: failureReason,
                expectedIdentity: expectedIdentity
            )
        )
    }

    private func enforceQuota(protecting protectedSnapshotID: UUID) -> [UUID] {
        guard policy.quotaBytes > 0 else { return [] }
        var evicted: [UUID] = []
        while activeByteCount > policy.quotaBytes {
            guard let victim = records.values
                .filter({ $0.id != protectedSnapshotID && $0.state != .deleted && !(references[$0.id]?.pinned ?? false) })
                .sorted(by: evictionSort)
                .first
            else { break }
            var invalidated = victim
            invalidated.state = .invalidated
            invalidated.encryptedBlob.removeAll(keepingCapacity: false)
            records[victim.id] = invalidated
            blobMetadata.removeValue(forKey: victim.id)
            if var reference = references[victim.id] {
                reference.state = .invalidated
                references[victim.id] = reference
            }
            evicted.append(victim.id)
        }
        return evicted
    }

    private var activeByteCount: Int64 {
        records.values
            .filter { $0.state == .active }
            .reduce(Int64(0)) { $0 + Int64($1.encryptedBlob.count) }
    }

    private func evictionSort(
        _ lhs: TurboQuantKVSnapshotRecord,
        _ rhs: TurboQuantKVSnapshotRecord
    ) -> Bool {
        let lhsRank = lhs.state.evictionRank
        let rhsRank = rhs.state.evictionRank
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        let lhsDate = lhs.lastUsedAt ?? lhs.manifest.createdAt
        let rhsDate = rhs.lastUsedAt ?? rhs.manifest.createdAt
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.encryptedBlob.count > rhs.encryptedBlob.count
    }
}

public enum TurboQuantKVSnapshotValidationFailure: Error, Hashable, LocalizedError, Sendable {
    case unsupportedSchema(name: String, version: Int)
    case securityPolicyRejected(String)
    case restoreDisabled(String)
    case missingEncryptionKeyID
    case blobByteCountMismatch(expected: Int64, actual: Int64)
    case missingBlob(UUID)
    case checksumMismatch(snapshotID: UUID)
    case modelIDMismatch(expected: String, actual: String)
    case modelRevisionMismatch(expected: String?, actual: String?)
    case tokenizerHashMismatch(expected: String, actual: String)
    case profileHashMismatch(expected: String, actual: String)
    case layoutVersionMismatch(expected: Int, actual: Int)
    case ropeConfigHashMismatch(expected: String, actual: String)
    case tokenPrefixHashMismatch(expected: String, actual: String)
    case fallbackContractHashMismatch(expected: String?, actual: String?)
    case logicalLengthMismatch(expected: Int, actual: Int)
    case pinnedPrefixLengthMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(name, version):
            "Unsupported \(name) schema version \(version)."
        case let .securityPolicyRejected(reason):
            "Snapshot security policy rejected restore: \(reason)."
        case let .restoreDisabled(reason):
            "Snapshot restore is disabled: \(reason)."
        case .missingEncryptionKeyID:
            "Snapshot manifest is missing an encryption key ID."
        case let .blobByteCountMismatch(expected, actual):
            "Snapshot blob byte count mismatch: expected \(expected), got \(actual)."
        case let .missingBlob(snapshotID):
            "Snapshot blob is missing for \(snapshotID.uuidString)."
        case let .checksumMismatch(snapshotID):
            "Snapshot blob checksum mismatch for \(snapshotID.uuidString)."
        case let .modelIDMismatch(expected, actual):
            "Snapshot model mismatch: expected \(expected), got \(actual)."
        case let .modelRevisionMismatch(expected, actual):
            "Snapshot model revision mismatch: expected \(expected ?? "nil"), got \(actual ?? "nil")."
        case let .tokenizerHashMismatch(expected, actual):
            "Snapshot tokenizer hash mismatch: expected \(expected), got \(actual)."
        case let .profileHashMismatch(expected, actual):
            "Snapshot profile hash mismatch: expected \(expected), got \(actual)."
        case let .layoutVersionMismatch(expected, actual):
            "Snapshot layout version mismatch: expected \(expected), got \(actual)."
        case let .ropeConfigHashMismatch(expected, actual):
            "Snapshot RoPE config hash mismatch: expected \(expected), got \(actual)."
        case let .tokenPrefixHashMismatch(expected, actual):
            "Snapshot token prefix hash mismatch: expected \(expected), got \(actual)."
        case let .fallbackContractHashMismatch(expected, actual):
            "Snapshot fallback contract hash mismatch: expected \(expected ?? "nil"), got \(actual ?? "nil")."
        case let .logicalLengthMismatch(expected, actual):
            "Snapshot logical length mismatch: expected \(expected), got \(actual)."
        case let .pinnedPrefixLengthMismatch(expected, actual):
            "Snapshot pinned prefix length mismatch: expected \(expected), got \(actual)."
        }
    }
}
