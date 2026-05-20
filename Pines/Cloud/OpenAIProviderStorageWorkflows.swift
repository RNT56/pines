import Foundation
import PinesCore

struct OpenAIProviderStorageRefreshResult: Sendable, Hashable {
    var files: [ProviderFileRecord]
    var vectorStores: [ProviderCacheRecord]
}

struct OpenAIVectorStoreMutation: Sendable, Hashable {
    var name: String?
    var description: String?
    var expiresAfter: JSONValue?
    var metadata: [String: String]
    var rawFields: [String: JSONValue]

    init(
        name: String? = nil,
        description: String? = nil,
        expiresAfter: JSONValue? = nil,
        metadata: [String: String] = [:],
        rawFields: [String: JSONValue] = [:]
    ) {
        self.name = name
        self.description = description
        self.expiresAfter = expiresAfter
        self.metadata = metadata
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        if let name {
            fields["name"] = .string(name)
        }
        if let description {
            fields["description"] = .string(description)
        }
        if let expiresAfter {
            fields["expires_after"] = expiresAfter
        }
        if !metadata.isEmpty {
            fields["metadata"] = .object(metadata.mapValues(JSONValue.string))
        }
        return .object(fields)
    }
}

struct OpenAIVectorStoreFileBatchPolling: Sendable {
    var intervalNanoseconds: UInt64
    var maxAttempts: Int
    var onUpdate: (@Sendable (ProviderBatchRecord) async -> Void)?

    init(
        intervalNanoseconds: UInt64 = 2_000_000_000,
        maxAttempts: Int = 30,
        onUpdate: (@Sendable (ProviderBatchRecord) async -> Void)? = nil
    ) {
        self.intervalNanoseconds = intervalNanoseconds
        self.maxAttempts = max(0, maxAttempts)
        self.onUpdate = onUpdate
    }
}

struct OpenAIFileSearchToolConfiguration: Sendable, Hashable {
    var vectorStoreIDs: [String]
    var maxResults: Int?
    var filters: JSONValue?
    var rankingOptions: JSONValue?

    init(
        vectorStoreIDs: [String],
        maxResults: Int? = nil,
        filters: JSONValue? = nil,
        rankingOptions: JSONValue? = nil
    ) {
        self.vectorStoreIDs = vectorStoreIDs
        self.maxResults = maxResults
        self.filters = filters
        self.rankingOptions = rankingOptions
    }

    var responsesTool: JSONValue {
        var fields: [String: JSONValue] = [
            "type": .string("file_search"),
            "vector_store_ids": .array(vectorStoreIDs.map(JSONValue.string)),
        ]
        if let maxResults {
            fields["max_num_results"] = .number(Double(maxResults))
        }
        if let filters {
            fields["filters"] = filters
        }
        if let rankingOptions {
            fields["ranking_options"] = rankingOptions
        }
        return .object(fields)
    }
}

extension OpenAIProviderLifecycleCoordinator {
    func refreshProviderStorage(purpose: String? = nil, limit: Int? = 100) async throws -> OpenAIProviderStorageRefreshResult {
        async let files = refreshFiles(purpose: purpose, limit: limit)
        async let vectorStores = refreshVectorStores(limit: limit)
        return try await OpenAIProviderStorageRefreshResult(files: files, vectorStores: vectorStores)
    }

