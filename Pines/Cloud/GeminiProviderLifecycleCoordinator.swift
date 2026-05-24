import Foundation
import PinesCore

typealias GeminiProviderLifecycleRepositories = OpenAIProviderLifecycleRepositories

struct GeminiProviderLifecycleCoordinator: Sendable {
    let service: GeminiProviderService
    let repositories: GeminiProviderLifecycleRepositories

    var providerID: ProviderID {
        service.configuration.id
    }

    func refreshFiles(pageSize: Int? = 100, pageToken: String? = nil) async throws -> [ProviderFileRecord] {
        let response = try await service.listFiles(GeminiListRequest(pageSize: pageSize, pageToken: pageToken))
        let records = response.listValues(for: "files").compactMap {
            GeminiProviderRecordMapper.providerFile(from: $0, providerID: providerID)
        }
        for record in records {
            try await repositories.files?.upsertProviderFile(record)
        }
        try await audit("Refreshed \(records.count) Gemini provider files")
        return records
    }

    func uploadFile(
        fileName: String,
        contentType: String,
        data: Data,
        localURL: URL? = nil,
        poll: GeminiFilePolling? = nil
    ) async throws -> ProviderFileRecord {
        let session = try await service.startResumableUpload(displayName: fileName, mimeType: contentType, byteCount: data.count)
        let response = try await service.uploadResumableData(to: session.uploadURL, data: data)
        guard var record = fileRecord(from: response.json, fallbackFileName: fileName, contentType: contentType, byteCount: data.count) else {
            throw CloudProviderError.invalidResponse
        }
        record.localURL = localURL
        record.contentType = record.contentType ?? contentType
        record.byteCount = record.byteCount == 0 ? Int64(data.count) : record.byteCount
        try await repositories.files?.upsertProviderFile(record)
        try await audit("Uploaded Gemini provider file \(record.fileName)")

        if let poll {
            return try await pollFile(name: record.id, polling: poll)
        }
        return record
    }

    func refreshFile(name: String) async throws -> ProviderFileRecord {
        let response = try await service.getFile(name)
        guard let record = fileRecord(from: response.json) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.files?.upsertProviderFile(record)
        return record
    }

    func pollFile(name: String, polling: GeminiFilePolling = GeminiFilePolling()) async throws -> ProviderFileRecord {
        var record = try await refreshFile(name: name)
        await polling.onUpdate?(record)
        for _ in 0..<polling.maxAttempts where !record.isTerminalGeminiFileStatus {
            try await Task.sleep(nanoseconds: polling.intervalNanoseconds)
            record = try await refreshFile(name: name)
            await polling.onUpdate?(record)
        }
        return record
    }

    func deleteFile(name: String) async throws {
        _ = try await service.deleteFile(name)
        try await repositories.files?.deleteProviderFile(id: normalizedResourceName(name, defaultCollection: "files"))
        try await audit("Deleted Gemini provider file \(name)")
    }

    func createCachedContent(body: JSONValue) async throws -> ProviderCacheRecord {
        let response = try await service.createCachedContent(body: body)
        guard let record = cacheRecord(from: response.json) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.caches?.upsertProviderCache(record)
        try await audit("Created Gemini cached content \(record.name ?? record.id)")
        return record
    }

    func refreshCachedContents(pageSize: Int? = 100, pageToken: String? = nil) async throws -> [ProviderCacheRecord] {
        let response = try await service.listCachedContents(GeminiListRequest(pageSize: pageSize, pageToken: pageToken))
        let records = response.listValues(for: "cachedContents").compactMap {
            GeminiProviderRecordMapper.providerCache(from: $0, providerID: providerID)
        }
        for record in records {
            try await repositories.caches?.upsertProviderCache(record)
        }
        try await audit("Refreshed \(records.count) Gemini cached contents")
        return records
    }

    func refreshCachedContent(name: String) async throws -> ProviderCacheRecord {
        let response = try await service.getCachedContent(name)
        guard let record = cacheRecord(from: response.json) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.caches?.upsertProviderCache(record)
        return record
    }

