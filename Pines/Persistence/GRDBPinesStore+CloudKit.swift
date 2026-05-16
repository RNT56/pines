import Foundation
import PinesCore

#if canImport(GRDB)
import GRDB

extension GRDBPinesStore: CloudKitSyncRepository {
    func cloudKitLocalSnapshot(includeVault: Bool, includeEmbeddings: Bool, includeClean: Bool) async throws -> CloudKitLocalSnapshot {
        try await database.read { db in
            let settings = try Self.fetchCloudKitSettings(db)
            let conversations = try Self.fetchCloudKitConversations(db, includeClean: includeClean)
            let messages = try Self.fetchCloudKitMessages(db, includeClean: includeClean)

            guard includeVault else {
                return CloudKitLocalSnapshot(
                    settings: settings,
                    conversations: conversations,
                    messages: messages,
                    documents: [],
                    chunks: [],
                    embeddings: []
                )
            }

            return CloudKitLocalSnapshot(
                settings: settings,
                conversations: conversations,
                messages: messages,
                documents: try Self.fetchCloudKitDocuments(db, includeClean: includeClean),
                chunks: try Self.fetchCloudKitChunks(db, includeClean: includeClean),
                embeddings: includeEmbeddings ? try Self.fetchCloudKitEmbeddings(db, includeClean: includeClean) : []
            )
        }
    }

    func applyCloudKitSnapshot(_ snapshot: CloudKitRemoteSnapshot) async throws {
        try await database.write { db in
            if let settings = snapshot.settings {
                try Self.applyCloudKitSettings(settings, db: db)
            }

            for deletion in snapshot.deletedRecords {
                try Self.applyCloudKitDeletion(deletion, db: db)
            }
            for conversation in snapshot.conversations {
                try Self.applyCloudKitConversation(conversation, db: db)
            }
            for message in snapshot.messages {
                try Self.applyCloudKitMessage(message, db: db)
            }
            for document in snapshot.documents {
                try Self.applyCloudKitDocument(document, db: db)
            }
            for chunk in snapshot.chunks {
                try Self.applyCloudKitChunk(chunk, db: db)
            }
            for embedding in snapshot.embeddings {
                try Self.applyCloudKitEmbedding(embedding, db: db)
            }
        }
    }

    func cloudKitServerChangeTokenData(zoneName: String) async throws -> Data? {
        try await database.read { db in
            guard let encoded = try String.fetchOne(
                db,
                sql: "SELECT change_tag FROM sync_records WHERE entity_table = ? AND entity_id = ?",
                arguments: ["cloudkit_zone", zoneName]
            ) else {
                return nil
            }
            return Data(base64Encoded: encoded)
        }
    }

