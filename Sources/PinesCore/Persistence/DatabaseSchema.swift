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
    public static let currentVersion = 10

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
        DatabaseMigration(version: 2, name: "production-runtime-state", sql: [
            """
            CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
                INSERT INTO messages_fts(rowid, content, conversation_id, message_id)
                VALUES (new.rowid, new.content, new.conversation_id, new.id);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, content, conversation_id, message_id)
                VALUES ('delete', old.rowid, old.content, old.conversation_id, old.id);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE OF content ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, content, conversation_id, message_id)
                VALUES ('delete', old.rowid, old.content, old.conversation_id, old.id);
                INSERT INTO messages_fts(rowid, content, conversation_id, message_id)
                VALUES (new.rowid, new.content, new.conversation_id, new.id);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_chunks_ai AFTER INSERT ON vault_chunks BEGIN
                INSERT INTO vault_chunks_fts(rowid, text, document_id, chunk_id)
                VALUES (new.rowid, new.text, new.document_id, new.id);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_chunks_ad AFTER DELETE ON vault_chunks BEGIN
                INSERT INTO vault_chunks_fts(vault_chunks_fts, rowid, text, document_id, chunk_id)
                VALUES ('delete', old.rowid, old.text, old.document_id, old.id);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_chunks_au AFTER UPDATE OF text ON vault_chunks BEGIN
                INSERT INTO vault_chunks_fts(vault_chunks_fts, rowid, text, document_id, chunk_id)
                VALUES ('delete', old.rowid, old.text, old.document_id, old.id);
                INSERT INTO vault_chunks_fts(rowid, text, document_id, chunk_id)
                VALUES (new.rowid, new.text, new.document_id, new.id);
            END;
            """,
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY NOT NULL,
                value_json TEXT NOT NULL,
                updated_at REAL NOT NULL,
                sync_state TEXT NOT NULL DEFAULT 'local'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS cloud_providers (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                display_name TEXT NOT NULL,
                base_url TEXT NOT NULL,
                default_model_id TEXT,
                validation_status TEXT NOT NULL,
                last_validation_error TEXT,
                extra_headers_json TEXT,
                keychain_service TEXT NOT NULL,
                keychain_account TEXT NOT NULL,
                enabled_for_agents INTEGER NOT NULL DEFAULT 0,
                last_validated_at REAL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS model_downloads (
                id TEXT PRIMARY KEY NOT NULL,
                repository TEXT NOT NULL,
                revision TEXT,
                status TEXT NOT NULL,
                bytes_received INTEGER NOT NULL DEFAULT 0,
                total_bytes INTEGER,
                current_file TEXT,
                checksum TEXT,
                local_path TEXT,
                error_message TEXT,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS sync_records (
                id TEXT PRIMARY KEY NOT NULL,
                entity_table TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                cloud_record_name TEXT,
                change_tag TEXT,
                state TEXT NOT NULL,
                last_synced_at REAL,
                UNIQUE(entity_table, entity_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS chat_runs (
                id TEXT PRIMARY KEY NOT NULL,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                request_id TEXT NOT NULL,
                status TEXT NOT NULL,
                provider_id TEXT,
                model_id TEXT NOT NULL,
                started_at REAL,
                finished_at REAL,
                error_message TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS agent_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                policy_json TEXT NOT NULL,
                provider_id TEXT,
                status TEXT NOT NULL,
                step_index INTEGER NOT NULL DEFAULT 0,
                tool_call_count INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                error_message TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS tool_runs (
                id TEXT PRIMARY KEY NOT NULL,
                agent_session_id TEXT,
                invocation_json TEXT NOT NULL,
                result_json TEXT,
                approval_status TEXT NOT NULL,
                created_at REAL NOT NULL,
                resolved_at REAL,
                network_domains TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS vault_import_jobs (
                id TEXT PRIMARY KEY NOT NULL,
                document_id TEXT,
                source_path TEXT,
                file_name TEXT NOT NULL,
                status TEXT NOT NULL,
                progress REAL NOT NULL DEFAULT 0,
                error_message TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS browser_actions (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                url TEXT,
                selector TEXT,
                text TEXT,
                requires_approval INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_model_downloads_repository ON model_downloads(repository);",
            "CREATE INDEX IF NOT EXISTS idx_chat_runs_conversation ON chat_runs(conversation_id, started_at);",
            "CREATE INDEX IF NOT EXISTS idx_tool_runs_session ON tool_runs(agent_session_id, created_at);",
            "CREATE INDEX IF NOT EXISTS idx_sync_records_state ON sync_records(state);",
        ]),
        DatabaseMigration(version: 3, name: "vault-turboquant-embeddings", sql: [
            """
            CREATE TABLE IF NOT EXISTS vault_embeddings (
                chunk_id TEXT PRIMARY KEY NOT NULL REFERENCES vault_chunks(id) ON DELETE CASCADE,
                document_id TEXT NOT NULL REFERENCES vault_documents(id) ON DELETE CASCADE,
                embedding_model_id TEXT NOT NULL,
                dimensions INTEGER NOT NULL,
                fp16_embedding BLOB NOT NULL,
                turboquant_code BLOB NOT NULL,
                norm REAL NOT NULL,
                codec_version INTEGER NOT NULL,
                checksum TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_model ON vault_embeddings(embedding_model_id, dimensions);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_document ON vault_embeddings(document_id);",
        ]),
        DatabaseMigration(version: 4, name: "remote-mcp-tools", sql: [
            """
            CREATE TABLE IF NOT EXISTS mcp_servers (
                id TEXT PRIMARY KEY NOT NULL,
                display_name TEXT NOT NULL,
                endpoint_url TEXT NOT NULL,
                auth_mode TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                allow_insecure_local_http INTEGER NOT NULL DEFAULT 0,
                keychain_service TEXT NOT NULL,
                keychain_account TEXT NOT NULL,
                oauth_authorization_url TEXT,
                oauth_token_url TEXT,
                oauth_client_id TEXT,
                oauth_scopes TEXT,
                oauth_resource TEXT,
                status TEXT NOT NULL,
                last_error TEXT,
                last_connected_at REAL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS mcp_tools (
                server_id TEXT NOT NULL REFERENCES mcp_servers(id) ON DELETE CASCADE,
                original_name TEXT NOT NULL,
                namespaced_name TEXT NOT NULL PRIMARY KEY,
                display_name TEXT NOT NULL,
                description TEXT NOT NULL,
                input_schema_json TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                last_discovered_at REAL NOT NULL,
                last_error TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_mcp_tools_server ON mcp_tools(server_id);",
        ]),
        DatabaseMigration(version: 5, name: "mcp-resources-prompts-sampling", sql: [
            "ALTER TABLE mcp_servers ADD COLUMN resources_enabled INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE mcp_servers ADD COLUMN prompts_enabled INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE mcp_servers ADD COLUMN sampling_enabled INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE mcp_servers ADD COLUMN byok_sampling_enabled INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE mcp_servers ADD COLUMN subscriptions_enabled INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE mcp_servers ADD COLUMN max_sampling_requests_per_session INTEGER NOT NULL DEFAULT 3;",
            """
            CREATE TABLE IF NOT EXISTS mcp_resources (
                server_id TEXT NOT NULL REFERENCES mcp_servers(id) ON DELETE CASCADE,
                uri TEXT NOT NULL,
                name TEXT NOT NULL,
                title TEXT,
                description TEXT,
                mime_type TEXT,
                size INTEGER,
                icons_json TEXT,
                annotations_json TEXT,
                selected_for_context INTEGER NOT NULL DEFAULT 0,
                subscribed INTEGER NOT NULL DEFAULT 0,
                last_discovered_at REAL NOT NULL,
                PRIMARY KEY(server_id, uri)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS mcp_resource_templates (
                server_id TEXT NOT NULL REFERENCES mcp_servers(id) ON DELETE CASCADE,
                uri_template TEXT NOT NULL,
                name TEXT NOT NULL,
                title TEXT,
                description TEXT,
                mime_type TEXT,
                icons_json TEXT,
                annotations_json TEXT,
                last_discovered_at REAL NOT NULL,
                PRIMARY KEY(server_id, uri_template)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS mcp_prompts (
                server_id TEXT NOT NULL REFERENCES mcp_servers(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                title TEXT,
                description TEXT,
                arguments_json TEXT,
                icons_json TEXT,
                last_discovered_at REAL NOT NULL,
                PRIMARY KEY(server_id, name)
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_mcp_resources_server ON mcp_resources(server_id);",
            "CREATE INDEX IF NOT EXISTS idx_mcp_prompts_server ON mcp_prompts(server_id);",
        ]),
        DatabaseMigration(version: 6, name: "retrieval-and-sync-indexes", sql: [
            "CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_conversations_list ON conversations(deleted_at, pinned DESC, updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_vault_documents_sync_updated ON vault_documents(sync_state, updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_scan ON vault_embeddings(dimensions, embedding_model_id, chunk_id);",
            "CREATE INDEX IF NOT EXISTS idx_vault_chunks_document_ordinal ON vault_chunks(document_id, ordinal);",
        ]),
        DatabaseMigration(version: 7, name: "conversation-provider-selection", sql: [
            "ALTER TABLE conversations ADD COLUMN default_provider_id TEXT;",
        ]),
        DatabaseMigration(version: 8, name: "cloudkit-message-and-embedding-merge-keys", sql: [
            "ALTER TABLE messages ADD COLUMN updated_at REAL;",
            "ALTER TABLE messages ADD COLUMN deleted_at REAL;",
            "ALTER TABLE messages ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'local';",
            "UPDATE messages SET updated_at = created_at WHERE updated_at IS NULL;",
            "CREATE INDEX IF NOT EXISTS idx_messages_sync_updated ON messages(sync_state, updated_at DESC);",
            """
            CREATE TABLE IF NOT EXISTS vault_embeddings_v2 (
                chunk_id TEXT NOT NULL REFERENCES vault_chunks(id) ON DELETE CASCADE,
                document_id TEXT NOT NULL REFERENCES vault_documents(id) ON DELETE CASCADE,
                embedding_model_id TEXT NOT NULL,
                dimensions INTEGER NOT NULL,
                fp16_embedding BLOB NOT NULL,
                turboquant_code BLOB NOT NULL,
                norm REAL NOT NULL,
                codec_version INTEGER NOT NULL,
                checksum TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY(chunk_id, embedding_model_id)
            );
            """,
            """
            INSERT OR REPLACE INTO vault_embeddings_v2
                (chunk_id, document_id, embedding_model_id, dimensions, fp16_embedding,
                 turboquant_code, norm, codec_version, checksum, created_at)
            SELECT chunk_id, document_id, embedding_model_id, dimensions, fp16_embedding,
                   turboquant_code, norm, codec_version, checksum, created_at
            FROM vault_embeddings;
            """,
            "DROP TABLE vault_embeddings;",
            "ALTER TABLE vault_embeddings_v2 RENAME TO vault_embeddings;",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_model ON vault_embeddings(embedding_model_id, dimensions);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_document ON vault_embeddings(document_id);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_scan ON vault_embeddings(dimensions, embedding_model_id, chunk_id);",
        ]),
        DatabaseMigration(version: 9, name: "message-provider-metadata", sql: [
            "ALTER TABLE messages ADD COLUMN provider_metadata_json TEXT;",
        ]),
        DatabaseMigration(version: 10, name: "vault-embedding-profiles", sql: [
            """
            CREATE TABLE IF NOT EXISTS vault_embedding_profiles (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                provider_id TEXT,
                display_name TEXT NOT NULL,
                model_id TEXT NOT NULL,
                dimensions INTEGER NOT NULL,
                document_task TEXT,
                query_task TEXT,
                normalized INTEGER NOT NULL DEFAULT 1,
                cloud_consent_granted INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                last_error TEXT,
                embedded_chunk_count INTEGER NOT NULL DEFAULT 0,
                total_chunk_count INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS vault_embedding_jobs (
                id TEXT PRIMARY KEY NOT NULL,
                profile_id TEXT NOT NULL REFERENCES vault_embedding_profiles(id) ON DELETE CASCADE,
                document_id TEXT REFERENCES vault_documents(id) ON DELETE CASCADE,
                status TEXT NOT NULL,
                processed_chunks INTEGER NOT NULL DEFAULT 0,
                total_chunks INTEGER NOT NULL DEFAULT 0,
                attempt_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS vault_retrieval_events (
                id TEXT PRIMARY KEY NOT NULL,
                profile_id TEXT,
                provider_id TEXT,
                query_hash TEXT NOT NULL,
                used_vector_search INTEGER NOT NULL DEFAULT 0,
                result_count INTEGER NOT NULL DEFAULT 0,
                elapsed_seconds REAL NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """,
            """
            INSERT OR IGNORE INTO vault_embedding_profiles
                (id, kind, provider_id, display_name, model_id, dimensions, normalized,
                 cloud_consent_granted, is_active, status, embedded_chunk_count,
                 total_chunk_count, created_at, updated_at)
            SELECT
                'localMLX::mlx-local::' || embedding_model_id || '::' || dimensions,
                'localMLX',
                'mlx-local',
                'Local ' || embedding_model_id,
                embedding_model_id,
                dimensions,
                1,
                1,
                0,
                'ready',
                COUNT(*),
                COUNT(*),
                MIN(created_at),
                MAX(created_at)
            FROM vault_embeddings
            GROUP BY embedding_model_id, dimensions;
            """,
            """
            CREATE TABLE IF NOT EXISTS vault_embeddings_v3 (
                chunk_id TEXT NOT NULL REFERENCES vault_chunks(id) ON DELETE CASCADE,
                document_id TEXT NOT NULL REFERENCES vault_documents(id) ON DELETE CASCADE,
                embedding_model_id TEXT NOT NULL,
                profile_id TEXT NOT NULL DEFAULT 'legacy-local',
                provider_id TEXT,
                provider_kind TEXT NOT NULL DEFAULT 'localMLX',
                dimensions INTEGER NOT NULL,
                normalized INTEGER NOT NULL DEFAULT 1,
                source_checksum TEXT,
                fp16_embedding BLOB NOT NULL,
                turboquant_code BLOB NOT NULL,
                norm REAL NOT NULL,
                codec_version INTEGER NOT NULL,
                checksum TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY(chunk_id, profile_id)
            );
            """,
            """
            INSERT OR REPLACE INTO vault_embeddings_v3
                (chunk_id, document_id, embedding_model_id, profile_id, provider_id, provider_kind,
                 dimensions, normalized, source_checksum, fp16_embedding, turboquant_code, norm,
                 codec_version, checksum, created_at)
            SELECT
                chunk_id,
                document_id,
                embedding_model_id,
                'localMLX::mlx-local::' || embedding_model_id || '::' || dimensions,
                'mlx-local',
                'localMLX',
                dimensions,
                1,
                checksum,
                fp16_embedding,
                turboquant_code,
                norm,
                codec_version,
                checksum,
                created_at
            FROM vault_embeddings;
            """,
            "DROP TABLE vault_embeddings;",
            "ALTER TABLE vault_embeddings_v3 RENAME TO vault_embeddings;",
            "CREATE INDEX IF NOT EXISTS idx_vault_embedding_profiles_active ON vault_embedding_profiles(is_active, updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embedding_jobs_status ON vault_embedding_jobs(status, updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_vault_retrieval_events_created ON vault_retrieval_events(created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_model ON vault_embeddings(embedding_model_id, dimensions);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_profile ON vault_embeddings(profile_id, dimensions);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_document ON vault_embeddings(document_id);",
            "CREATE INDEX IF NOT EXISTS idx_vault_embeddings_scan ON vault_embeddings(dimensions, profile_id, chunk_id);",
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