    func updateCachedContent(name: String, body: JSONValue, updateMask: String? = nil) async throws -> ProviderCacheRecord {
        let response = try await service.updateCachedContent(name, body: body, updateMask: updateMask)
        guard let record = cacheRecord(from: response.json) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.caches?.upsertProviderCache(record)
        try await audit("Updated Gemini cached content \(record.name ?? record.id)")
        return record
    }

    func deleteCachedContent(name: String) async throws {
        _ = try await service.deleteCachedContent(name)
        try await repositories.caches?.deleteProviderCache(id: normalizedResourceName(name, defaultCollection: "cachedContents"))
        try await audit("Deleted Gemini cached content \(name)")
    }

    func countTokens(modelID: ModelID, body: JSONValue) async throws -> Int {
        let response = try await service.countTokens(modelID: modelID, body: body)
        try await audit("Counted Gemini tokens", modelID: modelID)
        guard let totalTokens = response.json?.objectValue?.int(for: "totalTokens")
            ?? response.json?.objectValue?.int(for: "total_tokens")
        else {
            throw CloudProviderError.invalidResponse
        }
        return totalTokens
    }

    static func inlineDataPart(data: Data, mimeType: String) -> JSONValue {
        .object([
            "inlineData": .object([
                "mimeType": .string(mimeType),
                "data": .string(data.base64EncodedString()),
            ]),
        ])
    }

