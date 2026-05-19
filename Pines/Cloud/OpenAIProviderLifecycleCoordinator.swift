import Foundation
import PinesCore

struct OpenAIProviderLifecycleRepositories: Sendable {
    var files: (any ProviderFileRepository)?
    var artifacts: (any ProviderArtifactRepository)?
    var caches: (any ProviderCacheRepository)?
    var batches: (any ProviderBatchRepository)?
    var liveSessions: (any ProviderLiveSessionRepository)?
    var structuredOutputs: (any ProviderStructuredOutputRepository)?
    var modelCapabilities: (any ProviderModelCapabilityRepository)?
    var researchRuns: (any ProviderResearchRunRepository)?
    var audit: (any AuditEventRepository)?

    init(
        files: (any ProviderFileRepository)? = nil,
        artifacts: (any ProviderArtifactRepository)? = nil,
        caches: (any ProviderCacheRepository)? = nil,
        batches: (any ProviderBatchRepository)? = nil,
        liveSessions: (any ProviderLiveSessionRepository)? = nil,
        structuredOutputs: (any ProviderStructuredOutputRepository)? = nil,
        modelCapabilities: (any ProviderModelCapabilityRepository)? = nil,
        researchRuns: (any ProviderResearchRunRepository)? = nil,
        audit: (any AuditEventRepository)? = nil
    ) {
        self.files = files
        self.artifacts = artifacts
        self.caches = caches
        self.batches = batches
        self.liveSessions = liveSessions
        self.structuredOutputs = structuredOutputs
        self.modelCapabilities = modelCapabilities
        self.researchRuns = researchRuns
        self.audit = audit
    }
}

struct OpenAIProviderLifecycleCoordinator: Sendable {
    let service: OpenAIProviderService
    let repositories: OpenAIProviderLifecycleRepositories
    var artifactStore: OpenAIProviderArtifactStore = .default

    var providerID: ProviderID {
        service.configuration.id
    }

    func refreshFiles(purpose: String? = nil, limit: Int? = 100) async throws -> [ProviderFileRecord] {
        let response = try await service.listFiles(OpenAIFileListRequest(purpose: purpose, limit: limit))
        let records = response.listData.compactMap { OpenAIProviderRecordMapper.providerFile(from: $0, providerID: providerID) }
        for record in records {
            try await repositories.files?.upsertProviderFile(record)
        }
        try await audit("Refreshed \(records.count) OpenAI provider files")
        return records
    }