    func updateVectorStore(id: String, mutation: OpenAIVectorStoreMutation) async throws -> ProviderCacheRecord {
        let response = try await service.updateVectorStore(id, body: mutation.body)
        guard let record = response.json.flatMap({ OpenAIProviderRecordMapper.providerCache(fromVectorStore: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.caches?.upsertProviderCache(record)
        try await storageAudit("Updated OpenAI vector store \(record.name ?? record.id)")
        return record
    }

    func listVectorStoreFiles(
        vectorStoreID: String,
        limit: Int? = 100,
        order: OpenAIListOrder? = nil,
        after: String? = nil,
        before: String? = nil
    ) async throws -> [ProviderFileRecord] {
        let response = try await service.listVectorStoreFiles(
            vectorStoreID,
            request: OpenAIListRequest(limit: limit, order: order, after: after, before: before)
        )
        let records = response.listData.compactMap { vectorStoreFileRecord(from: $0, vectorStoreID: vectorStoreID) }
        for record in records {
            try await repositories.files?.upsertProviderFile(record)
        }
        try await storageAudit("Refreshed \(records.count) OpenAI vector store files for \(vectorStoreID)")
        return records
    }

    func detachFile(_ fileID: String, fromVectorStore vectorStoreID: String) async throws -> ProviderCacheRecord {
        _ = try await service.deleteVectorStoreFile(vectorStoreID, fileID: fileID)
        let record = try await refreshVectorStore(id: vectorStoreID)
        try await storageAudit("Detached OpenAI file \(fileID) from vector store \(vectorStoreID)")
        return record
    }

    func attachFilesBatch(
        _ fileIDs: [String],
        toVectorStore vectorStoreID: String,
        attributes: JSONValue? = nil,
        polling: OpenAIVectorStoreFileBatchPolling? = nil
    ) async throws -> ProviderBatchRecord {
        guard !fileIDs.isEmpty else {
            throw InferenceError.invalidRequest("Select at least one OpenAI file to attach.")
        }

        let response = try await service.createVectorStoreFileBatch(vectorStoreID, fileIDs: fileIDs, attributes: attributes)
        var record = try vectorStoreFileBatchRecord(from: response.json, vectorStoreID: vectorStoreID)
        try await repositories.batches?.upsertProviderBatch(record)
        try await storageAudit("Started OpenAI vector store file batch \(record.id)")

        if let polling {
            await polling.onUpdate?(record)
            for _ in 0..<polling.maxAttempts where !record.isTerminalProviderStorageStatus {
                try await Task.sleep(nanoseconds: polling.intervalNanoseconds)
                record = try await refreshVectorStoreFileBatch(vectorStoreID: vectorStoreID, batchID: record.id)
                await polling.onUpdate?(record)
            }
        }

        _ = try? await refreshVectorStore(id: vectorStoreID)
        return record
    }

    func refreshVectorStoreFileBatch(vectorStoreID: String, batchID: String) async throws -> ProviderBatchRecord {
        let response = try await service.retrieveVectorStoreFileBatch(vectorStoreID, batchID: batchID)
        let record = try vectorStoreFileBatchRecord(from: response.json, vectorStoreID: vectorStoreID)
        try await repositories.batches?.upsertProviderBatch(record)
        return record
    }

    func cancelVectorStoreFileBatch(vectorStoreID: String, batchID: String) async throws -> ProviderBatchRecord {
        let response = try await service.cancelVectorStoreFileBatch(vectorStoreID, batchID: batchID)
        let record = try vectorStoreFileBatchRecord(from: response.json, vectorStoreID: vectorStoreID)
        try await repositories.batches?.upsertProviderBatch(record)
        try await storageAudit("Cancelled OpenAI vector store file batch \(batchID)")
        return record
    }
}

private extension OpenAIProviderLifecycleCoordinator {
    func storageAudit(_ summary: String) async throws {
        try await repositories.audit?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: summary,
                providerID: providerID,
                networkDomains: ["api.openai.com"]
            )
        )
    }

    func vectorStoreFileRecord(from value: JSONValue, vectorStoreID: String) -> ProviderFileRecord? {
        guard let fields = value.objectValue,
              let id = fields.string(for: "file_id") ?? fields.string(for: "id")
        else { return nil }
        var metadata = metadata(from: fields["attributes"] ?? fields["metadata"])
        metadata["vector_store_id"] = vectorStoreID
        return ProviderFileRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            purpose: "assistants",
            fileName: fields.string(for: "filename") ?? fields.string(for: "file_name") ?? id,
            contentType: fields.string(for: "content_type"),
            byteCount: Int64(fields.int(for: "usage_bytes") ?? fields.int(for: "bytes") ?? 0),
            status: normalizedStatus(fields.string(for: "status")),
            providerObject: fields.string(for: "object"),
            providerMetadata: metadata,
            createdAt: date(from: fields["created_at"]) ?? Date(),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"])
        )
    }

    func vectorStoreFileBatchRecord(from value: JSONValue?, vectorStoreID: String) throws -> ProviderBatchRecord {
        guard let fields = value?.objectValue,
              let id = fields.string(for: "id")
        else {
            throw CloudProviderError.invalidResponse
        }
        return ProviderBatchRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            endpoint: "vector_stores/\(vectorStoreID)/file_batches",
            status: normalizedStatus(fields.string(for: "status")),
            inputFileID: nil,
            outputFileID: nil,
            errorFileID: nil,
            completionWindow: nil,
            requestCounts: fields["file_counts"],
            metadata: metadata(from: fields["metadata"]).merging(["vector_store_id": vectorStoreID]) { provider, _ in provider },
            createdAt: date(from: fields["created_at"]) ?? Date(),
            completedAt: date(from: fields["completed_at"]),
            expiresAt: date(from: fields["expires_at"]),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"])
        )
    }

    func normalizedStatus(_ value: String?) -> String {
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

    func metadata(from value: JSONValue?) -> [String: String] {
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

    func date(from value: JSONValue?) -> Date? {
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

    func errorMessage(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = value.stringValue, !string.isEmpty {
            return string
        }
        guard let object = value.objectValue else { return nil }
        return object.string(for: "message") ?? object.string(for: "error") ?? object.string(for: "code")
    }
}

private extension OpenAIProviderResponse {
    var listData: [JSONValue] {
        guard let json else { return [] }
        if let values = json.objectValue?["data"], case let .array(items) = values {
            return items
        }
        if case let .array(items) = json {
            return items
        }
        return [json]
    }
}

private extension ProviderBatchRecord {
    var isTerminalProviderStorageStatus: Bool {
        ["completed", "failed", "cancelled", "expired"].contains(status)
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(for key: String) -> String? {
        self[key]?.stringValue
    }

    func int(for key: String) -> Int? {
        self[key]?.intValue
    }
}