    func saveCloudKitServerChangeTokenData(_ data: Data?, zoneName: String) async throws {
        try await database.write { db in
            guard let data else {
                try db.execute(
                    sql: "DELETE FROM sync_records WHERE entity_table = ? AND entity_id = ?",
                    arguments: ["cloudkit_zone", zoneName]
                )
                return
            }

            try db.execute(
                sql: """
                INSERT INTO sync_records (id, entity_table, entity_id, cloud_record_name, change_tag, state, last_synced_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(entity_table, entity_id) DO UPDATE SET
                    change_tag = excluded.change_tag,
                    state = excluded.state,
                    last_synced_at = excluded.last_synced_at
                """,
                arguments: [
                    "cloudkit-zone-\(zoneName)",
                    "cloudkit_zone",
                    zoneName,
                    zoneName,
                    data.base64EncodedString(),
                    SyncState.synced.rawValue,
                    Date().timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    private static func fetchCloudKitSettings(_ db: Database) throws -> CloudKitSettingsSnapshot {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT value_json, updated_at FROM app_settings WHERE key = ?",
            arguments: ["app"]
        ) else {
            return CloudKitSettingsSnapshot(
                value: AppSettingsSnapshot(),
                updatedAt: Date(timeIntervalSinceReferenceDate: 0)
            )
        }
        let data = Data((row["value_json"] as String).utf8)
        return CloudKitSettingsSnapshot(
            value: try JSONDecoder().decode(AppSettingsSnapshot.self, from: data),
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"])
        )
    }

    private static func fetchCloudKitConversations(_ db: Database, includeClean: Bool) throws -> [CloudKitConversationSnapshot] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT id, title, updated_at, deleted_at, default_model_id, default_provider_id, archived_at, pinned
            FROM conversations
            WHERE ? OR sync_state != ?
            ORDER BY updated_at ASC
            """,
            arguments: [includeClean ? 1 : 0, SyncState.synced.rawValue]
        ).compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return CloudKitConversationSnapshot(
                id: id,
                title: row["title"],
                updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
                deletedAt: (row["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
                defaultModelID: (row["default_model_id"] as String?).map(ModelID.init(rawValue:)),
                defaultProviderID: (row["default_provider_id"] as String?).map(ProviderID.init(rawValue:)),
                archived: (row["archived_at"] as Double?) != nil,
                pinned: (row["pinned"] as Int) == 1
            )
        }
    }

    private static func fetchCloudKitMessages(_ db: Database, includeClean: Bool) throws -> [CloudKitMessageSnapshot] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT m.id, m.conversation_id, m.role, m.content, m.created_at,
                   COALESCE(m.updated_at, m.created_at) AS updated_at,
                   m.deleted_at, m.status, m.model_id, m.provider_id, m.tool_call_id
            FROM messages m
            JOIN conversations c ON c.id = m.conversation_id
            WHERE c.deleted_at IS NULL AND (? OR m.sync_state != ?)
            ORDER BY m.created_at ASC
            """,
            arguments: [includeClean ? 1 : 0, SyncState.synced.rawValue]
        ).compactMap { row in
            guard let id = UUID(uuidString: row["id"]),
                  let conversationID = UUID(uuidString: row["conversation_id"])
            else { return nil }
            return CloudKitMessageSnapshot(
                id: id,
                conversationID: conversationID,
                role: ChatRole(rawValue: row["role"]) ?? .assistant,
                content: row["content"],
                createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
                updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
                deletedAt: (row["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
                status: MessageStatus(rawValue: row["status"]) ?? .complete,
                modelID: (row["model_id"] as String?).map(ModelID.init(rawValue:)),
                providerID: (row["provider_id"] as String?).map(ProviderID.init(rawValue:)),
                toolCallID: row["tool_call_id"] as String?
            )
        }
    }

    private static func fetchCloudKitDocuments(_ db: Database, includeClean: Bool) throws -> [CloudKitVaultDocumentSnapshot] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT d.id, d.title, d.source_type, d.updated_at, d.sync_state, COUNT(c.id) AS chunk_count
            FROM vault_documents d
            LEFT JOIN vault_chunks c ON c.document_id = d.id
            WHERE ? OR d.sync_state != ?
            GROUP BY d.id
            ORDER BY d.updated_at ASC
            """,
            arguments: [includeClean ? 1 : 0, SyncState.synced.rawValue]
        ).compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let updatedAt = Date(timeIntervalSinceReferenceDate: row["updated_at"])
            let syncState = SyncState(rawValue: row["sync_state"]) ?? .local
            return CloudKitVaultDocumentSnapshot(
                id: id,
                title: row["title"],
                sourceType: row["source_type"],
                updatedAt: updatedAt,
                deletedAt: syncState == .deleted ? updatedAt : nil,
                chunkCount: row["chunk_count"]
            )
        }
    }

    private static func fetchCloudKitChunks(_ db: Database, includeClean: Bool) throws -> [CloudKitVaultChunkSnapshot] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT c.id, c.document_id, c.ordinal, c.text, c.token_estimate, c.created_at
            FROM vault_chunks c
            JOIN vault_documents d ON d.id = c.document_id
            WHERE d.sync_state != ? AND (? OR d.sync_state != ?)
            ORDER BY c.document_id ASC, c.ordinal ASC
            """,
            arguments: [SyncState.deleted.rawValue, includeClean ? 1 : 0, SyncState.synced.rawValue]
        ).compactMap { row in
            guard let documentID = UUID(uuidString: row["document_id"]) else { return nil }
            let text: String = row["text"]
            return CloudKitVaultChunkSnapshot(
                id: row["id"],
                documentID: documentID,
                ordinal: row["ordinal"],
                text: text,
                tokenEstimate: row["token_estimate"],
                checksum: StableSearchHash.hexDigest(for: text),
                createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"])
            )
        }
    }

    private static func fetchCloudKitEmbeddings(_ db: Database, includeClean: Bool) throws -> [VaultStoredEmbedding] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT e.chunk_id, e.document_id, e.embedding_model_id, e.dimensions, e.fp16_embedding,
                   e.turboquant_code, e.norm, e.codec_version, e.checksum, e.created_at
            FROM vault_embeddings e
            JOIN vault_documents d ON d.id = e.document_id
            WHERE d.sync_state != ? AND (? OR d.sync_state != ?)
            ORDER BY e.document_id ASC, e.chunk_id ASC, e.embedding_model_id ASC
            """,
            arguments: [SyncState.deleted.rawValue, includeClean ? 1 : 0, SyncState.synced.rawValue]
        ).map(vaultStoredEmbedding(from:))
    }

    private static func applyCloudKitSettings(_ settings: CloudKitSettingsSnapshot, db: Database) throws {
        let localUpdatedAt = try Double.fetchOne(
            db,
            sql: "SELECT updated_at FROM app_settings WHERE key = ?",
            arguments: ["app"]
        ).map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date(timeIntervalSinceReferenceDate: 0)
        guard settings.updatedAt >= localUpdatedAt else { return }

        let json = String(decoding: try JSONEncoder().encode(settings.value), as: UTF8.self)
        try db.execute(
            sql: """
            INSERT INTO app_settings (key, value_json, updated_at, sync_state)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value_json = excluded.value_json,
                updated_at = excluded.updated_at,
                sync_state = excluded.sync_state
            """,
            arguments: ["app", json, settings.updatedAt.timeIntervalSinceReferenceDate, SyncState.synced.rawValue]
        )
    }

    private static func applyCloudKitConversation(_ conversation: CloudKitConversationSnapshot, db: Database) throws {
        let local = try Row.fetchOne(
            db,
            sql: "SELECT updated_at, deleted_at FROM conversations WHERE id = ?",
            arguments: [conversation.id.uuidString]
        )
        let localUpdatedAt = (local?["updated_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            ?? Date(timeIntervalSinceReferenceDate: 0)
        let localDeletedAt = (local?["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))

        if let remoteDeletedAt = conversation.deletedAt {
            guard local == nil || remoteDeletedAt >= max(localUpdatedAt, localDeletedAt ?? Date(timeIntervalSinceReferenceDate: 0)) else {
                return
            }
            try upsertCloudKitConversation(conversation, deletedAt: remoteDeletedAt, db: db)
            return
        }

        if let localDeletedAt, localDeletedAt >= conversation.updatedAt {
            return
        }
        guard local == nil || conversation.updatedAt >= localUpdatedAt else {
            return
        }
        try upsertCloudKitConversation(conversation, deletedAt: nil, db: db)
    }

    private static func upsertCloudKitConversation(
        _ conversation: CloudKitConversationSnapshot,
        deletedAt: Date?,
        db: Database
    ) throws {
        let updatedAt = (deletedAt ?? conversation.updatedAt).timeIntervalSinceReferenceDate
        try db.execute(
            sql: """
            INSERT INTO conversations
                (id, title, created_at, updated_at, default_model_id, default_provider_id, archived_at, deleted_at, pinned, sync_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                default_model_id = excluded.default_model_id,
                default_provider_id = excluded.default_provider_id,
                archived_at = excluded.archived_at,
                deleted_at = excluded.deleted_at,
                pinned = excluded.pinned,
                sync_state = excluded.sync_state
            """,
            arguments: [
                conversation.id.uuidString,
                conversation.title,
                min(conversation.updatedAt.timeIntervalSinceReferenceDate, updatedAt),
                updatedAt,
                conversation.defaultModelID?.rawValue,
                conversation.defaultProviderID?.rawValue,
                conversation.archived ? updatedAt : nil,
                deletedAt?.timeIntervalSinceReferenceDate,
                conversation.pinned ? 1 : 0,
                deletedAt == nil ? SyncState.synced.rawValue : SyncState.deleted.rawValue,
            ]
        )
    }

    private static func applyCloudKitMessage(_ message: CloudKitMessageSnapshot, db: Database) throws {
        let parentIsActive = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM conversations WHERE id = ? AND deleted_at IS NULL)",
            arguments: [message.conversationID.uuidString]
        ) ?? false
        guard parentIsActive else { return }

        let local = try Row.fetchOne(
            db,
            sql: "SELECT COALESCE(updated_at, created_at) AS updated_at, deleted_at FROM messages WHERE id = ?",
            arguments: [message.id.uuidString]
        )
        let localUpdatedAt = (local?["updated_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            ?? Date(timeIntervalSinceReferenceDate: 0)
        let localDeletedAt = (local?["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))

        if let remoteDeletedAt = message.deletedAt {
            guard remoteDeletedAt >= max(localUpdatedAt, localDeletedAt ?? Date(timeIntervalSinceReferenceDate: 0)) else {
                return
            }
            try db.execute(
                sql: """
                INSERT INTO messages
                    (id, conversation_id, role, content, created_at, updated_at, deleted_at, status, model_id, provider_id, tool_call_id, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    conversation_id = excluded.conversation_id,
                    role = excluded.role,
                    content = excluded.content,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at,
                    status = excluded.status,
                    model_id = excluded.model_id,
                    provider_id = excluded.provider_id,
                    tool_call_id = excluded.tool_call_id,
                    sync_state = excluded.sync_state
                """,
                arguments: [
                    message.id.uuidString,
                    message.conversationID.uuidString,
                    message.role.rawValue,
                    message.content,
                    message.createdAt.timeIntervalSinceReferenceDate,
                    remoteDeletedAt.timeIntervalSinceReferenceDate,
                    remoteDeletedAt.timeIntervalSinceReferenceDate,
                    message.status.rawValue,
                    message.modelID?.rawValue,
                    message.providerID?.rawValue,
                    message.toolCallID,
                    SyncState.deleted.rawValue,
                ]
            )
            return
        }

        if let localDeletedAt, localDeletedAt >= message.updatedAt {
            return
        }
        guard local == nil || message.updatedAt >= localUpdatedAt else {
            return
        }

        try db.execute(
            sql: """
            INSERT INTO messages
                (id, conversation_id, role, content, created_at, updated_at, deleted_at, status, model_id, provider_id, tool_call_id, sync_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                conversation_id = excluded.conversation_id,
                role = excluded.role,
                content = excluded.content,
                updated_at = excluded.updated_at,
                deleted_at = NULL,
                status = excluded.status,
                model_id = excluded.model_id,
                provider_id = excluded.provider_id,
                tool_call_id = excluded.tool_call_id,
                sync_state = excluded.sync_state
            """,
            arguments: [
                message.id.uuidString,
                message.conversationID.uuidString,
                message.role.rawValue,
                message.content,
                message.createdAt.timeIntervalSinceReferenceDate,
                message.updatedAt.timeIntervalSinceReferenceDate,
                nil,
                message.status.rawValue,
                message.modelID?.rawValue,
                message.providerID?.rawValue,
                message.toolCallID,
                SyncState.synced.rawValue,
            ]
        )
    }

    private static func applyCloudKitDocument(_ document: CloudKitVaultDocumentSnapshot, db: Database) throws {
        let local = try Row.fetchOne(
            db,
            sql: "SELECT updated_at, sync_state FROM vault_documents WHERE id = ?",
            arguments: [document.id.uuidString]
        )
        let localUpdatedAt = (local?["updated_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            ?? Date(timeIntervalSinceReferenceDate: 0)
        let localSyncState = (local?["sync_state"] as String?).flatMap(SyncState.init(rawValue:))

        if let remoteDeletedAt = document.deletedAt {
            guard local == nil || remoteDeletedAt >= localUpdatedAt else { return }
            try upsertCloudKitDocument(document, syncState: .deleted, updatedAt: remoteDeletedAt, db: db)
            return
        }

        if localSyncState == .deleted && localUpdatedAt >= document.updatedAt {
            return
        }
        guard local == nil || document.updatedAt >= localUpdatedAt else {
            return
        }
        try upsertCloudKitDocument(document, syncState: .synced, updatedAt: document.updatedAt, db: db)
    }

    private static func upsertCloudKitDocument(
        _ document: CloudKitVaultDocumentSnapshot,
        syncState: SyncState,
        updatedAt: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO vault_documents
                (id, title, source_type, created_at, updated_at, sync_state)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                source_type = excluded.source_type,
                updated_at = excluded.updated_at,
                sync_state = excluded.sync_state
            """,
            arguments: [
                document.id.uuidString,
                document.title,
                document.sourceType,
                updatedAt.timeIntervalSinceReferenceDate,
                updatedAt.timeIntervalSinceReferenceDate,
                syncState.rawValue,
            ]
        )
    }

    private static func applyCloudKitChunk(_ chunk: CloudKitVaultChunkSnapshot, db: Database) throws {
        let parentIsActive = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM vault_documents WHERE id = ? AND sync_state != ?)",
            arguments: [chunk.documentID.uuidString, SyncState.deleted.rawValue]
        ) ?? false
        guard parentIsActive else { return }

        try db.execute(
            sql: """
            INSERT INTO vault_chunks
                (id, document_id, ordinal, text, token_estimate, embedding_model_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                document_id = excluded.document_id,
                ordinal = excluded.ordinal,
                text = excluded.text,
                token_estimate = excluded.token_estimate
            """,
            arguments: [
                chunk.id,
                chunk.documentID.uuidString,
                chunk.ordinal,
                chunk.text,
                chunk.tokenEstimate,
                nil,
                chunk.createdAt.timeIntervalSinceReferenceDate,
            ]
        )
    }

