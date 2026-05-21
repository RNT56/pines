import Foundation
import PinesCore

enum GeminiProviderRecordMapper {
    static func providerFile(from object: JSONValue, providerID: ProviderID) -> ProviderFileRecord? {
        guard let fields = object.objectValue,
              let name = fields.string(for: "name")
        else { return nil }
        let metadata = metadata(from: object, excluding: [
            "name", "displayName", "mimeType", "sizeBytes", "state", "createTime", "updateTime", "expirationTime", "sha256Hash", "uri", "error",
        ])
        return ProviderFileRecord(
            id: name,
            providerID: providerID,
            providerKind: .gemini,
            purpose: "generative",
            fileName: fields.string(for: "displayName") ?? URL(fileURLWithPath: name).lastPathComponent,
            contentType: fields.string(for: "mimeType"),
            byteCount: Int64(fields.int(for: "sizeBytes") ?? fields.int(for: "size_bytes") ?? 0),
            status: normalizedStatus(fields.string(for: "state")),
            sha256: fields.string(for: "sha256Hash") ?? fields.string(for: "sha256_hash"),
            providerObject: "file",
            providerMetadata: metadata,
            createdAt: date(from: fields["createTime"] ?? fields["create_time"]) ?? Date(),
            expiresAt: date(from: fields["expirationTime"] ?? fields["expiration_time"]),
            lastError: errorMessage(from: fields["error"])
        )
    }

    static func providerCache(from object: JSONValue, providerID: ProviderID) -> ProviderCacheRecord? {
        guard let fields = object.objectValue,
              let name = fields.string(for: "name")
        else { return nil }
        var configuration = [String: JSONValue]()
        for key in ["contents", "tools", "toolConfig", "systemInstruction"] {
            if let value = fields[key] {
                configuration[key] = value
            }
        }
        let usageBytes = Int64(fields.int(for: "usageMetadata.totalTokenCount") ?? fields.int(for: "totalTokenCount") ?? 0)
        return ProviderCacheRecord(
            id: name,
            providerID: providerID,
            providerKind: .gemini,
            kind: "cached_content",
            name: fields.string(for: "displayName") ?? name,
            modelID: fields.string(for: "model").map(ModelID.init(rawValue:)),
            status: "active",
            usageBytes: usageBytes,
            itemCounts: fields["usageMetadata"] ?? fields["usage_metadata"],
            configuration: configuration.isEmpty ? object : .object(configuration),
            metadata: metadata(from: fields["metadata"]),
            createdAt: date(from: fields["createTime"] ?? fields["create_time"]) ?? Date(),
            expiresAt: date(from: fields["expireTime"] ?? fields["expire_time"]),
            lastActiveAt: date(from: fields["updateTime"] ?? fields["update_time"]),
            lastError: errorMessage(from: fields["error"])
        )
    }

    static func providerBatch(
        fromOperation object: JSONValue,
        providerID: ProviderID,
        endpoint: String = "batchGenerateContent"
    ) -> ProviderBatchRecord? {
        guard let fields = object.objectValue,
              let name = fields.string(for: "name")
        else { return nil }
        let response = fields["response"]?.objectValue
        let metadataValue = fields["metadata"]
        let metadataObject = metadataValue?.objectValue
        let batchStats = metadataObject?["batchStats"] ?? metadataObject?["batch_stats"]
        let done = fields.bool(for: "done") ?? false
        let status = statusFromOperation(fields)
        return ProviderBatchRecord(
            id: name,
            providerID: providerID,
            providerKind: .gemini,
            endpoint: metadataObject?.string(for: "verb") ?? response?.string(for: "@type") ?? endpoint,
            status: status,
            inputFileID: metadataObject?.string(for: "inputConfig.fileName")
                ?? metadataObject?.string(for: "input_config.file_name")
                ?? response?.string(for: "inputConfig.fileName"),
            outputFileID: metadataObject?.string(for: "outputInfo.fileName")
                ?? metadataObject?.string(for: "output_info.file_name")
                ?? response?.string(for: "dest.fileName"),
            errorFileID: metadataObject?.string(for: "errorFileName")
                ?? metadataObject?.string(for: "error_file_name"),
            requestCounts: batchStats ?? metadataValue,
            metadata: metadata(from: metadataValue).merging(["operation_name": name]) { current, _ in current },
            createdAt: date(from: metadataObject?["createTime"] ?? metadataObject?["create_time"]) ?? Date(),
            completedAt: done ? (date(from: metadataObject?["endTime"] ?? metadataObject?["end_time"]) ?? Date()) : nil,
            lastError: errorMessage(from: fields["error"])
        )
    }

