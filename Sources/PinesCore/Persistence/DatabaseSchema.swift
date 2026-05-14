import Foundation

public struct DatabaseMigration: Hashable, Codable, Sendable {
    public var version: Int
    public var name: String
    public var sql: [String]

    public init(version: Int, name: String, sql: [String]) {
        self.version = version
        self.name = name
        self.sql = sql
    }
}

public enum PinesDatabaseSchema {
    public static let currentVersion = 1

    public static let migrations: [DatabaseMigration] = [
        DatabaseMigration(version: 1, name: "initial-local-first-schema", sql: [
            """
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                archived_at REAL,
                deleted_at REAL,
                pinned INTEGER NOT NULL DEFAULT 0,
                default_model_id TEXT,
                sync_state TEXT NOT NULL DEFAULT 'local'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY NOT NULL,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at REAL NOT NULL,
                status TEXT NOT NULL,
                model_id TEXT,
                provider_id TEXT,
                token_count INTEGER,
                tool_call_id TEXT
            );
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                content,
                conversation_id UNINDEXED,
                message_id UNINDEXED,
                tokenize = 'unicode61'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS attachments (
                id TEXT PRIMARY KEY NOT NULL,
                message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
                document_id TEXT,
                kind TEXT NOT NULL,
                file_name TEXT NOT NULL,
                content_type TEXT NOT NULL,
                local_path TEXT NOT NULL,
                byte_count INTEGER NOT NULL DEFAULT 0,
                sha256 TEXT,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS model_installs (
                id TEXT PRIMARY KEY NOT NULL,
                repository TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                revision TEXT,
                local_path TEXT,
                modalities TEXT NOT NULL,
                verification TEXT NOT NULL,
                state TEXT NOT NULL,
                model_type TEXT,
                processor_class TEXT,
                estimated_bytes INTEGER,
                license TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS vault_documents (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                source_type TEXT NOT NULL,
                local_path TEXT,
                web_url TEXT,
                sha256 TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                sync_state TEXT NOT NULL DEFAULT 'local'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS vault_chunks (
                id TEXT PRIMARY KEY NOT NULL,
                document_id TEXT NOT NULL REFERENCES vault_documents(id) ON DELETE CASCADE,
                ordinal INTEGER NOT NULL,
                text TEXT NOT NULL,
                token_estimate INTEGER NOT NULL,
                embedding_model_id TEXT,
                embedding BLOB,
                embedding_dimensions INTEGER,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS vault_chunks_fts USING fts5(
                text,
                document_id UNINDEXED,
                chunk_id UNINDEXED,
                tokenize = 'unicode61'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS audit_events (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                category TEXT NOT NULL,
                summary TEXT NOT NULL,
                redacted_payload TEXT,
                provider_id TEXT,
                model_id TEXT,
                tool_name TEXT,
                network_domains TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);",
            "CREATE INDEX IF NOT EXISTS idx_vault_chunks_document ON vault_chunks(document_id, ordinal);",
            "CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_events(created_at);",
        ]),
    ]
}

public enum DataProtectionClass: String, Codable, Sendable {
    case complete
    case completeUntilFirstUserAuthentication
}

public struct LocalStoreConfiguration: Hashable, Codable, Sendable {
    public var databaseFileName: String
    public var dataProtection: DataProtectionClass
    public var iCloudSyncEnabled: Bool
    public var syncsSourceDocuments: Bool
    public var syncsEmbeddings: Bool

    public init(
        databaseFileName: String = "pines.sqlite",
        dataProtection: DataProtectionClass = .completeUntilFirstUserAuthentication,
        iCloudSyncEnabled: Bool = false,
        syncsSourceDocuments: Bool = true,
        syncsEmbeddings: Bool = false
    ) {
        self.databaseFileName = databaseFileName
        self.dataProtection = dataProtection
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.syncsSourceDocuments = syncsSourceDocuments
        self.syncsEmbeddings = syncsEmbeddings
    }
}
