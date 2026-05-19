import Foundation

public enum OpenAIProviderRecordMapper {
    public static func providerFile(from object: JSONValue, providerID: ProviderID) -> ProviderFileRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id")
        else { return nil }
        return ProviderFileRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            purpose: fields.string(for: "purpose") ?? "unknown",
            fileName: fields.string(for: "filename") ?? fields.string(for: "file_name") ?? id,
            contentType: fields.string(for: "content_type"),
            byteCount: Int64(fields.int(for: "bytes") ?? fields.int(for: "byte_count") ?? 0),
            status: normalizedStatus(fields.string(for: "status")),
            sha256: fields.string(for: "sha256"),
            providerObject: fields.string(for: "object"),
            providerMetadata: metadata(from: fields["metadata"]),
            createdAt: date(from: fields["created_at"]) ?? Date(),
            expiresAt: date(from: fields["expires_at"]),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"])
        )
    }

    public static func providerCache(fromVectorStore object: JSONValue, providerID: ProviderID) -> ProviderCacheRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id")
        else { return nil }
        var configuration = [String: JSONValue]()
        if let expiresAfter = fields["expires_after"] {
            configuration["expires_after"] = expiresAfter
        }
        if let chunkingStrategy = fields["chunking_strategy"] {
            configuration["chunking_strategy"] = chunkingStrategy
        }
        return ProviderCacheRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            kind: "vector_store",
            name: fields.string(for: "name"),
            status: normalizedStatus(fields.string(for: "status")),
            usageBytes: Int64(fields.int(for: "usage_bytes") ?? 0),
            itemCounts: fields["file_counts"],
            configuration: configuration.isEmpty ? nil : .object(configuration),
            metadata: metadata(from: fields["metadata"]),
            createdAt: date(from: fields["created_at"]) ?? Date(),
            expiresAt: date(from: fields["expires_at"]),
            lastActiveAt: date(from: fields["last_active_at"]),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"])
        )
    }

    public static func providerBatch(from object: JSONValue, providerID: ProviderID) -> ProviderBatchRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id")
        else { return nil }
        return ProviderBatchRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            endpoint: fields.string(for: "endpoint") ?? "",
            status: normalizedStatus(fields.string(for: "status")),
            inputFileID: fields.string(for: "input_file_id"),
            outputFileID: fields.string(for: "output_file_id"),
            errorFileID: fields.string(for: "error_file_id"),
            completionWindow: fields.string(for: "completion_window"),
            requestCounts: fields["request_counts"],
            metadata: metadata(from: fields["metadata"]),
            createdAt: date(from: fields["created_at"]) ?? Date(),
            completedAt: date(from: fields["completed_at"]),
            expiresAt: date(from: fields["expires_at"]),
            lastError: errorMessage(from: fields["last_error"] ?? fields["errors"] ?? fields["error"])
        )
    }

    public static func providerLiveSession(from object: JSONValue, providerID: ProviderID, fallbackModelID: ModelID? = nil) -> ProviderLiveSessionRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id") ?? fields.string(for: "client_secret.value")
        else { return nil }
        return ProviderLiveSessionRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            modelID: fields.string(for: "model").map(ModelID.init(rawValue:)) ?? fallbackModelID ?? "gpt-realtime",
            status: normalizedStatus(fields.string(for: "status") ?? "created"),
            modalities: fields.arrayStrings(for: "modalities"),
            clientSecretKeychainAccount: nil,
            expiresAt: date(from: fields["expires_at"]),
            providerMetadata: metadata(from: fields["metadata"]),
            createdAt: date(from: fields["created_at"]) ?? Date(),
            closedAt: date(from: fields["closed_at"]),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"])
        )
    }

    public static func providerResearchRun(
        from request: OpenAIDeepResearchRequest,
        response: JSONValue?,
        createdAt: Date = Date()
    ) -> ProviderResearchRunRecord {
        let fields = response?.objectValue ?? [:]
        let responseID = fields.string(for: "id")
        let status = normalizedStatus(fields.string(for: "status") ?? OpenAIBackgroundResponseStatus.queued.rawValue)
        let metadata = metadata(from: fields["metadata"]).merging(request.metadata) { provider, _ in provider }
        let output = fields["output"]
        return ProviderResearchRunRecord(
            id: request.id.uuidString,
            providerID: request.providerID,
            providerKind: .openAI,
            modelID: request.modelID,
            title: request.title,
            prompt: request.prompt,
            depth: request.depth.rawValue,
            sourcePolicy: sourcePolicyValue(from: request.sourcePolicy),
            reportFormat: request.reportFormat.rawValue,
            includeCodeInterpreter: request.includeCodeInterpreter,
            serviceTier: request.serviceTier.rawValue,
            responseID: responseID,
            status: status,
            finalReportArtifactID: nil,
            citationCount: citationCount(in: output),
            toolCallCount: toolCallCount(in: output),
            providerMetadata: metadata,
            createdAt: date(from: fields["created_at"]) ?? createdAt,
            updatedAt: Date(),
            completedAt: completedAt(status: status, fields: fields),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"])
        )
    }

    public static func providerResearchRun(
        updating run: ProviderResearchRunRecord,
        response: JSONValue?
    ) -> ProviderResearchRunRecord {
        let fields = response?.objectValue ?? [:]
        let output = fields["output"]
        var updated = run
        updated.responseID = fields.string(for: "id") ?? run.responseID
        updated.status = normalizedStatus(fields.string(for: "status") ?? run.status)
        updated.citationCount = max(run.citationCount, citationCount(in: output))
        updated.toolCallCount = max(run.toolCallCount, toolCallCount(in: output))
        updated.providerMetadata = run.providerMetadata.merging(metadata(from: fields["metadata"])) { _, provider in provider }
        updated.updatedAt = Date()
        updated.completedAt = completedAt(status: updated.status, fields: fields) ?? run.completedAt
        updated.lastError = errorMessage(from: fields["last_error"] ?? fields["error"]) ?? run.lastError
        return updated
    }

    private static func sourcePolicyValue(from policy: OpenAIDeepResearchSourcePolicy) -> JSONValue {
        var fields: [String: JSONValue] = [
            "scope": .string(policy.scope.rawValue),
            "require_mcp_approval": .string(policy.requireMCPApproval),
        ]
        if !policy.vectorStoreIDs.isEmpty {
            fields["vector_store_ids"] = .array(policy.vectorStoreIDs.map { .string($0.rawValue) })
        }
        if !policy.providerFileIDs.isEmpty {
            fields["provider_file_ids"] = .array(policy.providerFileIDs.map { .string($0.rawValue) })
        }
        if !policy.vaultDocumentIDs.isEmpty {
            fields["vault_document_ids"] = .array(policy.vaultDocumentIDs.map { .string($0.uuidString) })
        }
        if !policy.allowedDomains.isEmpty {
            fields["allowed_domains"] = .array(policy.allowedDomains.map(JSONValue.string))
        }
        if !policy.blockedDomains.isEmpty {
            fields["blocked_domains"] = .array(policy.blockedDomains.map(JSONValue.string))
        }
        if let label = policy.mcpServerLabel {
            fields["mcp_server_label"] = .string(label)
        }
        if let url = policy.mcpServerURL {
            fields["mcp_server_url"] = .string(url.absoluteString)
        }
        return .object(fields)
    }

    private static func completedAt(status: String, fields: [String: JSONValue]) -> Date? {
        date(from: fields["completed_at"]) ?? (status == OpenAIBackgroundResponseStatus.completed.rawValue ? Date() : nil)
    }

    private static func normalizedStatus(_ value: String?) -> String {
        switch value {
        case "in_progress":
            OpenAIBackgroundResponseStatus.inProgress.rawValue
        case "requires_action":
            OpenAIBackgroundResponseStatus.requiresAction.rawValue
        case let value? where !value.isEmpty:
            value
        default:
            "unknown"
        }
    }

    private static func metadata(from value: JSONValue?) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        return object.reduce(into: [String: String]()) { result, item in
            if let string = item.value.stringValue {
                result[item.key] = string
            } else if let int = item.value.intValue {
                result[item.key] = String(int)
            } else if let bool = item.value.boolValue {
                result[item.key] = String(bool)
            }
        }
    }

    private static func date(from value: JSONValue?) -> Date? {
        guard let value else { return nil }
        if let seconds = value.intValue, seconds > 0 {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        if let string = value.stringValue {
            if let seconds = Double(string), seconds > 0 {
                return Date(timeIntervalSince1970: seconds)
            }
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private static func errorMessage(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = value.stringValue, !string.isEmpty {
            return string
        }
        guard let object = value.objectValue else { return nil }
        return object.string(for: "message")
            ?? object.string(for: "error")
            ?? object.string(for: "code")
    }

    private static func citationCount(in value: JSONValue?) -> Int {
        countObjects(in: value) { object in
            guard let type = object.string(for: "type") else { return false }
            return type == "url_citation" || type == "file_citation"
        }
    }

    private static func toolCallCount(in value: JSONValue?) -> Int {
        countObjects(in: value) { object in
            guard let type = object.string(for: "type") else { return false }
            return type.hasSuffix("_call") || type == "code_interpreter" || type == "file_search"
        }
    }

    private static func countObjects(in value: JSONValue?, matching predicate: ([String: JSONValue]) -> Bool) -> Int {
        switch value {
        case let .object(object):
            return (predicate(object) ? 1 : 0) + object.values.reduce(0) { $0 + countObjects(in: $1, matching: predicate) }
        case let .array(values):
            return values.reduce(0) { $0 + countObjects(in: $1, matching: predicate) }
        case .string, .number, .bool, .null, nil:
            return 0
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(for key: String) -> String? {
        if key.contains(".") {
            return nestedValue(for: key)?.stringValue
        }
        return self[key]?.stringValue
    }

    func int(for key: String) -> Int? {
        self[key]?.intValue
    }

    func arrayStrings(for key: String) -> [String] {
        guard case let .array(values) = self[key] else { return [] }
        return values.compactMap(\.stringValue)
    }

    private func nestedValue(for keyPath: String) -> JSONValue? {
        var current: JSONValue? = .object(self)
        for component in keyPath.split(separator: ".").map(String.init) {
            guard case let .object(object) = current else { return nil }
            current = object[component]
        }
        return current
    }
}
