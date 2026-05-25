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
    public static let currentVersion = 22

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
                DELETE FROM messages_fts WHERE rowid = old.rowid;
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE OF content ON messages BEGIN
                DELETE FROM messages_fts WHERE rowid = old.rowid;
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
                DELETE FROM vault_chunks_fts WHERE rowid = old.rowid;
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_chunks_au AFTER UPDATE OF text ON vault_chunks BEGIN
                DELETE FROM vault_chunks_fts WHERE rowid = old.rowid;
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
        DatabaseMigration(version: 11, name: "message-tool-call-payloads", sql: [
            "ALTER TABLE messages ADD COLUMN tool_name TEXT;",
            "ALTER TABLE messages ADD COLUMN tool_calls_json TEXT;",
        ]),
        DatabaseMigration(version: 12, name: "fts-delete-triggers", sql: [
            "DROP TRIGGER IF EXISTS messages_ad;",
            "DROP TRIGGER IF EXISTS messages_au;",
            "DROP TRIGGER IF EXISTS vault_chunks_ad;",
            "DROP TRIGGER IF EXISTS vault_chunks_au;",
            """
            CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                DELETE FROM messages_fts WHERE rowid = old.rowid;
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE OF content ON messages BEGIN
                DELETE FROM messages_fts WHERE rowid = old.rowid;
                INSERT INTO messages_fts(rowid, content, conversation_id, message_id)
                VALUES (new.rowid, new.content, new.conversation_id, new.id);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_chunks_ad AFTER DELETE ON vault_chunks BEGIN
                DELETE FROM vault_chunks_fts WHERE rowid = old.rowid;
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_chunks_au AFTER UPDATE OF text ON vault_chunks BEGIN
                DELETE FROM vault_chunks_fts WHERE rowid = old.rowid;
                INSERT INTO vault_chunks_fts(rowid, text, document_id, chunk_id)
                VALUES (new.rowid, new.text, new.document_id, new.id);
            END;
            """,
        ]),
        DatabaseMigration(version: 13, name: "high-assurance-security-reset", sql: [
            "ALTER TABLE cloud_providers ADD COLUMN headers_json TEXT;",
            "ALTER TABLE cloud_providers ADD COLUMN allow_insecure_local_http INTEGER NOT NULL DEFAULT 0;",
            "UPDATE cloud_providers SET headers_json = NULL, extra_headers_json = NULL, validation_status = 'unvalidated', last_validation_error = NULL;",
            "UPDATE mcp_servers SET status = 'disconnected', last_error = NULL;",
            """
            INSERT INTO audit_events (id, created_at, category, summary, redacted_payload, provider_id, model_id, tool_name, network_domains)
            VALUES (
                lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
                substr(lower(hex(randomblob(2))), 2) || '-' ||
                substr('89ab', abs(random()) % 4 + 1, 1) ||
                substr(lower(hex(randomblob(2))), 2) || '-' ||
                lower(hex(randomblob(6))),
                strftime('%s','now') - 978307200,
                'security',
                'Completed high-assurance security reset for sensitive provider and MCP configuration.',
                NULL,
                NULL,
                NULL,
                NULL,
                ''
            );
            """,
        ]),
        DatabaseMigration(version: 14, name: "openai-parity-contracts", sql: [
            "ALTER TABLE chat_runs ADD COLUMN provider_kind TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN provider_base_url TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN provider_request_id TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN provider_response_id TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN parent_response_id TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN background_response_id TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN batch_id TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN realtime_session_id TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN structured_output_result_id TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN used_responses_api INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE chat_runs ADD COLUMN response_storage TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN web_search_mode TEXT;",
            "ALTER TABLE chat_runs ADD COLUMN provider_metadata_json TEXT;",
            """
            CREATE TABLE IF NOT EXISTS openai_provider_files (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                purpose TEXT NOT NULL,
                file_name TEXT NOT NULL,
                content_type TEXT,
                byte_count INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                sha256 TEXT,
                local_path TEXT,
                provider_object TEXT,
                provider_metadata_json TEXT,
                created_at REAL NOT NULL,
                expires_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_vector_stores (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                name TEXT,
                status TEXT NOT NULL,
                file_counts_json TEXT NOT NULL,
                usage_bytes INTEGER NOT NULL DEFAULT 0,
                expiration_policy_json TEXT,
                metadata_json TEXT,
                created_at REAL NOT NULL,
                expires_at REAL,
                last_active_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_vector_store_files (
                id TEXT PRIMARY KEY NOT NULL,
                vector_store_id TEXT NOT NULL REFERENCES openai_vector_stores(id) ON DELETE CASCADE,
                provider_file_id TEXT NOT NULL REFERENCES openai_provider_files(id) ON DELETE CASCADE,
                status TEXT NOT NULL,
                usage_bytes INTEGER NOT NULL DEFAULT 0,
                chunking_strategy_json TEXT,
                attributes_json TEXT,
                created_at REAL NOT NULL,
                completed_at REAL,
                last_error TEXT,
                UNIQUE(vector_store_id, provider_file_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_hosted_tool_calls (
                id TEXT PRIMARY KEY NOT NULL,
                response_id TEXT,
                chat_run_id TEXT REFERENCES chat_runs(id) ON DELETE SET NULL,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                name TEXT,
                input_json TEXT,
                output_json TEXT,
                provider_metadata_json TEXT,
                created_at REAL NOT NULL,
                completed_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_artifacts (
                id TEXT PRIMARY KEY NOT NULL,
                response_id TEXT,
                hosted_tool_call_id TEXT REFERENCES openai_hosted_tool_calls(id) ON DELETE SET NULL,
                provider_file_id TEXT REFERENCES openai_provider_files(id) ON DELETE SET NULL,
                kind TEXT NOT NULL,
                file_name TEXT,
                content_type TEXT,
                byte_count INTEGER,
                text TEXT,
                content_json TEXT,
                local_path TEXT,
                remote_url TEXT,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_background_responses (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                model_id TEXT NOT NULL,
                status TEXT NOT NULL,
                conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
                chat_run_id TEXT REFERENCES chat_runs(id) ON DELETE SET NULL,
                previous_response_id TEXT,
                output_items_json TEXT,
                provider_metadata_json TEXT,
                created_at REAL NOT NULL,
                completed_at REAL,
                last_polled_at REAL,
                expires_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_realtime_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                model_id TEXT NOT NULL,
                status TEXT NOT NULL,
                modalities_json TEXT NOT NULL,
                voice TEXT,
                input_audio_format TEXT,
                output_audio_format TEXT,
                credential_keychain_account TEXT,
                expires_at REAL,
                provider_metadata_json TEXT,
                created_at REAL NOT NULL,
                closed_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_batch_jobs (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                status TEXT NOT NULL,
                input_file_id TEXT NOT NULL REFERENCES openai_provider_files(id) ON DELETE RESTRICT,
                output_file_id TEXT REFERENCES openai_provider_files(id) ON DELETE SET NULL,
                error_file_id TEXT REFERENCES openai_provider_files(id) ON DELETE SET NULL,
                completion_window TEXT NOT NULL,
                request_counts_json TEXT NOT NULL,
                metadata_json TEXT,
                created_at REAL NOT NULL,
                in_progress_at REAL,
                finalizing_at REAL,
                completed_at REAL,
                failed_at REAL,
                expired_at REAL,
                cancelled_at REAL,
                expires_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS openai_structured_output_results (
                id TEXT PRIMARY KEY NOT NULL,
                response_id TEXT,
                message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
                schema_name TEXT,
                schema_json TEXT,
                content_json TEXT,
                refusal TEXT,
                incomplete_reason TEXT,
                validation_errors_json TEXT,
                status TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_chat_runs_provider_response ON chat_runs(provider_response_id);",
            "CREATE INDEX IF NOT EXISTS idx_chat_runs_background_response ON chat_runs(background_response_id);",
            "CREATE INDEX IF NOT EXISTS idx_openai_provider_files_provider ON openai_provider_files(provider_id, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_openai_vector_stores_provider ON openai_vector_stores(provider_id, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_openai_vector_store_files_store ON openai_vector_store_files(vector_store_id, status);",
            "CREATE INDEX IF NOT EXISTS idx_openai_hosted_tool_calls_response ON openai_hosted_tool_calls(response_id, created_at);",
            "CREATE INDEX IF NOT EXISTS idx_openai_artifacts_response ON openai_artifacts(response_id, created_at);",
            "CREATE INDEX IF NOT EXISTS idx_openai_background_responses_status ON openai_background_responses(status, last_polled_at);",
            "CREATE INDEX IF NOT EXISTS idx_openai_realtime_sessions_provider ON openai_realtime_sessions(provider_id, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_openai_batch_jobs_provider ON openai_batch_jobs(provider_id, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_openai_structured_output_results_response ON openai_structured_output_results(response_id);",
        ]),
        DatabaseMigration(version: 15, name: "generic-provider-persistence", sql: [
            """
            CREATE TABLE IF NOT EXISTS provider_files (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                provider_kind TEXT NOT NULL,
                purpose TEXT NOT NULL,
                file_name TEXT NOT NULL,
                content_type TEXT,
                byte_count INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                sha256 TEXT,
                local_path TEXT,
                provider_object TEXT,
                provider_metadata_json TEXT,
                created_at REAL NOT NULL,
                expires_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_artifacts (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT,
                provider_kind TEXT NOT NULL,
                response_id TEXT,
                tool_call_id TEXT,
                provider_file_id TEXT,
                kind TEXT NOT NULL,
                file_name TEXT,
                content_type TEXT,
                byte_count INTEGER,
                text TEXT,
                content_json TEXT,
                local_path TEXT,
                remote_url TEXT,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_caches (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                provider_kind TEXT NOT NULL,
                kind TEXT NOT NULL,
                name TEXT,
                model_id TEXT,
                status TEXT NOT NULL,
                usage_bytes INTEGER NOT NULL DEFAULT 0,
                item_counts_json TEXT,
                configuration_json TEXT,
                metadata_json TEXT,
                created_at REAL NOT NULL,
                expires_at REAL,
                last_active_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_batches (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                provider_kind TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                status TEXT NOT NULL,
                input_file_id TEXT,
                output_file_id TEXT,
                error_file_id TEXT,
                completion_window TEXT,
                request_counts_json TEXT,
                metadata_json TEXT,
                created_at REAL NOT NULL,
                in_progress_at REAL,
                finalizing_at REAL,
                completed_at REAL,
                failed_at REAL,
                expired_at REAL,
                cancelled_at REAL,
                expires_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_live_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                provider_kind TEXT NOT NULL,
                model_id TEXT NOT NULL,
                status TEXT NOT NULL,
                modalities_json TEXT,
                voice TEXT,
                input_audio_format TEXT,
                output_audio_format TEXT,
                credential_keychain_account TEXT,
                expires_at REAL,
                provider_metadata_json TEXT,
                created_at REAL NOT NULL,
                closed_at REAL,
                last_error TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_structured_outputs (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT,
                provider_kind TEXT NOT NULL,
                response_id TEXT,
                message_id TEXT,
                schema_name TEXT,
                schema_json TEXT,
                content_json TEXT,
                refusal TEXT,
                incomplete_reason TEXT,
                validation_errors_json TEXT,
                status TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_model_capabilities (
                provider_id TEXT NOT NULL,
                provider_kind TEXT NOT NULL,
                model_id TEXT NOT NULL,
                capabilities_json TEXT NOT NULL,
                context_window_tokens INTEGER,
                input_modalities_json TEXT,
                output_modalities_json TEXT,
                metadata_json TEXT,
                fetched_at REAL NOT NULL,
                expires_at REAL,
                PRIMARY KEY(provider_id, model_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_research_runs (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                provider_kind TEXT NOT NULL,
                model_id TEXT NOT NULL,
                title TEXT NOT NULL,
                prompt TEXT NOT NULL,
                depth TEXT NOT NULL,
                source_policy_json TEXT NOT NULL,
                report_format TEXT NOT NULL,
                include_code_interpreter INTEGER NOT NULL DEFAULT 1,
                service_tier TEXT NOT NULL,
                response_id TEXT,
                status TEXT NOT NULL,
                final_report_artifact_id TEXT REFERENCES provider_artifacts(id) ON DELETE SET NULL,
                citation_count INTEGER NOT NULL DEFAULT 0,
                tool_call_count INTEGER NOT NULL DEFAULT 0,
                provider_metadata_json TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                completed_at REAL,
                last_error TEXT
            );
            """,
            """
            INSERT OR IGNORE INTO provider_files
                (id, provider_id, provider_kind, purpose, file_name, content_type, byte_count,
                 status, sha256, local_path, provider_object, provider_metadata_json, created_at,
                 expires_at, last_error)
            SELECT
                id, provider_id, 'openAI', purpose, file_name, content_type, byte_count,
                status, sha256, local_path, provider_object, provider_metadata_json, created_at,
                expires_at, last_error
            FROM openai_provider_files;
            """,
            """
            INSERT OR IGNORE INTO provider_artifacts
                (id, provider_id, provider_kind, response_id, tool_call_id, provider_file_id,
                 kind, file_name, content_type, byte_count, text, content_json, local_path,
                 remote_url, created_at)
            SELECT
                id, NULL, 'openAI', response_id, hosted_tool_call_id, provider_file_id,
                kind, file_name, content_type, byte_count, text, content_json, local_path,
                remote_url, created_at
            FROM openai_artifacts;
            """,
            """
            INSERT OR IGNORE INTO provider_caches
                (id, provider_id, provider_kind, kind, name, model_id, status, usage_bytes,
                 item_counts_json, configuration_json, metadata_json, created_at, expires_at,
                 last_active_at, last_error)
            SELECT
                id, provider_id, 'openAI', 'vector_store', name, NULL, status, usage_bytes,
                file_counts_json, expiration_policy_json, metadata_json, created_at, expires_at,
                last_active_at, last_error
            FROM openai_vector_stores;
            """,
            """
            INSERT OR IGNORE INTO provider_batches
                (id, provider_id, provider_kind, endpoint, status, input_file_id, output_file_id,
                 error_file_id, completion_window, request_counts_json, metadata_json, created_at,
                 in_progress_at, finalizing_at, completed_at, failed_at, expired_at, cancelled_at,
                 expires_at, last_error)
            SELECT
                id, provider_id, 'openAI', endpoint, status, input_file_id, output_file_id,
                error_file_id, completion_window, request_counts_json, metadata_json, created_at,
                in_progress_at, finalizing_at, completed_at, failed_at, expired_at, cancelled_at,
                expires_at, last_error
            FROM openai_batch_jobs;
            """,
            """
            INSERT OR IGNORE INTO provider_live_sessions
                (id, provider_id, provider_kind, model_id, status, modalities_json, voice,
                 input_audio_format, output_audio_format, credential_keychain_account,
                 expires_at, provider_metadata_json, created_at, closed_at, last_error)
            SELECT
                id, provider_id, 'openAI', model_id, status, modalities_json, voice,
                input_audio_format, output_audio_format, credential_keychain_account,
                expires_at, provider_metadata_json, created_at, closed_at, last_error
            FROM openai_realtime_sessions;
            """,
            """
            INSERT OR IGNORE INTO provider_structured_outputs
                (id, provider_id, provider_kind, response_id, message_id, schema_name,
                 schema_json, content_json, refusal, incomplete_reason, validation_errors_json,
                 status, created_at)
            SELECT
                id, NULL, 'openAI', response_id, message_id, schema_name,
                schema_json, content_json, refusal, incomplete_reason, validation_errors_json,
                status, created_at
            FROM openai_structured_output_results;
            """,
            "CREATE INDEX IF NOT EXISTS idx_provider_files_provider ON provider_files(provider_id, provider_kind, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_provider_artifacts_response ON provider_artifacts(provider_kind, response_id, created_at);",
            "CREATE INDEX IF NOT EXISTS idx_provider_caches_provider ON provider_caches(provider_id, provider_kind, kind, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_provider_batches_provider ON provider_batches(provider_id, provider_kind, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_provider_live_sessions_provider ON provider_live_sessions(provider_id, provider_kind, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_provider_structured_outputs_response ON provider_structured_outputs(provider_kind, response_id);",
            "CREATE INDEX IF NOT EXISTS idx_provider_model_capabilities_provider ON provider_model_capabilities(provider_id, provider_kind, fetched_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_provider_research_runs_provider ON provider_research_runs(provider_id, provider_kind, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_provider_research_runs_response ON provider_research_runs(provider_kind, response_id);",
            "CREATE INDEX IF NOT EXISTS idx_provider_research_runs_status ON provider_research_runs(status, updated_at);",
        ]),
        DatabaseMigration(version: 16, name: "project-spaces", sql: [
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                vault_enabled INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                deleted_at REAL
            );
            """,
            "ALTER TABLE conversations ADD COLUMN project_id TEXT REFERENCES projects(id) ON DELETE SET NULL;",
            "ALTER TABLE vault_documents ADD COLUMN project_id TEXT REFERENCES projects(id) ON DELETE SET NULL;",
            "CREATE INDEX IF NOT EXISTS idx_projects_updated ON projects(deleted_at, updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_conversations_project ON conversations(project_id, updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_vault_documents_project ON vault_documents(project_id, updated_at DESC);",
        ]),
        DatabaseMigration(version: 17, name: "model-install-runtime-metadata", sql: [
            "ALTER TABLE model_installs ADD COLUMN parameter_count INTEGER;",
            "ALTER TABLE model_installs ADD COLUMN key_head_dimension INTEGER;",
            "ALTER TABLE model_installs ADD COLUMN value_head_dimension INTEGER;",
        ]),
        DatabaseMigration(version: 18, name: "model-install-nested-runtime-metadata", sql: [
            "ALTER TABLE model_installs ADD COLUMN text_config_model_type TEXT;",
            "ALTER TABLE model_installs ADD COLUMN routed_experts INTEGER;",
            "ALTER TABLE model_installs ADD COLUMN experts_per_token INTEGER;",
        ]),
        DatabaseMigration(version: 19, name: "model-install-cache-topology-support", sql: [
            "ALTER TABLE model_installs ADD COLUMN cache_topology TEXT NOT NULL DEFAULT 'standardAttention';",
            "ALTER TABLE model_installs ADD COLUMN turbo_quant_family_support TEXT NOT NULL DEFAULT 'attentionKVFull';",
        ]),
        DatabaseMigration(version: 20, name: "turboquant-evidence-loop", sql: [
            """
            CREATE TABLE IF NOT EXISTS turboquant_profile_evidence (
                id TEXT PRIMARY KEY NOT NULL,
                schema_version INTEGER NOT NULL,
                evidence_level TEXT NOT NULL,
                compatibility_pair_id TEXT NOT NULL,
                model_id TEXT NOT NULL,
                model_revision TEXT,
                tokenizer_hash TEXT,
                profile_hash TEXT,
                fallback_contract_hash TEXT NOT NULL,
                device_class TEXT NOT NULL,
                hardware_model TEXT,
                os_build TEXT NOT NULL,
                user_mode TEXT NOT NULL,
                turboquant_preset TEXT,
                value_bits INTEGER,
                group_size INTEGER,
                layout_version INTEGER,
                active_attention_path TEXT,
                admitted_context_tokens INTEGER NOT NULL,
                peak_memory_bytes INTEGER NOT NULL,
                prompt_tokens_per_second REAL,
                decode_tokens_per_second_p50 REAL,
                decode_tokens_per_second_p95 REAL,
                first_token_latency_ms REAL,
                quality_gate_json TEXT NOT NULL,
                memory_calibration_sample_id TEXT,
                revoked_reason TEXT,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS turboquant_evidence_revocations (
                id TEXT PRIMARY KEY NOT NULL,
                schema_version INTEGER NOT NULL,
                evidence_id TEXT NOT NULL REFERENCES turboquant_profile_evidence(id) ON DELETE CASCADE,
                revoked_at REAL NOT NULL,
                reason TEXT NOT NULL,
                replacement_evidence_id TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS turboquant_memory_calibration_samples (
                id TEXT PRIMARY KEY NOT NULL,
                sample_json TEXT NOT NULL,
                compatibility_pair_id TEXT,
                model_id TEXT NOT NULL,
                model_revision TEXT,
                device_class TEXT NOT NULL,
                user_mode TEXT NOT NULL,
                attention_path TEXT,
                run_outcome TEXT NOT NULL,
                requested_context_tokens INTEGER NOT NULL,
                admitted_context_tokens INTEGER NOT NULL,
                observed_peak_memory_bytes INTEGER,
                memory_warnings_seen INTEGER NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS turboquant_memory_calibrations (
                id TEXT PRIMARY KEY NOT NULL,
                calibration_json TEXT NOT NULL,
                device_class TEXT NOT NULL,
                model_family TEXT NOT NULL,
                attention_path TEXT NOT NULL,
                sample_count INTEGER NOT NULL,
                estimated_to_actual_peak_ratio_p95 REAL NOT NULL,
                scratch_multiplier REAL NOT NULL,
                fallback_multiplier REAL NOT NULL,
                safety_reserve_bytes INTEGER NOT NULL,
                stale_after REAL,
                updated_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_turboquant_profile_evidence_lookup ON turboquant_profile_evidence(model_id, compatibility_pair_id, device_class, user_mode, fallback_contract_hash, evidence_level, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_turboquant_profile_evidence_tuple ON turboquant_profile_evidence(model_id, model_revision, tokenizer_hash, profile_hash, layout_version, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_turboquant_memory_samples_lookup ON turboquant_memory_calibration_samples(model_id, device_class, user_mode, attention_path, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_turboquant_memory_calibrations_lookup ON turboquant_memory_calibrations(device_class, model_family, attention_path, updated_at DESC);",
        ]),
        DatabaseMigration(version: 21, name: "turboquant-kv-snapshot-store", sql: [
            """
            CREATE TABLE IF NOT EXISTS kv_snapshot_manifest (
                snapshot_id TEXT PRIMARY KEY NOT NULL,
                schema_version INTEGER NOT NULL,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                model_id TEXT NOT NULL REFERENCES model_installs(repository) ON DELETE CASCADE,
                model_revision TEXT,
                tokenizer_hash TEXT NOT NULL,
                profile_hash TEXT NOT NULL,
                turboquant_layout_version INTEGER NOT NULL,
                rope_config_hash TEXT NOT NULL,
                token_prefix_hash TEXT NOT NULL,
                fallback_contract_hash TEXT,
                logical_length INTEGER NOT NULL,
                pinned_prefix_length INTEGER NOT NULL,
                compressed_key_bytes INTEGER NOT NULL,
                compressed_value_bytes INTEGER NOT NULL,
                blob_byte_count INTEGER NOT NULL,
                encryption_key_id TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                invalidated_reason TEXT,
                created_at REAL NOT NULL,
                last_validated_at REAL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS kv_snapshot_blob (
                snapshot_id TEXT PRIMARY KEY NOT NULL REFERENCES kv_snapshot_manifest(snapshot_id) ON DELETE CASCADE,
                storage_location TEXT NOT NULL,
                relative_path TEXT,
                encrypted_blob BLOB,
                encrypted_byte_count INTEGER NOT NULL,
                integrity_checksum TEXT NOT NULL,
                encryption_key_id TEXT NOT NULL,
                cloud_sync_allowed INTEGER NOT NULL DEFAULT 0,
                excluded_from_backup INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                committed_at REAL,
                last_verified_at REAL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS kv_snapshot_reference (
                id TEXT PRIMARY KEY NOT NULL,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                snapshot_id TEXT NOT NULL REFERENCES kv_snapshot_manifest(snapshot_id) ON DELETE CASCADE,
                pinned INTEGER NOT NULL DEFAULT 0,
                state TEXT NOT NULL DEFAULT 'active',
                created_at REAL NOT NULL,
                last_used_at REAL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS kv_snapshot_restore_attempt (
                id TEXT PRIMARY KEY NOT NULL,
                schema_version INTEGER NOT NULL,
                snapshot_id TEXT,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                attempted_at REAL NOT NULL,
                result TEXT NOT NULL,
                failure_reason TEXT,
                expected_identity_json TEXT
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS kv_snapshot_quarantine (
                id TEXT PRIMARY KEY NOT NULL,
                schema_version INTEGER NOT NULL,
                snapshot_id TEXT,
                conversation_id TEXT,
                stage TEXT NOT NULL,
                reason TEXT NOT NULL,
                blob_byte_count INTEGER NOT NULL,
                quarantined_at REAL NOT NULL,
                resolved_at REAL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_kv_snapshot_manifest_conversation ON kv_snapshot_manifest(conversation_id, status, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_kv_snapshot_manifest_model ON kv_snapshot_manifest(model_id, model_revision, status, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_kv_snapshot_manifest_identity ON kv_snapshot_manifest(model_id, model_revision, tokenizer_hash, profile_hash, turboquant_layout_version, rope_config_hash, token_prefix_hash, logical_length);",
            "CREATE INDEX IF NOT EXISTS idx_kv_snapshot_reference_conversation ON kv_snapshot_reference(conversation_id, state, last_used_at DESC, created_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_kv_snapshot_restore_attempt_conversation ON kv_snapshot_restore_attempt(conversation_id, attempted_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_kv_snapshot_quarantine_snapshot ON kv_snapshot_quarantine(snapshot_id, quarantined_at DESC);",
        ]),
        DatabaseMigration(version: 22, name: "turboquant-speculative-evidence", sql: [
            "ALTER TABLE turboquant_profile_evidence ADD COLUMN speculative_dimensions_json TEXT;",
            "ALTER TABLE turboquant_profile_evidence ADD COLUMN speculative_telemetry_json TEXT;",
            "ALTER TABLE turboquant_profile_evidence ADD COLUMN speculative_auto_disable_json TEXT;",
            "CREATE INDEX IF NOT EXISTS idx_turboquant_profile_evidence_speculative ON turboquant_profile_evidence(model_id, user_mode, layout_version, created_at DESC);",
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
        dataProtection: DataProtectionClass = .complete,
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
