import CloudKit
import Foundation
import OSLog
import PinesCore

private let cloudKitSyncLogger = Logger(subsystem: "com.schtack.pines", category: "CloudKitSync")

protocol CloudKitSyncRepository: Sendable {
    func cloudKitLocalSnapshot(includeVault: Bool, includeEmbeddings: Bool, includeClean: Bool) async throws -> CloudKitLocalSnapshot
    func applyCloudKitSnapshot(_ snapshot: CloudKitRemoteSnapshot) async throws
    func cloudKitServerChangeTokenData(zoneName: String) async throws -> Data?
    func saveCloudKitServerChangeTokenData(_ data: Data?, zoneName: String) async throws
}

struct CloudKitLocalSnapshot: Sendable {
    var settings: CloudKitSettingsSnapshot
    var conversations: [CloudKitConversationSnapshot]
    var messages: [CloudKitMessageSnapshot]
    var documents: [CloudKitVaultDocumentSnapshot]
    var chunks: [CloudKitVaultChunkSnapshot]
    var embeddings: [VaultStoredEmbedding]
}

struct CloudKitRemoteSnapshot: Sendable {
    var settings: CloudKitSettingsSnapshot?
    var conversations: [CloudKitConversationSnapshot] = []
    var messages: [CloudKitMessageSnapshot] = []
    var documents: [CloudKitVaultDocumentSnapshot] = []
    var chunks: [CloudKitVaultChunkSnapshot] = []
    var embeddings: [VaultStoredEmbedding] = []
    var deletedRecords: [CloudKitDeletedRecord] = []
    var serverChangeTokenData: Data?

    var isEmpty: Bool {
        settings == nil
            && conversations.isEmpty
            && messages.isEmpty
            && documents.isEmpty
            && chunks.isEmpty
            && embeddings.isEmpty
            && deletedRecords.isEmpty
    }

    mutating func merge(_ other: CloudKitRemoteSnapshot) {
        if let settings = other.settings {
            if self.settings == nil || settings.updatedAt >= self.settings!.updatedAt {
                self.settings = settings
            }
        }
        conversations.append(contentsOf: other.conversations)
        messages.append(contentsOf: other.messages)
        documents.append(contentsOf: other.documents)
        chunks.append(contentsOf: other.chunks)
        embeddings.append(contentsOf: other.embeddings)
        deletedRecords.append(contentsOf: other.deletedRecords)
        serverChangeTokenData = other.serverChangeTokenData ?? serverChangeTokenData
    }
}

struct CloudKitSettingsSnapshot: Hashable, Codable, Sendable {
    var value: AppSettingsSnapshot
    var updatedAt: Date
}

struct CloudKitConversationSnapshot: Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var updatedAt: Date
    var deletedAt: Date?
    var defaultModelID: ModelID?
    var defaultProviderID: ProviderID?
    var archived: Bool
    var pinned: Bool
}

struct CloudKitMessageSnapshot: Hashable, Codable, Sendable {
    var id: UUID
    var conversationID: UUID
    var role: ChatRole
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var status: MessageStatus
    var modelID: ModelID?
    var providerID: ProviderID?
    var toolCallID: String?
    var toolName: String?
    var toolCalls: [ToolCallDelta] = []
    var providerMetadata: [String: String] = [:]
}

struct CloudKitVaultDocumentSnapshot: Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var sourceType: String
    var updatedAt: Date
    var deletedAt: Date?
    var chunkCount: Int
}

struct CloudKitVaultChunkSnapshot: Hashable, Codable, Sendable {
    var id: String
    var documentID: UUID
    var ordinal: Int
    var text: String
    var tokenEstimate: Int
    var checksum: String
    var createdAt: Date
}

struct CloudKitDeletedRecord: Hashable, Codable, Sendable {
    var recordType: String
    var recordName: String
    var deletedAt: Date
}