    static func providerArtifact(
        fromOperation object: JSONValue,
        providerID: ProviderID,
        kind: String = "media_operation"
    ) -> ProviderArtifactRecord? {
        guard let fields = object.objectValue,
              let name = fields.string(for: "name")
        else { return nil }
        return ProviderArtifactRecord(
            id: name,
            providerID: providerID,
            providerKind: .gemini,
            responseID: name,
            kind: kind,
            text: statusFromOperation(fields),
            content: object,
            createdAt: date(from: fields["metadata"]?.objectValue?["createTime"]) ?? Date()
        )
    }

    static func generatedMediaArtifacts(
        from object: JSONValue?,
        providerID: ProviderID,
        responseID: String? = nil,
        defaultKind: String = "generated_media"
    ) -> [ProviderArtifactRecord] {
        var records = [ProviderArtifactRecord]()
        collectGeneratedMediaArtifacts(
            in: object,
            providerID: providerID,
            responseID: responseID,
            defaultKind: defaultKind,
            records: &records
        )
        return records
    }

    static func providerModelCapability(from object: JSONValue, providerID: ProviderID) -> ProviderModelCapabilityRecord? {
        guard let fields = object.objectValue,
              let name = fields.string(for: "name")
        else { return nil }
        let methods = fields.arrayStrings(for: "supportedGenerationMethods")
        let modelID = ModelID(rawValue: name)
        let text = CloudProviderModelEligibility.isTextOutputModel(
            id: name,
            providerKind: .gemini,
            supportedGenerationMethods: methods
        )
        let generatedImages = methods.contains("predict") && name.lowercased().contains("imagen")
        let generatedVideo = methods.contains("generateVideos") || name.lowercased().contains("veo")
        let embeddings = methods.contains { $0.lowercased().contains("embed") }
        let capabilities = ProviderCapabilities(
            local: false,
            streaming: methods.contains("streamGenerateContent") || methods.contains("createInteraction"),
            textGeneration: text,
            vision: text,
            imageInputs: text,
            audioInputs: text,
            videoInputs: text,
            pdfInputs: text,
            textDocumentInputs: text,
            files: text,
            embeddings: embeddings,
            toolCalling: text,
            hostedTools: text,
            jsonMode: text,
            structuredOutputs: text,
            contextCache: text,
            live: false,
            generatedImages: generatedImages,
            generatedVideo: generatedVideo,
            batch: methods.contains("batchGenerateContent"),
            tokenCounting: methods.contains("countTokens"),
            maxContextTokens: fields.int(for: "inputTokenLimit"),
            maxOutputTokens: fields.int(for: "outputTokenLimit")
        )
        return ProviderModelCapabilityRecord(
            providerID: providerID,
            providerKind: .gemini,
            modelID: modelID,
            capabilities: capabilities,
            contextWindowTokens: fields.int(for: "inputTokenLimit"),
            inputModalities: inputModalities(for: name, methods: methods, text: text),
            outputModalities: outputModalities(for: name, methods: methods, text: text),
            metadata: metadata(from: object).merging([
                "display_name": fields.string(for: "displayName") ?? "",
                "version": fields.string(for: "version") ?? "",
                "supported_generation_methods": methods.joined(separator: ","),
            ]) { current, new in current.isEmpty ? new : current },
            fetchedAt: Date()
        )
    }

