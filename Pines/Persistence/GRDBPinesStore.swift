import Foundation
import PinesCore

#if canImport(GRDB)
import GRDB

actor GRDBPinesStore:
    ConversationRepository,
    ModelInstallRepository,
    VaultRepository,
    SettingsRepository,
    CloudProviderRepository,
    ModelDownloadRepository,
    AuditEventRepository
{
    private let database: DatabasePool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: LocalStoreConfiguration = .init()) throws {
        let url = try Self.databaseURL(fileName: configuration.databaseFileName)
        database = try DatabasePool(path: url.path)
        try Self.migrator.migrate(database)
        try seedCuratedModels()
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
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, title, updated_at, default_model_id, archived_at, pinned
                FROM conversations
                WHERE deleted_at IS NULL
                ORDER BY pinned DESC, updated_at DESC
                """
            ).map(Self.conversation(from:))
        }
    }

    nonisolated func observeConversations() -> AsyncStream<[ConversationRecord]> {
        pollingStream { try await self.listConversations() }
    }

    func createConversation(title: String, defaultModelID: ModelID?) async throws -> ConversationRecord {
        let record = ConversationRecord(title: title, defaultModelID: defaultModelID)
        let now = Date()
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO conversations (id, title, created_at, updated_at, default_model_id, sync_state)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString,
                    record.title,
                    now.timeIntervalSinceReferenceDate,
                    now.timeIntervalSinceReferenceDate,
                    record.defaultModelID?.rawValue,
                    SyncState.local.rawValue,
                ]
            )
        }
        return record
    }

    func updateConversationTitle(_ title: String, conversationID: UUID) async throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?",
                arguments: [title, Date().timeIntervalSinceReferenceDate, conversationID.uuidString]
            )
        }
    }

    func setConversationArchived(_ archived: Bool, conversationID: UUID) async throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET archived_at = ?, updated_at = ? WHERE id = ?",
                arguments: [
                    archived ? Date().timeIntervalSinceReferenceDate : nil,
                    Date().timeIntervalSinceReferenceDate,
                    conversationID.uuidString,
                ]
            )
        }
    }

    func deleteConversation(id: UUID) async throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET deleted_at = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [Date().timeIntervalSinceReferenceDate, Date().timeIntervalSinceReferenceDate, SyncState.deleted.rawValue, id.uuidString]
            )
        }
    }

    func messages(in conversationID: UUID) async throws -> [ChatMessage] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, role, content, created_at, tool_call_id
                FROM messages
                WHERE conversation_id = ?
                ORDER BY created_at ASC
                """,
                arguments: [conversationID.uuidString]
            ).map(Self.message(from:))
        }
    }

    nonisolated func observeMessages(in conversationID: UUID) -> AsyncStream<[ChatMessage]> {
        pollingStream { try await self.messages(in: conversationID) }
    }

    func appendMessage(
        _ message: ChatMessage,
        status: MessageStatus,
        conversationID: UUID,
        modelID: ModelID?,
        providerID: ProviderID?
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO messages
                    (id, conversation_id, role, content, created_at, status, model_id, provider_id, tool_call_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.id.uuidString,
                    conversationID.uuidString,
                    message.role.rawValue,
                    message.content,
                    message.createdAt.timeIntervalSinceReferenceDate,
                    status.rawValue,
                    modelID?.rawValue,
                    providerID?.rawValue,
                    message.toolCallID,
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
                sql: "UPDATE conversations SET updated_at = ? WHERE id = ?",
                arguments: [Date().timeIntervalSinceReferenceDate, conversationID.uuidString]
            )
        }
    }

    func updateMessage(id: UUID, content: String, status: MessageStatus, tokenCount: Int?) async throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE messages SET content = ?, status = ?, token_count = ? WHERE id = ?",
                arguments: [content, status.rawValue, tokenCount, id.uuidString]
            )
        }
    }

    // MARK: - Models

    func listInstalledAndCuratedModels() async throws -> [ModelInstall] {
        let installed = try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM model_installs ORDER BY updated_at DESC"
            ).map(Self.modelInstall(from:))
        }

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

    nonisolated func observeInstalledAndCuratedModels() -> AsyncStream<[ModelInstall]> {
        pollingStream { try await self.listInstalledAndCuratedModels() }
    }

    func upsertInstall(_ install: ModelInstall) async throws {
        let now = Date()
        try database.write { db in
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
        try database.write { db in
            try db.execute(
                sql: "UPDATE model_installs SET state = ?, updated_at = ? WHERE repository = ?",
                arguments: [state.rawValue, Date().timeIntervalSinceReferenceDate, repository]
            )
        }
    }

    func deleteInstall(repository: String) async throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM model_installs WHERE repository = ?", arguments: [repository])
        }
    }

    // MARK: - Vault

    func listDocuments() async throws -> [VaultDocumentRecord] {
        try database.read { db in
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
            ).map(Self.vaultDocument(from:))
        }
    }

    nonisolated func observeDocuments() -> AsyncStream<[VaultDocumentRecord]> {
        pollingStream { try await self.listDocuments() }
    }

    func upsertDocument(_ document: VaultDocumentRecord, localURL: URL?, checksum: String?) async throws {
        let now = Date()
        try database.write { db in
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
        try database.write { db in
            try db.execute(
                sql: "UPDATE vault_documents SET sync_state = ?, updated_at = ? WHERE id = ?",
                arguments: [SyncState.deleted.rawValue, Date().timeIntervalSinceReferenceDate, id.uuidString]
            )
        }
    }

    func chunks(documentID: UUID) async throws -> [VaultChunk] {
        try database.read { db in
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

    func replaceChunks(_ chunks: [VaultChunk], documentID: UUID, embeddingModelID: ModelID?) async throws {
        try database.write { db in
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
                        chunk.tokenEstimate,
                        embeddingModelID?.rawValue,
                        Date().timeIntervalSinceReferenceDate,
                    ]
                )
            }
        }
    }

    func search(query: String, embedding: [Float]?, limit: Int) async throws -> [VaultSearchResult] {
        let normalizedLimit = max(1, limit)
        return try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id AS chunk_id, c.document_id, c.ordinal, c.text, c.token_estimate, d.title, d.source_type, d.updated_at
                FROM vault_chunks_fts f
                JOIN vault_chunks c ON c.id = f.chunk_id
                JOIN vault_documents d ON d.id = c.document_id
                WHERE vault_chunks_fts MATCH ?
                ORDER BY bm25(vault_chunks_fts)
                LIMIT ?
                """,
                arguments: [query.isEmpty ? "*" : query, normalizedLimit]
            )

            return rows.map { row in
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
                return VaultSearchResult(document: document, chunk: chunk, score: 1, snippet: String(text.prefix(320)))
            }
        }
    }

    // MARK: - Settings

    func loadSettings() async throws -> AppSettingsSnapshot {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT value_json FROM app_settings WHERE key = ?", arguments: ["app"]) else {
                return AppSettingsSnapshot()
            }
            let data = Data((row["value_json"] as String).utf8)
            return try decoder.decode(AppSettingsSnapshot.self, from: data)
        }
    }

    nonisolated func observeSettings() -> AsyncStream<AppSettingsSnapshot> {
        pollingStream { try await self.loadSettings() }
    }

    func saveSettings(_ settings: AppSettingsSnapshot) async throws {
        let json = String(decoding: try encoder.encode(settings), as: UTF8.self)
        try database.write { db in
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
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM cloud_providers ORDER BY display_name").map(Self.provider(from:))
        }
    }

    nonisolated func observeProviders() -> AsyncStream<[CloudProviderConfiguration]> {
        pollingStream { try await self.listProviders() }
    }

    func upsertProvider(_ provider: CloudProviderConfiguration) async throws {
        let now = Date()
        try database.write { db in
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
        try database.write { db in
            try db.execute(sql: "DELETE FROM cloud_providers WHERE id = ?", arguments: [id.rawValue])
        }
    }

    // MARK: - Downloads

    func listDownloads() async throws -> [ModelDownloadProgress] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM model_downloads ORDER BY updated_at DESC").map(Self.download(from:))
        }
    }

    nonisolated func observeDownloads() -> AsyncStream<[ModelDownloadProgress]> {
        pollingStream { try await self.listDownloads() }
    }

    func upsertDownload(_ progress: ModelDownloadProgress) async throws {
        try database.write { db in
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
        try database.write { db in
            try db.execute(sql: "DELETE FROM model_downloads WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Audit

    func append(_ event: AuditEvent) async throws {
        try database.write { db in
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
        try database.read { db in
            let sql: String
            let arguments: StatementArguments
            if let category {
                sql = "SELECT * FROM audit_events WHERE category = ? ORDER BY created_at DESC LIMIT ?"
                arguments = [category.rawValue, limit]
            } else {
                sql = "SELECT * FROM audit_events ORDER BY created_at DESC LIMIT ?"
                arguments = [limit]
            }
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.audit(from:))
        }
    }

    nonisolated func observeRecent(limit: Int) -> AsyncStream<[AuditEvent]> {
        pollingStream { try await self.list(category: nil, limit: limit) }
    }

    // MARK: - Mapping

    private func seedCuratedModels() throws {
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
            archived: (row["archived_at"] as Double?) != nil,
            pinned: (row["pinned"] as Int) == 1
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

    nonisolated private func pollingStream<Value: Sendable>(
        _ load: @escaping @Sendable () async throws -> Value
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let value = try? await load() {
                        continuation.yield(value)
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private enum StableSearchHash {
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