struct CloudKitSyncService {
    static let defaultContainerIdentifier = "iCloud.com.schtack.pines"

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "PinesPrivate", ownerName: CKCurrentUserDefaultName)

    let conversationRepository: any ConversationRepository
    let vaultRepository: any VaultRepository
    let settingsRepository: any SettingsRepository
    let syncRepository: (any CloudKitSyncRepository)?
    let auditRepository: (any AuditEventRepository)?

    init(
        containerIdentifier: String = Self.defaultContainerIdentifier,
        conversationRepository: any ConversationRepository,
        vaultRepository: any VaultRepository,
        settingsRepository: any SettingsRepository,
        syncRepository: (any CloudKitSyncRepository)? = nil,
        auditRepository: (any AuditEventRepository)?
    ) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        self.conversationRepository = conversationRepository
        self.vaultRepository = vaultRepository
        self.settingsRepository = settingsRepository
        self.syncRepository = syncRepository ?? (conversationRepository as? any CloudKitSyncRepository)
        self.auditRepository = auditRepository
    }

    static func hasRequiredEntitlements(containerIdentifier: String = Self.defaultContainerIdentifier) -> Bool {
        #if PINES_CLOUDKIT_ENABLED
        return !containerIdentifier.isEmpty
        #else
        return false
        #endif
    }

    func syncNow() async throws {
        let settings = try await settingsRepository.loadSettings()
        guard settings.storeConfiguration.iCloudSyncEnabled else { return }
        guard Self.hasRequiredEntitlements() else { return }
        guard let syncRepository else {
            try await auditRepository?.append(
                AuditEvent(category: .security, summary: "Skipped iCloud sync because the local store does not expose merge APIs.")
            )
            return
        }

        try await ensureZone()

        let hadServerChangeToken = try await syncRepository.cloudKitServerChangeTokenData(zoneName: zoneID.zoneName) != nil
        let remoteBeforeUpload = try await fetchRemoteSnapshot(using: syncRepository)
        if !remoteBeforeUpload.isEmpty {
            try await syncRepository.applyCloudKitSnapshot(remoteBeforeUpload)
        }
        if let tokenData = remoteBeforeUpload.serverChangeTokenData {
            try await syncRepository.saveCloudKitServerChangeTokenData(tokenData, zoneName: zoneID.zoneName)
        }

        let mergedSettings = try await settingsRepository.loadSettings()
        let localSnapshot = try await syncRepository.cloudKitLocalSnapshot(
            includeVault: mergedSettings.storeConfiguration.syncsSourceDocuments,
            includeEmbeddings: mergedSettings.storeConfiguration.syncsEmbeddings,
            includeClean: !hadServerChangeToken
        )
        try await save(records(from: localSnapshot))

        let remoteAfterUpload = try await fetchRemoteSnapshot(using: syncRepository)
        if !remoteAfterUpload.isEmpty {
            try await syncRepository.applyCloudKitSnapshot(remoteAfterUpload)
        }
        if let tokenData = remoteAfterUpload.serverChangeTokenData ?? remoteBeforeUpload.serverChangeTokenData {
            try await syncRepository.saveCloudKitServerChangeTokenData(tokenData, zoneName: zoneID.zoneName)
        }

        try await auditRepository?.append(
            AuditEvent(category: .security, summary: "Completed iCloud private database bidirectional sync.")
        )
    }

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
    }

    private func fetchRemoteSnapshot(using repository: any CloudKitSyncRepository) async throws -> CloudKitRemoteSnapshot {
        let tokenData = try await repository.cloudKitServerChangeTokenData(zoneName: zoneID.zoneName)
        let token = try tokenData.flatMap(Self.decodeChangeToken(from:))
        do {
            return try await fetchRemoteSnapshot(since: token)
        } catch let error as CKError where error.code == .changeTokenExpired {
            try await repository.saveCloudKitServerChangeTokenData(nil, zoneName: zoneID.zoneName)
            return try await fetchRemoteSnapshot(since: nil)
        }
    }

    private func fetchRemoteSnapshot(since initialToken: CKServerChangeToken?) async throws -> CloudKitRemoteSnapshot {
        var aggregate = CloudKitRemoteSnapshot()
        var token = initialToken
        var moreComing = true

        while moreComing {
            let changes = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: token,
                resultsLimit: 400
            )
            var batch = CloudKitRemoteSnapshot()

            for result in changes.modificationResultsByID.values {
                let modification = try result.get()
                batch.add(record: modification.record)
            }

            let deletedAt = Date()
            batch.deletedRecords = changes.deletions.map {
                CloudKitDeletedRecord(
                    recordType: $0.recordType,
                    recordName: $0.recordID.recordName,
                    deletedAt: deletedAt
                )
            }
            batch.serverChangeTokenData = try Self.encodeChangeToken(changes.changeToken)
            aggregate.merge(batch)

            token = changes.changeToken
            moreComing = changes.moreComing
        }

        return aggregate
    }

    private func save(_ records: [CKRecord]) async throws {
        let chunkSize = 200
        var index = 0
        while index < records.count {
            let chunk = Array(records[index..<min(records.count, index + chunkSize)])
            _ = try await database.modifyRecords(saving: chunk, deleting: [])
            index += chunkSize
        }
    }

    private func records(from snapshot: CloudKitLocalSnapshot) throws -> [CKRecord] {
        var records = [CKRecord]()
        records.append(try settingsRecord(snapshot.settings))
        records.append(contentsOf: snapshot.conversations.map(conversationRecord))
        records.append(contentsOf: snapshot.messages.map(messageRecord))
        records.append(contentsOf: snapshot.documents.map(vaultDocumentRecord))
        records.append(contentsOf: snapshot.chunks.map(vaultChunkRecord))
        records.append(contentsOf: snapshot.embeddings.map(vaultEmbeddingRecord))
        return records
    }

    private func settingsRecord(_ settings: CloudKitSettingsSnapshot) throws -> CKRecord {
        let record = CKRecord(recordType: "AppSettings", recordID: CKRecord.ID(recordName: "app", zoneID: zoneID))
        let data = try JSONEncoder().encode(settings.value)
        record["valueJSON"] = String(decoding: data, as: UTF8.self) as CKRecordValue
        record["updatedAt"] = settings.updatedAt as CKRecordValue
        return record
    }

    private func conversationRecord(_ conversation: CloudKitConversationSnapshot) -> CKRecord {
        let record = CKRecord(recordType: "Conversation", recordID: CKRecord.ID(recordName: conversation.id.uuidString, zoneID: zoneID))
        record["title"] = conversation.title as CKRecordValue
        record["updatedAt"] = conversation.updatedAt as CKRecordValue
        record["deletedAt"] = conversation.deletedAt as CKRecordValue?
        record["defaultModelID"] = conversation.defaultModelID?.rawValue as CKRecordValue?
        record["defaultProviderID"] = conversation.defaultProviderID?.rawValue as CKRecordValue?
        record["archived"] = conversation.archived as CKRecordValue
        record["pinned"] = conversation.pinned as CKRecordValue
        return record
    }

    private func messageRecord(_ message: CloudKitMessageSnapshot) -> CKRecord {
        let record = CKRecord(recordType: "Message", recordID: CKRecord.ID(recordName: message.id.uuidString, zoneID: zoneID))
        record["conversationID"] = message.conversationID.uuidString as CKRecordValue
        record["role"] = message.role.rawValue as CKRecordValue
        record["content"] = message.content as CKRecordValue
        record["createdAt"] = message.createdAt as CKRecordValue
        record["updatedAt"] = message.updatedAt as CKRecordValue
        record["deletedAt"] = message.deletedAt as CKRecordValue?
        record["status"] = message.status.rawValue as CKRecordValue
        record["modelID"] = message.modelID?.rawValue as CKRecordValue?
        record["providerID"] = message.providerID?.rawValue as CKRecordValue?
        record["toolCallID"] = message.toolCallID as CKRecordValue?
        record["toolName"] = message.toolName as CKRecordValue?
        record["toolCallsJSON"] = Self.encodeToolCalls(message.toolCalls) as CKRecordValue?
        record["providerMetadataJSON"] = Self.encodeProviderMetadata(message.providerMetadata) as CKRecordValue?
        return record
    }

    private func vaultDocumentRecord(_ document: CloudKitVaultDocumentSnapshot) -> CKRecord {
        let record = CKRecord(recordType: "VaultDocument", recordID: CKRecord.ID(recordName: document.id.uuidString, zoneID: zoneID))
        record["title"] = document.title as CKRecordValue
        record["sourceType"] = document.sourceType as CKRecordValue
        record["updatedAt"] = document.updatedAt as CKRecordValue
        record["deletedAt"] = document.deletedAt as CKRecordValue?
        record["chunkCount"] = document.chunkCount as CKRecordValue
        return record
    }

    private func vaultChunkRecord(_ chunk: CloudKitVaultChunkSnapshot) -> CKRecord {
        let record = CKRecord(recordType: "VaultChunk", recordID: CKRecord.ID(recordName: chunk.id, zoneID: zoneID))
        record["documentID"] = chunk.documentID.uuidString as CKRecordValue
        record["ordinal"] = chunk.ordinal as CKRecordValue
        record["text"] = chunk.text as CKRecordValue
        record["tokenEstimate"] = chunk.tokenEstimate as CKRecordValue
        record["checksum"] = chunk.checksum as CKRecordValue
        record["createdAt"] = chunk.createdAt as CKRecordValue
        return record
    }

    private func vaultEmbeddingRecord(_ embedding: VaultStoredEmbedding) -> CKRecord {
        let recordName = "\(embedding.chunkID)-\(Self.stableRecordSuffix(embedding.modelID.rawValue))"
        let record = CKRecord(recordType: "VaultEmbedding", recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        record["chunkID"] = embedding.chunkID as CKRecordValue
        record["documentID"] = embedding.documentID.uuidString as CKRecordValue
        record["modelID"] = embedding.modelID.rawValue as CKRecordValue
        record["dimensions"] = embedding.dimensions as CKRecordValue
        record["fp16Embedding"] = embedding.fp16Embedding as NSData
        record["turboQuantCode"] = embedding.turboQuantCode as NSData
        record["norm"] = embedding.norm as CKRecordValue
        record["codecVersion"] = embedding.codecVersion as CKRecordValue
        record["checksum"] = embedding.checksum as CKRecordValue
        record["createdAt"] = embedding.createdAt as CKRecordValue
        return record
    }

    private static func encodeChangeToken(_ token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func decodeChangeToken(from data: Data) throws -> CKServerChangeToken? {
        try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func encodeProviderMetadata(_ metadata: [String: String]) -> String? {
        guard !metadata.isEmpty else {
            return nil
        }
        do {
            let data = try JSONEncoder().encode(metadata)
            return String(decoding: data, as: UTF8.self)
        } catch {
            cloudKitSyncLogger.error("Failed to encode CloudKit provider metadata: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func encodeToolCalls(_ toolCalls: [ToolCallDelta]) -> String? {
        guard !toolCalls.isEmpty else {
            return nil
        }
        do {
            let data = try JSONEncoder().encode(toolCalls)
            return String(decoding: data, as: UTF8.self)
        } catch {
            cloudKitSyncLogger.error("Failed to encode CloudKit tool calls: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    fileprivate static func stableRecordSuffix(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private extension CloudKitRemoteSnapshot {
    mutating func add(record: CKRecord) {
        switch record.recordType {
        case "AppSettings":
            guard let valueJSON = record["valueJSON"] as? String,
                  let updatedAt = record["updatedAt"] as? Date
            else { return }
            do {
                let value = try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data(valueJSON.utf8))
                settings = CloudKitSettingsSnapshot(value: value, updatedAt: updatedAt)
            } catch {
                cloudKitSyncLogger.error("Failed to decode CloudKit app settings record \(record.recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

        case "Conversation":
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let title = record["title"] as? String,
                  let updatedAt = record["updatedAt"] as? Date
            else { return }
            conversations.append(
                CloudKitConversationSnapshot(
                    id: id,
                    title: title,
                    updatedAt: updatedAt,
                    deletedAt: record["deletedAt"] as? Date,
                    defaultModelID: (record["defaultModelID"] as? String).map(ModelID.init(rawValue:)),
                    defaultProviderID: (record["defaultProviderID"] as? String).map(ProviderID.init(rawValue:)),
                    archived: Self.bool("archived", in: record),
                    pinned: Self.bool("pinned", in: record)
                )
            )

        case "Message":
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let conversationIDString = record["conversationID"] as? String,
                  let conversationID = UUID(uuidString: conversationIDString),
                  let roleValue = record["role"] as? String,
                  let role = ChatRole(rawValue: roleValue),
                  let content = record["content"] as? String,
                  let createdAt = record["createdAt"] as? Date
            else { return }
            let updatedAt = (record["updatedAt"] as? Date) ?? createdAt
            messages.append(
                CloudKitMessageSnapshot(
                    id: id,
                    conversationID: conversationID,
                    role: role,
                    content: content,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    deletedAt: record["deletedAt"] as? Date,
                    status: (record["status"] as? String).flatMap(MessageStatus.init(rawValue:)) ?? .complete,
                    modelID: (record["modelID"] as? String).map(ModelID.init(rawValue:)),
                    providerID: (record["providerID"] as? String).map(ProviderID.init(rawValue:)),
                    toolCallID: record["toolCallID"] as? String,
                    toolName: record["toolName"] as? String,
                    toolCalls: Self.decodeToolCalls(record["toolCallsJSON"] as? String),
                    providerMetadata: Self.decodeProviderMetadata(record["providerMetadataJSON"] as? String)
                )
            )

        case "VaultDocument":
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let title = record["title"] as? String,
                  let sourceType = record["sourceType"] as? String,
                  let updatedAt = record["updatedAt"] as? Date
            else { return }
            documents.append(
                CloudKitVaultDocumentSnapshot(
                    id: id,
                    title: title,
                    sourceType: sourceType,
                    updatedAt: updatedAt,
                    deletedAt: record["deletedAt"] as? Date,
                    chunkCount: Self.int("chunkCount", in: record)
                )
            )

        case "VaultChunk":
            guard let documentIDString = record["documentID"] as? String,
                  let documentID = UUID(uuidString: documentIDString),
                  let text = record["text"] as? String
            else { return }
            chunks.append(
                CloudKitVaultChunkSnapshot(
                    id: record.recordID.recordName,
                    documentID: documentID,
                    ordinal: Self.int("ordinal", in: record),
                    text: text,
                    tokenEstimate: max(1, Self.int("tokenEstimate", in: record)),
                    checksum: (record["checksum"] as? String) ?? CloudKitSyncService.stableRecordSuffix(text),
                    createdAt: (record["createdAt"] as? Date) ?? Date(timeIntervalSinceReferenceDate: 0)
                )
            )

        case "VaultEmbedding":
            guard let chunkID = record["chunkID"] as? String,
                  let documentIDString = record["documentID"] as? String,
                  let documentID = UUID(uuidString: documentIDString),
                  let modelIDValue = record["modelID"] as? String,
                  let fp16Embedding = Self.data("fp16Embedding", in: record),
                  let turboQuantCode = Self.data("turboQuantCode", in: record)
            else { return }
            embeddings.append(
                VaultStoredEmbedding(
                    chunkID: chunkID,
                    documentID: documentID,
                    modelID: ModelID(rawValue: modelIDValue),
                    dimensions: Self.int("dimensions", in: record),
                    fp16Embedding: fp16Embedding,
                    turboQuantCode: turboQuantCode,
                    norm: Self.double("norm", in: record),
                    codecVersion: Self.int("codecVersion", in: record),
                    checksum: (record["checksum"] as? String) ?? "",
                    createdAt: (record["createdAt"] as? Date) ?? Date(timeIntervalSinceReferenceDate: 0)
                )
            )

        default:
            return
        }
    }

    private static func bool(_ key: String, in record: CKRecord) -> Bool {
        if let value = record[key] as? Bool { return value }
        if let value = record[key] as? NSNumber { return value.boolValue }
        return false
    }

    private static func int(_ key: String, in record: CKRecord) -> Int {
        if let value = record[key] as? Int { return value }
        if let value = record[key] as? NSNumber { return value.intValue }
        return 0
    }

    private static func double(_ key: String, in record: CKRecord) -> Double {
        if let value = record[key] as? Double { return value }
        if let value = record[key] as? NSNumber { return value.doubleValue }
        return 0
    }

    private static func data(_ key: String, in record: CKRecord) -> Data? {
        if let value = record[key] as? Data { return value }
        if let value = record[key] as? NSData { return value as Data }
        return nil
    }

    private static func encodeProviderMetadata(_ metadata: [String: String]) -> String? {
        guard !metadata.isEmpty else {
            return nil
        }
        do {
            let data = try JSONEncoder().encode(metadata)
            return String(decoding: data, as: UTF8.self)
        } catch {
            cloudKitSyncLogger.error("Failed to encode CloudKit provider metadata: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func decodeProviderMetadata(_ rawValue: String?) -> [String: String] {
        guard let rawValue, let data = rawValue.data(using: .utf8) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            cloudKitSyncLogger.error("Failed to decode CloudKit provider metadata: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private static func decodeToolCalls(_ rawValue: String?) -> [ToolCallDelta] {
        guard let rawValue, let data = rawValue.data(using: .utf8) else {
            return []
        }
        do {
            return try JSONDecoder().decode([ToolCallDelta].self, from: data)
        } catch {
            cloudKitSyncLogger.error("Failed to decode CloudKit tool calls: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
