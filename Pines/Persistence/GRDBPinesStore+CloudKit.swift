import Foundation
import PinesCore

#if canImport(GRDB)
import GRDB

extension GRDBPinesStore: CloudKitSyncRepository {
    func cloudKitLocalSnapshot(includeVault: Bool, includeEmbeddings: Bool, includeClean: Bool) async throws -> CloudKitLocalSnapshot {
        try await database.read { db in
            let settings = try Self.fetchCloudKitSettings(db)
            let projects = try Self.fetchCloudKitProjects(db, includeClean: includeClean)
            let conversations = try Self.fetchCloudKitConversations(db, includeClean: includeClean)
            let messages = try Self.fetchCloudKitMessages(db, includeClean: includeClean)

            guard includeVault else {
                return CloudKitLocalSnapshot(
                    settings: settings,
                    projects: projects,
                    conversations: conversations,
                    messages: messages,
                    documents: [],
                    chunks: [],
                    embeddings: []
                )
            }

            return CloudKitLocalSnapshot(
                settings: settings,
                projects: projects,
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
            for project in snapshot.projects {
                try Self.applyCloudKitProject(project, db: db)
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

    private static func fetchCloudKitProjects(_ db: Database, includeClean: Bool) throws -> [CloudKitProjectSnapshot] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT id, name, vault_enabled, created_at, updated_at, deleted_at
            FROM projects
            WHERE ? OR sync_state != ?
            ORDER BY updated_at ASC
            """,
            arguments: [includeClean ? 1 : 0, SyncState.synced.rawValue]
        ).compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return CloudKitProjectSnapshot(
                id: id,
                name: row["name"],
                vaultEnabled: (row["vault_enabled"] as Int) == 1,
                createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
                updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
                deletedAt: (row["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            )
        }
    }

    private static func fetchCloudKitConversations(_ db: Database, includeClean: Bool) throws -> [CloudKitConversationSnapshot] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT id, title, updated_at, deleted_at, default_model_id, default_provider_id, project_id, archived_at, pinned
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
                projectID: (row["project_id"] as String?).flatMap(UUID.init(uuidString:)),
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
                   m.deleted_at, m.status, m.model_id, m.provider_id, m.tool_call_id,
                   m.tool_name, m.tool_calls_json, m.provider_metadata_json
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
                toolCallID: row["tool_call_id"] as String?,
                toolName: row["tool_name"] as String?,
                toolCalls: decodeToolCalls(row["tool_calls_json"] as String?),
                providerMetadata: decodeProviderMetadata(row["provider_metadata_json"] as String?)
            )
        }
    }

    private static func fetchCloudKitDocuments(_ db: Database, includeClean: Bool) throws -> [CloudKitVaultDocumentSnapshot] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT d.id, d.title, d.source_type, d.project_id, d.updated_at, d.sync_state, COUNT(c.id) AS chunk_count
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
                projectID: (row["project_id"] as String?).flatMap(UUID.init(uuidString:)),
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

    private static func applyCloudKitProject(_ project: CloudKitProjectSnapshot, db: Database) throws {
        let local = try Row.fetchOne(
            db,
            sql: "SELECT updated_at, deleted_at FROM projects WHERE id = ?",
            arguments: [project.id.uuidString]
        )
        let localUpdatedAt = (local?["updated_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            ?? Date(timeIntervalSinceReferenceDate: 0)
        let localDeletedAt = (local?["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))

        if let remoteDeletedAt = project.deletedAt {
            guard local == nil || remoteDeletedAt >= max(localUpdatedAt, localDeletedAt ?? .distantPast) else {
                return
            }
            try upsertCloudKitProject(project, deletedAt: remoteDeletedAt, db: db)
            return
        }

        if let localDeletedAt, localDeletedAt >= project.updatedAt {
            return
        }
        guard local == nil || project.updatedAt >= localUpdatedAt else { return }
        try upsertCloudKitProject(project, deletedAt: nil, db: db)
    }

    private static func upsertCloudKitProject(
        _ project: CloudKitProjectSnapshot,
        deletedAt: Date?,
        db: Database
    ) throws {
        let effectiveUpdatedAt = max(project.updatedAt, deletedAt ?? .distantPast)
        try db.execute(
            sql: """
            INSERT INTO projects
                (id, name, vault_enabled, created_at, updated_at, deleted_at, sync_state)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                vault_enabled = excluded.vault_enabled,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                sync_state = excluded.sync_state
            """,
            arguments: [
                project.id.uuidString,
                project.name,
                project.vaultEnabled ? 1 : 0,
                project.createdAt.timeIntervalSinceReferenceDate,
                effectiveUpdatedAt.timeIntervalSinceReferenceDate,
                deletedAt?.timeIntervalSinceReferenceDate,
                deletedAt == nil ? SyncState.synced.rawValue : SyncState.deleted.rawValue,
            ]
        )
        if deletedAt != nil {
            try db.execute(
                sql: "UPDATE conversations SET project_id = NULL WHERE project_id = ?",
                arguments: [project.id.uuidString]
            )
            try db.execute(
                sql: "UPDATE vault_documents SET project_id = NULL WHERE project_id = ?",
                arguments: [project.id.uuidString]
            )
        }
    }

    private static func applyCloudKitConversation(_ conversation: CloudKitConversationSnapshot, db: Database) throws {
        let local = try Row.fetchOne(
            db,
            sql: """
            SELECT title, updated_at, deleted_at, default_model_id, default_provider_id, project_id,
                   archived_at, pinned, sync_state
            FROM conversations WHERE id = ?
            """,
            arguments: [conversation.id.uuidString]
        )
        let localUpdatedAt = (local?["updated_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            ?? Date(timeIntervalSinceReferenceDate: 0)
        let localDeletedAt = (local?["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
        let localSyncState = (local?["sync_state"] as String?).flatMap(SyncState.init(rawValue:))

        if let local,
           [.local, .pendingUpload, .conflicted].contains(localSyncState),
           try cloudKitConversationDiffers(local: local, remote: conversation) {
            try recordCloudKitConversationConflict(local: local, remote: conversation, db: db)
            try db.execute(
                sql: "UPDATE conversations SET sync_state = ? WHERE id = ?",
                arguments: [SyncState.conflicted.rawValue, conversation.id.uuidString]
            )
            return
        }

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

    static func upsertCloudKitConversation(
        _ conversation: CloudKitConversationSnapshot,
        deletedAt: Date?,
        db: Database
    ) throws {
        let updatedAt = (deletedAt ?? conversation.updatedAt).timeIntervalSinceReferenceDate
        let projectID = try activeProjectID(conversation.projectID, db: db)?.uuidString
        try db.execute(
            sql: """
            INSERT INTO conversations
                (id, title, created_at, updated_at, default_model_id, default_provider_id, project_id, archived_at, deleted_at, pinned, sync_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                default_model_id = excluded.default_model_id,
                default_provider_id = excluded.default_provider_id,
                project_id = excluded.project_id,
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
                projectID,
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
                    (id, conversation_id, role, content, created_at, updated_at, deleted_at, status, model_id, provider_id, tool_call_id, tool_name, tool_calls_json, provider_metadata_json, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    tool_name = excluded.tool_name,
                    tool_calls_json = excluded.tool_calls_json,
                    provider_metadata_json = excluded.provider_metadata_json,
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
                    message.toolName,
                    encodeToolCalls(message.toolCalls),
                    encodeProviderMetadata(message.providerMetadata),
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
                (id, conversation_id, role, content, created_at, updated_at, deleted_at, status, model_id, provider_id, tool_call_id, tool_name, tool_calls_json, provider_metadata_json, sync_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                tool_name = excluded.tool_name,
                tool_calls_json = excluded.tool_calls_json,
                provider_metadata_json = excluded.provider_metadata_json,
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
                message.toolName,
                encodeToolCalls(message.toolCalls),
                encodeProviderMetadata(message.providerMetadata),
                SyncState.synced.rawValue,
            ]
        )
    }

    private static func applyCloudKitDocument(_ document: CloudKitVaultDocumentSnapshot, db: Database) throws {
        let local = try Row.fetchOne(
            db,
            sql: "SELECT title, source_type, project_id, updated_at, sync_state FROM vault_documents WHERE id = ?",
            arguments: [document.id.uuidString]
        )
        let localUpdatedAt = (local?["updated_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            ?? Date(timeIntervalSinceReferenceDate: 0)
        let localSyncState = (local?["sync_state"] as String?).flatMap(SyncState.init(rawValue:))

        if let local,
           [.local, .pendingUpload, .conflicted].contains(localSyncState),
           try cloudKitDocumentDiffers(local: local, remote: document) {
            try recordCloudKitDocumentConflict(local: local, remote: document, db: db)
            try db.execute(
                sql: "UPDATE vault_documents SET sync_state = ? WHERE id = ?",
                arguments: [SyncState.conflicted.rawValue, document.id.uuidString]
            )
            return
        }

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

    static func upsertCloudKitDocument(
        _ document: CloudKitVaultDocumentSnapshot,
        syncState: SyncState,
        updatedAt: Date,
        db: Database
    ) throws {
        let projectID = try activeProjectID(document.projectID, db: db)?.uuidString
        try db.execute(
            sql: """
            INSERT INTO vault_documents
                (id, title, source_type, project_id, created_at, updated_at, sync_state)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                source_type = excluded.source_type,
                project_id = excluded.project_id,
                updated_at = excluded.updated_at,
                sync_state = excluded.sync_state
            """,
            arguments: [
                document.id.uuidString,
                document.title,
                document.sourceType,
                projectID,
                updatedAt.timeIntervalSinceReferenceDate,
                updatedAt.timeIntervalSinceReferenceDate,
                syncState.rawValue,
            ]
        )
    }

    private static func cloudKitConversationDiffers(local: Row, remote: CloudKitConversationSnapshot) throws -> Bool {
        let localDeletedAt = (local["deleted_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
        let localArchivedAt = (local["archived_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
        return (local["title"] as String) != remote.title
            || (local["default_model_id"] as String?) != remote.defaultModelID?.rawValue
            || (local["default_provider_id"] as String?) != remote.defaultProviderID?.rawValue
            || (local["project_id"] as String?) != remote.projectID?.uuidString
            || (local["pinned"] as Int) != (remote.pinned ? 1 : 0)
            || (localArchivedAt != nil) != remote.archived
            || localDeletedAt != remote.deletedAt
    }

    private static func cloudKitDocumentDiffers(local: Row, remote: CloudKitVaultDocumentSnapshot) throws -> Bool {
        (local["title"] as String) != remote.title
            || (local["source_type"] as String) != remote.sourceType
            || (local["project_id"] as String?) != remote.projectID?.uuidString
            || remote.deletedAt != nil
    }

    private static func recordCloudKitConversationConflict(
        local: Row,
        remote: CloudKitConversationSnapshot,
        db: Database
    ) throws {
        let localPayload: [String: String] = [
            "title": local["title"],
            "default_model_id": (local["default_model_id"] as String?) ?? "",
            "default_provider_id": (local["default_provider_id"] as String?) ?? "",
            "project_id": (local["project_id"] as String?) ?? "",
            "archived": (local["archived_at"] as Double?) == nil ? "false" : "true",
            "pinned": (local["pinned"] as Int) == 1 ? "true" : "false",
        ]
        try recordCloudKitConflict(
            entity: .conversation,
            entityID: remote.id,
            title: local["title"],
            deviceSummary: "This device has unsynced conversation changes from \(dateLabel(local["updated_at"] as Double)).",
            iCloudSummary: remote.deletedAt == nil
                ? "iCloud has \"\(remote.title)\" from \(dateLabel(remote.updatedAt.timeIntervalSinceReferenceDate))."
                : "The conversation was deleted from iCloud at \(dateLabel(remote.deletedAt!.timeIntervalSinceReferenceDate)).",
            devicePayloadJSON: String(decoding: try JSONEncoder().encode(localPayload), as: UTF8.self),
            iCloudPayloadJSON: String(decoding: try JSONEncoder().encode(remote), as: UTF8.self),
            deviceUpdatedAt: Date(timeIntervalSinceReferenceDate: local["updated_at"]),
            iCloudUpdatedAt: remote.deletedAt ?? remote.updatedAt,
            db: db
        )
    }

    private static func recordCloudKitDocumentConflict(
        local: Row,
        remote: CloudKitVaultDocumentSnapshot,
        db: Database
    ) throws {
        let localPayload: [String: String] = [
            "title": local["title"],
            "source_type": local["source_type"],
            "project_id": (local["project_id"] as String?) ?? "",
        ]
        try recordCloudKitConflict(
            entity: .vaultDocument,
            entityID: remote.id,
            title: local["title"],
            deviceSummary: "This device has unsynced Vault changes from \(dateLabel(local["updated_at"] as Double)).",
            iCloudSummary: remote.deletedAt == nil
                ? "iCloud has \"\(remote.title)\" from \(dateLabel(remote.updatedAt.timeIntervalSinceReferenceDate))."
                : "The Vault document was deleted from iCloud at \(dateLabel(remote.deletedAt!.timeIntervalSinceReferenceDate)).",
            devicePayloadJSON: String(decoding: try JSONEncoder().encode(localPayload), as: UTF8.self),
            iCloudPayloadJSON: String(decoding: try JSONEncoder().encode(remote), as: UTF8.self),
            deviceUpdatedAt: Date(timeIntervalSinceReferenceDate: local["updated_at"]),
            iCloudUpdatedAt: remote.deletedAt ?? remote.updatedAt,
            db: db
        )
    }

    private static func recordCloudKitConflict(
        entity: CloudKitConflictEntity,
        entityID: UUID,
        title: String,
        deviceSummary: String,
        iCloudSummary: String,
        devicePayloadJSON: String,
        iCloudPayloadJSON: String,
        deviceUpdatedAt: Date,
        iCloudUpdatedAt: Date,
        db: Database
    ) throws {
        let existingID = try String.fetchOne(
            db,
            sql: "SELECT id FROM cloudkit_conflicts WHERE entity = ? AND entity_id = ? AND resolution = ?",
            arguments: [entity.rawValue, entityID.uuidString, CloudKitConflictResolution.unresolved.rawValue]
        )
        try db.execute(
            sql: """
            INSERT INTO cloudkit_conflicts
                (id, entity, entity_id, title, device_summary, icloud_summary, device_payload_json,
                 icloud_payload_json, device_updated_at, icloud_updated_at, resolution, detected_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                device_summary = excluded.device_summary,
                icloud_summary = excluded.icloud_summary,
                device_payload_json = excluded.device_payload_json,
                icloud_payload_json = excluded.icloud_payload_json,
                device_updated_at = excluded.device_updated_at,
                icloud_updated_at = excluded.icloud_updated_at
            """,
            arguments: [
                existingID ?? UUID().uuidString,
                entity.rawValue,
                entityID.uuidString,
                title,
                deviceSummary,
                iCloudSummary,
                devicePayloadJSON,
                iCloudPayloadJSON,
                deviceUpdatedAt.timeIntervalSinceReferenceDate,
                iCloudUpdatedAt.timeIntervalSinceReferenceDate,
                CloudKitConflictResolution.unresolved.rawValue,
                Date().timeIntervalSinceReferenceDate,
            ]
        )
    }

    private static func dateLabel(_ referenceTime: Double) -> String {
        Date(timeIntervalSinceReferenceDate: referenceTime).formatted(date: .abbreviated, time: .shortened)
    }

    private static func activeProjectID(_ projectID: UUID?, db: Database) throws -> UUID? {
        guard let projectID else { return nil }
        let exists = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM projects WHERE id = ? AND deleted_at IS NULL)",
            arguments: [projectID.uuidString]
        ) ?? false
        return exists ? projectID : nil
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
                (chunk_id, document_id, embedding_model_id, profile_id, provider_id, provider_kind,
                 dimensions, normalized, source_checksum, fp16_embedding, turboquant_code,
                 norm, codec_version, checksum, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chunk_id, profile_id) DO UPDATE SET
                document_id = excluded.document_id,
                embedding_model_id = excluded.embedding_model_id,
                provider_id = excluded.provider_id,
                provider_kind = excluded.provider_kind,
                dimensions = excluded.dimensions,
                normalized = excluded.normalized,
                source_checksum = excluded.source_checksum,
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
                VaultEmbeddingProfile.stableID(
                    kind: .localMLX,
                    providerID: ProviderID(rawValue: "mlx-local"),
                    modelID: embedding.modelID,
                    dimensions: embedding.dimensions
                ),
                "mlx-local",
                VaultEmbeddingProfileKind.localMLX.rawValue,
                embedding.dimensions,
                1,
                embedding.checksum,
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
        case "Project":
            try db.execute(
                sql: "UPDATE projects SET deleted_at = ?, updated_at = ?, sync_state = ? WHERE id = ? AND updated_at <= ?",
                arguments: [deletedAt, deletedAt, SyncState.deleted.rawValue, deletion.recordName, deletedAt]
            )
            try db.execute(sql: "UPDATE conversations SET project_id = NULL WHERE project_id = ?", arguments: [deletion.recordName])
            try db.execute(sql: "UPDATE vault_documents SET project_id = NULL WHERE project_id = ?", arguments: [deletion.recordName])
        case "Conversation":
            if let id = UUID(uuidString: deletion.recordName),
               let local = try Row.fetchOne(
                db,
                sql: """
                SELECT title, updated_at, deleted_at, default_model_id, default_provider_id, project_id,
                       archived_at, pinned, sync_state
                FROM conversations WHERE id = ?
                """,
                arguments: [deletion.recordName]
               ),
               let state = (local["sync_state"] as String?).flatMap(SyncState.init(rawValue:)),
               [.local, .pendingUpload, .conflicted].contains(state) {
                let remote = CloudKitConversationSnapshot(
                    id: id,
                    title: local["title"],
                    updatedAt: deletion.deletedAt,
                    deletedAt: deletion.deletedAt,
                    defaultModelID: (local["default_model_id"] as String?).map(ModelID.init(rawValue:)),
                    defaultProviderID: (local["default_provider_id"] as String?).map(ProviderID.init(rawValue:)),
                    projectID: (local["project_id"] as String?).flatMap(UUID.init(uuidString:)),
                    archived: (local["archived_at"] as Double?) != nil,
                    pinned: (local["pinned"] as Int) == 1
                )
                try recordCloudKitConversationConflict(local: local, remote: remote, db: db)
                try db.execute(
                    sql: "UPDATE conversations SET sync_state = ? WHERE id = ?",
                    arguments: [SyncState.conflicted.rawValue, deletion.recordName]
                )
                return
            }
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
            if let id = UUID(uuidString: deletion.recordName),
               let local = try Row.fetchOne(
                db,
                sql: "SELECT title, source_type, project_id, updated_at, sync_state FROM vault_documents WHERE id = ?",
                arguments: [deletion.recordName]
               ),
               let state = (local["sync_state"] as String?).flatMap(SyncState.init(rawValue:)),
               [.local, .pendingUpload, .conflicted].contains(state) {
                let remote = CloudKitVaultDocumentSnapshot(
                    id: id,
                    title: local["title"],
                    sourceType: local["source_type"],
                    projectID: (local["project_id"] as String?).flatMap(UUID.init(uuidString:)),
                    updatedAt: deletion.deletedAt,
                    deletedAt: deletion.deletedAt,
                    chunkCount: 0
                )
                try recordCloudKitDocumentConflict(local: local, remote: remote, db: db)
                try db.execute(
                    sql: "UPDATE vault_documents SET sync_state = ? WHERE id = ?",
                    arguments: [SyncState.conflicted.rawValue, deletion.recordName]
                )
                return
            }
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