    func uploadFile(
        fileName: String,
        contentType: String,
        data: Data,
        purpose: String,
        localURL: URL? = nil,
        fields: [String: String] = [:]
    ) async throws -> ProviderFileRecord {
        let response = try await service.uploadFile(
            OpenAIFileUploadRequest(
                fileName: fileName,
                contentType: contentType,
                data: data,
                purpose: purpose,
                fields: fields
            )
        )
        guard var record = response.json.flatMap({ OpenAIProviderRecordMapper.providerFile(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        record.localURL = localURL
        record.contentType = record.contentType ?? contentType
        record.byteCount = record.byteCount == 0 ? Int64(data.count) : record.byteCount
        try await repositories.files?.upsertProviderFile(record)
        try await audit("Uploaded OpenAI provider file \(record.fileName)")
        return record
    }

    func deleteFile(id: String) async throws {
        _ = try await service.deleteFile(id)
        try await repositories.files?.deleteProviderFile(id: id)
        try await audit("Deleted OpenAI provider file \(id)")
    }

    func refreshVectorStores(limit: Int? = 100) async throws -> [ProviderCacheRecord] {
        let response = try await service.listVectorStores(OpenAIListRequest(limit: limit))
        let records = response.listData.compactMap { OpenAIProviderRecordMapper.providerCache(fromVectorStore: $0, providerID: providerID) }
        for record in records {
            try await repositories.caches?.upsertProviderCache(record)
        }
        try await audit("Refreshed \(records.count) OpenAI vector stores")
        return records
    }

    func createVectorStore(
        name: String?,
        description: String? = nil,
        fileIDs: [String] = [],
        expiresAfter: JSONValue? = nil,
        metadata: [String: String] = [:]
    ) async throws -> ProviderCacheRecord {
        let response = try await service.createVectorStore(
            OpenAIVectorStoreCreateRequest(
                name: name,
                description: description,
                fileIDs: fileIDs,
                expiresAfter: expiresAfter,
                metadata: metadata
            )
        )
        guard let record = response.json.flatMap({ OpenAIProviderRecordMapper.providerCache(fromVectorStore: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.caches?.upsertProviderCache(record)
        try await audit("Created OpenAI vector store \(record.name ?? record.id)")
        return record
    }

    func refreshVectorStore(id: String) async throws -> ProviderCacheRecord {
        let response = try await service.retrieveVectorStore(id)
        guard let record = response.json.flatMap({ OpenAIProviderRecordMapper.providerCache(fromVectorStore: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.caches?.upsertProviderCache(record)
        return record
    }

    func attachFile(_ fileID: String, toVectorStore vectorStoreID: String, attributes: JSONValue? = nil) async throws -> ProviderCacheRecord {
        _ = try await service.attachVectorStoreFile(vectorStoreID, fileID: fileID, attributes: attributes)
        let record = try await refreshVectorStore(id: vectorStoreID)
        try await audit("Attached OpenAI file \(fileID) to vector store \(vectorStoreID)")
        return record
    }

    func deleteVectorStore(id: String) async throws {
        _ = try await service.deleteVectorStore(id)
        try await repositories.caches?.deleteProviderCache(id: id)
        try await audit("Deleted OpenAI vector store \(id)")
    }

    func createBatch(
        inputFileID: String,
        endpoint: OpenAIBatchEndpoint,
        completionWindow: String = "24h",
        metadata: [String: String] = [:]
    ) async throws -> ProviderBatchRecord {
        let response = try await service.createBatch(
            OpenAIBatchCreateRequest(
                inputFileID: inputFileID,
                endpoint: endpoint.rawValue,
                completionWindow: completionWindow,
                metadata: metadata
            )
        )
        guard let record = response.json.flatMap({ OpenAIProviderRecordMapper.providerBatch(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.batches?.upsertProviderBatch(record)
        try await audit("Created OpenAI batch \(record.id)")
        return record
    }

    func refreshBatch(id: String) async throws -> ProviderBatchRecord {
        let response = try await service.retrieveBatch(id)
        guard let record = response.json.flatMap({ OpenAIProviderRecordMapper.providerBatch(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.batches?.upsertProviderBatch(record)
        return record
    }

    func cancelBatch(id: String) async throws -> ProviderBatchRecord {
        let response = try await service.cancelBatch(id)
        guard let record = response.json.flatMap({ OpenAIProviderRecordMapper.providerBatch(from: $0, providerID: providerID) }) else {
            throw CloudProviderError.invalidResponse
        }
        try await repositories.batches?.upsertProviderBatch(record)
        try await audit("Cancelled OpenAI batch \(record.id)")
        return record
    }

    func createDeepResearchRun(_ request: OpenAIDeepResearchRequest) async throws -> ProviderResearchRunRecord {
        let result = try await service.createDeepResearchRunRecord(request)
        try await repositories.researchRuns?.upsertProviderResearchRun(result.run)
        try await persistArtifacts(from: result.response, responseID: result.run.responseID, runID: result.run.id)
        try await audit("Started OpenAI Deep Research run \(result.run.title)", modelID: result.run.modelID)
        return result.run
    }

    func refreshDeepResearchRun(_ run: ProviderResearchRunRecord) async throws -> ProviderResearchRunRecord {
        let result = try await service.retrieveDeepResearchRunRecord(run)
        var updated = result.run
        if updated.status == OpenAIBackgroundResponseStatus.completed.rawValue,
           updated.finalReportArtifactID == nil,
           let artifact = try await persistFinalReportArtifact(from: result.response, run: updated) {
            updated.finalReportArtifactID = artifact.id
        }
        try await repositories.researchRuns?.upsertProviderResearchRun(updated)
        try await persistArtifacts(from: result.response, responseID: updated.responseID, runID: updated.id)
        return updated
    }

    func cancelDeepResearchRun(_ run: ProviderResearchRunRecord) async throws -> ProviderResearchRunRecord {
        let result = try await service.cancelDeepResearchRunRecord(run)
        try await repositories.researchRuns?.upsertProviderResearchRun(result.run)
        try await audit("Cancelled OpenAI Deep Research run \(result.run.title)", modelID: result.run.modelID)
        return result.run
    }

    func createRealtimeClientSecret(
        request: OpenAIRealtimeClientSecretRequest,
        modelID: ModelID,
        modalities: [String]
    ) async throws -> ProviderLiveSessionRecord {
        let response = try await service.createRealtimeClientSecret(request)
        let record = try await liveSessionRecord(from: response, fallbackModelID: modelID, modalities: modalities, storesSecret: true)
        try await repositories.liveSessions?.upsertProviderLiveSession(record)
        try await audit("Created OpenAI realtime client secret", modelID: modelID)
        return record
    }

    func createRealtimeSession(body: JSONValue, fallbackModelID: ModelID) async throws -> ProviderLiveSessionRecord {
        let response = try await service.createRealtimeSession(body: body)
        let record = try await liveSessionRecord(from: response, fallbackModelID: fallbackModelID, modalities: nil, storesSecret: false)
        try await repositories.liveSessions?.upsertProviderLiveSession(record)
        try await audit("Created OpenAI realtime session", modelID: record.modelID)
        return record
    }

    func createImageArtifacts(prompt: String, model: String? = nil, fields: [String: JSONValue] = [:]) async throws -> [ProviderArtifactRecord] {
        let response = try await service.createImage(OpenAIImageCreateRequest(prompt: prompt, model: model, rawFields: fields))
        let artifacts = artifactRecords(fromImageResponse: response, prompt: prompt)
        for artifact in artifacts {
            try await repositories.artifacts?.upsertProviderArtifact(artifact)
        }
        try await audit("Created \(artifacts.count) OpenAI image artifact(s)", modelID: model.map(ModelID.init(rawValue:)))
        return artifacts
    }

    func createVideoJob(prompt: String, model: String? = nil, fields: [String: JSONValue] = [:]) async throws -> ProviderArtifactRecord {
        let response = try await service.createVideo(OpenAIVideoCreateRequest(prompt: prompt, model: model, rawFields: fields))
        let artifact = artifactRecord(
            from: response.json,
            fallbackID: "video-\(UUID().uuidString)",
            kind: "video_job",
            fileName: nil,
            contentType: "application/json",
            text: prompt
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        try await audit("Created OpenAI video job", modelID: model.map(ModelID.init(rawValue:)))
        return artifact
    }

    func refreshVideoJob(id: String) async throws -> ProviderArtifactRecord {
        let response = try await service.retrieveVideo(id)
        let artifact = artifactRecord(
            from: response.json,
            fallbackID: id,
            kind: "video_job",
            fileName: nil,
            contentType: "application/json",
            text: response.json?.objectValue?.string(for: "status")
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        return artifact
    }

    func downloadVideoContent(videoID: String, variant: String = "content", contentType: String = "video/mp4") async throws -> ProviderArtifactRecord {
        let response = try await service.retrieveVideoContent(videoID)
        let fileName = "\(videoID)-\(variant).mp4"
        let localURL = try artifactStore.write(data: response.data, fileName: fileName)
        let artifact = ProviderArtifactRecord(
            id: "video-content-\(videoID)-\(variant)",
            providerID: providerID,
            providerKind: .openAI,
            providerFileID: videoID,
            kind: "video",
            fileName: fileName,
            contentType: contentType,
            byteCount: Int64(response.data.count),
            localURL: localURL
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        try await audit("Downloaded OpenAI video content \(videoID)")
        return artifact
    }

    func createSpeechArtifact(body: JSONValue, fileName: String = "speech.mp3", contentType: String = "audio/mpeg") async throws -> ProviderArtifactRecord {
        let response = try await service.createSpeech(body: body)
        let localURL = try artifactStore.write(data: response.data, fileName: uniqueArtifactFileName(fileName))
        let artifact = ProviderArtifactRecord(
            id: "audio-\(UUID().uuidString)",
            providerID: providerID,
            providerKind: .openAI,
            kind: "audio",
            fileName: localURL.lastPathComponent,
            contentType: contentType,
            byteCount: Int64(response.data.count),
            content: body,
            localURL: localURL
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        try await audit("Created OpenAI speech artifact")
        return artifact
    }

    func createTranscriptionArtifact(multipart: OpenAIMultipartForm) async throws -> ProviderArtifactRecord {
        let response = try await service.createTranscription(multipart: multipart)
        let artifact = transcriptArtifact(from: response, kind: "transcription")
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        try await audit("Created OpenAI transcription artifact")
        return artifact
    }

    func createTranslationArtifact(multipart: OpenAIMultipartForm) async throws -> ProviderArtifactRecord {
        let response = try await service.createTranslation(multipart: multipart)
        let artifact = transcriptArtifact(from: response, kind: "translation")
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        try await audit("Created OpenAI translation artifact")
        return artifact
    }

    private func persistArtifacts(from response: OpenAIProviderResponse, responseID: String?, runID: String?) async throws {
        let artifacts = artifactRecords(fromResponseOutput: response.json, responseID: responseID, runID: runID)
        for artifact in artifacts {
            try await repositories.artifacts?.upsertProviderArtifact(artifact)
        }
    }

    private func persistFinalReportArtifact(
        from response: OpenAIProviderResponse,
        run: ProviderResearchRunRecord
    ) async throws -> ProviderArtifactRecord? {
        guard let report = finalOutputText(from: response.json), !report.isEmpty else { return nil }
        let artifact = ProviderArtifactRecord(
            id: "deep-research-report-\(run.id)",
            providerID: providerID,
            providerKind: .openAI,
            responseID: run.responseID,
            kind: "deep_research_report",
            fileName: "\(run.title.sanitizedArtifactFileStem).md",
            contentType: "text/markdown",
            text: report,
            content: response.json,
            createdAt: Date()
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        return artifact
    }

    private func artifactRecords(fromImageResponse response: OpenAIProviderResponse, prompt: String) -> [ProviderArtifactRecord] {
        response.listData.enumerated().map { index, value in
            let fields = value.objectValue ?? [:]
            let remoteURL = fields.string(for: "url").flatMap(URL.init(string:))
            let revisedPrompt = fields.string(for: "revised_prompt") ?? prompt
            return ProviderArtifactRecord(
                id: fields.string(for: "id") ?? "image-\(UUID().uuidString)-\(index)",
                providerID: providerID,
                providerKind: .openAI,
                kind: "image",
                fileName: remoteURL?.lastPathComponent,
                contentType: "image/png",
                text: revisedPrompt,
                content: value,
                remoteURL: remoteURL
            )
        }
    }

    private func artifactRecords(fromResponseOutput json: JSONValue?, responseID: String?, runID: String?) -> [ProviderArtifactRecord] {
        var artifacts = [ProviderArtifactRecord]()
        collectArtifactRecords(in: json, responseID: responseID, runID: runID, into: &artifacts)
        return artifacts
    }

    private func collectArtifactRecords(
        in value: JSONValue?,
        responseID: String?,
        runID: String?,
        into artifacts: inout [ProviderArtifactRecord]
    ) {
        switch value {
        case let .object(object):
            if let artifact = artifactRecordFromOutputObject(object, responseID: responseID, runID: runID) {
                artifacts.append(artifact)
            }
            object.values.forEach { collectArtifactRecords(in: $0, responseID: responseID, runID: runID, into: &artifacts) }
        case let .array(values):
            values.forEach { collectArtifactRecords(in: $0, responseID: responseID, runID: runID, into: &artifacts) }
        case .string, .number, .bool, .null, nil:
            break
        }
    }

    private func artifactRecordFromOutputObject(
        _ object: [String: JSONValue],
        responseID: String?,
        runID: String?
    ) -> ProviderArtifactRecord? {
        let type = object.string(for: "type") ?? ""
        if type == "container_file_citation" || type == "file_citation" {
            let fileID = object.string(for: "file_id")
            return ProviderArtifactRecord(
                id: object.string(for: "id") ?? "file-citation-\(fileID ?? UUID().uuidString)",
                providerID: providerID,
                providerKind: .openAI,
                responseID: responseID,
                toolCallID: object.string(for: "tool_call_id"),
                providerFileID: fileID,
                kind: "generated_file",
                fileName: object.string(for: "filename"),
                contentType: object.string(for: "content_type"),
                text: object.string(for: "quote"),
                content: .object(object)
            )
        }
        if type == "image_generation_call" || type == "image_generation" {
            return ProviderArtifactRecord(
                id: object.string(for: "id") ?? "image-call-\(UUID().uuidString)",
                providerID: providerID,
                providerKind: .openAI,
                responseID: responseID,
                toolCallID: object.string(for: "call_id"),
                kind: "image",
                fileName: object.string(for: "filename"),
                contentType: object.string(for: "content_type") ?? "image/png",
                text: object.string(for: "revised_prompt"),
                content: .object(object)
            )
        }
        if type == "web_search_call" || type == "file_search_call" || type == "code_interpreter_call" {
            return ProviderArtifactRecord(
                id: object.string(for: "id") ?? "\(type)-\(UUID().uuidString)",
                providerID: providerID,
                providerKind: .openAI,
                responseID: responseID,
                toolCallID: object.string(for: "call_id"),
                kind: "hosted_tool_call",
                text: object.string(for: "status"),
                content: .object(object)
            )
        }
        if let runID, type == "message", object["content"] != nil {
            return ProviderArtifactRecord(
                id: "deep-research-output-\(runID)",
                providerID: providerID,
                providerKind: .openAI,
                responseID: responseID,
                kind: "deep_research_output",
                text: finalOutputText(from: .object(object)),
                content: .object(object)
            )
        }
        return nil
    }

    private func artifactRecord(
        from json: JSONValue?,
        fallbackID: String,
        kind: String,
        fileName: String?,
        contentType: String?,
        text: String?
    ) -> ProviderArtifactRecord {
        let fields = json?.objectValue ?? [:]
        return ProviderArtifactRecord(
            id: fields.string(for: "id") ?? fallbackID,
            providerID: providerID,
            providerKind: .openAI,
            providerFileID: fields.string(for: "id"),
            kind: kind,
            fileName: fileName,
            contentType: contentType,
            text: text,
            content: json,
            remoteURL: fields.string(for: "url").flatMap(URL.init(string:))
        )
    }

    private func transcriptArtifact(from response: OpenAIProviderResponse, kind: String) -> ProviderArtifactRecord {
        let text = response.json?.objectValue?.string(for: "text")
            ?? String(data: response.data, encoding: .utf8)
        return ProviderArtifactRecord(
            id: "\(kind)-\(UUID().uuidString)",
            providerID: providerID,
            providerKind: .openAI,
            kind: kind,
            fileName: "\(kind).txt",
            contentType: "text/plain",
            byteCount: Int64(response.data.count),
            text: text,
            content: response.json
        )
    }

    private func liveSessionRecord(
        from response: OpenAIProviderResponse,
        fallbackModelID: ModelID,
        modalities: [String]?,
        storesSecret: Bool
    ) async throws -> ProviderLiveSessionRecord {
        let json = response.json
        let fields = json?.objectValue ?? [:]
        let secretValue = fields.string(for: "client_secret.value")
        let session = fields["session"]?.objectValue
        let sessionID = fields.string(for: "id") ?? session?.string(for: "id") ?? "realtime-\(UUID().uuidString)"
        var credentialAccount: String?
        if storesSecret, let secretValue {
            credentialAccount = "openai-realtime-\(providerID.rawValue)-\(sessionID)"
            try await service.secretStore.write(secretValue, service: service.configuration.keychainService, account: credentialAccount!)
        }
        let model = fields.string(for: "model")
            ?? session?.string(for: "model")
            ?? fallbackModelID.rawValue
        let resolvedModalities = modalities
            ?? fields.arrayStrings(for: "modalities")
            ?? session?.arrayStrings(for: "modalities")
            ?? []
        return ProviderLiveSessionRecord(
            id: sessionID,
            providerID: providerID,
            providerKind: .openAI,
            modelID: ModelID(rawValue: model),
            status: fields.string(for: "status") ?? session?.string(for: "status") ?? OpenAIRealtimeSessionStatus.created.rawValue,
            modalities: resolvedModalities,
            credentialKeychainAccount: credentialAccount,
            expiresAt: OpenAIProviderLifecycleCoordinator.date(from: fields["expires_at"] ?? fields["expires"]),
            providerMetadata: [
                "request_id": response.requestID,
                "stores_client_secret": storesSecret ? "true" : "false",
            ].compactMapValues { $0 },
            createdAt: OpenAIProviderLifecycleCoordinator.date(from: fields["created_at"]) ?? Date(),
            lastError: fields.string(for: "error")
        )
    }

    private func finalOutputText(from json: JSONValue?) -> String? {
        switch json {
        case let .object(object):
            if let outputText = object.string(for: "output_text"), !outputText.isEmpty {
                return outputText
            }
            if let text = object.string(for: "text"), !text.isEmpty {
                return text
            }
            if let content = object["content"] {
                return finalOutputText(from: content)
            }
            if let output = object["output"] {
                return finalOutputText(from: output)
            }
            return object.values.compactMap(finalOutputText(from:)).joined(separator: "\n\n").nilIfEmpty
        case let .array(values):
            return values.compactMap(finalOutputText(from:)).joined(separator: "\n\n").nilIfEmpty
        case let .string(value):
            return value
        case .number, .bool, .null, nil:
            return nil
        }
    }

    private func uniqueArtifactFileName(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let stem = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        if pathExtension.isEmpty {
            return "\(stem)-\(UUID().uuidString)"
        }
        return "\(stem)-\(UUID().uuidString).\(pathExtension)"
    }

    private func audit(_ summary: String, modelID: ModelID? = nil) async throws {
        try await repositories.audit?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: summary,
                providerID: providerID,
                modelID: modelID,
                networkDomains: ["api.openai.com"]
            )
        )
    }
}

struct OpenAIProviderArtifactStore: Sendable {
    var rootDirectory: URL

    static var `default`: OpenAIProviderArtifactStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "OpenAIProviderArtifacts", directoryHint: .isDirectory)
            ?? FileManager.default.temporaryDirectory.appending(path: "OpenAIProviderArtifacts", directoryHint: .isDirectory)
        return OpenAIProviderArtifactStore(rootDirectory: root)
    }

    func write(data: Data, fileName: String) throws -> URL {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let url = rootDirectory.appending(path: fileName)
        try data.write(to: url, options: .atomic)
        return url
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

private extension [String: JSONValue] {
    func string(for key: String) -> String? {
        if key.contains(".") {
            return nestedValue(for: key)?.stringValue
        }
        return self[key]?.stringValue
    }

    func arrayStrings(for key: String) -> [String]? {
        guard let value = self[key], case let .array(values) = value else { return nil }
        return values.compactMap(\.stringValue)
    }

    private func nestedValue(for key: String) -> JSONValue? {
        key.split(separator: ".").reduce(nil as JSONValue?) { current, segment in
            let object: [String: JSONValue]?
            if let current {
                object = current.objectValue
            } else {
                object = self
            }
            return object?[String(segment)]
        }
    }
}

private extension OpenAIProviderLifecycleCoordinator {
    static func date(from value: JSONValue?) -> Date? {
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var sanitizedArtifactFileStem: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let stem = String(scalars).split(separator: "-").joined(separator: "-")
        return stem.isEmpty ? "openai-artifact" : stem
    }
}
