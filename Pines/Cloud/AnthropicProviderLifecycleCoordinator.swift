import Foundation
import PinesCore

typealias AnthropicProviderLifecycleRepositories = OpenAIProviderLifecycleRepositories

struct AnthropicProviderLifecycleCoordinator: Sendable {
    let service: AnthropicProviderService
    let repositories: AnthropicProviderLifecycleRepositories

    var providerID: ProviderID {
        service.configuration.id
    }

    func refreshFiles(limit: Int? = 100, afterID: String? = nil) async throws -> [ProviderFileRecord] {
        let response = try await service.listFiles(AnthropicListRequest(afterID: afterID, limit: limit))
        let records = response.listData.compactMap {
            AnthropicProviderRecordMapper.providerFile(from: $0, providerID: providerID)
        }
        for record in records {
            try await repositories.files?.upsertProviderFile(record)
        }
        try await audit("Refreshed \(records.count) Anthropic provider files")
        return records
    }

    func uploadFile(
        fileName: String,
        contentType: String,
        data: Data,
        localURL: URL? = nil,
        fields: [String: String] = [:],
        uploadProgress: ProviderUploadProgress? = nil
    ) async throws -> ProviderFileRecord {
        let response = try await service.uploadFile(AnthropicFileUploadRequest(
            fileName: fileName,
            contentType: contentType,
            data: data,
            fields: fields
        ), uploadProgress: uploadProgress)
        guard var record = response.json.flatMap({ AnthropicProviderRecordMapper.providerFile(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        record.localURL = localURL
        record.contentType = record.contentType ?? contentType
        if record.byteCount == 0 {
            record.byteCount = Int64(data.count)
        }
        try await repositories.files?.upsertProviderFile(record)
        try await audit("Uploaded Anthropic provider file \(record.fileName)")
        return record
    }

    func uploadFile(
        fileName: String,
        contentType: String,
        fileURL: URL,
        byteCount: Int64,
        localURL: URL? = nil,
        fields: [String: String] = [:],
        uploadProgress: ProviderUploadProgress? = nil
    ) async throws -> ProviderFileRecord {
        let response = try await service.uploadFile(
            fromFile: fileURL,
            fileName: fileName,
            contentType: contentType,
            fields: fields,
            uploadProgress: uploadProgress
        )
        guard var record = response.json.flatMap({ AnthropicProviderRecordMapper.providerFile(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        record.localURL = localURL
        record.contentType = record.contentType ?? contentType
        record.byteCount = record.byteCount == 0 ? byteCount : record.byteCount
        try await repositories.files?.upsertProviderFile(record)
        try await audit("Uploaded Anthropic provider file \(record.fileName)")
        return record
    }

    func refreshFile(id: String) async throws -> ProviderFileRecord {
        let response = try await service.retrieveFile(id)
        guard let record = response.json.flatMap({ AnthropicProviderRecordMapper.providerFile(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.files?.upsertProviderFile(record)
        return record
    }

    func downloadFileContent(
        id: String,
        fileName: String? = nil,
        contentType: String? = nil,
        responseID: String? = nil,
        toolCallID: String? = nil
    ) async throws -> ProviderArtifactRecord {
        let response = try await service.retrieveFileContent(id)
        let artifact = ProviderArtifactRecord(
            id: ["anthropic-download", responseID, toolCallID, id]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "-"),
            providerID: providerID,
            providerKind: .anthropic,
            responseID: responseID,
            toolCallID: toolCallID,
            providerFileID: id,
            kind: "downloaded_file",
            fileName: fileName ?? id,
            contentType: contentType ?? response.headerValue("content-type"),
            byteCount: Int64(response.data.count),
            content: .object([
                "file_id": .string(id),
                "encoding": .string("base64"),
                "data": .string(response.data.base64EncodedString()),
            ]),
            createdAt: Date()
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        try await audit("Downloaded Anthropic provider file \(id)")
        return artifact
    }

    func deleteFile(id: String) async throws {
        _ = try await service.deleteFile(id)
        try await repositories.files?.deleteProviderFile(id: id)
        try await audit("Deleted Anthropic provider file \(id)")
    }

    func refreshBatches(limit: Int? = 100, afterID: String? = nil) async throws -> [ProviderBatchRecord] {
        let response = try await service.listBatches(AnthropicListRequest(afterID: afterID, limit: limit))
        let records = response.listData.compactMap {
            AnthropicProviderRecordMapper.providerBatch(from: $0, providerID: providerID)
        }
        for record in records {
            try await repositories.batches?.upsertProviderBatch(record)
        }
        try await audit("Refreshed \(records.count) Anthropic message batches")
        return records
    }

    func createBatch(_ request: AnthropicMessageBatchCreateRequest) async throws -> ProviderBatchRecord {
        try await createBatch(body: request.body)
    }

    func createBatch(body: JSONValue) async throws -> ProviderBatchRecord {
        let response = try await service.createBatch(body: body)
        let record = try batchRecord(from: response.json)
        try await repositories.batches?.upsertProviderBatch(record)
        try await audit("Created Anthropic message batch \(record.id)")
        return record
    }

    func refreshBatch(id: String) async throws -> ProviderBatchRecord {
        let response = try await service.retrieveBatch(id)
        let record = try batchRecord(from: response.json)
        try await repositories.batches?.upsertProviderBatch(record)
        return record
    }

    func cancelBatch(id: String) async throws -> ProviderBatchRecord {
        let response = try await service.cancelBatch(id)
        let record = try batchRecord(from: response.json)
        try await repositories.batches?.upsertProviderBatch(record)
        try await audit("Cancelled Anthropic message batch \(id)")
        return record
    }

    func deleteBatch(id: String) async throws {
        _ = try await service.deleteBatch(id)
        try await repositories.batches?.deleteProviderBatch(id: id)
        try await audit("Deleted Anthropic message batch \(id)")
    }

    func importBatchResults(id: String) async throws -> [ProviderArtifactRecord] {
        let response = try await service.retrieveBatchResults(id)
        let records = AnthropicProviderRecordMapper.batchResultArtifacts(fromJSONLines: response.data, providerID: providerID, batchID: id)
        for record in records {
            try await repositories.artifacts?.upsertProviderArtifact(record)
        }
        try await audit("Imported \(records.count) Anthropic batch results")
        return records
    }

    func countTokens(modelID: ModelID, body: JSONValue) async throws -> Int {
        let response = try await service.countTokens(modelID: modelID, body: body)
        try await audit("Counted Anthropic tokens", modelID: modelID)
        guard let fields = response.json?.objectValue,
              let inputTokens = fields.int(for: "input_tokens") ?? fields.int(for: "inputTokens")
        else {
            throw CloudProviderError.invalidResponse
        }
        return inputTokens
    }

    static func countTokensBody(messages: [JSONValue], system: JSONValue? = nil, tools: [JSONValue] = []) -> JSONValue {
        var fields: [String: JSONValue] = [
            "messages": .array(messages),
        ]
        if let system {
            fields["system"] = system
        }
        if !tools.isEmpty {
            fields["tools"] = .array(tools)
        }
        return .object(fields)
    }

    func refreshModelCapabilities(limit: Int? = 100, afterID: String? = nil) async throws -> [ProviderModelCapabilityRecord] {
        let response = try await service.listModels(AnthropicListRequest(afterID: afterID, limit: limit))
        let records = response.listData.compactMap {
            AnthropicProviderRecordMapper.providerModelCapability(from: $0, providerID: providerID)
        }
        for record in records {
            try await repositories.modelCapabilities?.upsertProviderModelCapability(record)
        }
        try await audit("Refreshed \(records.count) Anthropic model capabilities")
        return records
    }

    func refreshModelCapability(modelID: ModelID) async throws -> ProviderModelCapabilityRecord {
        let response = try await service.retrieveModel(modelID)
        guard let record = response.json.flatMap({ AnthropicProviderRecordMapper.providerModelCapability(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.modelCapabilities?.upsertProviderModelCapability(record)
        return record
    }

    private func batchRecord(from json: JSONValue?) throws -> ProviderBatchRecord {
        guard let json,
              let record = AnthropicProviderRecordMapper.providerBatch(from: json, providerID: providerID)
        else {
            throw CloudProviderError.invalidResponse
        }
        return record
    }

    private func audit(_ summary: String, modelID: ModelID? = nil) async throws {
        try await repositories.audit?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: summary,
                providerID: providerID,
                modelID: modelID,
                networkDomains: ["api.anthropic.com"]
            )
        )
    }
}

private extension AnthropicProviderResponse {
    var listData: [JSONValue] {
        guard let fields = json?.objectValue else { return [] }
        if let data = fields["data"]?.arrayValue {
            return data
        }
        if let files = fields["files"]?.arrayValue {
            return files
        }
        if let batches = fields["batches"]?.arrayValue {
            return batches
        }
        if let models = fields["models"]?.arrayValue {
            return models
        }
        return []
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func int(for key: String) -> Int? {
        if key.contains(".") {
            return nestedValue(for: key)?.intValue
        }
        return self[key]?.intValue
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