    private static func applyCloudKitEmbedding(_ embedding: VaultStoredEmbedding, db: Database) throws {
        let chunkIsActive = try Bool.fetchOne(
            db,
            sql: """
            SELECT EXISTS(
                SELECT 1
                FROM vault_chunks c
                JOIN vault_documents d ON d.id = c.document_id
                WHERE c.id = ? AND d.sync_state != ?
            )
            """,
            arguments: [embedding.chunkID, SyncState.deleted.rawValue]
        ) ?? false
        guard chunkIsActive else { return }

        try db.execute(
            sql: """
            INSERT INTO vault_embeddings
                (chunk_id, document_id, embedding_model_id, dimensions, fp16_embedding,
                 turboquant_code, norm, codec_version, checksum, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chunk_id, embedding_model_id) DO UPDATE SET
                document_id = excluded.document_id,
                dimensions = excluded.dimensions,
                fp16_embedding = excluded.fp16_embedding,
                turboquant_code = excluded.turboquant_code,
                norm = excluded.norm,
                codec_version = excluded.codec_version,
                checksum = excluded.checksum,
                created_at = excluded.created_at
            """,
            arguments: [
                embedding.chunkID,
                embedding.documentID.uuidString,
                embedding.modelID.rawValue,
                embedding.dimensions,
                embedding.fp16Embedding,
                embedding.turboQuantCode,
                embedding.norm,
                embedding.codecVersion,
                embedding.checksum,
                embedding.createdAt.timeIntervalSinceReferenceDate,
            ]
        )
    }