    static func fileDataPart(fileURI: String, mimeType: String? = nil, name: String? = nil) -> JSONValue {
        var fileData: [String: JSONValue] = [
            "fileUri": .string(fileURI),
        ]
        if let mimeType, !mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fileData["mimeType"] = .string(mimeType)
        }
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fileData["name"] = .string(name)
        }
        return .object([
            "fileData": .object(fileData),
        ])
    }

    static func cachedContentBody(
        modelID: ModelID,
        contents: [JSONValue],
        displayName: String? = nil,
        systemInstruction: JSONValue? = nil,
        tools: [JSONValue] = [],
        toolConfig: JSONValue? = nil,
        ttl: String? = nil,
        expireTime: String? = nil
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(normalizedModelName(modelID)),
            "contents": .array(contents),
        ]
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["displayName"] = .string(displayName)
        }
        if let systemInstruction {
            body["systemInstruction"] = systemInstruction
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools)
        }
        if let toolConfig {
            body["toolConfig"] = toolConfig
        }
        if let ttl, !ttl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["ttl"] = .string(ttl)
        }
        if let expireTime, !expireTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["expireTime"] = .string(expireTime)
        }
        return .object(body)
    }

    static func countTokensBody(
        contents: [JSONValue],
        systemInstruction: JSONValue? = nil,
        tools: [JSONValue] = [],
        toolConfig: JSONValue? = nil,
        cachedContentName: String? = nil
    ) -> JSONValue {
        var generateContentRequest: [String: JSONValue] = [
            "contents": .array(contents),
        ]
        if let systemInstruction {
            generateContentRequest["systemInstruction"] = systemInstruction
        }
        if !tools.isEmpty {
            generateContentRequest["tools"] = .array(tools)
        }
        if let toolConfig {
            generateContentRequest["toolConfig"] = toolConfig
        }
        if let cachedContentName, !cachedContentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            generateContentRequest["cachedContent"] = .string(cachedContentName)
        }
        return .object(["generateContentRequest": .object(generateContentRequest)])
    }

    func createBatch(modelID: ModelID, body: JSONValue) async throws -> ProviderBatchRecord {
        let response = try await service.batchGenerateContent(modelID: modelID, body: body)
        let record = try batchRecord(from: response.json, endpoint: "models/\(modelID.rawValue):batchGenerateContent")
        try await repositories.batches?.upsertProviderBatch(record)
        try await audit("Created Gemini batch operation \(record.id)", modelID: modelID)
        return record
    }

    func refreshBatch(operationName: String) async throws -> ProviderBatchRecord {
        let response = try await service.getOperation(operationName)
        let record = try batchRecord(from: response.json)
        try await repositories.batches?.upsertProviderBatch(record)
        return record
    }

    func cancelBatch(operationName: String) async throws -> ProviderBatchRecord {
        _ = try await service.cancelOperation(operationName)
        let record = try await refreshBatch(operationName: operationName)
        try await audit("Cancelled Gemini batch operation \(operationName)")
        return record
    }

    func importBatchOperation(_ operation: JSONValue) async throws -> ProviderBatchRecord {
        let record = try batchRecord(from: operation)
        try await repositories.batches?.upsertProviderBatch(record)
        try await audit("Imported Gemini batch operation \(record.id)")
        return record
    }

    func createGeneratedMediaOperation(
        modelID: ModelID,
        body: JSONValue,
        method: GeminiGeneratedMediaMethod = .generateVideos
    ) async throws -> ProviderArtifactRecord {
        let response: GeminiProviderResponse
        switch method {
        case .generateVideos:
            response = try await service.generateVideos(modelID: modelID, body: body)
        case .predict:
            response = try await service.predict(modelID: modelID, body: body)
        case .generateContent:
            response = try await service.generateContent(modelID: modelID, body: body)
        }
        let artifact = try await persistMediaOperationAndArtifacts(
            from: response.json,
            fallbackKind: method.artifactKind,
            modelID: modelID
        )
        try await audit("Created Gemini generated media \(method.rawValue)", modelID: modelID)
        return artifact
    }

    func refreshGeneratedMediaOperation(
        operationName: String,
        artifactKind: String = "media_operation"
    ) async throws -> ProviderArtifactRecord {
        let response = try await service.getOperation(operationName)
        return try await persistMediaOperationAndArtifacts(from: response.json, fallbackKind: artifactKind)
    }

    func cancelGeneratedMediaOperation(operationName: String) async throws -> ProviderArtifactRecord {
        _ = try await service.cancelOperation(operationName)
        let artifact = try await refreshGeneratedMediaOperation(operationName: operationName)
        try await audit("Cancelled Gemini generated media operation \(operationName)")
        return artifact
    }

    func importGeneratedMediaOperation(_ operation: JSONValue, artifactKind: String = "media_operation") async throws -> ProviderArtifactRecord {
        try await persistMediaOperationAndArtifacts(from: operation, fallbackKind: artifactKind)
    }

    func createGeneratedMediaArtifacts(
        modelID: ModelID,
        body: JSONValue,
        method: GeminiGeneratedMediaMethod = .predict
    ) async throws -> [ProviderArtifactRecord] {
        let response: GeminiProviderResponse
        switch method {
        case .generateVideos:
            response = try await service.generateVideos(modelID: modelID, body: body)
        case .predict:
            response = try await service.predict(modelID: modelID, body: body)
        case .generateContent:
            response = try await service.generateContent(modelID: modelID, body: body)
        }
        let records = GeminiProviderRecordMapper.generatedMediaArtifacts(
            from: response.json,
            providerID: providerID,
            responseID: GeminiProviderRecordMapper.operationName(from: response.json),
            defaultKind: method.artifactKind
        )
        for record in records {
            try await repositories.artifacts?.upsertProviderArtifact(record)
        }
        try await audit("Created \(records.count) Gemini media artifact(s)", modelID: modelID)
        return records
    }

    func createDeepResearchRun(_ request: GeminiDeepResearchRequest) async throws -> ProviderResearchRunRecord {
        let response = try await service.createInteraction(body: request.requestBody)
        var run = GeminiProviderRecordMapper.providerResearchRun(
            from: request,
            response: response.json,
            requestID: response.requestID
        )
        try await repositories.researchRuns?.upsertProviderResearchRun(run)
        if run.finalReportArtifactID == nil,
           let artifact = try await persistFinalReportArtifact(from: response.json, run: run) {
            run.finalReportArtifactID = artifact.id
            try await repositories.researchRuns?.upsertProviderResearchRun(run)
        }
        try await audit("Started Gemini Deep Research run \(run.title)", modelID: run.modelID)
        return run
    }

    func refreshDeepResearchRun(_ run: ProviderResearchRunRecord) async throws -> ProviderResearchRunRecord {
        let response = try await service.getInteraction(run.responseID ?? run.id)
        var updated = GeminiProviderRecordMapper.providerResearchRun(
            updating: run,
            response: response.json,
            requestID: response.requestID
        )
        if updated.finalReportArtifactID == nil,
           updated.status == "completed",
           let artifact = try await persistFinalReportArtifact(from: response.json, run: updated) {
            updated.finalReportArtifactID = artifact.id
        }
        try await repositories.researchRuns?.upsertProviderResearchRun(updated)
        return updated
    }

    func cancelDeepResearchRun(_ run: ProviderResearchRunRecord) async throws -> ProviderResearchRunRecord {
        let response = try await service.cancelInteraction(run.responseID ?? run.id)
        let updated = GeminiProviderRecordMapper.providerResearchRun(
            updating: run,
            response: response.json,
            requestID: response.requestID
        )
        try await repositories.researchRuns?.upsertProviderResearchRun(updated)
        try await audit("Cancelled Gemini Deep Research run \(run.title)", modelID: run.modelID)
        return updated
    }

    func refreshModelCapabilities(pageSize: Int? = 100, pageToken: String? = nil) async throws -> [ProviderModelCapabilityRecord] {
        let response = try await service.listModels(GeminiListRequest(pageSize: pageSize, pageToken: pageToken))
        let records = response.listValues(for: "models").compactMap {
            GeminiProviderRecordMapper.providerModelCapability(from: $0, providerID: providerID)
        }
        for record in records {
            try await repositories.modelCapabilities?.upsertProviderModelCapability(record)
        }
        try await audit("Refreshed \(records.count) Gemini model capabilities")
        return records
    }

    func refreshModelCapability(modelID: ModelID) async throws -> ProviderModelCapabilityRecord {
        let response = try await service.getModel(modelID.rawValue)
        guard let record = GeminiProviderRecordMapper.providerModelCapability(from: response.json ?? .object([:]), providerID: providerID) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.modelCapabilities?.upsertProviderModelCapability(record)
        return record
    }

    private func fileRecord(
        from json: JSONValue?,
        fallbackFileName: String? = nil,
        contentType: String? = nil,
        byteCount: Int? = nil
    ) -> ProviderFileRecord? {
        let value = json?.objectValue?["file"] ?? json
        guard var record = value.flatMap({ GeminiProviderRecordMapper.providerFile(from: $0, providerID: providerID) }) else {
            return nil
        }
        if let fallbackFileName, record.fileName == record.id {
            record.fileName = fallbackFileName
        }
        record.contentType = record.contentType ?? contentType
        if let byteCount, record.byteCount == 0 {
            record.byteCount = Int64(byteCount)
        }
        return record
    }

    private func cacheRecord(from json: JSONValue?) -> ProviderCacheRecord? {
        json.flatMap { GeminiProviderRecordMapper.providerCache(from: $0, providerID: providerID) }
    }

    private func batchRecord(from json: JSONValue?, endpoint: String = "batchGenerateContent") throws -> ProviderBatchRecord {
        guard let json,
              let record = GeminiProviderRecordMapper.providerBatch(fromOperation: json, providerID: providerID, endpoint: endpoint)
        else {
            throw CloudProviderError.invalidResponse
        }
        return record
    }

    private func persistMediaOperationAndArtifacts(
        from json: JSONValue?,
        fallbackKind: String,
        modelID: ModelID? = nil
    ) async throws -> ProviderArtifactRecord {
        guard let json,
              let operation = GeminiProviderRecordMapper.providerArtifact(fromOperation: json, providerID: providerID, kind: fallbackKind)
        else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.artifacts?.upsertProviderArtifact(operation)
        let artifacts = GeminiProviderRecordMapper.generatedMediaArtifacts(
            from: json,
            providerID: providerID,
            responseID: operation.responseID,
            defaultKind: fallbackKind
        )
        for artifact in artifacts {
            try await repositories.artifacts?.upsertProviderArtifact(artifact)
        }
        if !artifacts.isEmpty {
            try await audit("Imported \(artifacts.count) Gemini generated media artifact(s)", modelID: modelID)
        }
        return operation
    }

    private func persistFinalReportArtifact(from json: JSONValue?, run: ProviderResearchRunRecord) async throws -> ProviderArtifactRecord? {
        guard let report = GeminiProviderRecordMapper.deepResearchFinalOutputText(from: json), !report.isEmpty else { return nil }
        let artifact = ProviderArtifactRecord(
            id: "gemini-deep-research-report-\(run.id)",
            providerID: providerID,
            providerKind: .gemini,
            responseID: run.responseID,
            kind: "deep_research_report",
            fileName: "\(run.title.sanitizedGeminiArtifactFileStem).md",
            contentType: "text/markdown",
            text: report,
            content: json,
            createdAt: Date()
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        return artifact
    }

    private func normalizedResourceName(_ name: String, defaultCollection: String) -> String {
        let raw = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.contains("/") ? raw : "\(defaultCollection)/\(raw)"
    }

    private static func normalizedModelName(_ modelID: ModelID) -> String {
        let rawValue = modelID.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rawValue.hasPrefix("models/") ? rawValue : "models/\(rawValue)"
    }

    private func audit(_ summary: String, modelID: ModelID? = nil) async throws {
        try await repositories.audit?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: summary,
                providerID: providerID,
                modelID: modelID,
                networkDomains: ["generativelanguage.googleapis.com"]
            )
        )
    }
}

