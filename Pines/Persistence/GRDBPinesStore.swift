import Foundation
import PinesCore

#if canImport(GRDB)
import GRDB
import OSLog
#if canImport(SQLCipher)
import SQLCipher
#endif

actor GRDBPinesStore:
    ConversationRepository,
    ProjectRepository,
    ModelInstallRepository,
    VaultRepository,
    SettingsRepository,
    CloudProviderRepository,
    ProviderFileRepository,
    ProviderArtifactRepository,
    ProviderCacheRepository,
    ProviderBatchRepository,
    ProviderLiveSessionRepository,
    ProviderStructuredOutputRepository,
    ProviderModelCapabilityRepository,
    ProviderResearchRunRepository,
    MCPServerRepository,
    ModelDownloadRepository,
    AuditEventRepository,
    AppDataResetRepository
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

        let databaseKey = try Self.prepareDatabaseKey(at: url, dataProtection: configuration.dataProtection)

        let openStartedAt = Date()
        database = try DatabasePool(path: url.path, configuration: Self.databaseConfiguration(databaseKey: databaseKey))
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

    private static func prepareDatabaseKey(at url: URL, dataProtection: DataProtectionClass) throws -> Data? {
        #if DEBUG
        if PinesUITestLaunchConfiguration.usesPlaintextDatabase {
            try applyProtection(dataProtection, to: url.deletingLastPathComponent())
            return nil
        }
        #endif
        #if canImport(SQLCipher)
        let key = try SecureKeyStore.loadOrCreateDataKey(purpose: .encryptedDatabase, keyID: SecureKeyStore.databaseKeyID)
        if isPlaintextSQLiteDatabase(at: url) {
            try migratePlaintextDatabase(at: url, databaseKey: key)
        }
        try applyProtection(dataProtection, to: url)
        try applyProtection(dataProtection, to: url.deletingLastPathComponent())
        return key
        #else
        throw StoreSecurityError.sqlCipherUnavailable
        #endif
    }

    private static func databaseConfiguration(databaseKey: Data?) throws -> Configuration {
        var configuration = Configuration()
        guard let databaseKey else {
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            return configuration
        }
        #if canImport(SQLCipher)
        let rawKey = databaseKey.map { String(format: "%02x", $0) }.joined()
        configuration.prepareDatabase { db in
            try db.execute(sql: #"PRAGMA key = "x'\#(rawKey)'""#)
            guard let cipherVersion = try String.fetchOne(db, sql: "PRAGMA cipher_version"),
                  !cipherVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw StoreSecurityError.sqlCipherUnavailable
            }
            try db.execute(sql: "PRAGMA cipher_memory_security = ON")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        #else
        _ = databaseKey
        #endif
        return configuration
    }

    private static func isPlaintextSQLiteDatabase(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return false
        }
        defer { try? handle.close() }
        let header = try? handle.read(upToCount: 16)
        return header == Data("SQLite format 3\u{0}".utf8)
    }

    private static func migratePlaintextDatabase(at url: URL, databaseKey: Data) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let migrationID = UUID().uuidString
        let encryptedURL = directory.appending(path: "\(url.lastPathComponent).encrypted-\(migrationID)")
        let backupName = "\(url.lastPathComponent).plaintext-\(migrationID)"
        let backupURL = directory.appending(path: backupName)

        try removeDatabaseFiles(at: encryptedURL)
        let queue = try DatabaseQueue(path: encryptedURL.path, configuration: databaseConfiguration(databaseKey: databaseKey))
        try migrator.migrate(queue)
        try queue.write { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: "ATTACH DATABASE ? AS plaintext KEY ''", arguments: [url.path])
            defer { try? db.execute(sql: "DETACH DATABASE plaintext") }

            for table in plaintextMigrationTables {
                guard try tableExists(table, in: "main", db: db),
                      try tableExists(table, in: "plaintext", db: db)
                else {
                    continue
                }
                let destinationColumns = try columnNames(table: table, schema: "main", db: db)
                let sourceColumns = Set(try columnNames(table: table, schema: "plaintext", db: db))
                let columns = destinationColumns.filter { sourceColumns.contains($0) && shouldMigrateColumn($0, table: table) }
                guard !columns.isEmpty else { continue }
                let columnSQL = columns.map(quotedIdentifier).joined(separator: ", ")
                try db.execute(sql: """
                    INSERT OR REPLACE INTO main.\(quotedIdentifier(table)) (\(columnSQL))
                    SELECT \(columnSQL) FROM plaintext.\(quotedIdentifier(table))
                    """)
            }

            try rebuildFTS("messages_fts", db: db)
            try rebuildFTS("vault_chunks_fts", db: db)
            try verifyMigratedRowCounts(db: db)
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }

        _ = try fileManager.replaceItemAt(url, withItemAt: encryptedURL, backupItemName: backupName)
        try removeDatabaseFiles(at: backupURL)
        try removeDatabaseFiles(at: encryptedURL)
        try removeDatabaseSidecars(for: url)
    }

    private static let plaintextMigrationTables = [
        "conversations",
        "messages",
        "attachments",
        "model_installs",
        "vault_documents",
        "vault_chunks",
        "audit_events",
        "app_settings",
        "cloud_providers",
        "model_downloads",
        "sync_records",
        "chat_runs",
        "agent_sessions",
        "tool_runs",
        "vault_import_jobs",
        "browser_actions",
        "vault_embeddings",
        "mcp_servers",
        "mcp_tools",
        "mcp_resources",
        "mcp_resource_templates",
        "mcp_prompts",
        "vault_embeddings_v2",
        "vault_embedding_profiles",
        "vault_embedding_jobs",
        "vault_retrieval_events",
        "vault_embeddings_v3",
        "openai_provider_files",
        "openai_vector_stores",
        "openai_vector_store_files",
        "openai_hosted_tool_calls",
        "openai_artifacts",
        "openai_background_responses",
        "openai_realtime_sessions",
        "openai_batch_jobs",
        "openai_structured_output_results",
        "provider_files",
        "provider_artifacts",
        "provider_caches",
        "provider_batches",
        "provider_live_sessions",
        "provider_structured_outputs",
        "provider_model_capabilities",
        "provider_research_runs",
        "projects",
    ]

    private static let userResetTables = plaintextMigrationTables

    private static let criticalMigrationTables = [
        "conversations",
        "messages",
        "vault_chunks",
        "vault_embeddings_v3",
        "app_settings",
        "audit_events",
    ]

    private static func shouldMigrateColumn(_ column: String, table: String) -> Bool {
        guard table == "cloud_providers" else { return true }
        return column != "extra_headers_json" && column != "headers_json"
    }

    private static func tableExists(_ table: String, in schema: String, db: Database) throws -> Bool {
        try String.fetchOne(
            db,
            sql: "SELECT name FROM \(quotedIdentifier(schema)).sqlite_master WHERE type = 'table' AND name = ?",
            arguments: [table]
        ) != nil
    }

    private static func columnNames(table: String, schema: String, db: Database) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: "PRAGMA \(quotedIdentifier(schema)).table_info(\(quotedIdentifier(table)))")
        return rows.compactMap { row in row["name"] as String? }
    }

    private static func verifyMigratedRowCounts(db: Database) throws {
        for table in criticalMigrationTables {
            guard try tableExists(table, in: "main", db: db),
                  try tableExists(table, in: "plaintext", db: db)
            else {
                continue
            }
            let primaryKeys = try primaryKeyColumns(table: table, schema: "plaintext", db: db)
            guard !primaryKeys.isEmpty else {
                try verifyMigratedTableCount(table: table, db: db)
                continue
            }
            let sourceCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plaintext.\(quotedIdentifier(table))") ?? 0
            let primaryKeyPredicates = primaryKeys
                .map { "destination.\(quotedIdentifier($0)) = source.\(quotedIdentifier($0))" }
                .joined(separator: " AND ")
            let migratedSourceCount = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM plaintext.\(quotedIdentifier(table)) AS source
                WHERE EXISTS (
                    SELECT 1
                    FROM main.\(quotedIdentifier(table)) AS destination
                    WHERE \(primaryKeyPredicates)
                )
                """
            ) ?? 0
            guard sourceCount == migratedSourceCount else {
                throw StoreSecurityError.migrationVerificationFailed(table: table, expected: sourceCount, actual: migratedSourceCount)
            }
        }
    }

    private static func verifyMigratedTableCount(table: String, db: Database) throws {
        let sourceCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plaintext.\(quotedIdentifier(table))") ?? 0
        let destinationCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM main.\(quotedIdentifier(table))") ?? 0
        guard sourceCount == destinationCount else {
            throw StoreSecurityError.migrationVerificationFailed(table: table, expected: sourceCount, actual: destinationCount)
        }
    }

    private static func primaryKeyColumns(table: String, schema: String, db: Database) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: "PRAGMA \(quotedIdentifier(schema)).table_info(\(quotedIdentifier(table)))")
        return rows.compactMap { row -> (position: Int, name: String)? in
            let name: String = row["name"]
            let position: Int = row["pk"]
            guard position > 0 else { return nil }
            return (position, name)
        }
        .sorted { $0.position < $1.position }
        .map(\.name)
    }

    private static func rebuildFTS(_ table: String, db: Database) throws {
        guard try tableExists(table, in: "main", db: db) else { return }
        try db.execute(sql: "INSERT INTO \(quotedIdentifier(table))(\(quotedIdentifier(table))) VALUES('rebuild')")
    }

    private static func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func removeDatabaseFiles(at url: URL) throws {
        try removeIfPresent(url)
        try removeDatabaseSidecars(for: url)
    }

    private static func removeDatabaseSidecars(for url: URL) throws {
        try removeIfPresent(URL(fileURLWithPath: "\(url.path)-wal"))
        try removeIfPresent(URL(fileURLWithPath: "\(url.path)-shm"))
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func applyProtection(_ dataProtection: DataProtectionClass, to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let protection: FileProtectionType = switch dataProtection {
        case .complete:
            .complete
        case .completeUntilFirstUserAuthentication:
            .completeUntilFirstUserAuthentication
        }
        try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
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

    func deleteAllUserRecords() async throws {
        try await database.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            defer {
                try? db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            for table in Self.userResetTables.reversed() {
                guard try Self.tableExists(table, in: "main", db: db) else { continue }
                try db.execute(sql: "DELETE FROM \(Self.quotedIdentifier(table))")
            }
            if try Self.tableExists("messages_fts", in: "main", db: db) {
                try db.execute(sql: "DELETE FROM messages_fts")
            }
            if try Self.tableExists("vault_chunks_fts", in: "main", db: db) {
                try db.execute(sql: "DELETE FROM vault_chunks_fts")
            }
        }
        try Self.seedCuratedModels(in: database)
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
        try await createConversation(title: title, defaultModelID: defaultModelID, defaultProviderID: defaultProviderID, projectID: nil)
    }

    func createConversation(title: String, defaultModelID: ModelID?, defaultProviderID: ProviderID?, projectID: UUID?) async throws -> ConversationRecord {
        let record = ConversationRecord(title: title, defaultModelID: defaultModelID, defaultProviderID: defaultProviderID, projectID: projectID)
        let now = Date()
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO conversations (id, title, created_at, updated_at, default_model_id, default_provider_id, project_id, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString,
                    record.title,
                    now.timeIntervalSinceReferenceDate,
                    now.timeIntervalSinceReferenceDate,
                    record.defaultModelID?.rawValue,
                    record.defaultProviderID?.rawValue,
                    record.projectID?.uuidString,
                    SyncState.local.rawValue,
                ]
            )
        }
        return record
    }

    func moveConversation(_ conversationID: UUID, toProject projectID: UUID?) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE conversations SET project_id = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [projectID?.uuidString, Date().timeIntervalSinceReferenceDate, SyncState.local.rawValue, conversationID.uuidString]
            )
        }
    }

    // MARK: - Projects

    func listProjects() async throws -> [ProjectRecord] {
        try await database.read(Self.fetchProjects)
    }

    func createProject(name: String) async throws -> ProjectRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let record = ProjectRecord(name: trimmed.isEmpty ? "New project" : trimmed, createdAt: now, updatedAt: now)
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO projects (id, name, vault_enabled, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString,
                    record.name,
                    record.vaultEnabled ? 1 : 0,
                    record.createdAt.timeIntervalSinceReferenceDate,
                    record.updatedAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
        return record
    }

    func updateProjectName(_ name: String, projectID: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE projects SET name = ?, updated_at = ? WHERE id = ?",
                arguments: [name.trimmingCharacters(in: .whitespacesAndNewlines), Date().timeIntervalSinceReferenceDate, projectID.uuidString]
            )
        }
    }

    func setProjectVaultEnabled(_ enabled: Bool, projectID: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE projects SET vault_enabled = ?, updated_at = ? WHERE id = ?",
                arguments: [enabled ? 1 : 0, Date().timeIntervalSinceReferenceDate, projectID.uuidString]
            )
        }
    }

    func deleteProject(id: UUID) async throws {
        try await database.write { db in
            let now = Date().timeIntervalSinceReferenceDate
            try db.execute(sql: "UPDATE projects SET deleted_at = ?, updated_at = ? WHERE id = ?", arguments: [now, now, id.uuidString])
            try db.execute(sql: "UPDATE conversations SET project_id = NULL, updated_at = ? WHERE project_id = ?", arguments: [now, id.uuidString])
            try db.execute(sql: "UPDATE vault_documents SET project_id = NULL, updated_at = ? WHERE project_id = ?", arguments: [now, id.uuidString])
        }
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

    func recentMessages(in conversationID: UUID, limit: Int, requiredMessageIDs: Set<UUID>) async throws -> [ChatMessage] {
        try await database.read { db in
            try Self.fetchRecentMessages(
                db,
                conversationID: conversationID,
                limit: limit,
                requiredMessageIDs: requiredMessageIDs
            )
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

    func deleteMessages(after messageID: UUID, in conversationID: UUID) async throws {
        try await database.write { db in
            guard let anchorRow = try Row.fetchOne(
                db,
                sql: """
                SELECT rowid
                FROM messages
                WHERE id = ? AND conversation_id = ? AND deleted_at IS NULL
                """,
                arguments: [messageID.uuidString, conversationID.uuidString]
            ) else {
                return
            }

            let updatedAt = Date().timeIntervalSinceReferenceDate
            try db.execute(
                sql: """
                UPDATE messages
                SET deleted_at = ?, updated_at = ?, sync_state = ?
                WHERE conversation_id = ?
                    AND deleted_at IS NULL
                    AND rowid > ?
                """,
                arguments: [
                    updatedAt,
                    updatedAt,
                    SyncState.local.rawValue,
                    conversationID.uuidString,
                    anchorRow["rowid"] as Int64,
                ]
            )
            try db.execute(
                sql: "UPDATE conversations SET updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [updatedAt, SyncState.local.rawValue, conversationID.uuidString]
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

    func searchConversations(query: String, limit: Int) async throws -> [ConversationSearchResult] {
        try await database.read { db in
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let ftsQuery = Self.safeFTSQuery(from: normalizedQuery) else {
                return []
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    c.id AS conversation_id,
                    c.title AS conversation_title,
                    c.updated_at AS conversation_updated_at,
                    m.id AS message_id,
                    m.role AS role,
                    m.content AS content,
                    m.created_at AS created_at
                FROM messages_fts f
                JOIN messages m ON m.id = f.message_id
                JOIN conversations c ON c.id = f.conversation_id
                WHERE messages_fts MATCH ?
                    AND c.deleted_at IS NULL
                    AND m.deleted_at IS NULL
                    AND m.role != ?
                ORDER BY bm25(messages_fts)
                LIMIT ?
                """,
                arguments: [ftsQuery, ChatRole.tool.rawValue, max(1, limit)]
            )
            return rows.map { row in
                let content: String = row["content"]
                return ConversationSearchResult(
                    conversationID: row["conversation_id"],
                    conversationTitle: row["conversation_title"],
                    conversationUpdatedAtISO8601: ConversationSearchResult.iso8601(
                        Date(timeIntervalSinceReferenceDate: row["conversation_updated_at"])
                    ),
                    messageID: row["message_id"],
                    role: row["role"],
                    createdAtISO8601: ConversationSearchResult.iso8601(
                        Date(timeIntervalSinceReferenceDate: row["created_at"])
                    ),
                    snippet: ConversationSearchResult.snippet(from: content, query: normalizedQuery)
                )
            }
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
                    (id, title, source_type, local_path, sha256, project_id, created_at, updated_at, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    source_type = excluded.source_type,
                    local_path = excluded.local_path,
                    sha256 = excluded.sha256,
                    project_id = excluded.project_id,
                    updated_at = excluded.updated_at,
                    sync_state = excluded.sync_state
                """,
                arguments: [
                    document.id.uuidString,
                    document.title,
                    document.sourceType,
                    localURL?.path,
                    checksum,
                    document.projectID?.uuidString,
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

    func deleteChunk(id: String, documentID: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "DELETE FROM vault_chunks WHERE id = ? AND document_id = ?",
                arguments: [id, documentID.uuidString]
            )
            try db.execute(
                sql: "UPDATE vault_documents SET updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [Date().timeIntervalSinceReferenceDate, SyncState.local.rawValue, documentID.uuidString]
            )
        }
    }

    func moveDocument(_ documentID: UUID, toProject projectID: UUID?) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE vault_documents SET project_id = ?, updated_at = ?, sync_state = ? WHERE id = ?",
                arguments: [
                    projectID?.uuidString,
                    Date().timeIntervalSinceReferenceDate,
                    SyncState.local.rawValue,
                    documentID.uuidString,
                ]
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
                     extra_headers_json, headers_json, keychain_service, keychain_account, allow_insecure_local_http, enabled_for_agents,
                     last_validated_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    display_name = excluded.display_name,
                    base_url = excluded.base_url,
                    default_model_id = excluded.default_model_id,
                    validation_status = excluded.validation_status,
                    last_validation_error = excluded.last_validation_error,
                    extra_headers_json = NULL,
                    headers_json = excluded.headers_json,
                    keychain_service = excluded.keychain_service,
                    keychain_account = excluded.keychain_account,
                    allow_insecure_local_http = excluded.allow_insecure_local_http,
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
                    nil,
                    Self.encodeJSON(provider.headers),
                    provider.keychainService,
                    provider.keychainAccount,
                    provider.allowInsecureLocalHTTP ? 1 : 0,
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

    // MARK: - Provider Lifecycle Records

    func listProviderFiles(providerID: ProviderID?) async throws -> [ProviderFileRecord] {
        try await database.read { db in
            if let providerID {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_files WHERE provider_id = ? ORDER BY created_at DESC",
                    arguments: [providerID.rawValue]
                ).map(Self.providerFile(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM provider_files ORDER BY created_at DESC").map(Self.providerFile(from:))
        }
    }

    func upsertProviderFile(_ file: ProviderFileRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_files
                    (id, provider_id, provider_kind, purpose, file_name, content_type, byte_count, status, sha256,
                     local_path, provider_object, provider_metadata_json, created_at, expires_at, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    purpose = excluded.purpose,
                    file_name = excluded.file_name,
                    content_type = excluded.content_type,
                    byte_count = excluded.byte_count,
                    status = excluded.status,
                    sha256 = excluded.sha256,
                    local_path = excluded.local_path,
                    provider_object = excluded.provider_object,
                    provider_metadata_json = excluded.provider_metadata_json,
                    expires_at = excluded.expires_at,
                    last_error = excluded.last_error
                """,
                arguments: [
                    file.id,
                    file.providerID.rawValue,
                    file.providerKind.rawValue,
                    file.purpose,
                    file.fileName,
                    file.contentType,
                    file.byteCount,
                    file.status,
                    file.sha256,
                    file.localURL?.path,
                    file.providerObject,
                    Self.encodeProviderMetadata(file.providerMetadata),
                    file.createdAt.timeIntervalSinceReferenceDate,
                    file.expiresAt?.timeIntervalSinceReferenceDate,
                    file.lastError,
                ]
            )
        }
    }

    func deleteProviderFile(id: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_files WHERE id = ?", arguments: [id])
        }
    }

    func listProviderArtifacts(responseID: String?) async throws -> [ProviderArtifactRecord] {
        try await database.read { db in
            if let responseID {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_artifacts WHERE response_id = ? ORDER BY created_at ASC",
                    arguments: [responseID]
                ).map(Self.providerArtifact(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM provider_artifacts ORDER BY created_at DESC").map(Self.providerArtifact(from:))
        }
    }

    func upsertProviderArtifact(_ artifact: ProviderArtifactRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_artifacts
                    (id, provider_id, provider_kind, response_id, tool_call_id, provider_file_id, kind, file_name,
                     content_type, byte_count, text, content_json, local_path, remote_url, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    response_id = excluded.response_id,
                    tool_call_id = excluded.tool_call_id,
                    provider_file_id = excluded.provider_file_id,
                    kind = excluded.kind,
                    file_name = excluded.file_name,
                    content_type = excluded.content_type,
                    byte_count = excluded.byte_count,
                    text = excluded.text,
                    content_json = excluded.content_json,
                    local_path = excluded.local_path,
                    remote_url = excluded.remote_url
                """,
                arguments: [
                    artifact.id,
                    artifact.providerID?.rawValue,
                    artifact.providerKind.rawValue,
                    artifact.responseID,
                    artifact.toolCallID,
                    artifact.providerFileID,
                    artifact.kind,
                    artifact.fileName,
                    artifact.contentType,
                    artifact.byteCount,
                    artifact.text,
                    Self.encodeJSON(artifact.content),
                    artifact.localURL?.path,
                    artifact.remoteURL?.absoluteString,
                    artifact.createdAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func deleteProviderArtifact(id: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_artifacts WHERE id = ?", arguments: [id])
        }
    }

    func listProviderCaches(providerID: ProviderID?, kind: String?) async throws -> [ProviderCacheRecord] {
        try await database.read { db in
            switch (providerID, kind) {
            case let (providerID?, kind?):
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_caches WHERE provider_id = ? AND kind = ? ORDER BY created_at DESC",
                    arguments: [providerID.rawValue, kind]
                ).map(Self.providerCache(from:))
            case let (providerID?, nil):
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_caches WHERE provider_id = ? ORDER BY created_at DESC",
                    arguments: [providerID.rawValue]
                ).map(Self.providerCache(from:))
            case let (nil, kind?):
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_caches WHERE kind = ? ORDER BY created_at DESC",
                    arguments: [kind]
                ).map(Self.providerCache(from:))
            case (nil, nil):
                return try Row.fetchAll(db, sql: "SELECT * FROM provider_caches ORDER BY created_at DESC").map(Self.providerCache(from:))
            }
        }
    }

    func upsertProviderCache(_ cache: ProviderCacheRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_caches
                    (id, provider_id, provider_kind, kind, name, model_id, status, usage_bytes, item_counts_json,
                     configuration_json, metadata_json, created_at, expires_at, last_active_at, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    kind = excluded.kind,
                    name = excluded.name,
                    model_id = excluded.model_id,
                    status = excluded.status,
                    usage_bytes = excluded.usage_bytes,
                    item_counts_json = excluded.item_counts_json,
                    configuration_json = excluded.configuration_json,
                    metadata_json = excluded.metadata_json,
                    expires_at = excluded.expires_at,
                    last_active_at = excluded.last_active_at,
                    last_error = excluded.last_error
                """,
                arguments: [
                    cache.id,
                    cache.providerID.rawValue,
                    cache.providerKind.rawValue,
                    cache.kind,
                    cache.name,
                    cache.modelID?.rawValue,
                    cache.status,
                    cache.usageBytes,
                    Self.encodeJSON(cache.itemCounts),
                    Self.encodeJSON(cache.configuration),
                    Self.encodeJSON(cache.metadata),
                    cache.createdAt.timeIntervalSinceReferenceDate,
                    cache.expiresAt?.timeIntervalSinceReferenceDate,
                    cache.lastActiveAt?.timeIntervalSinceReferenceDate,
                    cache.lastError,
                ]
            )
        }
    }

    func deleteProviderCache(id: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_caches WHERE id = ?", arguments: [id])
        }
    }

    func listProviderBatches(providerID: ProviderID?) async throws -> [ProviderBatchRecord] {
        try await database.read { db in
            if let providerID {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_batches WHERE provider_id = ? ORDER BY created_at DESC",
                    arguments: [providerID.rawValue]
                ).map(Self.providerBatch(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM provider_batches ORDER BY created_at DESC").map(Self.providerBatch(from:))
        }
    }

    func upsertProviderBatch(_ batch: ProviderBatchRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_batches
                    (id, provider_id, provider_kind, endpoint, status, input_file_id, output_file_id, error_file_id,
                     completion_window, request_counts_json, metadata_json, created_at, completed_at, expires_at, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    endpoint = excluded.endpoint,
                    status = excluded.status,
                    input_file_id = excluded.input_file_id,
                    output_file_id = excluded.output_file_id,
                    error_file_id = excluded.error_file_id,
                    completion_window = excluded.completion_window,
                    request_counts_json = excluded.request_counts_json,
                    metadata_json = excluded.metadata_json,
                    completed_at = excluded.completed_at,
                    expires_at = excluded.expires_at,
                    last_error = excluded.last_error
                """,
                arguments: [
                    batch.id,
                    batch.providerID.rawValue,
                    batch.providerKind.rawValue,
                    batch.endpoint,
                    batch.status,
                    batch.inputFileID,
                    batch.outputFileID,
                    batch.errorFileID,
                    batch.completionWindow,
                    Self.encodeJSON(batch.requestCounts),
                    Self.encodeJSON(batch.metadata),
                    batch.createdAt.timeIntervalSinceReferenceDate,
                    batch.completedAt?.timeIntervalSinceReferenceDate,
                    batch.expiresAt?.timeIntervalSinceReferenceDate,
                    batch.lastError,
                ]
            )
        }
    }

    func deleteProviderBatch(id: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_batches WHERE id = ?", arguments: [id])
        }
    }

    func listProviderLiveSessions(providerID: ProviderID?) async throws -> [ProviderLiveSessionRecord] {
        try await database.read { db in
            if let providerID {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_live_sessions WHERE provider_id = ? ORDER BY created_at DESC",
                    arguments: [providerID.rawValue]
                ).map(Self.providerLiveSession(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM provider_live_sessions ORDER BY created_at DESC").map(Self.providerLiveSession(from:))
        }
    }

    func upsertProviderLiveSession(_ session: ProviderLiveSessionRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_live_sessions
                    (id, provider_id, provider_kind, model_id, status, modalities_json, credential_keychain_account,
                     expires_at, provider_metadata_json, created_at, closed_at, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    model_id = excluded.model_id,
                    status = excluded.status,
                    modalities_json = excluded.modalities_json,
                    credential_keychain_account = excluded.credential_keychain_account,
                    expires_at = excluded.expires_at,
                    provider_metadata_json = excluded.provider_metadata_json,
                    closed_at = excluded.closed_at,
                    last_error = excluded.last_error
                """,
                arguments: [
                    session.id,
                    session.providerID.rawValue,
                    session.providerKind.rawValue,
                    session.modelID.rawValue,
                    session.status,
                    Self.encodeJSON(session.modalities),
                    session.credentialKeychainAccount,
                    session.expiresAt?.timeIntervalSinceReferenceDate,
                    Self.encodeProviderMetadata(session.providerMetadata),
                    session.createdAt.timeIntervalSinceReferenceDate,
                    session.closedAt?.timeIntervalSinceReferenceDate,
                    session.lastError,
                ]
            )
        }
    }

    func deleteProviderLiveSession(id: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_live_sessions WHERE id = ?", arguments: [id])
        }
    }

    func listProviderStructuredOutputs(responseID: String?) async throws -> [ProviderStructuredOutputRecord] {
        try await database.read { db in
            if let responseID {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_structured_outputs WHERE response_id = ? ORDER BY created_at ASC",
                    arguments: [responseID]
                ).map(Self.providerStructuredOutput(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM provider_structured_outputs ORDER BY created_at DESC").map(Self.providerStructuredOutput(from:))
        }
    }

    func upsertProviderStructuredOutput(_ output: ProviderStructuredOutputRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_structured_outputs
                    (id, provider_id, provider_kind, response_id, message_id, schema_name, schema_json, content_json,
                     refusal, incomplete_reason, validation_errors_json, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    response_id = excluded.response_id,
                    message_id = excluded.message_id,
                    schema_name = excluded.schema_name,
                    schema_json = excluded.schema_json,
                    content_json = excluded.content_json,
                    refusal = excluded.refusal,
                    incomplete_reason = excluded.incomplete_reason,
                    validation_errors_json = excluded.validation_errors_json,
                    status = excluded.status
                """,
                arguments: [
                    output.id.uuidString,
                    output.providerID?.rawValue,
                    output.providerKind.rawValue,
                    output.responseID,
                    output.messageID?.uuidString,
                    output.schemaName,
                    Self.encodeJSON(output.schema),
                    Self.encodeJSON(output.content),
                    output.refusal,
                    output.incompleteReason,
                    Self.encodeJSON(output.validationErrors),
                    output.status,
                    output.createdAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func deleteProviderStructuredOutput(id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_structured_outputs WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func listProviderModelCapabilities(providerID: ProviderID?) async throws -> [ProviderModelCapabilityRecord] {
        try await database.read { db in
            if let providerID {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_model_capabilities WHERE provider_id = ? ORDER BY fetched_at DESC",
                    arguments: [providerID.rawValue]
                ).map(Self.providerModelCapability(from:))
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM provider_model_capabilities ORDER BY fetched_at DESC").map(Self.providerModelCapability(from:))
        }
    }

    func upsertProviderModelCapability(_ capability: ProviderModelCapabilityRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_model_capabilities
                    (provider_id, provider_kind, model_id, capabilities_json, context_window_tokens,
                     input_modalities_json, output_modalities_json, metadata_json, fetched_at, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(provider_id, model_id) DO UPDATE SET
                    provider_kind = excluded.provider_kind,
                    capabilities_json = excluded.capabilities_json,
                    context_window_tokens = excluded.context_window_tokens,
                    input_modalities_json = excluded.input_modalities_json,
                    output_modalities_json = excluded.output_modalities_json,
                    metadata_json = excluded.metadata_json,
                    fetched_at = excluded.fetched_at,
                    expires_at = excluded.expires_at
                """,
                arguments: [
                    capability.providerID.rawValue,
                    capability.providerKind.rawValue,
                    capability.modelID.rawValue,
                    Self.encodeJSON(capability.capabilities),
                    capability.contextWindowTokens,
                    Self.encodeJSON(capability.inputModalities),
                    Self.encodeJSON(capability.outputModalities),
                    Self.encodeJSON(capability.metadata),
                    capability.fetchedAt.timeIntervalSinceReferenceDate,
                    capability.expiresAt?.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func deleteProviderModelCapability(providerID: ProviderID, modelID: ModelID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "DELETE FROM provider_model_capabilities WHERE provider_id = ? AND model_id = ?",
                arguments: [providerID.rawValue, modelID.rawValue]
            )
        }
    }

    func listProviderResearchRuns(providerID: ProviderID?, status: String?) async throws -> [ProviderResearchRunRecord] {
        try await database.read { db in
            switch (providerID, status) {
            case let (providerID?, status?):
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_research_runs WHERE provider_id = ? AND status = ? ORDER BY updated_at DESC",
                    arguments: [providerID.rawValue, status]
                ).map(Self.providerResearchRun(from:))
            case let (providerID?, nil):
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_research_runs WHERE provider_id = ? ORDER BY updated_at DESC",
                    arguments: [providerID.rawValue]
                ).map(Self.providerResearchRun(from:))
            case let (nil, status?):
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM provider_research_runs WHERE status = ? ORDER BY updated_at DESC",
                    arguments: [status]
                ).map(Self.providerResearchRun(from:))
            case (nil, nil):
                return try Row.fetchAll(db, sql: "SELECT * FROM provider_research_runs ORDER BY updated_at DESC").map(Self.providerResearchRun(from:))
            }
        }
    }

    func upsertProviderResearchRun(_ run: ProviderResearchRunRecord) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO provider_research_runs
                    (id, provider_id, provider_kind, model_id, title, prompt, depth, source_policy_json, report_format,
                     include_code_interpreter, service_tier, response_id, status, final_report_artifact_id,
                     citation_count, tool_call_count, provider_metadata_json, created_at, updated_at, completed_at, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    provider_id = excluded.provider_id,
                    provider_kind = excluded.provider_kind,
                    model_id = excluded.model_id,
                    title = excluded.title,
                    prompt = excluded.prompt,
                    depth = excluded.depth,
                    source_policy_json = excluded.source_policy_json,
                    report_format = excluded.report_format,
                    include_code_interpreter = excluded.include_code_interpreter,
                    service_tier = excluded.service_tier,
                    response_id = excluded.response_id,
                    status = excluded.status,
                    final_report_artifact_id = excluded.final_report_artifact_id,
                    citation_count = excluded.citation_count,
                    tool_call_count = excluded.tool_call_count,
                    provider_metadata_json = excluded.provider_metadata_json,
                    updated_at = excluded.updated_at,
                    completed_at = excluded.completed_at,
                    last_error = excluded.last_error
                """,
                arguments: [
                    run.id,
                    run.providerID.rawValue,
                    run.providerKind.rawValue,
                    run.modelID.rawValue,
                    run.title,
                    run.prompt,
                    run.depth,
                    Self.encodeJSON(run.sourcePolicy),
                    run.reportFormat,
                    run.includeCodeInterpreter ? 1 : 0,
                    run.serviceTier,
                    run.responseID,
                    run.status,
                    run.finalReportArtifactID,
                    run.citationCount,
                    run.toolCallCount,
                    Self.encodeProviderMetadata(run.providerMetadata),
                    run.createdAt.timeIntervalSinceReferenceDate,
                    run.updatedAt.timeIntervalSinceReferenceDate,
                    run.completedAt?.timeIntervalSinceReferenceDate,
                    run.lastError,
                ]
            )
        }
    }

    func deleteProviderResearchRun(id: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM provider_research_runs WHERE id = ?", arguments: [id])
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
            let redactor = Redactor()
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
                    redactor.redact(event.summary),
                    event.redactedPayload.map(redactor.redact),
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
            SELECT id, title, updated_at, default_model_id, default_provider_id, project_id, archived_at, pinned
            FROM conversations
            WHERE deleted_at IS NULL
            ORDER BY pinned DESC, updated_at DESC
            """
        ).map(conversation(from:))
    }

    private static func fetchProjects(_ db: Database) throws -> [ProjectRecord] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT id, name, vault_enabled, created_at, updated_at
            FROM projects
            WHERE deleted_at IS NULL
            ORDER BY updated_at DESC, name COLLATE NOCASE ASC
            """
        ).map(project(from:))
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
                c.project_id,
                c.archived_at,
                c.pinned,
                lm.content AS last_message,
                lm.status AS last_message_status,
                tm.content AS title_source_message,
                COALESCE(stats.token_count, 0) AS token_count
            FROM conversations c
            LEFT JOIN messages lm ON lm.id = (
                SELECT id
                FROM messages
                WHERE conversation_id = c.id AND deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT 1
            )
            LEFT JOIN messages tm ON tm.id = (
                SELECT id
                FROM messages
                WHERE conversation_id = c.id
                    AND deleted_at IS NULL
                    AND role IN ('user', 'assistant')
                    AND TRIM(content) != ''
                ORDER BY
                    CASE WHEN role = 'user' THEN 0 ELSE 1 END,
                    created_at ASC,
                    rowid ASC
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
            SELECT id, role, content, created_at, status, tool_call_id, tool_name, tool_calls_json, provider_metadata_json
            FROM messages
            WHERE conversation_id = ? AND deleted_at IS NULL
            ORDER BY created_at ASC, rowid ASC
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

    private static func fetchRecentMessages(
        _ db: Database,
        conversationID: UUID,
        limit: Int,
        requiredMessageIDs: Set<UUID>
    ) throws -> [ChatMessage] {
        let normalizedLimit = max(1, limit)
        let requiredIDs = requiredMessageIDs.map(\.uuidString).sorted()
        let requiredClause: String
        if requiredIDs.isEmpty {
            requiredClause = ""
        } else {
            let placeholders = Array(repeating: "?", count: requiredIDs.count).joined(separator: ",")
            requiredClause = " OR id IN (\(placeholders))"
        }

        var arguments: StatementArguments = [conversationID.uuidString, normalizedLimit]
        if !requiredIDs.isEmpty {
            _ = arguments.append(contentsOf: StatementArguments(requiredIDs))
        }

        var messages = try Row.fetchAll(
            db,
            sql: """
            WITH ranked_messages AS (
                SELECT
                    rowid AS message_rowid,
                    id,
                    role,
                    content,
                    created_at,
                    status,
                    tool_call_id,
                    tool_name,
                    tool_calls_json,
                    provider_metadata_json,
                    ROW_NUMBER() OVER (ORDER BY created_at DESC, rowid DESC) AS recent_rank
                FROM messages
                WHERE conversation_id = ? AND deleted_at IS NULL
            )
            SELECT id, role, content, created_at, status, tool_call_id, tool_name, tool_calls_json, provider_metadata_json
            FROM ranked_messages
            WHERE recent_rank <= ?\(requiredClause)
            ORDER BY created_at ASC, message_rowid ASC
            """,
            arguments: arguments
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
            SELECT d.id, d.title, d.source_type, d.local_path, d.sha256, d.project_id, d.updated_at, COUNT(c.id) AS chunk_count
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

private enum StoreSecurityError: Error, LocalizedError {
    case sqlCipherUnavailable
    case migrationVerificationFailed(table: String, expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .sqlCipherUnavailable:
            "SQLCipher is required for the encrypted local store but is not available."
        case let .migrationVerificationFailed(table, expected, actual):
            "Encrypted store migration failed verification for \(table): expected \(expected) rows, migrated \(actual)."
        }
    }
}
#endif
