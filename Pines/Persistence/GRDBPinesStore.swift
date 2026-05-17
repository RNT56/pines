import Foundation
import PinesCore

#if canImport(GRDB)
import GRDB
import OSLog

actor GRDBPinesStore:
    ConversationRepository,
    ModelInstallRepository,
    VaultRepository,
    SettingsRepository,
    CloudProviderRepository,
    MCPServerRepository,
    ModelDownloadRepository,
    AuditEventRepository
{
    let database: DatabasePool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let retrievalLogger = Logger(subsystem: "com.schtack.pines", category: "vault-retrieval")
    static let persistenceLogger = Logger(subsystem: "com.schtack.pines", category: "persistence")

    init(configuration: LocalStoreConfiguration = .init(), runtimeMetrics: PinesRuntimeMetrics = .shared) throws {
        let urlStartedAt = Date()
        let url = try Self.databaseURL(fileName: configuration.databaseFileName)
        runtimeMetrics.recordStartupPhase("store_url", elapsedSeconds: Date().timeIntervalSince(urlStartedAt))

        let openStartedAt = Date()
        database = try DatabasePool(path: url.path)
        runtimeMetrics.recordStartupPhase("store_open", elapsedSeconds: Date().timeIntervalSince(openStartedAt))

        let migrationStartedAt = Date()
        try Self.migrator.migrate(database)
        runtimeMetrics.recordStartupPhase("store_migrate", elapsedSeconds: Date().timeIntervalSince(migrationStartedAt))

        let seedStartedAt = Date()
        try Self.seedCuratedModels(in: database)
        runtimeMetrics.recordStartupPhase("store_seed", elapsedSeconds: Date().timeIntervalSince(seedStartedAt))
    }

    private static func databaseURL(fileName: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Pines", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: fileName)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false

        for migration in PinesDatabaseSchema.migrations.sorted(by: { $0.version < $1.version }) {
            migrator.registerMigration("\(migration.version)-\(migration.name)") { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                for statement in migration.sql {
                    try db.execute(sql: statement)
                }
            }
        }

        return migrator
    }

    // MARK: - Conversations

    func listConversations() async throws -> [ConversationRecord] {
        try await database.read(Self.fetchConversations)
    }

    func listConversationPreviews() async throws -> [ConversationPreviewRecord] {
        try await database.read(Self.fetchConversationPreviews)
    }

    nonisolated func observeConversations() -> AsyncStream<[ConversationRecord]> {
        observationStream(Self.fetchConversations)
    }

    nonisolated func observeConversationPreviews() -> AsyncStream<[ConversationPreviewRecord]> {
        observationStream(Self.fetchConversationPreviews)
    }

    func createConversation(title: String, defaultModelID: ModelID?, defaultProviderID: ProviderID?) async throws -> ConversationRecord {
        let record = ConversationRecord(title: title, defaultModelID: defaultModelID, defaultProviderID: defaultProviderID)
        let now = Date()
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO conversations (id, title, created_at, updated_at, default_model_id, default_provider_id, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString,
                    record.title,
                    now.timeIntervalSinceReferenceDate,
                    now.timeIntervalSinceReferenceDate,
                    record.defaultModelID?.rawValue,
                    record.defaultProviderID?.rawValue,
                    SyncState.local.rawValue,
                ]
            )
        }
        return record
    }

    func updateConversationTitle(_ title: String, conversationID: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET title = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [title, Date().timeIntervalSinceReferenceDate, SyncState.local.rawValue, conversationID.uuidString]
            )
        }
    }

    func updateConversationModel(modelID: ModelID?, providerID: ProviderID?, conversationID: UUID) async throws {
        let modelRawValue: String? = modelID?.rawValue
        let providerRawValue: String? = providerID?.rawValue
        try await database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET default_model_id = ?, default_provider_id = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [
                    modelRawValue,
                    providerRawValue,
                    Date().timeIntervalSinceReferenceDate,
                    SyncState.local.rawValue,
                    conversationID.uuidString,
                ]
            )
        }
    }

    func setConversationArchived(_ archived: Bool, conversationID: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET archived_at = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [
                    archived ? Date().timeIntervalSinceReferenceDate : nil,
                    Date().timeIntervalSinceReferenceDate,
                    SyncState.local.rawValue,
                    conversationID.uuidString,
                ]
            )
        }
    }

    func setConversationPinned(_ pinned: Bool, conversationID: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET pinned = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [
                    pinned ? 1 : 0,
                    Date().timeIntervalSinceReferenceDate,
                    SyncState.local.rawValue,
                    conversationID.uuidString,
                ]
            )
        }
    }

    func deleteConversation(id: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET deleted_at = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [Date().timeIntervalSinceReferenceDate, Date().timeIntervalSinceReferenceDate, SyncState.deleted.rawValue, id.uuidString]
            )
        }
    }

    func messages(in conversationID: UUID) async throws -> [ChatMessage] {
        try await database.read { db in
            try Self.fetchMessages(db, conversationID: conversationID)
        }
    }

    nonisolated func observeMessages(in conversationID: UUID) -> AsyncStream<[ChatMessage]> {
        observationStream { db in
            try Self.fetchMessages(db, conversationID: conversationID)
        }
    }

    func appendMessage(
        _ message: ChatMessage,
        status: MessageStatus,
        conversationID: UUID,
        modelID: ModelID?,
        providerID: ProviderID?
    ) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO messages
                    (id, conversation_id, role, content, created_at, updated_at, status, model_id, provider_id, tool_call_id, tool_name, tool_calls_json, provider_metadata_json, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.id.uuidString,
                    conversationID.uuidString,
                    message.role.rawValue,
                    message.content,
                    message.createdAt.timeIntervalSinceReferenceDate,
                    Date().timeIntervalSinceReferenceDate,
                    status.rawValue,
                    modelID?.rawValue,
                    providerID?.rawValue,
                    message.toolCallID,
                    message.toolName,
                    Self.encodeToolCalls(message.toolCalls),
                    Self.encodeProviderMetadata(message.providerMetadata),
                    SyncState.local.rawValue,
                ]
            )

            for attachment in message.attachments {
                try db.execute(
                    sql: """
                    INSERT INTO attachments
                        (id, message_id, kind, file_name, content_type, local_path, byte_count, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        attachment.id.uuidString,
                        message.id.uuidString,
                        attachment.kind.rawValue,
                        attachment.fileName,
                        attachment.contentType,
                        attachment.localURL?.path ?? "",
                        attachment.byteCount,
                        Date().timeIntervalSinceReferenceDate,
                    ]
                )
            }

            try db.execute(
                sql: "UPDATE conversations SET updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [Date().timeIntervalSinceReferenceDate, SyncState.local.rawValue, conversationID.uuidString]
            )
        }
    }

    func updateMessage(
        id: UUID,
        content: String,
        status: MessageStatus,
        tokenCount: Int?,
        providerMetadata: [String: String]?,
        toolName: String?,
        toolCalls: [ToolCallDelta]?
    ) async throws {
        try await database.write { db in
            let updatedAt = Date().timeIntervalSinceReferenceDate
            var assignments = [
                "content = ?",
                "status = ?",
                "token_count = ?",
            ]
            var arguments: StatementArguments = [content, status.rawValue, tokenCount]
            if let providerMetadata {
                assignments.append("provider_metadata_json = ?")
                _ = arguments.append(contentsOf: StatementArguments([Self.encodeProviderMetadata(providerMetadata)]))
            }
            if let toolName {
                assignments.append("tool_name = ?")
                _ = arguments.append(contentsOf: StatementArguments([toolName]))
            }
            if let toolCalls {
                assignments.append("tool_calls_json = ?")
                _ = arguments.append(contentsOf: StatementArguments([Self.encodeToolCalls(toolCalls)]))
            }
            assignments.append("updated_at = ?")
            assignments.append("sync_state = ?")
            let finalArguments: StatementArguments = [
                updatedAt,
                SyncState.local.rawValue,
                id.uuidString,
            ]
            _ = arguments.append(contentsOf: finalArguments)
            try db.execute(
                sql: "UPDATE messages SET \(assignments.joined(separator: ", ")) WHERE id = ?",
                arguments: arguments
            )
            try db.execute(
                sql: "UPDATE conversations SET updated_at = ?, sync_state = ? WHERE id = (SELECT conversation_id FROM messages WHERE id = ?)",
                arguments: [updatedAt, SyncState.local.rawValue, id.uuidString]
            )
        }
    }

    // MARK: - Models

    func listInstalledAndCuratedModels() async throws -> [ModelInstall] {
        try await database.read(Self.fetchInstalledAndCuratedModels)
    }

    nonisolated func observeInstalledAndCuratedModels() -> AsyncStream<[ModelInstall]> {
        observationStream(Self.fetchInstalledAndCuratedModels)
    }

    func upsertInstall(_ install: ModelInstall) async throws {
        let now = Date()
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO model_installs
                    (id, repository, display_name, revision, local_path, modalities, verification, state, model_type, processor_class, estimated_bytes, license, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(repository) DO UPDATE SET
                    display_name = excluded.display_name,
                    revision = excluded.revision,
                    local_path = excluded.local_path,
                    modalities = excluded.modalities,
                    verification = excluded.verification,
                    state = excluded.state,
                    model_type = excluded.model_type,
                    processor_class = excluded.processor_class,
                    estimated_bytes = excluded.estimated_bytes,
                    license = excluded.license,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    install.id.uuidString,
                    install.repository,
                    install.displayName,
                    install.revision,
                    install.localURL?.path,
                    Self.encodeModalities(install.modalities),
                    install.verification.rawValue,
                    install.state.rawValue,
                    install.modelType,
                    install.processorClass,
                    install.estimatedBytes,
                    install.license,
                    install.createdAt.timeIntervalSinceReferenceDate,
                    now.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func updateInstallState(_ state: ModelInstallState, for repository: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE model_installs SET state = ?, updated_at = ? WHERE repository = ?",
                arguments: [state.rawValue, Date().timeIntervalSinceReferenceDate, repository]
            )
        }
    }

    func deleteInstall(repository: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM model_installs WHERE repository = ?", arguments: [repository])
        }
    }

    // MARK: - Vault

    func listDocuments() async throws -> [VaultDocumentRecord] {
        try await database.read(Self.fetchDocuments)
    }

    nonisolated func observeDocuments() -> AsyncStream<[VaultDocumentRecord]> {
        observationStream(Self.fetchDocuments)
    }

    func upsertDocument(_ document: VaultDocumentRecord, localURL: URL?, checksum: String?) async throws {
        let now = Date()
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO vault_documents
                    (id, title, source_type, local_path, sha256, created_at, updated_at, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    source_type = excluded.source_type,
                    local_path = excluded.local_path,
                    sha256 = excluded.sha256,
                    updated_at = excluded.updated_at,
                    sync_state = excluded.sync_state
                """,
                arguments: [
                    document.id.uuidString,
                    document.title,
                    document.sourceType,
                    localURL?.path,
                    checksum,
                    now.timeIntervalSinceReferenceDate,
                    document.updatedAt.timeIntervalSinceReferenceDate,
                    SyncState.local.rawValue,
                ]
            )
        }
    }

    func deleteDocument(id: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE vault_documents SET sync_state = ?, updated_at = ? WHERE id = ?",
                arguments: [SyncState.deleted.rawValue, Date().timeIntervalSinceReferenceDate, id.uuidString]
            )
        }
    }

    func chunks(documentID: UUID) async throws -> [VaultChunk] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, document_id, ordinal, text, token_estimate, created_at
                FROM vault_chunks
                WHERE document_id = ?
                ORDER BY ordinal ASC
                """,
                arguments: [documentID.uuidString]
            ).map(Self.vaultChunk(from:))
        }
    }

    func embeddings(documentID: UUID) async throws -> [VaultStoredEmbedding] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT chunk_id, document_id, embedding_model_id, profile_id, provider_id,
                       provider_kind, normalized, source_checksum, dimensions, fp16_embedding,
                       turboquant_code, norm, codec_version, checksum, created_at
                FROM vault_embeddings
                WHERE document_id = ?
                ORDER BY created_at ASC, chunk_id ASC
                """,
                arguments: [documentID.uuidString]
            ).map(Self.vaultStoredEmbedding(from:))
        }
    }

    func listEmbeddingProfiles() async throws -> [VaultEmbeddingProfile] {
        try await database.read(Self.fetchEmbeddingProfiles)
    }

    nonisolated func observeEmbeddingProfiles() -> AsyncStream<[VaultEmbeddingProfile]> {
        observationStream(Self.fetchEmbeddingProfiles)
    }

    func activeEmbeddingProfile() async throws -> VaultEmbeddingProfile? {
        try await database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT *
                FROM vault_embedding_profiles
                WHERE is_active = 1
                ORDER BY updated_at DESC
                LIMIT 1
                """
            ).map(Self.vaultEmbeddingProfile(from:))
        }
    }

    func upsertEmbeddingProfile(_ profile: VaultEmbeddingProfile) async throws {
        try await database.write { db in
            try Self.upsertEmbeddingProfile(profile, db: db)
        }
    }

    func setActiveEmbeddingProfile(id: String?) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE vault_embedding_profiles SET is_active = 0, updated_at = ?", arguments: [Date().timeIntervalSinceReferenceDate])
            guard let id else { return }
            try db.execute(
                sql: "UPDATE vault_embedding_profiles SET is_active = 1, updated_at = ? WHERE id = ?",
                arguments: [Date().timeIntervalSinceReferenceDate, id]
            )
        }
    }

    func updateEmbeddingProfileConsent(id: String, granted: Bool) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                UPDATE vault_embedding_profiles
                SET cloud_consent_granted = ?, status = CASE WHEN ? = 1 THEN 'available' ELSE 'needsConsent' END, updated_at = ?
                WHERE id = ?
                """,
                arguments: [granted ? 1 : 0, granted ? 1 : 0, Date().timeIntervalSinceReferenceDate, id]
            )
        }
    }

    func upsertEmbeddingJob(_ job: VaultEmbeddingJob) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO vault_embedding_jobs
                    (id, profile_id, document_id, status, processed_chunks, total_chunks,
                     attempt_count, last_error, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    profile_id = excluded.profile_id,
                    document_id = excluded.document_id,
                    status = excluded.status,
                    processed_chunks = excluded.processed_chunks,
                    total_chunks = excluded.total_chunks,
                    attempt_count = excluded.attempt_count,
                    last_error = excluded.last_error,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    job.id.uuidString,
                    job.profileID,
                    job.documentID?.uuidString,
                    job.status.rawValue,
                    job.processedChunks,
                    job.totalChunks,
                    job.attemptCount,
                    job.lastError,
                    job.createdAt.timeIntervalSinceReferenceDate,
                    job.updatedAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func listEmbeddingJobs(limit: Int) async throws -> [VaultEmbeddingJob] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM vault_embedding_jobs ORDER BY updated_at DESC LIMIT ?",
                arguments: [max(1, limit)]
            ).map(Self.vaultEmbeddingJob(from:))
        }
    }

    func recordRetrievalEvent(_ event: VaultRetrievalEvent) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO vault_retrieval_events
                    (id, profile_id, provider_id, query_hash, used_vector_search, result_count, elapsed_seconds, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString,
                    event.profileID,
                    event.providerID?.rawValue,
                    event.queryHash,
                    event.usedVectorSearch ? 1 : 0,
                    event.resultCount,
                    event.elapsedSeconds,
                    event.createdAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func listRetrievalEvents(limit: Int) async throws -> [VaultRetrievalEvent] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM vault_retrieval_events ORDER BY created_at DESC LIMIT ?",
                arguments: [max(1, limit)]
            ).map(Self.vaultRetrievalEvent(from:))
        }
    }

    func replaceChunks(_ chunks: [VaultChunk], documentID: UUID, embeddingModelID: ModelID?) async throws {
        try await replaceChunks(chunks, embeddings: nil, documentID: documentID, embeddingModelID: embeddingModelID)
    }

    func replaceChunks(
        _ chunks: [VaultChunk],
        embeddings: VaultEmbeddingBatch?,
        documentID: UUID,
        embeddingModelID: ModelID?
    ) async throws {
        try await replaceChunks(chunks, embeddings: embeddings, documentID: documentID, embeddingProfile: nil)
    }

    func replaceChunks(
        _ chunks: [VaultChunk],
        embeddings: VaultEmbeddingBatch?,
        documentID: UUID,
        embeddingProfile: VaultEmbeddingProfile?
    ) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM vault_embeddings WHERE document_id = ?", arguments: [documentID.uuidString])
            try db.execute(sql: "DELETE FROM vault_chunks WHERE document_id = ?", arguments: [documentID.uuidString])
            for chunk in chunks {
                try db.execute(
                    sql: """
                    INSERT INTO vault_chunks
                        (id, document_id, ordinal, text, token_estimate, embedding_model_id, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id,
                        documentID.uuidString,
                        chunk.ordinal,
                        chunk.text,
                        max(1, chunk.characterCount / 4),
                        embeddingProfile?.modelID.rawValue ?? embeddings?.modelID.rawValue,
                        Date().timeIntervalSinceReferenceDate,
                    ]
                )
            }

            let now = Date().timeIntervalSinceReferenceDate
            try db.execute(
                sql: "UPDATE vault_documents SET updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [now, SyncState.local.rawValue, documentID.uuidString]
            )

            guard let embeddings, !embeddings.embeddings.isEmpty else {
                return
            }

            let embeddingByChunkID = Dictionary(uniqueKeysWithValues: embeddings.embeddings.map { ($0.chunkID, $0) })
            let firstDimensions = embeddings.embeddings.first?.vector.count ?? embeddingProfile?.dimensions ?? 0
            let profileID = embeddingProfile?.id ?? VaultEmbeddingProfile.stableID(
                kind: .localMLX,
                providerID: ProviderID(rawValue: "mlx-local"),
                modelID: embeddings.modelID,
                dimensions: firstDimensions
            )
            let providerID = embeddingProfile?.providerID?.rawValue
            let providerKind = embeddingProfile?.kind.rawValue ?? VaultEmbeddingProfileKind.localMLX.rawValue
            let normalized = embeddingProfile?.normalized ?? true
            for chunk in chunks {
                guard let embedding = embeddingByChunkID[chunk.id], !embedding.vector.isEmpty else {
                    continue
                }
                let norm = Self.vectorMagnitude(embedding.vector)
                guard norm > 0 else {
                    continue
                }
                let codec = Self.vaultTurboQuantCodec(modelID: embeddings.modelID, dimensions: embedding.vector.count)
                let encodedCode = try codec.encode(embedding.vector)
                let codeData = try JSONEncoder().encode(encodedCode)
                try db.execute(
                    sql: """
                    INSERT INTO vault_embeddings
                        (chunk_id, document_id, embedding_model_id, profile_id, provider_id, provider_kind,
                         dimensions, normalized, source_checksum, fp16_embedding, turboquant_code,
                         norm, codec_version, checksum, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id,
                        documentID.uuidString,
                        embeddings.modelID.rawValue,
                        profileID,
                        providerID,
                        providerKind,
                        embedding.vector.count,
                        normalized ? 1 : 0,
                        chunk.checksum,
                        Self.encodeFP16(embedding.vector),
                        codeData,
                        Double(norm),
                        encodedCode.codecVersion,
                        StableSearchHash.hexDigest(for: "\(chunk.checksum)|\(embeddings.modelID.rawValue)|\(embedding.vector.count)"),
                        now,
                    ]
                )
            }
            try db.execute(
                sql: """
                UPDATE vault_embedding_profiles
                SET embedded_chunk_count = (
                        SELECT COUNT(*) FROM vault_embeddings WHERE profile_id = ?
                    ),
                    total_chunk_count = (
                        SELECT COUNT(*) FROM vault_chunks
                    ),
                    dimensions = CASE WHEN dimensions = 0 THEN ? ELSE dimensions END,
                    status = CASE
                        WHEN (
                            SELECT COUNT(*) FROM vault_embeddings WHERE profile_id = ?
                        ) > 0 THEN 'ready'
                        ELSE status
                    END,
                    last_error = NULL,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [profileID, firstDimensions, profileID, now, profileID]
            )
        }
    }

    func upsertEmbeddings(
        _ embeddings: VaultEmbeddingBatch,
        documentID: UUID,
        embeddingProfile: VaultEmbeddingProfile
    ) async throws {
        try await database.write { db in
            let chunks = try Row.fetchAll(
                db,
                sql: """
                SELECT id, document_id, ordinal, text, token_estimate, created_at
                FROM vault_chunks
                WHERE document_id = ?
                ORDER BY ordinal ASC
                """,
                arguments: [documentID.uuidString]
            ).map(Self.vaultChunk(from:))
            guard !chunks.isEmpty else { return }

            let profileID = embeddingProfile.id
            let now = Date().timeIntervalSinceReferenceDate
            let embeddingByChunkID = Dictionary(uniqueKeysWithValues: embeddings.embeddings.map { ($0.chunkID, $0) })
            try db.execute(
                sql: "DELETE FROM vault_embeddings WHERE document_id = ? AND profile_id = ?",
                arguments: [documentID.uuidString, profileID]
            )

            for chunk in chunks {
                guard let embedding = embeddingByChunkID[chunk.id], !embedding.vector.isEmpty else {
                    continue
                }
                let norm = Self.vectorMagnitude(embedding.vector)
                guard norm > 0 else {
                    continue
                }
                let codec = Self.vaultTurboQuantCodec(modelID: embeddings.modelID, dimensions: embedding.vector.count)
                let encodedCode = try codec.encode(embedding.vector)
                let codeData = try JSONEncoder().encode(encodedCode)
                try db.execute(
                    sql: """
                    INSERT INTO vault_embeddings
                        (chunk_id, document_id, embedding_model_id, profile_id, provider_id, provider_kind,
                         dimensions, normalized, source_checksum, fp16_embedding, turboquant_code,
                         norm, codec_version, checksum, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id,
                        documentID.uuidString,
                        embeddings.modelID.rawValue,
                        profileID,
                        embeddingProfile.providerID?.rawValue,
                        embeddingProfile.kind.rawValue,
                        embedding.vector.count,
                        embeddingProfile.normalized ? 1 : 0,
                        chunk.checksum,
                        Self.encodeFP16(embedding.vector),
                        codeData,
                        Double(norm),
                        encodedCode.codecVersion,
                        StableSearchHash.hexDigest(for: "\(chunk.checksum)|\(embeddings.modelID.rawValue)|\(embedding.vector.count)"),
                        now,
                    ]
                )
            }

            let firstDimensions = embeddings.embeddings.first?.vector.count ?? embeddingProfile.dimensions
            try db.execute(
                sql: """
                UPDATE vault_embedding_profiles
                SET embedded_chunk_count = (
                        SELECT COUNT(*) FROM vault_embeddings WHERE profile_id = ?
                    ),
                    total_chunk_count = (
                        SELECT COUNT(*) FROM vault_chunks
                    ),
                    dimensions = CASE WHEN dimensions = 0 THEN ? ELSE dimensions END,
                    status = CASE
                        WHEN (
                            SELECT COUNT(*) FROM vault_embeddings WHERE profile_id = ?
                        ) > 0 THEN 'ready'
                        ELSE status
                    END,
                    last_error = NULL,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [profileID, firstDimensions, profileID, now, profileID]
            )
        }
    }

    func search(query: String, embedding: [Float]?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, embeddingModelID: nil, limit: limit)
    }

    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, embeddingModelID: embeddingModelID, profileID: nil, limit: limit)
    }

    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, profileID: String?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, embeddingModelID: embeddingModelID, profileID: profileID, limit: limit, options: .default)
    }

    private func search(
        query: String,
        embedding: [Float]?,
        embeddingModelID: ModelID?,
        profileID: String?,
        limit: Int,
        options: VaultSearchOptions
    ) async throws -> [VaultSearchResult] {
        let normalizedLimit = max(1, limit)
        if let embedding, !embedding.isEmpty {
            let vectorResults = try await vectorSearch(
                embedding: embedding,
                embeddingModelID: embeddingModelID,
                profileID: profileID,
                limit: normalizedLimit,
                options: options
            )
            if !vectorResults.isEmpty {
                return vectorResults
            }
        }

        return try await fullTextSearch(query: query, limit: normalizedLimit, options: options)
    }

    private func vectorSearch(
        embedding: [Float],
        embeddingModelID: ModelID?,
        profileID: String?,
        limit: Int,
        options: VaultSearchOptions
    ) async throws -> [VaultSearchResult] {
        return try await database.read { db in
            struct Candidate {
                let chunkID: String
                let dimensions: Int
                let fp16Embedding: Data
                let approximateScore: Double
            }

            let startedAt = Date()
            let deadline = options.timeoutMilliseconds.map {
                startedAt.addingTimeInterval(Double($0) / 1000)
            }
            let batchSize = options.semanticBatchSize
            let approximateLimit = max(limit, options.semanticRerankCount)
            var scannedRows = 0
            var offset = 0
            var topCandidates = [Candidate]()
            var decodeFailureCount = 0
            var scoringFailureCount = 0

            while true {
                if let deadline, Date() >= deadline {
                    break
                }

                let rows: [Row]
                if let profileID {
                    rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT e.chunk_id, e.dimensions, e.fp16_embedding, e.turboquant_code
                        FROM vault_embeddings e
                        JOIN vault_documents d ON d.id = e.document_id
                        WHERE e.dimensions = ? AND e.profile_id = ? AND d.sync_state != ?
                        ORDER BY e.chunk_id ASC
                        LIMIT ? OFFSET ?
                        """,
                        arguments: [
                            embedding.count,
                            profileID,
                            SyncState.deleted.rawValue,
                            batchSize,
                            offset,
                        ]
                    )
                } else if let embeddingModelID {
                    rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT e.chunk_id, e.dimensions, e.fp16_embedding, e.turboquant_code
                        FROM vault_embeddings e
                        JOIN vault_documents d ON d.id = e.document_id
                        WHERE e.dimensions = ? AND e.embedding_model_id = ? AND d.sync_state != ?
                        ORDER BY e.chunk_id ASC
                        LIMIT ? OFFSET ?
                        """,
                        arguments: [
                            embedding.count,
                            embeddingModelID.rawValue,
                            SyncState.deleted.rawValue,
                            batchSize,
                            offset,
                        ]
                    )
                } else {
                    rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT e.chunk_id, e.dimensions, e.fp16_embedding, e.turboquant_code
                        FROM vault_embeddings e
                        JOIN vault_documents d ON d.id = e.document_id
                        WHERE e.dimensions = ? AND d.sync_state != ?
                        ORDER BY e.chunk_id ASC
                        LIMIT ? OFFSET ?
                        """,
                        arguments: [
                            embedding.count,
                            SyncState.deleted.rawValue,
                            batchSize,
                            offset,
                        ]
                    )
                }

                if rows.isEmpty {
                    break
                }
                scannedRows += rows.count
                offset += rows.count

                topCandidates.append(
                    contentsOf: rows.compactMap { row -> Candidate? in
                        let codeData: Data = row["turboquant_code"]
                        let code: TurboQuantVectorCode
                        do {
                            code = try JSONDecoder().decode(TurboQuantVectorCode.self, from: codeData)
                        } catch {
                            decodeFailureCount += 1
                            return nil
                        }
                        let codec = TurboQuantVectorCodec(preset: code.preset, seed: code.seed)
                        let score: Double
                        do {
                            score = try codec.approximateCosineSimilarity(query: embedding, code: code)
                        } catch {
                            scoringFailureCount += 1
                            return nil
                        }
                        return Candidate(
                            chunkID: row["chunk_id"],
                            dimensions: row["dimensions"],
                            fp16Embedding: row["fp16_embedding"],
                            approximateScore: score
                        )
                    }
                )
                topCandidates.sort { lhs, rhs in
                    if lhs.approximateScore == rhs.approximateScore {
                        return lhs.chunkID < rhs.chunkID
                    }
                    return lhs.approximateScore > rhs.approximateScore
                }
                if topCandidates.count > approximateLimit {
                    topCandidates.removeLast(topCandidates.count - approximateLimit)
                }

                if rows.count < batchSize {
                    break
                }
            }

            if decodeFailureCount > 0 || scoringFailureCount > 0 {
                Self.retrievalLogger.warning(
                    "Vector retrieval skipped corrupted TurboQuant candidates decode_failures=\(decodeFailureCount, privacy: .public) scoring_failures=\(scoringFailureCount, privacy: .public)"
                )
            }

            var rerankDecodeFailureCount = 0
            let reranked = topCandidates.compactMap { candidate -> (chunkID: String, score: Double)? in
                let storedVector: [Float]
                do {
                    storedVector = try Self.decodeFP16(candidate.fp16Embedding, dimensions: candidate.dimensions)
                } catch {
                    rerankDecodeFailureCount += 1
                    return nil
                }
                return (candidate.chunkID, Self.cosineSimilarity(embedding, storedVector))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.chunkID < rhs.chunkID
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)

            if rerankDecodeFailureCount > 0 {
                Self.retrievalLogger.warning(
                    "Vector retrieval skipped corrupted FP16 rerank candidates count=\(rerankDecodeFailureCount, privacy: .public)"
                )
            }

            let chunkIDs = reranked.map(\.chunkID)
            guard !chunkIDs.isEmpty else {
                Self.retrievalLogger.debug("Vector retrieval scanned \(scannedRows) embeddings in \(Date().timeIntervalSince(startedAt), privacy: .public)s and found no candidates")
                return []
            }

            let placeholders = Array(repeating: "?", count: chunkIDs.count).joined(separator: ",")
            let detailRows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id AS chunk_id, c.document_id, c.ordinal, c.text, c.token_estimate, d.title, d.source_type, d.updated_at
                FROM vault_chunks c
                JOIN vault_documents d ON d.id = c.document_id
                WHERE c.id IN (\(placeholders)) AND d.sync_state != ?
                """,
                arguments: StatementArguments(chunkIDs + [SyncState.deleted.rawValue])
            )
            let rowsByChunkID = Dictionary(uniqueKeysWithValues: detailRows.map { row in
                (row["chunk_id"] as String, row)
            })

            let results = reranked.compactMap { candidate -> VaultSearchResult? in
                guard let row = rowsByChunkID[candidate.chunkID] else {
                        return nil
                    }
                return Self.vaultSearchResult(from: row, score: candidate.score)
            }
            Self.retrievalLogger.debug("Vector retrieval scanned \(scannedRows) embeddings, reranked \(topCandidates.count), returned \(results.count) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
            return results
        }
    }

    private func fullTextSearch(query: String, limit: Int, options: VaultSearchOptions) async throws -> [VaultSearchResult] {
        return try await database.read { db in
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let ftsQuery = Self.safeFTSQuery(from: normalizedQuery)
            let candidateLimit = max(limit, options.lexicalCandidateCount)
            let rows: [Row]
            if ftsQuery == nil {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT c.id AS chunk_id, c.document_id, c.ordinal, c.text, c.token_estimate, d.title, d.source_type, d.updated_at
                    FROM vault_chunks c
                    JOIN vault_documents d ON d.id = c.document_id
                    WHERE d.sync_state != ?
                    ORDER BY d.updated_at DESC, c.ordinal ASC
                    LIMIT ?
                    """,
                    arguments: [SyncState.deleted.rawValue, candidateLimit]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT c.id AS chunk_id, c.document_id, c.ordinal, c.text, c.token_estimate, d.title, d.source_type, d.updated_at
                    FROM vault_chunks_fts f
                    JOIN vault_chunks c ON c.id = f.chunk_id
                    JOIN vault_documents d ON d.id = c.document_id
                    WHERE vault_chunks_fts MATCH ? AND d.sync_state != ?
                    ORDER BY bm25(vault_chunks_fts)
                    LIMIT ?
                    """,
                    arguments: [ftsQuery!, SyncState.deleted.rawValue, candidateLimit]
                )
            }

            return rows.prefix(limit).map { Self.vaultSearchResult(from: $0, score: 1) }
        }
    }

    private static func safeFTSQuery(from query: String) -> String? {
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(12)
        guard !tokens.isEmpty else { return nil }
        return tokens.map { token in
            "\"\(token.replacingOccurrences(of: "\"", with: "\"\""))\""
        }.joined(separator: " AND ")
    }

    // MARK: - Settings

    func loadSettings() async throws -> AppSettingsSnapshot {
        try await database.read(Self.fetchSettings)
    }

    nonisolated func observeSettings() -> AsyncStream<AppSettingsSnapshot> {
        observationStream(Self.fetchSettings)
    }

    func saveSettings(_ settings: AppSettingsSnapshot) async throws {
        let json = String(decoding: try encoder.encode(settings), as: UTF8.self)
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_settings (key, value_json, updated_at, sync_state)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value_json = excluded.value_json,
                    updated_at = excluded.updated_at,
                    sync_state = excluded.sync_state
                """,
                arguments: ["app", json, Date().timeIntervalSinceReferenceDate, SyncState.local.rawValue]
            )
        }
    }

    // MARK: - Cloud Providers

    func listProviders() async throws -> [CloudProviderConfiguration] {
        try await database.read(Self.fetchProviders)
    }

    nonisolated func observeProviders() -> AsyncStream<[CloudProviderConfiguration]> {
        observationStream(Self.fetchProviders)
    }

    func upsertProvider(_ provider: CloudProviderConfiguration) async throws {
        let now = Date()
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO cloud_providers
                    (id, kind, display_name, base_url, default_model_id, validation_status, last_validation_error,
                     extra_headers_json, keychain_service, keychain_account, enabled_for_agents,
                     last_validated_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    display_name = excluded.display_name,
                    base_url = excluded.base_url,
                    default_model_id = excluded.default_model_id,
                    validation_status = excluded.validation_status,
                    last_validation_error = excluded.last_validation_error,
                    extra_headers_json = excluded.extra_headers_json,
                    keychain_service = excluded.keychain_service,
                    keychain_account = excluded.keychain_account,
                    enabled_for_agents = excluded.enabled_for_agents,
                    last_validated_at = excluded.last_validated_at,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    provider.id.rawValue,
                    provider.kind.rawValue,
                    provider.displayName,
                    provider.baseURL.absoluteString,
                    provider.defaultModelID?.rawValue,
                    provider.validationStatus.rawValue,
                    provider.lastValidationError,
                    provider.extraHeadersJSON,
                    provider.keychainService,
                    provider.keychainAccount,
                    provider.enabledForAgents ? 1 : 0,
                    provider.lastValidatedAt?.timeIntervalSinceReferenceDate,
                    now.timeIntervalSinceReferenceDate,
                    now.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func deleteProvider(id: ProviderID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM cloud_providers WHERE id = ?", arguments: [id.rawValue])
        }
    }

    // MARK: - MCP Servers

    func listMCPServers() async throws -> [MCPServerConfiguration] {
        try await database.read(Self.fetchMCPServers)
    }

    nonisolated func observeMCPServers() -> AsyncStream<[MCPServerConfiguration]> {
        observationStream(Self.fetchMCPServers)
    }

    func upsertMCPServer(_ server: MCPServerConfiguration) async throws {
        let now = Date()
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO mcp_servers
                    (id, display_name, endpoint_url, auth_mode, enabled, allow_insecure_local_http,
                     keychain_service, keychain_account, oauth_authorization_url, oauth_token_url, oauth_client_id,
                     oauth_scopes, oauth_resource, resources_enabled, prompts_enabled, sampling_enabled,
                     byok_sampling_enabled, subscriptions_enabled, max_sampling_requests_per_session,
                     status, last_error, last_connected_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    display_name = excluded.display_name,
                    endpoint_url = excluded.endpoint_url,
                    auth_mode = excluded.auth_mode,
                    enabled = excluded.enabled,
                    allow_insecure_local_http = excluded.allow_insecure_local_http,
                    keychain_service = excluded.keychain_service,
                    keychain_account = excluded.keychain_account,
                    oauth_authorization_url = excluded.oauth_authorization_url,
                    oauth_token_url = excluded.oauth_token_url,
                    oauth_client_id = excluded.oauth_client_id,
                    oauth_scopes = excluded.oauth_scopes,
                    oauth_resource = excluded.oauth_resource,
                    resources_enabled = excluded.resources_enabled,
                    prompts_enabled = excluded.prompts_enabled,
                    sampling_enabled = excluded.sampling_enabled,
                    byok_sampling_enabled = excluded.byok_sampling_enabled,
                    subscriptions_enabled = excluded.subscriptions_enabled,
                    max_sampling_requests_per_session = excluded.max_sampling_requests_per_session,
                    status = excluded.status,
                    last_error = excluded.last_error,
                    last_connected_at = excluded.last_connected_at,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    server.id.rawValue,
                    server.displayName,
                    server.endpointURL.absoluteString,
                    server.authMode.rawValue,
                    server.enabled ? 1 : 0,
                    server.allowInsecureLocalHTTP ? 1 : 0,
                    server.keychainService,
                    server.keychainAccount,
                    server.oauthAuthorizationURL?.absoluteString,
                    server.oauthTokenURL?.absoluteString,
                    server.oauthClientID,
                    server.oauthScopes,
                    server.oauthResource,
                    server.resourcesEnabled ? 1 : 0,
                    server.promptsEnabled ? 1 : 0,
                    server.samplingEnabled ? 1 : 0,
                    server.byokSamplingEnabled ? 1 : 0,
                    server.subscriptionsEnabled ? 1 : 0,
                    server.maxSamplingRequestsPerSession,
                    server.status.rawValue,
                    server.lastError,
                    server.lastConnectedAt?.timeIntervalSinceReferenceDate,
                    server.createdAt.timeIntervalSinceReferenceDate,
                    now.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func deleteMCPServer(id: MCPServerID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM mcp_servers WHERE id = ?", arguments: [id.rawValue])
        }
    }

    func listMCPTools(serverID: MCPServerID?) async throws -> [MCPToolRecord] {
        try await database.read { db in
            try Self.fetchMCPTools(db, serverID: serverID)
        }
    }

    nonisolated func observeMCPTools() -> AsyncStream<[MCPToolRecord]> {
        observationStream { db in
            try Self.fetchMCPTools(db, serverID: nil)
        }
    }

    func replaceMCPTools(_ tools: [MCPToolRecord], serverID: MCPServerID) async throws {
        try await database.write { db in
            let existingRows = try Row.fetchAll(
                db,
                sql: "SELECT namespaced_name, enabled FROM mcp_tools WHERE server_id = ?",
                arguments: [serverID.rawValue]
            )
            let enabledByName = Dictionary(uniqueKeysWithValues: existingRows.map { row in
                (row["namespaced_name"] as String, (row["enabled"] as Int) == 1)
            })
            try db.execute(sql: "DELETE FROM mcp_tools WHERE server_id = ?", arguments: [serverID.rawValue])
            for var tool in tools {
                if let previousEnabled = enabledByName[tool.namespacedName] {
                    tool.enabled = previousEnabled
                }
                try Self.insertMCPTool(tool, db: db)
            }
        }
    }

    func updateMCPToolEnabled(serverID: MCPServerID, namespacedName: String, enabled: Bool) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE mcp_tools SET enabled = ? WHERE server_id = ? AND namespaced_name = ?",
                arguments: [enabled ? 1 : 0, serverID.rawValue, namespacedName]
            )
        }
    }

    func listMCPResources(serverID: MCPServerID?) async throws -> [MCPResourceRecord] {
        try await database.read { db in
            try Self.fetchMCPResources(db, serverID: serverID)
        }
    }

    nonisolated func observeMCPResources() -> AsyncStream<[MCPResourceRecord]> {
        observationStream { db in
            try Self.fetchMCPResources(db, serverID: nil)
        }
    }

    func replaceMCPResources(_ resources: [MCPResourceRecord], serverID: MCPServerID) async throws {
        try await database.write { db in
            let existingRows = try Row.fetchAll(
                db,
                sql: "SELECT uri, selected_for_context, subscribed FROM mcp_resources WHERE server_id = ?",
                arguments: [serverID.rawValue]
            )
            let stateByURI = Dictionary(uniqueKeysWithValues: existingRows.map { row in
                (
                    row["uri"] as String,
                    ((row["selected_for_context"] as Int) == 1, (row["subscribed"] as Int) == 1)
                )
            })
            try db.execute(sql: "DELETE FROM mcp_resources WHERE server_id = ?", arguments: [serverID.rawValue])
            for var resource in resources {
                if let state = stateByURI[resource.uri] {
                    resource.selectedForContext = state.0
                    resource.subscribed = state.1
                }
                try Self.insertMCPResource(resource, db: db)
            }
        }
    }

    func updateMCPResourceSelection(serverID: MCPServerID, uri: String, selected: Bool) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE mcp_resources SET selected_for_context = ? WHERE server_id = ? AND uri = ?",
                arguments: [selected ? 1 : 0, serverID.rawValue, uri]
            )
        }
    }

    func updateMCPResourceSubscription(serverID: MCPServerID, uri: String, subscribed: Bool) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE mcp_resources SET subscribed = ? WHERE server_id = ? AND uri = ?",
                arguments: [subscribed ? 1 : 0, serverID.rawValue, uri]
            )
        }
    }

    func listMCPResourceTemplates(serverID: MCPServerID?) async throws -> [MCPResourceTemplateRecord] {
        try await database.read { db in
            try Self.fetchMCPResourceTemplates(db, serverID: serverID)
        }
    }

    func replaceMCPResourceTemplates(_ templates: [MCPResourceTemplateRecord], serverID: MCPServerID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM mcp_resource_templates WHERE server_id = ?", arguments: [serverID.rawValue])
            for template in templates {
                try Self.insertMCPResourceTemplate(template, db: db)
            }
        }
    }

    func listMCPPrompts(serverID: MCPServerID?) async throws -> [MCPPromptRecord] {
        try await database.read { db in
            try Self.fetchMCPPrompts(db, serverID: serverID)
        }
    }

    nonisolated func observeMCPPrompts() -> AsyncStream<[MCPPromptRecord]> {
        observationStream { db in
            try Self.fetchMCPPrompts(db, serverID: nil)
        }
    }

    func replaceMCPPrompts(_ prompts: [MCPPromptRecord], serverID: MCPServerID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM mcp_prompts WHERE server_id = ?", arguments: [serverID.rawValue])
            for prompt in prompts {
                try Self.insertMCPPrompt(prompt, db: db)
            }
        }
    }

    // MARK: - Downloads

    func listDownloads() async throws -> [ModelDownloadProgress] {
        try await database.read(Self.fetchDownloads)
    }

    nonisolated func observeDownloads() -> AsyncStream<[ModelDownloadProgress]> {
        observationStream(Self.fetchDownloads)
    }

    func upsertDownload(_ progress: ModelDownloadProgress) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO model_downloads
                    (id, repository, revision, status, bytes_received, total_bytes, current_file, checksum, local_path, error_message, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    status = excluded.status,
                    bytes_received = excluded.bytes_received,
                    total_bytes = excluded.total_bytes,
                    current_file = excluded.current_file,
                    checksum = excluded.checksum,
                    local_path = excluded.local_path,
                    error_message = excluded.error_message,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    progress.id.uuidString,
                    progress.repository,
                    progress.revision,
                    progress.status.rawValue,
                    progress.bytesReceived,
                    progress.totalBytes,
                    progress.currentFile,
                    progress.checksum,
                    progress.localURL?.path,
                    progress.errorMessage,
                    progress.updatedAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func deleteDownload(id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM model_downloads WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Audit

    func append(_ event: AuditEvent) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_events
                    (id, created_at, category, summary, redacted_payload, provider_id, model_id, tool_name, network_domains)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString,
                    event.createdAt.timeIntervalSinceReferenceDate,
                    event.category.rawValue,
                    event.summary,
                    event.redactedPayload,
                    event.providerID?.rawValue,
                    event.modelID?.rawValue,
                    event.toolName,
                    event.networkDomains.joined(separator: ","),
                ]
            )
        }
    }

    func list(category: AuditCategory?, limit: Int) async throws -> [AuditEvent] {
        try await database.read { db in
            try Self.fetchAuditEvents(db, category: category, limit: limit)
        }
    }

    nonisolated func observeRecent(limit: Int) -> AsyncStream<[AuditEvent]> {
        observationStream { db in
            try Self.fetchAuditEvents(db, category: nil, limit: limit)
        }
    }

    // MARK: - Observation Fetches

    private static func fetchConversations(_ db: Database) throws -> [ConversationRecord] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT id, title, updated_at, default_model_id, default_provider_id, archived_at, pinned
            FROM conversations
            WHERE deleted_at IS NULL
            ORDER BY pinned DESC, updated_at DESC
            """
        ).map(conversation(from:))
    }

    private static func fetchConversationPreviews(_ db: Database) throws -> [ConversationPreviewRecord] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT
                c.id,
                c.title,
                c.updated_at,
                c.default_model_id,
                c.default_provider_id,
                c.archived_at,
                c.pinned,
                lm.content AS last_message,
                lm.status AS last_message_status,
                COALESCE(stats.token_count, 0) AS token_count
            FROM conversations c
            LEFT JOIN messages lm ON lm.id = (
                SELECT id
                FROM messages
                WHERE conversation_id = c.id AND deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT 1
            )
            LEFT JOIN (
                SELECT
                    conversation_id,
                    SUM(
                        CASE
                            WHEN TRIM(content) = '' THEN 0
                            ELSE LENGTH(TRIM(content)) - LENGTH(REPLACE(TRIM(content), ' ', '')) + 1
                        END
                    ) AS token_count
                FROM messages
                WHERE deleted_at IS NULL
                GROUP BY conversation_id
            ) stats ON stats.conversation_id = c.id
            WHERE c.deleted_at IS NULL
            ORDER BY c.pinned DESC, c.updated_at DESC
            """
        ).map(conversationPreview(from:))
    }

    private static func fetchMessages(_ db: Database, conversationID: UUID) throws -> [ChatMessage] {
        var messages = try Row.fetchAll(
            db,
            sql: """
            SELECT id, role, content, created_at, tool_call_id, tool_name, tool_calls_json, provider_metadata_json
            FROM messages
            WHERE conversation_id = ? AND deleted_at IS NULL
            ORDER BY created_at ASC
            """,
            arguments: [conversationID.uuidString]
        ).map(message(from:))

        guard !messages.isEmpty else { return [] }

        let messageIDs = messages.map { $0.id.uuidString }
        let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
        let attachmentRows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, message_id, kind, file_name, content_type, local_path, byte_count
            FROM attachments
            WHERE message_id IN (\(placeholders))
            ORDER BY created_at ASC
            """,
            arguments: StatementArguments(messageIDs)
        )
        let attachmentsByMessageID = Dictionary(grouping: attachmentRows, by: { row in
            row["message_id"] as String
        }).mapValues { rows in
            rows.map(attachment(from:))
        }

        for index in messages.indices {
            messages[index].attachments = attachmentsByMessageID[messages[index].id.uuidString] ?? []
        }
        return messages
    }

    private static func fetchInstalledAndCuratedModels(_ db: Database) throws -> [ModelInstall] {
        let installed = try Row.fetchAll(
            db,
            sql: "SELECT * FROM model_installs ORDER BY updated_at DESC"
        ).map(modelInstall(from:))

        var byRepository = Dictionary(uniqueKeysWithValues: installed.map { ($0.repository.lowercased(), $0) })
        for entry in CuratedModelManifest.default.entries where byRepository[entry.repository.lowercased()] == nil {
            byRepository[entry.repository.lowercased()] = ModelInstall(
                modelID: ModelID(rawValue: entry.repository),
                displayName: entry.displayName,
                repository: entry.repository,
                modalities: entry.modalities,
                verification: CuratedModelManifest.default.contains(repository: entry.repository) ? .verified : .installable,
                state: .remote
            )
        }

        return byRepository.values.sorted { lhs, rhs in
            if lhs.state == rhs.state {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.state == .installed
        }
    }

    private static func fetchDocuments(_ db: Database) throws -> [VaultDocumentRecord] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT d.id, d.title, d.source_type, d.updated_at, COUNT(c.id) AS chunk_count
            FROM vault_documents d
            LEFT JOIN vault_chunks c ON c.document_id = d.id
            WHERE d.sync_state != ?
            GROUP BY d.id
            ORDER BY d.updated_at DESC
            """,
            arguments: [SyncState.deleted.rawValue]
        ).map(vaultDocument(from:))
    }

    private static func fetchEmbeddingProfiles(_ db: Database) throws -> [VaultEmbeddingProfile] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT *
            FROM vault_embedding_profiles
            ORDER BY is_active DESC, updated_at DESC, display_name COLLATE NOCASE ASC
            """
        ).map(vaultEmbeddingProfile(from:))
    }

    private static func fetchSettings(_ db: Database) throws -> AppSettingsSnapshot {
        guard let row = try Row.fetchOne(db, sql: "SELECT value_json FROM app_settings WHERE key = ?", arguments: ["app"]) else {
            return AppSettingsSnapshot()
        }
        let data = Data((row["value_json"] as String).utf8)
        return try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)
    }

    private static func fetchProviders(_ db: Database) throws -> [CloudProviderConfiguration] {
        try Row.fetchAll(db, sql: "SELECT * FROM cloud_providers ORDER BY display_name").map(provider(from:))
    }

    private static func fetchMCPServers(_ db: Database) throws -> [MCPServerConfiguration] {
        try Row.fetchAll(db, sql: "SELECT * FROM mcp_servers ORDER BY display_name").map(mcpServer(from:))
    }

    private static func fetchMCPTools(_ db: Database, serverID: MCPServerID?) throws -> [MCPToolRecord] {
        if let serverID {
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM mcp_tools WHERE server_id = ? ORDER BY display_name",
                arguments: [serverID.rawValue]
            ).map(mcpTool(from:))
        }
        return try Row.fetchAll(db, sql: "SELECT * FROM mcp_tools ORDER BY server_id, display_name").map(mcpTool(from:))
    }

    private static func fetchMCPResources(_ db: Database, serverID: MCPServerID?) throws -> [MCPResourceRecord] {
        if let serverID {
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM mcp_resources WHERE server_id = ? ORDER BY name",
                arguments: [serverID.rawValue]
            ).map(mcpResource(from:))
        }
        return try Row.fetchAll(db, sql: "SELECT * FROM mcp_resources ORDER BY server_id, name").map(mcpResource(from:))
    }

    private static func fetchMCPResourceTemplates(_ db: Database, serverID: MCPServerID?) throws -> [MCPResourceTemplateRecord] {
        if let serverID {
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM mcp_resource_templates WHERE server_id = ? ORDER BY name",
                arguments: [serverID.rawValue]
            ).map(mcpResourceTemplate(from:))
        }
        return try Row.fetchAll(db, sql: "SELECT * FROM mcp_resource_templates ORDER BY server_id, name").map(mcpResourceTemplate(from:))
    }

    private static func fetchMCPPrompts(_ db: Database, serverID: MCPServerID?) throws -> [MCPPromptRecord] {
        if let serverID {
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM mcp_prompts WHERE server_id = ? ORDER BY name",
                arguments: [serverID.rawValue]
            ).map(mcpPrompt(from:))
        }
        return try Row.fetchAll(db, sql: "SELECT * FROM mcp_prompts ORDER BY server_id, name").map(mcpPrompt(from:))
    }

    private static func fetchDownloads(_ db: Database) throws -> [ModelDownloadProgress] {
        try Row.fetchAll(db, sql: "SELECT * FROM model_downloads ORDER BY updated_at DESC").map(download(from:))
    }

    private static func fetchAuditEvents(_ db: Database, category: AuditCategory?, limit: Int) throws -> [AuditEvent] {
        let sql: String
        let arguments: StatementArguments
        if let category {
            sql = "SELECT * FROM audit_events WHERE category = ? ORDER BY created_at DESC LIMIT ?"
            arguments = [category.rawValue, limit]
        } else {
            sql = "SELECT * FROM audit_events ORDER BY created_at DESC LIMIT ?"
            arguments = [limit]
        }
        return try Row.fetchAll(db, sql: sql, arguments: arguments).map(audit(from:))
    }

    nonisolated private func observationStream<Value: Sendable & Equatable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncStream<Value> {
        let database = database
        return AsyncStream { continuation in
            let task = Task {
                let observation = ValueObservation.tracking(fetch).removeDuplicates()
                do {
                    for try await value in observation.values(in: database) {
                        continuation.yield(value)
                    }
                } catch {
                    continuation.finish()
                    return
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
#endif