struct GeminiFilePolling: Sendable {
    var maxAttempts: Int
    var intervalNanoseconds: UInt64
    var onUpdate: (@Sendable (ProviderFileRecord) async -> Void)?

    init(
        maxAttempts: Int = 30,
        intervalNanoseconds: UInt64 = 1_000_000_000,
        onUpdate: (@Sendable (ProviderFileRecord) async -> Void)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.intervalNanoseconds = intervalNanoseconds
        self.onUpdate = onUpdate
    }
}

enum GeminiGeneratedMediaMethod: String, Sendable {
    case predict
    case generateVideos
    case generateContent

    var artifactKind: String {
        switch self {
        case .predict, .generateContent:
            "generated_media"
        case .generateVideos:
            "media_operation"
        }
    }
}

struct GeminiDeepResearchRequest: Sendable {
    var id: UUID
    var providerID: ProviderID
    var agentID: ModelID
    var title: String
    var prompt: String
    var depth: String
    var sourcePolicy: JSONValue
    var reportFormat: String
    var includeCodeInterpreter: Bool
    var serviceTier: String
    var metadata: [String: String]
    var previousInteractionID: String?
    var lastEventID: String?
    var background: Bool
    var store: Bool

    init(
        id: UUID = UUID(),
        providerID: ProviderID,
        agentID: ModelID,
        title: String,
        prompt: String,
        depth: String = "standard",
        sourcePolicy: JSONValue = .object([:]),
        reportFormat: String = "markdown",
        includeCodeInterpreter: Bool = false,
        serviceTier: String = "default",
        metadata: [String: String] = [:],
        previousInteractionID: String? = nil,
        lastEventID: String? = nil,
        background: Bool = true,
        store: Bool = true
    ) {
        self.id = id
        self.providerID = providerID
        self.agentID = agentID
        self.title = title
        self.prompt = prompt
        self.depth = depth
        self.sourcePolicy = sourcePolicy
        self.reportFormat = reportFormat
        self.includeCodeInterpreter = includeCodeInterpreter
        self.serviceTier = serviceTier
        self.metadata = metadata
        self.previousInteractionID = previousInteractionID
        self.lastEventID = lastEventID
        self.background = background
        self.store = store
    }

