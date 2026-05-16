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

    init(configuration: LocalStoreConfiguration = .init()) throws {
        let url = try Self.databaseURL(fileName: configuration.databaseFileName)
        database = try DatabasePool(path: url.path)
        try Self.migrator.migrate(database)
        try Self.seedCuratedModels(in: database)
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
                    (id, conversation_id, role, content, created_at, updated_at, status, model_id, provider_id, tool_call_id, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

    func updateMessage(id: UUID, content: String, status: MessageStatus, tokenCount: Int?) async throws {
        try await database.write { db in
            let updatedAt = Date().timeIntervalSinceReferenceDate
            try db.execute(
                sql: "UPDATE messages SET content = ?, status = ?, token_count = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [content, status.rawValue, tokenCount, updatedAt, SyncState.local.rawValue, id.uuidString]
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
                SELECT chunk_id, document_id, embedding_model_id, dimensions, fp16_embedding,
                       turboquant_code, norm, codec_version, checksum, created_at
                FROM vault_embeddings
                WHERE document_id = ?
                ORDER BY created_at ASC, chunk_id ASC
                """,
                arguments: [documentID.uuidString]
            ).map(Self.vaultStoredEmbedding(from:))
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
                        embeddingModelID?.rawValue,
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
                        (chunk_id, document_id, embedding_model_id, dimensions, fp16_embedding,
                         turboquant_code, norm, codec_version, checksum, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id,
                        documentID.uuidString,
                        embeddings.modelID.rawValue,
                        embedding.vector.count,
                        Self.encodeFP16(embedding.vector),
                        codeData,
                        Double(norm),
                        encodedCode.codecVersion,
                        StableSearchHash.hexDigest(for: "\(chunk.checksum)|\(embeddings.modelID.rawValue)|\(embedding.vector.count)"),
                        now,
                    ]
                )
            }
        }
    }

    func search(query: String, embedding: [Float]?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, embeddingModelID: nil, limit: limit)
    }

    func search(query: String, embedding: [Float]?, embeddingModelID: ModelID?, limit: Int) async throws -> [VaultSearchResult] {
        try await search(query: query, embedding: embedding, embeddingModelID: embeddingModelID, limit: limit, options: .default)
    }

    private func search(
        query: String,
        embedding: [Float]?,
        embeddingModelID: ModelID?,
        limit: Int,
        options: VaultSearchOptions
    ) async throws -> [VaultSearchResult] {
        let normalizedLimit = max(1, limit)
        if let embedding, !embedding.isEmpty {
            let vectorResults = try await vectorSearch(
                embedding: embedding,
                embeddingModelID: embeddingModelID,
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

            while true {
                if let deadline, Date() >= deadline {
                    break
                }

                let rows: [Row]
                if let embeddingModelID {
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
                        guard let code = try? JSONDecoder().decode(TurboQuantVectorCode.self, from: codeData) else {
                            return nil
                        }
                        let codec = TurboQuantVectorCodec(preset: code.preset, seed: code.seed)
                        guard let score = try? codec.approximateCosineSimilarity(query: embedding, code: code) else {
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

            let reranked = topCandidates.compactMap { candidate -> (chunkID: String, score: Double)? in
                guard let storedVector = try? Self.decodeFP16(candidate.fp16Embedding, dimensions: candidate.dimensions) else {
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
        try Row.fetchAll(
            db,
            sql: """
            SELECT id, role, content, created_at, tool_call_id
            FROM messages
            WHERE conversation_id = ? AND deleted_at IS NULL
            ORDER BY created_at ASC
            """,
            arguments: [conversationID.uuidString]
        ).map(message(from:))
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

    // MARK: - Mapping

    private static func seedCuratedModels(in database: DatabasePool) throws {
        try database.write { db in
            for entry in CuratedModelManifest.default.entries {
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM model_installs WHERE repository = ?)",
                    arguments: [entry.repository]
                ) ?? false
                guard !exists else { continue }
                try db.execute(
                    sql: """
                    INSERT INTO model_installs
                        (id, repository, display_name, modalities, verification, state, estimated_bytes, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        UUID().uuidString,
                        entry.repository,
                        entry.displayName,
                        Self.encodeModalities(entry.modalities),
                        entry.repository.localizedCaseInsensitiveContains("bitnet") ? ModelVerificationState.experimental.rawValue : ModelVerificationState.verified.rawValue,
                        ModelInstallState.remote.rawValue,
                        nil,
                        Date().timeIntervalSinceReferenceDate,
                        Date().timeIntervalSinceReferenceDate,
                    ]
                )
            }
        }
    }

    private static func conversation(from row: Row) -> ConversationRecord {
        ConversationRecord(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            title: row["title"],
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
            defaultModelID: (row["default_model_id"] as String?).map(ModelID.init(rawValue:)),
            defaultProviderID: (row["default_provider_id"] as String?).map(ProviderID.init(rawValue:)),
            archived: (row["archived_at"] as Double?) != nil,
            pinned: (row["pinned"] as Int) == 1
        )
    }

    private static func conversationPreview(from row: Row) -> ConversationPreviewRecord {
        ConversationPreviewRecord(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            title: row["title"],
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
            defaultModelID: (row["default_model_id"] as String?).map(ModelID.init(rawValue:)),
            defaultProviderID: (row["default_provider_id"] as String?).map(ProviderID.init(rawValue:)),
            archived: (row["archived_at"] as Double?) != nil,
            pinned: (row["pinned"] as Int) == 1,
            lastMessage: row["last_message"] as String?,
            lastMessageStatus: (row["last_message_status"] as String?).flatMap(MessageStatus.init(rawValue:)),
            tokenCount: row["token_count"] as Int
        )
    }

    private static func message(from row: Row) -> ChatMessage {
        ChatMessage(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            role: ChatRole(rawValue: row["role"]) ?? .assistant,
            content: row["content"],
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
            toolCallID: row["tool_call_id"] as String?
        )
    }

    private static func modelInstall(from row: Row) -> ModelInstall {
        ModelInstall(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            modelID: ModelID(rawValue: row["repository"]),
            displayName: row["display_name"],
            repository: row["repository"],
            revision: row["revision"] as String?,
            localURL: (row["local_path"] as String?).map(URL.init(fileURLWithPath:)),
            modalities: decodeModalities(row["modalities"]),
            verification: ModelVerificationState(rawValue: row["verification"]) ?? .installable,
            state: ModelInstallState(rawValue: row["state"]) ?? .remote,
            estimatedBytes: row["estimated_bytes"] as Int64?,
            license: row["license"] as String?,
            modelType: row["model_type"] as String?,
            processorClass: row["processor_class"] as String?,
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"])
        )
    }

    private static func vaultDocument(from row: Row) -> VaultDocumentRecord {
        VaultDocumentRecord(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            title: row["title"],
            sourceType: row["source_type"],
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
            chunkCount: row["chunk_count"]
        )
    }

    private static func vaultChunk(from row: Row) -> VaultChunk {
        let text: String = row["text"]
        return VaultChunk(
            id: row["id"],
            sourceID: row["document_id"],
            ordinal: row["ordinal"],
            text: text,
            startOffset: 0,
            endOffset: text.count,
            checksum: StableSearchHash.hexDigest(for: text)
        )
    }

    static func vaultStoredEmbedding(from row: Row) -> VaultStoredEmbedding {
        VaultStoredEmbedding(
            chunkID: row["chunk_id"],
            documentID: UUID(uuidString: row["document_id"]) ?? UUID(),
            modelID: ModelID(rawValue: row["embedding_model_id"]),
            dimensions: row["dimensions"],
            fp16Embedding: row["fp16_embedding"],
            turboQuantCode: row["turboquant_code"],
            norm: row["norm"],
            codecVersion: row["codec_version"],
            checksum: row["checksum"],
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"])
        )
    }

    private static func vaultSearchResult(from row: Row, score: Double) -> VaultSearchResult {
        let documentID = UUID(uuidString: row["document_id"]) ?? UUID()
        let text: String = row["text"]
        let document = VaultDocumentRecord(
            id: documentID,
            title: row["title"],
            sourceType: row["source_type"],
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
            chunkCount: 0
        )
        let chunk = VaultChunk(
            id: row["chunk_id"],
            sourceID: documentID.uuidString,
            ordinal: row["ordinal"],
            text: text,
            startOffset: 0,
            endOffset: text.count,
            checksum: StableSearchHash.hexDigest(for: text)
        )
        return VaultSearchResult(document: document, chunk: chunk, score: score, snippet: String(text.prefix(320)))
    }

    private static func vaultTurboQuantCodec(modelID: ModelID, dimensions: Int) -> TurboQuantVectorCodec {
        TurboQuantVectorCodec(
            preset: .turbo3_5,
            seed: TurboQuantVectorCodec.stableSeed(for: "\(modelID.rawValue)|\(dimensions)|vault-v1")
        )
    }

    private static func encodeFP16(_ vector: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(vector.count * MemoryLayout<UInt16>.size)
        for value in vector {
            var bitPattern = Float16(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bitPattern) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    private static func decodeFP16(_ data: Data, dimensions: Int) throws -> [Float] {
        guard data.count == dimensions * MemoryLayout<UInt16>.size else {
            throw VectorIndexError.dimensionMismatch(expected: dimensions * MemoryLayout<UInt16>.size, actual: data.count)
        }

        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return []
            }

            return (0..<dimensions).map { index in
                let bitPattern = baseAddress
                    .advanced(by: index * MemoryLayout<UInt16>.size)
                    .loadUnaligned(as: UInt16.self)
                return Float(Float16(bitPattern: UInt16(littleEndian: bitPattern)))
            }
        }
    }

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count else {
            return 0
        }
        let lhsMagnitude = vectorMagnitude(lhs)
        let rhsMagnitude = vectorMagnitude(rhs)
        guard lhsMagnitude > 0, rhsMagnitude > 0 else {
            return 0
        }
        let dot = zip(lhs, rhs).reduce(Float(0)) { partialResult, pair in
            partialResult + pair.0 * pair.1
        }
        return Double(dot / (lhsMagnitude * rhsMagnitude))
    }

    private static func vectorMagnitude(_ vector: [Float]) -> Float {
        vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
    }

    private static func provider(from row: Row) -> CloudProviderConfiguration {
        CloudProviderConfiguration(
            id: ProviderID(rawValue: row["id"]),
            kind: CloudProviderKind(rawValue: row["kind"]) ?? .custom,
            displayName: row["display_name"],
            baseURL: URL(string: row["base_url"]) ?? URL(string: "https://example.invalid")!,
            defaultModelID: (row["default_model_id"] as String?).map(ModelID.init(rawValue:)),
            validationStatus: ProviderValidationStatus(rawValue: row["validation_status"]) ?? .unvalidated,
            lastValidationError: row["last_validation_error"] as String?,
            extraHeadersJSON: row["extra_headers_json"] as String?,
            keychainService: row["keychain_service"],
            keychainAccount: row["keychain_account"],
            enabledForAgents: (row["enabled_for_agents"] as Int) == 1,
            lastValidatedAt: (row["last_validated_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }

    private static func mcpServer(from row: Row) -> MCPServerConfiguration {
        MCPServerConfiguration(
            id: MCPServerID(rawValue: row["id"]),
            displayName: row["display_name"],
            endpointURL: URL(string: row["endpoint_url"]) ?? URL(string: "https://example.invalid/mcp")!,
            authMode: MCPAuthMode(rawValue: row["auth_mode"]) ?? .none,
            enabled: (row["enabled"] as Int) == 1,
            allowInsecureLocalHTTP: (row["allow_insecure_local_http"] as Int) == 1,
            keychainService: row["keychain_service"],
            keychainAccount: row["keychain_account"],
            oauthAuthorizationURL: (row["oauth_authorization_url"] as String?).flatMap(URL.init(string:)),
            oauthTokenURL: (row["oauth_token_url"] as String?).flatMap(URL.init(string:)),
            oauthClientID: row["oauth_client_id"] as String?,
            oauthScopes: row["oauth_scopes"] as String?,
            oauthResource: row["oauth_resource"] as String?,
            resourcesEnabled: ((row["resources_enabled"] as Int?) ?? 0) == 1,
            promptsEnabled: ((row["prompts_enabled"] as Int?) ?? 0) == 1,
            samplingEnabled: ((row["sampling_enabled"] as Int?) ?? 0) == 1,
            byokSamplingEnabled: ((row["byok_sampling_enabled"] as Int?) ?? 0) == 1,
            subscriptionsEnabled: ((row["subscriptions_enabled"] as Int?) ?? 0) == 1,
            maxSamplingRequestsPerSession: (row["max_sampling_requests_per_session"] as Int?) ?? 3,
            status: MCPConnectionStatus(rawValue: row["status"]) ?? .disconnected,
            lastError: row["last_error"] as String?,
            lastConnectedAt: (row["last_connected_at"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"])
        )
    }

    private static func mcpTool(from row: Row) -> MCPToolRecord {
        let schemaJSON = row["input_schema_json"] as String
        let schema = (try? JSONDecoder().decode(JSONValue.self, from: Data(schemaJSON.utf8))) ?? JSONValue.objectSchema()
        return MCPToolRecord(
            serverID: MCPServerID(rawValue: row["server_id"]),
            originalName: row["original_name"],
            namespacedName: row["namespaced_name"],
            displayName: row["display_name"],
            description: row["description"],
            inputSchema: schema,
            enabled: (row["enabled"] as Int) == 1,
            lastDiscoveredAt: Date(timeIntervalSinceReferenceDate: row["last_discovered_at"]),
            lastError: row["last_error"] as String?
        )
    }

    private static func insertMCPTool(_ tool: MCPToolRecord, db: Database) throws {
        let schemaJSON = String(decoding: try JSONEncoder().encode(tool.inputSchema), as: UTF8.self)
        try db.execute(
            sql: """
            INSERT INTO mcp_tools
                (server_id, original_name, namespaced_name, display_name, description, input_schema_json,
                 enabled, last_discovered_at, last_error)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                tool.serverID.rawValue,
                tool.originalName,
                tool.namespacedName,
                tool.displayName,
                tool.description,
                schemaJSON,
                tool.enabled ? 1 : 0,
                tool.lastDiscoveredAt.timeIntervalSinceReferenceDate,
                tool.lastError,
            ]
        )
    }

    private static func mcpResource(from row: Row) -> MCPResourceRecord {
        MCPResourceRecord(
            serverID: MCPServerID(rawValue: row["server_id"]),
            uri: row["uri"],
            name: row["name"],
            title: row["title"] as String?,
            description: row["description"] as String?,
            mimeType: row["mime_type"] as String?,
            size: row["size"] as Int64?,
            icons: decodeJSON(row["icons_json"] as String?) ?? [],
            annotations: decodeJSON(row["annotations_json"] as String?),
            selectedForContext: (row["selected_for_context"] as Int) == 1,
            subscribed: (row["subscribed"] as Int) == 1,
            lastDiscoveredAt: Date(timeIntervalSinceReferenceDate: row["last_discovered_at"])
        )
    }

    private static func mcpResourceTemplate(from row: Row) -> MCPResourceTemplateRecord {
        MCPResourceTemplateRecord(
            serverID: MCPServerID(rawValue: row["server_id"]),
            uriTemplate: row["uri_template"],
            name: row["name"],
            title: row["title"] as String?,
            description: row["description"] as String?,
            mimeType: row["mime_type"] as String?,
            icons: decodeJSON(row["icons_json"] as String?) ?? [],
            annotations: decodeJSON(row["annotations_json"] as String?),
            lastDiscoveredAt: Date(timeIntervalSinceReferenceDate: row["last_discovered_at"])
        )
    }

    private static func mcpPrompt(from row: Row) -> MCPPromptRecord {
        MCPPromptRecord(
            serverID: MCPServerID(rawValue: row["server_id"]),
            name: row["name"],
            title: row["title"] as String?,
            description: row["description"] as String?,
            arguments: decodeJSON(row["arguments_json"] as String?) ?? [],
            icons: decodeJSON(row["icons_json"] as String?) ?? [],
            lastDiscoveredAt: Date(timeIntervalSinceReferenceDate: row["last_discovered_at"])
        )
    }

    private static func insertMCPResource(_ resource: MCPResourceRecord, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO mcp_resources
                (server_id, uri, name, title, description, mime_type, size, icons_json, annotations_json,
                 selected_for_context, subscribed, last_discovered_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                resource.serverID.rawValue,
                resource.uri,
                resource.name,
                resource.title,
                resource.description,
                resource.mimeType,
                resource.size,
                encodeJSON(resource.icons),
                encodeJSON(resource.annotations),
                resource.selectedForContext ? 1 : 0,
                resource.subscribed ? 1 : 0,
                resource.lastDiscoveredAt.timeIntervalSinceReferenceDate,
            ]
        )
    }

    private static func insertMCPResourceTemplate(_ template: MCPResourceTemplateRecord, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO mcp_resource_templates
                (server_id, uri_template, name, title, description, mime_type, icons_json, annotations_json, last_discovered_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                template.serverID.rawValue,
                template.uriTemplate,
                template.name,
                template.title,
                template.description,
                template.mimeType,
                encodeJSON(template.icons),
                encodeJSON(template.annotations),
                template.lastDiscoveredAt.timeIntervalSinceReferenceDate,
            ]
        )
    }

    private static func insertMCPPrompt(_ prompt: MCPPromptRecord, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO mcp_prompts
                (server_id, name, title, description, arguments_json, icons_json, last_discovered_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                prompt.serverID.rawValue,
                prompt.name,
                prompt.title,
                prompt.description,
                encodeJSON(prompt.arguments),
                encodeJSON(prompt.icons),
                prompt.lastDiscoveredAt.timeIntervalSinceReferenceDate,
            ]
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeJSON<T: Decodable>(_ string: String?) -> T? {
        guard let string, !string.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(string.utf8))
    }

    private static func download(from row: Row) -> ModelDownloadProgress {
        ModelDownloadProgress(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            repository: row["repository"],
            revision: row["revision"] as String?,
            status: ModelDownloadStatus(rawValue: row["status"]) ?? .queued,
            bytesReceived: row["bytes_received"],
            totalBytes: row["total_bytes"] as Int64?,
            currentFile: row["current_file"] as String?,
            checksum: row["checksum"] as String?,
            localURL: (row["local_path"] as String?).map(URL.init(fileURLWithPath:)),
            errorMessage: row["error_message"] as String?,
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"])
        )
    }

    private static func audit(from row: Row) -> AuditEvent {
        let domains = (row["network_domains"] as String?)?
            .split(separator: ",")
            .map(String.init) ?? []
        return AuditEvent(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
            category: AuditCategory(rawValue: row["category"]) ?? .security,
            summary: row["summary"],
            redactedPayload: row["redacted_payload"] as String?,
            providerID: (row["provider_id"] as String?).map(ProviderID.init(rawValue:)),
            modelID: (row["model_id"] as String?).map(ModelID.init(rawValue:)),
            toolName: row["tool_name"] as String?,
            networkDomains: domains
        )
    }

    private static func encodeModalities(_ modalities: Set<ModelModality>) -> String {
        modalities.map(\.rawValue).sorted().joined(separator: ",")
    }

    private static func decodeModalities(_ rawValue: String) -> Set<ModelModality> {
        Set(rawValue.split(separator: ",").compactMap { ModelModality(rawValue: String($0)) })
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