    static func providerResearchRun(
        from request: GeminiDeepResearchRequest,
        response: JSONValue?,
        requestID: String? = nil,
        createdAt: Date = Date()
    ) -> ProviderResearchRunRecord {
        let fields = response?.objectValue ?? [:]
        let interaction = fields["interaction"]?.objectValue ?? fields
        let id = interaction.string(for: "id") ?? request.id.uuidString
        let status = normalizedStatus(interaction.string(for: "status"))
        let citationCount = citationCount(in: response)
        let toolCallCount = toolCallCount(in: response)
        return ProviderResearchRunRecord(
            id: id,
            providerID: request.providerID,
            providerKind: .gemini,
            modelID: request.agentID,
            title: request.title,
            prompt: request.prompt,
            depth: request.depth,
            sourcePolicy: request.sourcePolicy,
            reportFormat: request.reportFormat,
            includeCodeInterpreter: request.includeCodeInterpreter,
            serviceTier: request.serviceTier,
            responseID: id,
            status: status,
            citationCount: citationCount,
            toolCallCount: toolCallCount,
            providerMetadata: providerResearchMetadata(
                request: request,
                response: response,
                interaction: interaction,
                interactionID: id,
                requestID: requestID,
                citationCount: citationCount,
                toolCallCount: toolCallCount
            ),
            createdAt: date(from: interaction["createTime"] ?? interaction["created_at"]) ?? createdAt,
            updatedAt: Date(),
            completedAt: completedAt(status: status, fields: interaction),
            lastError: errorMessage(from: interaction["error"] ?? fields["error"])
        )
    }

    static func providerResearchRun(
        updating run: ProviderResearchRunRecord,
        response: JSONValue?,
        requestID: String? = nil
    ) -> ProviderResearchRunRecord {
        let fields = response?.objectValue ?? [:]
        let interaction = fields["interaction"]?.objectValue ?? fields
        let status = normalizedStatus(interaction.string(for: "status") ?? run.status)
        let interactionID = interaction.string(for: "id") ?? run.responseID ?? run.id
        let citationCount = max(run.citationCount, citationCount(in: response))
        let toolCallCount = max(run.toolCallCount, toolCallCount(in: response))
        var updated = run
        updated.responseID = interactionID
        updated.status = status
        updated.citationCount = citationCount
        updated.toolCallCount = toolCallCount
        updated.providerMetadata = run.providerMetadata.merging(providerResearchMetadata(
            request: nil,
            response: response,
            interaction: interaction,
            interactionID: interactionID,
            requestID: requestID,
            citationCount: citationCount,
            toolCallCount: toolCallCount
        )) { _, provider in provider }
        updated.updatedAt = Date()
        updated.completedAt = completedAt(status: status, fields: interaction) ?? run.completedAt
        updated.lastError = errorMessage(from: interaction["error"] ?? fields["error"]) ?? run.lastError
        return updated
    }