    func followUp(
        id: UUID = UUID(),
        title: String? = nil,
        prompt: String,
        previousInteractionID followUpInteractionID: String? = nil,
        previousEventID: String? = nil,
        metadata extraMetadata: [String: String] = [:]
    ) -> GeminiDeepResearchRequest {
        var mergedMetadata = metadata
        for (key, value) in extraMetadata {
            mergedMetadata[key] = value
        }
        return GeminiDeepResearchRequest(
            id: id,
            providerID: providerID,
            agentID: agentID,
            title: title ?? self.title,
            prompt: prompt,
            depth: depth,
            sourcePolicy: sourcePolicy,
            reportFormat: reportFormat,
            includeCodeInterpreter: includeCodeInterpreter,
            serviceTier: serviceTier,
            metadata: mergedMetadata,
            previousInteractionID: followUpInteractionID ?? previousInteractionID,
            lastEventID: previousEventID ?? lastEventID,
            background: background,
            store: store
        )
    }

    var requestBody: JSONValue {
        var requestMetadata = metadata
        requestMetadata["pines_run_type"] = "deep_research"
        requestMetadata["pines_research_request_id"] = id.uuidString
        requestMetadata["pines_research_depth"] = depth
        if let previousInteractionID, !previousInteractionID.isEmpty {
            requestMetadata["gemini.previous_interaction_id"] = previousInteractionID
        }
        if let lastEventID, !lastEventID.isEmpty {
            requestMetadata["gemini.last_event_id"] = lastEventID
        }

        var agentConfig: [String: JSONValue] = [
            "type": .string("deep-research"),
            "thinking_summaries": .string("auto"),
            "visualization": .string("auto"),
            "collaborative_planning": .bool(false),
            "depth": .string(depth),
            "report_format": .string(reportFormat),
            "source_policy": sourcePolicy,
        ]
        if includeCodeInterpreter {
            agentConfig["include_code_interpreter"] = .bool(true)
        }
        var fields: [String: JSONValue] = [
            "background": .bool(background),
            "stream": .bool(false),
            "store": .bool(store),
            "agent": .string(agentID.rawValue),
            "agent_config": .object(agentConfig),
            "input": .string(prompt),
            "metadata": .object(requestMetadata.reduce(into: [String: JSONValue]()) { result, item in
                result[item.key] = .string(item.value)
            }),
        ]
        if !serviceTier.isEmpty {
            fields["service_tier"] = .string(serviceTier)
        }
        if let previousInteractionID, !previousInteractionID.isEmpty {
            fields["previous_interaction_id"] = .string(previousInteractionID)
        }
        let tools = fileSearchTools(from: sourcePolicy)
        if !tools.isEmpty {
            fields["tools"] = .array(tools)
        }
        return .object(fields)
    }

