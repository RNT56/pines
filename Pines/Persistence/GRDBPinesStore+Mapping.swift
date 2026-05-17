import Foundation
import PinesCore

#if canImport(GRDB)
import GRDB
import OSLog

extension GRDBPinesStore {
    // MARK: - Mapping

    static func seedCuratedModels(in database: DatabasePool) throws {
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

    static func conversation(from row: Row) -> ConversationRecord {
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

    static func conversationPreview(from row: Row) -> ConversationPreviewRecord {
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

    static func message(from row: Row) -> ChatMessage {
        ChatMessage(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            role: ChatRole(rawValue: row["role"]) ?? .assistant,
            content: row["content"],
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
            toolCallID: row["tool_call_id"] as String?,
            toolName: row["tool_name"] as String?,
            toolCalls: decodeToolCalls(row["tool_calls_json"] as String?),
            providerMetadata: decodeProviderMetadata(row["provider_metadata_json"] as String?)
        )
    }

    static func attachment(from row: Row) -> ChatAttachment {
        let localPath = row["local_path"] as String
        return ChatAttachment(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            kind: AttachmentKind(rawValue: row["kind"]) ?? .document,
            fileName: row["file_name"],
            contentType: row["content_type"],
            localURL: localPath.isEmpty ? nil : URL(fileURLWithPath: localPath),
            byteCount: row["byte_count"]
        )
    }

    static func modelInstall(from row: Row) -> ModelInstall {
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

    static func vaultDocument(from row: Row) -> VaultDocumentRecord {
        VaultDocumentRecord(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            title: row["title"],
            sourceType: row["source_type"],
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]),
            chunkCount: row["chunk_count"]
        )
    }

    static func vaultChunk(from row: Row) -> VaultChunk {
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
            profileID: row["profile_id"] as String?,
            providerID: (row["provider_id"] as String?).map(ProviderID.init(rawValue:)),
            providerKind: (row["provider_kind"] as String?).flatMap(VaultEmbeddingProfileKind.init(rawValue:)),
            normalized: ((row["normalized"] as Int?) ?? 1) == 1,
            sourceChecksum: row["source_checksum"] as String?,
            dimensions: row["dimensions"],
            fp16Embedding: row["fp16_embedding"],
            turboQuantCode: row["turboquant_code"],
            norm: row["norm"],
            codecVersion: row["codec_version"],
            checksum: row["checksum"],
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"])
        )
    }

    static func vaultEmbeddingProfile(from row: Row) -> VaultEmbeddingProfile {
        VaultEmbeddingProfile(
            id: row["id"],
            kind: VaultEmbeddingProfileKind(rawValue: row["kind"]) ?? .custom,
            providerID: (row["provider_id"] as String?).map(ProviderID.init(rawValue:)),
            displayName: row["display_name"],
            modelID: ModelID(rawValue: row["model_id"]),
            dimensions: row["dimensions"],
            documentTask: row["document_task"] as String?,
            queryTask: row["query_task"] as String?,
            normalized: (row["normalized"] as Int) == 1,
            cloudConsentGranted: (row["cloud_consent_granted"] as Int) == 1,
            isActive: (row["is_active"] as Int) == 1,
            status: VaultEmbeddingProfileStatus(rawValue: row["status"]) ?? .available,
            lastError: row["last_error"] as String?,
            embeddedChunkCount: row["embedded_chunk_count"],
            totalChunkCount: row["total_chunk_count"],
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"])
        )
    }

    static func vaultEmbeddingJob(from row: Row) -> VaultEmbeddingJob {
        VaultEmbeddingJob(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            profileID: row["profile_id"],
            documentID: (row["document_id"] as String?).flatMap(UUID.init(uuidString:)),
            status: VaultEmbeddingJobStatus(rawValue: row["status"]) ?? .queued,
            processedChunks: row["processed_chunks"],
            totalChunks: row["total_chunks"],
            attemptCount: row["attempt_count"],
            lastError: row["last_error"] as String?,
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]),
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"])
        )
    }

    static func vaultRetrievalEvent(from row: Row) -> VaultRetrievalEvent {
        VaultRetrievalEvent(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            profileID: row["profile_id"] as String?,
            providerID: (row["provider_id"] as String?).map(ProviderID.init(rawValue:)),
            queryHash: row["query_hash"],
            usedVectorSearch: (row["used_vector_search"] as Int) == 1,
            resultCount: row["result_count"],
            elapsedSeconds: row["elapsed_seconds"],
            createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"])
        )
    }

    static func upsertEmbeddingProfile(_ profile: VaultEmbeddingProfile, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO vault_embedding_profiles
                (id, kind, provider_id, display_name, model_id, dimensions, document_task,
                 query_task, normalized, cloud_consent_granted, is_active, status, last_error,
                 embedded_chunk_count, total_chunk_count, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                provider_id = excluded.provider_id,
                display_name = excluded.display_name,
                model_id = excluded.model_id,
                dimensions = CASE
                    WHEN vault_embedding_profiles.dimensions > 0 THEN vault_embedding_profiles.dimensions
                    ELSE excluded.dimensions
                END,
                document_task = excluded.document_task,
                query_task = excluded.query_task,
                normalized = excluded.normalized,
                cloud_consent_granted = MAX(vault_embedding_profiles.cloud_consent_granted, excluded.cloud_consent_granted),
                is_active = CASE
                    WHEN vault_embedding_profiles.is_active = 1 THEN 1
                    ELSE excluded.is_active
                END,
                status = CASE
                    WHEN vault_embedding_profiles.status = 'ready' THEN 'ready'
                    ELSE excluded.status
                END,
                last_error = excluded.last_error,
                embedded_chunk_count = MAX(vault_embedding_profiles.embedded_chunk_count, excluded.embedded_chunk_count),
                total_chunk_count = MAX(vault_embedding_profiles.total_chunk_count, excluded.total_chunk_count),
                updated_at = excluded.updated_at
            """,
            arguments: [
                profile.id,
                profile.kind.rawValue,
                profile.providerID?.rawValue,
                profile.displayName,
                profile.modelID.rawValue,
                profile.dimensions,
                profile.documentTask,
                profile.queryTask,
                profile.normalized ? 1 : 0,
                profile.cloudConsentGranted ? 1 : 0,
                profile.isActive ? 1 : 0,
                profile.status.rawValue,
                profile.lastError,
                profile.embeddedChunkCount,
                profile.totalChunkCount,
                profile.createdAt.timeIntervalSinceReferenceDate,
                profile.updatedAt.timeIntervalSinceReferenceDate,
            ]
        )
    }

    static func vaultSearchResult(from row: Row, score: Double) -> VaultSearchResult {
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

    static func vaultTurboQuantCodec(modelID: ModelID, dimensions: Int) -> TurboQuantVectorCodec {
        TurboQuantVectorCodec(
            preset: .turbo3_5,
            seed: TurboQuantVectorCodec.stableSeed(for: "\(modelID.rawValue)|\(dimensions)|vault-v1")
        )
    }

    static func encodeFP16(_ vector: [Float]) -> Data {
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

    static func decodeFP16(_ data: Data, dimensions: Int) throws -> [Float] {
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

    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
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

    static func vectorMagnitude(_ vector: [Float]) -> Float {
        vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
    }

    static func provider(from row: Row) -> CloudProviderConfiguration {
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

    static func mcpServer(from row: Row) -> MCPServerConfiguration {
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

    static func mcpTool(from row: Row) -> MCPToolRecord {
        let schemaJSON = row["input_schema_json"] as String
        let serverID = row["server_id"] as String
        let namespacedName = row["namespaced_name"] as String
        let schema: JSONValue
        do {
            schema = try JSONDecoder().decode(JSONValue.self, from: Data(schemaJSON.utf8))
        } catch {
            persistenceLogger.warning("mcp_tool_schema_decode_failed server=\(serverID, privacy: .public) tool=\(namespacedName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            schema = JSONValue.objectSchema()
        }
        return MCPToolRecord(
            serverID: MCPServerID(rawValue: serverID),
            originalName: row["original_name"],
            namespacedName: namespacedName,
            displayName: row["display_name"],
            description: row["description"],
            inputSchema: schema,
            enabled: (row["enabled"] as Int) == 1,
            lastDiscoveredAt: Date(timeIntervalSinceReferenceDate: row["last_discovered_at"]),
            lastError: row["last_error"] as String?
        )
    }

    static func insertMCPTool(_ tool: MCPToolRecord, db: Database) throws {
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

    static func mcpResource(from row: Row) -> MCPResourceRecord {
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

    static func mcpResourceTemplate(from row: Row) -> MCPResourceTemplateRecord {
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

    static func mcpPrompt(from row: Row) -> MCPPromptRecord {
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

    static func insertMCPResource(_ resource: MCPResourceRecord, db: Database) throws {
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

    static func insertMCPResourceTemplate(_ template: MCPResourceTemplateRecord, db: Database) throws {
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

    static func insertMCPPrompt(_ prompt: MCPPromptRecord, db: Database) throws {
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

    static func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        return encodeJSON(value)
    }

    static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        do {
            let data = try JSONEncoder().encode(value)
            return String(decoding: data, as: UTF8.self)
        } catch {
            persistenceLogger.error("json_encode_failed type=\(String(describing: T.self), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func decodeJSON<T: Decodable>(_ string: String?) -> T? {
        guard let string, !string.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: Data(string.utf8))
        } catch {
            persistenceLogger.warning("json_decode_failed type=\(String(describing: T.self), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func encodeProviderMetadata(_ metadata: [String: String]) -> String? {
        metadata.isEmpty ? nil : encodeJSON(metadata)
    }

    static func decodeProviderMetadata(_ rawValue: String?) -> [String: String] {
        decodeJSON(rawValue) ?? [:]
    }

    static func encodeToolCalls(_ toolCalls: [ToolCallDelta]) -> String? {
        toolCalls.isEmpty ? nil : encodeJSON(toolCalls)
    }

    static func decodeToolCalls(_ rawValue: String?) -> [ToolCallDelta] {
        decodeJSON(rawValue) ?? []
    }

    static func download(from row: Row) -> ModelDownloadProgress {
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

    static func audit(from row: Row) -> AuditEvent {
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

    static func encodeModalities(_ modalities: Set<ModelModality>) -> String {
        modalities.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func decodeModalities(_ rawValue: String) -> Set<ModelModality> {
        Set(rawValue.split(separator: ",").compactMap { ModelModality(rawValue: String($0)) })
    }

}
#endif
