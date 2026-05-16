import CloudKit
import Foundation
import PinesCore

struct CloudKitSyncService {
    static let defaultContainerIdentifier = "iCloud.com.schtack.pines"

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "PinesPrivate", ownerName: CKCurrentUserDefaultName)

    let conversationRepository: any ConversationRepository
    let vaultRepository: any VaultRepository
    let settingsRepository: any SettingsRepository
    let auditRepository: (any AuditEventRepository)?

    init(
        containerIdentifier: String = Self.defaultContainerIdentifier,
        conversationRepository: any ConversationRepository,
        vaultRepository: any VaultRepository,
        settingsRepository: any SettingsRepository,
        auditRepository: (any AuditEventRepository)?
    ) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        self.conversationRepository = conversationRepository
        self.vaultRepository = vaultRepository
        self.settingsRepository = settingsRepository
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
        try await ensureZone()

        var records = [CKRecord]()
        records.append(try settingsRecord(settings))

        let conversations = try await conversationRepository.listConversations()
        for conversation in conversations {
            records.append(conversationRecord(conversation))
            let messages = try await conversationRepository.messages(in: conversation.id)
            for message in messages {
                records.append(messageRecord(message, conversationID: conversation.id))
            }
        }

        if settings.storeConfiguration.syncsSourceDocuments {
            let documents = try await vaultRepository.listDocuments()
            for document in documents {
                records.append(vaultDocumentRecord(document))
                let chunks = try await vaultRepository.chunks(documentID: document.id)
                records.append(contentsOf: chunks.map { vaultChunkRecord($0, documentID: document.id) })

                if settings.storeConfiguration.syncsEmbeddings {
                    let embeddings = try await vaultRepository.embeddings(documentID: document.id)
                    records.append(contentsOf: embeddings.map(vaultEmbeddingRecord))
                }
            }
        }

        try await save(records)
        try await auditRepository?.append(
            AuditEvent(category: .security, summary: "Completed iCloud private database sync.")
        )
    }

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
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

    private func settingsRecord(_ settings: AppSettingsSnapshot) throws -> CKRecord {
        let record = CKRecord(recordType: "AppSettings", recordID: CKRecord.ID(recordName: "app", zoneID: zoneID))
        let data = try JSONEncoder().encode(settings)
        record["valueJSON"] = String(decoding: data, as: UTF8.self) as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func conversationRecord(_ conversation: ConversationRecord) -> CKRecord {
        let record = CKRecord(recordType: "Conversation", recordID: CKRecord.ID(recordName: conversation.id.uuidString, zoneID: zoneID))
        record["title"] = conversation.title as CKRecordValue
        record["updatedAt"] = conversation.updatedAt as CKRecordValue
        record["defaultModelID"] = conversation.defaultModelID?.rawValue as CKRecordValue?
        record["defaultProviderID"] = conversation.defaultProviderID?.rawValue as CKRecordValue?
        record["archived"] = conversation.archived as CKRecordValue
        record["pinned"] = conversation.pinned as CKRecordValue
        return record
    }

    private func messageRecord(_ message: ChatMessage, conversationID: UUID) -> CKRecord {
        let record = CKRecord(recordType: "Message", recordID: CKRecord.ID(recordName: message.id.uuidString, zoneID: zoneID))
        record["conversationID"] = conversationID.uuidString as CKRecordValue
        record["role"] = message.role.rawValue as CKRecordValue
        record["content"] = message.content as CKRecordValue
        record["createdAt"] = message.createdAt as CKRecordValue
        record["toolCallID"] = message.toolCallID as CKRecordValue?
        return record
    }

    private func vaultDocumentRecord(_ document: VaultDocumentRecord) -> CKRecord {
        let record = CKRecord(recordType: "VaultDocument", recordID: CKRecord.ID(recordName: document.id.uuidString, zoneID: zoneID))
        record["title"] = document.title as CKRecordValue
        record["sourceType"] = document.sourceType as CKRecordValue
        record["updatedAt"] = document.updatedAt as CKRecordValue
        record["chunkCount"] = document.chunkCount as CKRecordValue
        return record
    }

    private func vaultChunkRecord(_ chunk: VaultChunk, documentID: UUID) -> CKRecord {
        let record = CKRecord(recordType: "VaultChunk", recordID: CKRecord.ID(recordName: chunk.id, zoneID: zoneID))
        record["documentID"] = documentID.uuidString as CKRecordValue
        record["ordinal"] = chunk.ordinal as CKRecordValue
        record["text"] = chunk.text as CKRecordValue
        record["startOffset"] = chunk.startOffset as CKRecordValue
        record["endOffset"] = chunk.endOffset as CKRecordValue
        record["checksum"] = chunk.checksum as CKRecordValue
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

    private static func stableRecordSuffix(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