    private static func applyCloudKitDeletion(_ deletion: CloudKitDeletedRecord, db: Database) throws {
        let deletedAt = deletion.deletedAt.timeIntervalSinceReferenceDate
        switch deletion.recordType {
        case "Conversation":
            try db.execute(
                sql: "UPDATE conversations SET deleted_at = ?, updated_at = ?, sync_state = ? WHERE id = ? AND updated_at <= ?",
                arguments: [deletedAt, deletedAt, SyncState.deleted.rawValue, deletion.recordName, deletedAt]
            )
        case "Message":
            try db.execute(
                sql: "UPDATE messages SET deleted_at = ?, updated_at = ?, sync_state = ? WHERE id = ? AND COALESCE(updated_at, created_at) <= ?",
                arguments: [deletedAt, deletedAt, SyncState.deleted.rawValue, deletion.recordName, deletedAt]
            )
        case "VaultDocument":
            try db.execute(
                sql: "UPDATE vault_documents SET sync_state = ?, updated_at = ? WHERE id = ? AND updated_at <= ?",
                arguments: [SyncState.deleted.rawValue, deletedAt, deletion.recordName, deletedAt]
            )
        case "VaultChunk":
            try db.execute(sql: "DELETE FROM vault_chunks WHERE id = ?", arguments: [deletion.recordName])
        case "VaultEmbedding":
            let parts = deletion.recordName.split(separator: "-")
            guard let suffix = parts.last else { return }
            let chunkID = parts.dropLast().joined(separator: "-")
            guard !chunkID.isEmpty else { return }
            let modelIDs = try String.fetchAll(
                db,
                sql: "SELECT embedding_model_id FROM vault_embeddings WHERE chunk_id = ?",
                arguments: [chunkID]
            )
            for modelID in modelIDs where StableSearchHash.hexDigest(for: modelID) == suffix {
                try db.execute(
                    sql: "DELETE FROM vault_embeddings WHERE chunk_id = ? AND embedding_model_id = ?",
                    arguments: [chunkID, modelID]
                )
            }
        default:
            return
        }
    }
}

enum StableSearchHash {
    static func hexDigest(for text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
#endif
