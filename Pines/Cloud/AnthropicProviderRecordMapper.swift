import Foundation
import PinesCore

enum AnthropicProviderRecordMapper {
    static func providerFile(from object: JSONValue, providerID: ProviderID) -> ProviderFileRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id")
        else { return nil }
        var providerMetadata = metadata(from: object, excluding: [
            "id", "type", "filename", "file_name", "mime_type", "mimeType", "size_bytes", "bytes", "created_at", "createdAt", "error",
        ])
        if let downloadable = fields.bool(for: "downloadable") {
            providerMetadata["downloadable"] = String(downloadable)
        }
        if let type = fields.string(for: "type") {
            providerMetadata["provider_type"] = type
        }
        return ProviderFileRecord(
            id: id,
            providerID: providerID,
            providerKind: .anthropic,
            purpose: fields.string(for: "purpose") ?? (fields.bool(for: "downloadable") == true ? "generated" : "messages"),
            fileName: fields.string(for: "filename") ?? fields.string(for: "file_name") ?? id,
            contentType: fields.string(for: "mime_type") ?? fields.string(for: "mimeType"),
            byteCount: Int64(fields.int(for: "size_bytes") ?? fields.int(for: "bytes") ?? 0),
            status: normalizedFileStatus(fields.string(for: "status"), downloadable: fields.bool(for: "downloadable")),
            sha256: fields.string(for: "sha256"),
            providerObject: fields.string(for: "type") ?? "file",
            providerMetadata: providerMetadata,
            createdAt: date(from: fields["created_at"] ?? fields["createdAt"]) ?? Date(),
            expiresAt: date(from: fields["expires_at"] ?? fields["expiresAt"]),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"])
        )
    }

    static func providerBatch(from object: JSONValue, providerID: ProviderID) -> ProviderBatchRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id")
        else { return nil }
        var metadata = metadata(from: object, excluding: [
            "id", "type", "processing_status", "status", "request_counts", "created_at", "ended_at", "expires_at", "archived_at", "cancel_initiated_at", "results_url", "error",
        ])
        if let resultsURL = fields.string(for: "results_url") {
            metadata["results_url"] = resultsURL
        }
        if let archivedAt = fields.string(for: "archived_at") {
            metadata["archived_at"] = archivedAt
        }
        if let cancelInitiatedAt = fields.string(for: "cancel_initiated_at") {
            metadata["cancel_initiated_at"] = cancelInitiatedAt
        }
        return ProviderBatchRecord(
            id: id,
            providerID: providerID,
            providerKind: .anthropic,
            endpoint: fields.string(for: "endpoint") ?? "messages/batches",
            status: normalizedBatchStatus(fields.string(for: "processing_status") ?? fields.string(for: "status")),
            inputFileID: fields.string(for: "input_file_id") ?? fields.string(for: "inputFileId"),
            outputFileID: fields.string(for: "output_file_id") ?? fields.string(for: "results_url"),
            errorFileID: fields.string(for: "error_file_id"),
            completionWindow: fields.string(for: "completion_window") ?? fields.string(for: "completionWindow"),
            requestCounts: fields["request_counts"] ?? fields["requestCounts"],
            metadata: metadata,
            createdAt: date(from: fields["created_at"] ?? fields["createdAt"]) ?? Date(),
            completedAt: date(from: fields["ended_at"] ?? fields["completed_at"] ?? fields["completedAt"]),
            expiresAt: date(from: fields["expires_at"] ?? fields["expiresAt"]),
            lastError: errorMessage(from: fields["last_error"] ?? fields["error"] ?? fields["errors"])
        )
    }

    static func providerArtifact(
        fromFile object: JSONValue,
        providerID: ProviderID,
        responseID: String? = nil,
        toolCallID: String? = nil,
        kind: String = "generated_file",
        localURL: URL? = nil
    ) -> ProviderArtifactRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id") ?? fields.string(for: "file_id") ?? fields.string(for: "fileId")
        else { return nil }
        return ProviderArtifactRecord(
            id: artifactID(prefix: "anthropic-file", id: id, responseID: responseID, toolCallID: toolCallID),
            providerID: providerID,
            providerKind: .anthropic,
            responseID: responseID,
            toolCallID: toolCallID,
            providerFileID: id,
            kind: kind,
            fileName: fields.string(for: "filename") ?? fields.string(for: "file_name") ?? fields.string(for: "name") ?? id,
            contentType: fields.string(for: "mime_type") ?? fields.string(for: "mimeType"),
            byteCount: fields.int(for: "size_bytes").map(Int64.init) ?? fields.int(for: "bytes").map(Int64.init),
            content: object,
            localURL: localURL,
            createdAt: date(from: fields["created_at"] ?? fields["createdAt"]) ?? Date()
        )
    }

    static func providerArtifacts(
        fromMessage object: JSONValue?,
        providerID: ProviderID,
        responseID: String? = nil,
        toolCallID: String? = nil,
        defaultKind: String = "generated_file"
    ) -> [ProviderArtifactRecord] {
        var records = [ProviderArtifactRecord]()
        collectProviderFileArtifacts(
            in: object,
            providerID: providerID,
            responseID: responseID,
            toolCallID: toolCallID,
            defaultKind: defaultKind,
            records: &records
        )
        return records.uniquedByID()
    }

    static func batchResultArtifacts(
        fromJSONLines data: Data,
        providerID: ProviderID,
        batchID: String
    ) -> [ProviderArtifactRecord] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in
                guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
                    return nil
                }
                let fields = json.objectValue ?? [:]
                let customID = fields.string(for: "custom_id") ?? fields.string(for: "customId")
                let result = fields["result"]
                let status = result?.objectValue?.string(for: "type") ?? fields.string(for: "type") ?? "result"
                return ProviderArtifactRecord(
                    id: "anthropic-batch-\(batchID)-\(customID ?? String(index))",
                    providerID: providerID,
                    providerKind: .anthropic,
                    responseID: batchID,
                    kind: "batch_result",
                    fileName: customID.map { "\($0).json" },
                    contentType: "application/json",
                    text: status,
                    content: json,
                    createdAt: Date()
                )
            }
    }

    static func providerModelCapability(from object: JSONValue, providerID: ProviderID) -> ProviderModelCapabilityRecord? {
        guard let fields = object.objectValue,
              let id = fields.string(for: "id")
        else { return nil }
        let lowercasedID = id.lowercased()
        let isClaude = lowercasedID.contains("claude")
        let supportsVision = isClaude && !lowercasedID.contains("text-embedding")
        let capabilities = ProviderCapabilities(
            local: false,
            streaming: isClaude,
            textGeneration: isClaude,
            vision: supportsVision,
            imageInputs: supportsVision,
            audioInputs: false,
            audioOutputs: false,
            videoInputs: false,
            videoOutputs: false,
            pdfInputs: supportsVision,
            textDocumentInputs: isClaude,
            files: isClaude,
            embeddings: false,
            toolCalling: isClaude,
            hostedTools: isClaude,
            jsonMode: isClaude,
            structuredOutputs: isClaude,
            contextCache: isClaude,
            live: false,
            generatedImages: false,
            generatedAudio: false,
            generatedVideo: false,
            batch: isClaude,
            tokenCounting: isClaude,
            maxContextTokens: fields.int(for: "context_window_tokens") ?? fields.int(for: "input_token_limit"),
            maxOutputTokens: fields.int(for: "max_output_tokens") ?? fields.int(for: "output_token_limit")
        )
        return ProviderModelCapabilityRecord(
            providerID: providerID,
            providerKind: .anthropic,
            modelID: ModelID(rawValue: id),
            capabilities: capabilities,
            contextWindowTokens: fields.int(for: "context_window_tokens") ?? fields.int(for: "input_token_limit"),
            inputModalities: supportsVision ? ["text", "image", "pdf", "document"] : ["text"],
            outputModalities: isClaude ? ["text"] : [],
            metadata: metadata(from: object).merging([
                "display_name": fields.string(for: "display_name") ?? fields.string(for: "displayName") ?? id,
            ]) { current, new in current.isEmpty ? new : current },
            fetchedAt: Date(),
            expiresAt: date(from: fields["deprecated_at"] ?? fields["expires_at"])
        )
    }

    static func firstMessageID(in value: JSONValue?) -> String? {
        switch value {
        case let .object(object):
            if object.string(for: "type") == "message", let id = object.string(for: "id") {
                return id
            }
            for child in object.values {
                if let id = firstMessageID(in: child) {
                    return id
                }
            }
            return nil
        case let .array(values):
            for child in values {
                if let id = firstMessageID(in: child) {
                    return id
                }
            }
            return nil
        case .string, .number, .bool, .null, nil:
            return nil
        }
    }

    private static func collectProviderFileArtifacts(
        in value: JSONValue?,
        providerID: ProviderID,
        responseID: String?,
        toolCallID: String?,
        defaultKind: String,
        records: inout [ProviderArtifactRecord]
    ) {
        switch value {
        case let .object(object):
            if let artifact = fileArtifact(
                from: object,
                providerID: providerID,
                responseID: responseID,
                toolCallID: object.string(for: "tool_use_id") ?? object.string(for: "toolUseId") ?? toolCallID,
                defaultKind: defaultKind
            ) {
                records.append(artifact)
            }
            object.values.forEach {
                collectProviderFileArtifacts(
                    in: $0,
                    providerID: providerID,
                    responseID: responseID,
                    toolCallID: toolCallID,
                    defaultKind: defaultKind,
                    records: &records
                )
            }
        case let .array(values):
            values.forEach {
                collectProviderFileArtifacts(
                    in: $0,
                    providerID: providerID,
                    responseID: responseID,
                    toolCallID: toolCallID,
                    defaultKind: defaultKind,
                    records: &records
                )
            }
        case .string, .number, .bool, .null, nil:
            break
        }
    }

    private static func fileArtifact(
        from object: [String: JSONValue],
        providerID: ProviderID,
        responseID: String?,
        toolCallID: String?,
        defaultKind: String
    ) -> ProviderArtifactRecord? {
        let fileID = object.string(for: "file_id")
            ?? object.string(for: "fileId")
            ?? object["file"]?.objectValue?.string(for: "id")
        guard let fileID else { return nil }
        let fileObject = object["file"]?.objectValue
        let type = object.string(for: "type") ?? fileObject?.string(for: "type") ?? defaultKind
        let mimeType = object.string(for: "mime_type")
            ?? object.string(for: "mimeType")
            ?? fileObject?.string(for: "mime_type")
            ?? fileObject?.string(for: "mimeType")
        return ProviderArtifactRecord(
            id: artifactID(prefix: "anthropic-file", id: fileID, responseID: responseID, toolCallID: toolCallID),
            providerID: providerID,
            providerKind: .anthropic,
            responseID: responseID,
            toolCallID: toolCallID,
            providerFileID: fileID,
            kind: artifactKind(from: type, mimeType: mimeType, fallback: defaultKind),
            fileName: object.string(for: "filename")
                ?? object.string(for: "file_name")
                ?? object.string(for: "name")
                ?? fileObject?.string(for: "filename")
                ?? fileObject?.string(for: "name"),
            contentType: mimeType,
            byteCount: object.int(for: "size_bytes").map(Int64.init)
                ?? object.int(for: "bytes").map(Int64.init)
                ?? fileObject?.int(for: "size_bytes").map(Int64.init)
                ?? fileObject?.int(for: "bytes").map(Int64.init),
            content: .object(object),
            createdAt: date(from: object["created_at"] ?? fileObject?["created_at"]) ?? Date()
        )
    }

    private static func artifactKind(from type: String, mimeType: String?, fallback: String) -> String {
        if type == "file" || type == "file_reference" || type == "container_upload" {
            return fallback
        }
        if type.contains("code") {
            return "code_execution_file"
        }
        guard let mimeType else { return type.isEmpty ? fallback : type }
        if mimeType.hasPrefix("image/") { return "image" }
        if mimeType.hasPrefix("audio/") { return "audio" }
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType == "application/pdf" { return "pdf" }
        return type.isEmpty ? fallback : type
    }

    private static func artifactID(prefix: String, id: String, responseID: String?, toolCallID: String?) -> String {
        [prefix, responseID, toolCallID, id]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func normalizedFileStatus(_ value: String?, downloadable: Bool?) -> String {
        switch value?.lowercased() {
        case "available", "active", "uploaded", "downloadable":
            "active"
        case "processing", "in_progress":
            "in_progress"
        case "deleted":
            "deleted"
        case "failed", "error":
            "failed"
        case let value? where !value.isEmpty:
            value
        default:
            downloadable == true ? "downloadable" : "active"
        }
    }

    private static func normalizedBatchStatus(_ value: String?) -> String {
        switch value?.lowercased() {
        case "in_progress", "processing", "running":
            "in_progress"
        case "canceling", "cancelling":
            "cancelling"
        case "ended", "succeeded", "success", "completed", "done":
            "completed"
        case "canceled", "cancelled":
            "cancelled"
        case "expired":
            "expired"
        case "errored", "failed", "error":
            "failed"
        case let value? where !value.isEmpty:
            value
        default:
            "unknown"
        }
    }

    private static func metadata(from value: JSONValue?, excluding excludedKeys: Set<String> = []) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        var result = [String: String]()
        for (key, value) in object where !excludedKeys.contains(key) {
            if key == "metadata", let nested = value.objectValue {
                result.merge(metadata(from: .object(nested))) { provider, _ in provider }
            } else if let string = value.stringValue {
                result[key] = string
            } else if let int = value.intValue {
                result[key] = String(int)
            } else if let bool = value.boolValue {
                result[key] = String(bool)
            }
        }
        return result
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
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(for key: String) -> String? {
        if key.contains(".") {
            return nestedValue(for: key)?.stringValue
        }
        return self[key]?.stringValue
    }

    func int(for key: String) -> Int? {
        if key.contains(".") {
            return nestedValue(for: key)?.intValue
        }
        return self[key]?.intValue
    }

    func bool(for key: String) -> Bool? {
        if key.contains(".") {
            return nestedValue(for: key)?.boolValue
        }
        return self[key]?.boolValue
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

private extension Array where Element == ProviderArtifactRecord {
    func uniquedByID() -> [ProviderArtifactRecord] {
        var seen = Set<String>()
        return filter { record in
            seen.insert(record.id).inserted
        }
    }
}
