import CloudKit
import Foundation
import PinesCore

struct CloudKitSyncService {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "PinesPrivate", ownerName: CKCurrentUserDefaultName)

    let conversationRepository: any ConversationRepository
    let vaultRepository: any VaultRepository
    let settingsRepository: any SettingsRepository
    let auditRepository: (any AuditEventRepository)?

    init(
        containerIdentifier: String = "iCloud.com.schtack.pines",
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

    func syncNow() async throws {
        let settings = try await settingsRepository.loadSettings()
        guard settings.storeConfiguration.iCloudSyncEnabled else { return }
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

        let documents = try await vaultRepository.listDocuments()
        for document in documents {
            records.append(vaultDocumentRecord(document))
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
}