    static func deepResearchFinalOutputText(from response: JSONValue?) -> String? {
        let fields = response?.objectValue ?? [:]
        let interaction = fields["interaction"]?.objectValue ?? fields
        for value in [
            fields["output_text"],
            fields["final_output"],
            fields["text"],
            interaction["output_text"],
            interaction["final_output"],
            interaction["text"],
        ] {
            if let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        for key in ["outputs", "output", "steps", "candidates", "content"] {
            if let text = deepResearchOutputTexts(from: interaction[key]).joined(separator: "\n\n").nilIfEmpty {
                return text
            }
        }
        for key in ["outputs", "output", "steps", "candidates", "content"] {
            if let text = deepResearchOutputTexts(from: fields[key]).joined(separator: "\n\n").nilIfEmpty {
                return text
            }
        }
        return nil
    }

    static func operationName(from object: JSONValue?) -> String? {
        object?.objectValue?.string(for: "name")
    }

    private static func collectGeneratedMediaArtifacts(
        in value: JSONValue?,
        providerID: ProviderID,
        responseID: String?,
        defaultKind: String,
        records: inout [ProviderArtifactRecord]
    ) {
        switch value {
        case let .object(object):
            if let artifact = generatedMediaArtifact(from: object, providerID: providerID, responseID: responseID, defaultKind: defaultKind) {
                records.append(artifact)
            }
            object.values.forEach {
                collectGeneratedMediaArtifacts(
                    in: $0,
                    providerID: providerID,
                    responseID: responseID,
                    defaultKind: defaultKind,
                    records: &records
                )
            }
        case let .array(values):
            values.forEach {
                collectGeneratedMediaArtifacts(
                    in: $0,
                    providerID: providerID,
                    responseID: responseID,
                    defaultKind: defaultKind,
                    records: &records
                )
            }
        case .string, .number, .bool, .null, nil:
            break
        }
    }

    private static func generatedMediaArtifact(
        from object: [String: JSONValue],
        providerID: ProviderID,
        responseID: String?,
        defaultKind: String
    ) -> ProviderArtifactRecord? {
        let inlineData = object["inlineData"]?.objectValue ?? object["inline_data"]?.objectValue
        let fileData = object["fileData"]?.objectValue ?? object["file_data"]?.objectValue
        let video = object["video"]?.objectValue
        if let inlineData {
            let mimeType = inlineData.string(for: "mimeType") ?? inlineData.string(for: "mime_type")
            let byteCount = inlineData.string(for: "data").map { Int64($0.utf8.count) }
            return ProviderArtifactRecord(
                id: "gemini-inline-\(UUID().uuidString)",
                providerID: providerID,
                providerKind: .gemini,
                responseID: responseID,
                kind: mediaKind(from: mimeType, fallback: defaultKind),
                contentType: mimeType,
                byteCount: byteCount,
                content: .object(object)
            )
        }
        if let fileData {
            let uri = fileData.string(for: "fileUri") ?? fileData.string(for: "file_uri") ?? fileData.string(for: "uri")
            let mimeType = fileData.string(for: "mimeType") ?? fileData.string(for: "mime_type")
            return ProviderArtifactRecord(
                id: uri ?? "gemini-file-\(UUID().uuidString)",
                providerID: providerID,
                providerKind: .gemini,
                responseID: responseID,
                providerFileID: fileData.string(for: "name"),
                kind: mediaKind(from: mimeType, fallback: defaultKind),
                fileName: uri.flatMap { URL(string: $0)?.lastPathComponent },
                contentType: mimeType,
                content: .object(object),
                remoteURL: uri.flatMap(URL.init(string:))
            )
        }
        if let video {
            let uri = video.string(for: "uri") ?? video.string(for: "fileUri") ?? video.string(for: "file_uri")
            return ProviderArtifactRecord(
                id: uri ?? object.string(for: "name") ?? "gemini-video-\(UUID().uuidString)",
                providerID: providerID,
                providerKind: .gemini,
                responseID: responseID,
                kind: "video",
                fileName: uri.flatMap { URL(string: $0)?.lastPathComponent },
                contentType: video.string(for: "mimeType") ?? "video/mp4",
                content: .object(object),
                remoteURL: uri.flatMap(URL.init(string:))
            )
        }
        return nil
    }

    private static func mediaKind(from mimeType: String?, fallback: String) -> String {
        guard let mimeType else { return fallback }
        if mimeType.hasPrefix("image/") { return "image" }
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType.hasPrefix("audio/") { return "audio" }
        return fallback
    }

    private static func inputModalities(for name: String, methods: [String], text: Bool) -> [String] {
        if methods.contains(where: { $0.lowercased().contains("embed") }) {
            return ["text"]
        }
        if name.lowercased().contains("imagen") {
            return ["text", "image"]
        }
        return text ? ["text", "image", "audio", "video", "pdf"] : ["text"]
    }

    private static func outputModalities(for name: String, methods: [String], text: Bool) -> [String] {
        if methods.contains(where: { $0.lowercased().contains("embed") }) {
            return ["embedding"]
        }
        if name.lowercased().contains("imagen") {
            return ["image"]
        }
        if name.lowercased().contains("veo") || methods.contains("generateVideos") {
            return ["video"]
        }
        return text ? ["text"] : []
    }

    private static func statusFromOperation(_ fields: [String: JSONValue]) -> String {
        if let error = fields["error"], error.objectValue != nil || error.stringValue != nil {
            return "failed"
        }
        if fields.bool(for: "done") == true {
            return "completed"
        }
        return "in_progress"
    }

    private static func normalizedStatus(_ value: String?) -> String {
        switch value?.lowercased() {
        case "state_unspecified":
            "unknown"
        case "processing", "running":
            "in_progress"
        case "active", "succeeded", "success", "done":
            "completed"
        case "cancelled", "canceled":
            "cancelled"
        case "failed":
            "failed"
        case let value? where !value.isEmpty:
            value
        default:
            "unknown"
        }
    }

    private static func completedAt(status: String, fields: [String: JSONValue]) -> Date? {
        date(from: fields["completedAt"] ?? fields["completed_at"] ?? fields["updateTime"])
            ?? (status == "completed" ? Date() : nil)
    }

    private static func citationCount(in value: JSONValue?) -> Int {
        let citations = citationSummaries(in: value)
        guard citations.isEmpty else { return citations.count }
        return countObjects(in: value) { object in
            object["web"] != nil
                || object.string(for: "type") == "url_citation"
                || object.string(for: "type") == "file_citation"
        }
    }

    private static func toolCallCount(in value: JSONValue?) -> Int {
        toolCallSummaries(in: value).count
    }

    private static func providerResearchMetadata(
        request: GeminiDeepResearchRequest?,
        response: JSONValue?,
        interaction: [String: JSONValue],
        interactionID: String,
        requestID: String?,
        citationCount: Int,
        toolCallCount: Int
    ) -> [String: String] {
        var result = request?.metadata ?? [:]
        result.merge(metadata(from: response)) { provider, _ in provider }
        if let providerMetadata = interaction["metadata"]?.objectValue {
            result.merge(metadata(from: .object(providerMetadata))) { _, provider in provider }
        }
        result[CloudProviderMetadataKeys.geminiInteractionID] = interactionID
        result[CloudProviderMetadataKeys.geminiResponseID] = interactionID
        if let requestID, !requestID.isEmpty {
            result[CloudProviderMetadataKeys.geminiRequestID] = requestID
        }
        if let model = interaction.string(for: "model") ?? interaction.string(for: "modelVersion"), !model.isEmpty {
            result[CloudProviderMetadataKeys.geminiModelVersion] = model
        }
        if let request {
            result["pines_run_type"] = "deep_research"
            result["pines_research_request_id"] = request.id.uuidString
            result["pines_research_depth"] = request.depth
            result["pines_research_report_format"] = request.reportFormat
            if let previousInteractionID = request.previousInteractionID, !previousInteractionID.isEmpty {
                result["gemini.previous_interaction_id"] = previousInteractionID
            }
            if let lastEventID = request.lastEventID, !lastEventID.isEmpty {
                result["gemini.last_event_id"] = lastEventID
            }
        }
        if let previousInteractionID = interaction.string(for: "previousInteractionId")
            ?? interaction.string(for: "previous_interaction_id"),
            !previousInteractionID.isEmpty {
            result["gemini.previous_interaction_id"] = previousInteractionID
        }
        if let lastEventID = interaction.string(for: "lastEventId")
            ?? interaction.string(for: "last_event_id")
            ?? interaction.string(for: "eventId")
            ?? interaction.string(for: "event_id"),
            !lastEventID.isEmpty {
            result["gemini.last_event_id"] = lastEventID
        }
        result["gemini.deep_research.background"] = "true"
        result["gemini.deep_research.store"] = "true"
        result["gemini.deep_research.citation_count"] = String(citationCount)
        result["gemini.deep_research.tool_call_count"] = String(toolCallCount)
        if deepResearchFinalOutputText(from: response) != nil {
            result["gemini.deep_research.final_output_available"] = "true"
        }
        let citations = citationSummaries(in: response)
        if !citations.isEmpty, let json = jsonString(from: .array(citations.map(JSONValue.object))) {
            result[CloudProviderMetadataKeys.webSearchCitationsJSON] = json
        }
        let toolCalls = toolCallSummaries(in: response)
        if !toolCalls.isEmpty, let json = jsonString(from: .array(toolCalls.map(JSONValue.object))) {
            result["gemini.deep_research.tool_calls_json"] = json
        }
        if let usage = interaction["usage"] ?? interaction["usageMetadata"],
           let json = jsonString(from: usage) {
            result[CloudProviderMetadataKeys.geminiCacheUsageJSON] = json
        }
        return result
    }

    private static func deepResearchOutputTexts(from value: JSONValue?) -> [String] {
        switch value {
        case let .object(object):
            if let outputText = object.string(for: "output_text") ?? object.string(for: "final_output"),
               !outputText.isEmpty {
                return [outputText]
            }
            if let type = object.string(for: "type")?.lowercased(),
               ["text", "output_text", "message", "model_output"].contains(type),
               let text = object.string(for: "text"),
               !text.isEmpty {
                return [text]
            }
            if object.count == 1, let text = object.string(for: "text"), !text.isEmpty {
                return [text]
            }
            return ["content", "parts", "outputs", "output", "steps", "candidates"]
                .flatMap { deepResearchOutputTexts(from: object[$0]) }
        case let .array(values):
            return values.flatMap(deepResearchOutputTexts(from:))
        case .string, .number, .bool, .null, nil:
            return []
        }
    }

    private static func citationSummaries(in value: JSONValue?) -> [[String: JSONValue]] {
        var summaries = [[String: JSONValue]]()
        collectCitationSummaries(in: value, summaries: &summaries)
        var seen = Set<String>()
        return summaries.filter { summary in
            let identifier = summary.string(for: "url")
                ?? summary.string(for: "uri")
                ?? summary.string(for: "file_id")
                ?? summary.string(for: "title")
                ?? String(describing: summary)
            return seen.insert(identifier).inserted
        }
    }

    private static func collectCitationSummaries(in value: JSONValue?, summaries: inout [[String: JSONValue]]) {
        switch value {
        case let .object(object):
            if let web = object["web"]?.objectValue {
                var summary = [String: JSONValue]()
                if let uri = web.string(for: "uri") ?? web.string(for: "url") {
                    summary["url"] = .string(uri)
                }
                if let title = web.string(for: "title") {
                    summary["title"] = .string(title)
                }
                if !summary.isEmpty {
                    summaries.append(summary)
                }
            } else if let type = object.string(for: "type"),
                      type == "url_citation" || type == "file_citation" {
                var summary = [String: JSONValue]()
                for key in ["url", "uri", "file_id", "title", "quote"] {
                    if let value = object.string(for: key) {
                        summary[key] = .string(value)
                    }
                }
                if !summary.isEmpty {
                    summaries.append(summary)
                }
            }
            object.values.forEach { collectCitationSummaries(in: $0, summaries: &summaries) }
        case let .array(values):
            values.forEach { collectCitationSummaries(in: $0, summaries: &summaries) }
        case .string, .number, .bool, .null, nil:
            break
        }
    }

    private static func toolCallSummaries(in value: JSONValue?) -> [[String: JSONValue]] {
        var summaries = [[String: JSONValue]]()
        collectToolCallSummaries(in: value, summaries: &summaries)
        var seen = Set<String>()
        return summaries.filter { summary in
            let identifier = summary.string(for: "id")
                ?? [summary.string(for: "type"), summary.string(for: "name")]
                    .compactMap { $0 }
                    .joined(separator: ":")
            return seen.insert(identifier.isEmpty ? String(describing: summary) : identifier).inserted
        }
    }

    private static func collectToolCallSummaries(in value: JSONValue?, summaries: inout [[String: JSONValue]]) {
        switch value {
        case let .object(object):
            if let functionCall = object["functionCall"]?.objectValue ?? object["function_call"]?.objectValue {
                summaries.append(toolCallSummary(type: "function_call", object: functionCall))
            }
            if let executableCode = object["executableCode"]?.objectValue ?? object["executable_code"]?.objectValue {
                summaries.append(toolCallSummary(type: "executable_code", object: executableCode))
            }
            if let type = object.string(for: "type"), type.hasSuffix("_call") {
                summaries.append(toolCallSummary(type: type, object: object))
            }
            object.values.forEach { collectToolCallSummaries(in: $0, summaries: &summaries) }
        case let .array(values):
            values.forEach { collectToolCallSummaries(in: $0, summaries: &summaries) }
        case .string, .number, .bool, .null, nil:
            break
        }
    }

    private static func toolCallSummary(type: String, object: [String: JSONValue]) -> [String: JSONValue] {
        var summary: [String: JSONValue] = ["type": .string(type)]
        for key in ["id", "name", "language"] {
            if let value = object.string(for: key), !value.isEmpty {
                summary[key] = .string(value)
            }
        }
        return summary
    }

    private static func jsonString(from value: JSONValue?) -> String? {
        guard let value,
              let data = try? JSONEncoder().encode(value)
        else { return nil }
        return String(data: data, encoding: .utf8)
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

    private static func metadata(from value: JSONValue?, excluding excludedKeys: Set<String> = []) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        return object.reduce(into: [String: String]()) { result, item in
            guard !excludedKeys.contains(item.key) else { return }
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