    private func fileSearchTools(from sourcePolicy: JSONValue) -> [JSONValue] {
        guard let object = sourcePolicy.objectValue else { return [] }
        let storeNames = [
            "file_search_store_names",
            "fileSearchStoreNames",
            "vector_store_ids",
            "cached_content_ids",
        ]
            .flatMap { object.arrayStrings(for: $0) }
            .removingDuplicates()
        guard !storeNames.isEmpty else { return [] }
        return [
            .object([
                "type": .string("file_search"),
                "file_search_store_names": .array(storeNames.map(JSONValue.string)),
            ]),
        ]
    }
}

private extension ProviderFileRecord {
    var isTerminalGeminiFileStatus: Bool {
        switch status.lowercased() {
        case "completed", "active", "failed", "cancelled", "canceled":
            true
        default:
            false
        }
    }
}

private extension GeminiProviderResponse {
    func listValues(for key: String) -> [JSONValue] {
        guard let json else { return [] }
        if let value = json.objectValue?[key], case let .array(items) = value {
            return items
        }
        if case let .array(items) = json {
            return items
        }
        return [json]
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

    private func nestedValue(for keyPath: String) -> JSONValue? {
        var current: JSONValue? = .object(self)
        for component in keyPath.split(separator: ".").map(String.init) {
            guard case let .object(object) = current else { return nil }
            current = object[component]
        }
        return current
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func arrayStrings(for key: String) -> [String] {
        guard case let .array(values) = self[key] else { return [] }
        return values.compactMap(\.stringValue)
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value).inserted
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var sanitizedGeminiArtifactFileStem: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let stem = String(scalars).split(separator: "-").joined(separator: "-")
        return stem.isEmpty ? "gemini-artifact" : stem
    }
}
