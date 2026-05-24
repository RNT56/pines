import Foundation
import PinesCore
import UniformTypeIdentifiers

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
        _ = try await persistArtifacts(from: result.response, responseID: result.run.responseID, runID: result.run.id)
        try await audit("Started OpenAI Deep Research run \(result.run.title)", modelID: result.run.modelID)
        return result.run
    }

    func refreshDeepResearchRun(_ run: ProviderResearchRunRecord) async throws -> ProviderResearchRunRecord {
        let result = try await service.retrieveDeepResearchRunRecord(run)
        var updated = result.run
        let responseArtifacts = try await persistArtifacts(from: result.response, responseID: updated.responseID, runID: updated.id)
        if updated.status == OpenAIBackgroundResponseStatus.completed.rawValue, updated.finalReportArtifactID == nil {
            if let outputArtifact = responseArtifacts.first(where: { $0.kind == "deep_research_output" && ($0.text?.isEmpty == false) }) {
                updated.finalReportArtifactID = outputArtifact.id
            } else if let artifact = try await persistFinalReportArtifact(from: result.response, run: updated) {
                updated.finalReportArtifactID = artifact.id
            }
        }
        try await repositories.researchRuns?.upsertProviderResearchRun(updated)
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
        let artifacts = try artifactRecords(fromImageResponse: response, prompt: prompt)
        for artifact in artifacts {
            try await repositories.artifacts?.upsertProviderArtifact(artifact)
        }
        try await audit("Created \(artifacts.count) OpenAI image artifact(s)", modelID: model.map(ModelID.init(rawValue:)))
        return artifacts
    }

    func createImageEditArtifacts(
        prompt: String,
        model: String? = nil,
        reference: ProviderArtifactRecord,
        fields: [String: JSONValue] = [:]
    ) async throws -> [ProviderArtifactRecord] {
        let imageFile = try await referenceImageFile(from: reference)
        var multipartFields = Self.multipartFields(from: fields)
        multipartFields["prompt"] = prompt
        multipartFields["model"] = model ?? multipartFields["model"] ?? "gpt-image-2"

        let response = try await service.createImageEdit(
            multipart: OpenAIMultipartForm(fields: multipartFields, files: [imageFile])
        )
        let artifacts = try artifactRecords(fromImageResponse: response, prompt: prompt).map { artifact in
            annotatedRemixArtifact(
                artifact,
                reference: reference,
                prompt: prompt,
                model: multipartFields["model"],
                options: fields
            )
        }
        for artifact in artifacts {
            try await repositories.artifacts?.upsertProviderArtifact(artifact)
        }
        try await audit("Created \(artifacts.count) OpenAI image remix artifact(s)", modelID: multipartFields["model"].map(ModelID.init(rawValue:)))
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

    @discardableResult
    private func persistArtifacts(from response: OpenAIProviderResponse, responseID: String?, runID: String?) async throws -> [ProviderArtifactRecord] {
        let artifacts = artifactRecords(fromResponseOutput: response.json, responseID: responseID, runID: runID)
        for artifact in artifacts {
            try await repositories.artifacts?.upsertProviderArtifact(artifact)
        }
        return artifacts
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

    private func artifactRecords(fromImageResponse response: OpenAIProviderResponse, prompt: String) throws -> [ProviderArtifactRecord] {
        try response.listData.enumerated().map { index, value in
            let fields = value.objectValue ?? [:]
            let remoteURL = fields.string(for: "url").flatMap(URL.init(string:))
            let imageData = fields.string(for: "b64_json").flatMap { Data(base64Encoded: $0, options: [.ignoreUnknownCharacters]) }
            let localURL = try imageData.map { data in
                try artifactStore.write(data: data, fileName: uniqueArtifactFileName("image-\(UUID().uuidString).png"))
            }
            let revisedPrompt = fields.string(for: "revised_prompt") ?? prompt
            return ProviderArtifactRecord(
                id: fields.string(for: "id") ?? "image-\(UUID().uuidString)-\(index)",
                providerID: providerID,
                providerKind: .openAI,
                kind: "image",
                fileName: localURL?.lastPathComponent ?? remoteURL?.lastPathComponent,
                contentType: "image/png",
                byteCount: imageData.map { Int64($0.count) } ?? 0,
                text: revisedPrompt,
                content: value,
                localURL: localURL,
                remoteURL: remoteURL
            )
        }
    }

    private func referenceImageFile(from artifact: ProviderArtifactRecord) async throws -> OpenAIMultipartFile {
        if let localURL = artifact.localURL,
           localURL.isFileURL,
           FileManager.default.fileExists(atPath: localURL.path) {
            let data = try Data(contentsOf: localURL)
            guard !data.isEmpty else {
                throw InferenceError.invalidRequest("Reference image \(artifact.fileName ?? artifact.id) is empty.")
            }
            return OpenAIMultipartFile(
                name: "image[]",
                fileName: Self.safeMultipartFileName(artifact.fileName ?? localURL.lastPathComponent, fallbackExtension: localURL.pathExtension),
                contentType: Self.imageContentType(for: artifact, fileName: localURL.lastPathComponent),
                data: data
            )
        }

        if let data = artifact.content.flatMap(Self.firstBase64ImageData(in:)) {
            return OpenAIMultipartFile(
                name: "image[]",
                fileName: Self.safeMultipartFileName(artifact.fileName ?? "reference.png", fallbackExtension: "png"),
                contentType: Self.imageContentType(for: artifact, fileName: artifact.fileName),
                data: data
            )
        }

        if let remoteURL = artifact.remoteURL {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard !data.isEmpty else {
                throw InferenceError.invalidRequest("Reference image \(artifact.fileName ?? artifact.id) could not be downloaded.")
            }
            let responseContentType = response.mimeType?.hasPrefix("image/") == true ? response.mimeType : nil
            return OpenAIMultipartFile(
                name: "image[]",
                fileName: Self.safeMultipartFileName(artifact.fileName ?? remoteURL.lastPathComponent, fallbackExtension: remoteURL.pathExtension),
                contentType: responseContentType ?? Self.imageContentType(for: artifact, fileName: remoteURL.lastPathComponent),
                data: data
            )
        }

        throw InferenceError.invalidRequest("Reference image \(artifact.fileName ?? artifact.id) has no local file, remote URL, or embedded image data.")
    }

    private func annotatedRemixArtifact(
        _ artifact: ProviderArtifactRecord,
        reference: ProviderArtifactRecord,
        prompt: String,
        model: String?,
        options: [String: JSONValue]
    ) -> ProviderArtifactRecord {
        var updated = artifact
        var metadata: [String: JSONValue] = [
            "source_artifact_id": .string(reference.id),
            "prompt": .string(prompt),
            "mode": .string("image_remix"),
            "provider": .string("openai"),
        ]
        if let model, !model.isEmpty {
            metadata["model"] = .string(model)
        }
        if !options.isEmpty {
            metadata["options"] = .object(options)
        }

        var content = artifact.content?.objectValue ?? [:]
        if content.isEmpty, let original = artifact.content {
            content["provider_response"] = original
        }
        content["pines_remix"] = .object(metadata)
        updated.content = .object(content)
        updated.text = artifact.text ?? prompt
        return updated
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
            guard let text = finalOutputText(from: .object(object)), !text.isEmpty else {
                return nil
            }
            return ProviderArtifactRecord(
                id: "deep-research-output-\(runID)",
                providerID: providerID,
                providerKind: .openAI,
                responseID: responseID,
                kind: "deep_research_output",
                fileName: "Final report.md",
                contentType: "text/markdown",
                text: text,
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
            if let type = object.string(for: "type"),
               ["reasoning", "web_search_call", "file_search_call", "code_interpreter_call", "image_generation_call", "function_call", "computer_call"].contains(type) {
                return nil
            }
            if let outputText = object.string(for: "output_text"), !outputText.isEmpty {
                return outputText
            }
            if let type = object.string(for: "type"),
               ["output_text", "text", "message"].contains(type),
               let text = object.string(for: "text"),
               !text.isEmpty {
                return text
            }
            if object.string(for: "type") == "message", let content = object["content"] {
                return finalOutputText(from: content)
            }
            if let output = object["output"] {
                return finalOutputText(from: output)
            }
            return nil
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

    static func multipartFields(from fields: [String: JSONValue]) -> [String: String] {
        fields.compactMapValues { value in
            switch value {
            case .string(let string):
                string
            case .number(let number):
                number.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(number)) : String(number)
            case .bool(let bool):
                bool ? "true" : "false"
            case .object, .array, .null:
                nil
            }
        }
    }

    static func imageContentType(for artifact: ProviderArtifactRecord, fileName: String?) -> String {
        if let contentType = artifact.contentType?.lowercased(), contentType.hasPrefix("image/") {
            return contentType
        }
        if let fileName,
           let contentType = UTType(filenameExtension: URL(fileURLWithPath: fileName).pathExtension)?.preferredMIMEType,
           contentType.hasPrefix("image/") {
            return contentType
        }
        return "image/png"
    }

    static func safeMultipartFileName(_ rawName: String, fallbackExtension: String?) -> String {
        let sanitized = rawName
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        var fileName = sanitized.isEmpty ? "reference" : sanitized
        if URL(fileURLWithPath: fileName).pathExtension.isEmpty {
            let fallback = fallbackExtension?.trimmingCharacters(in: CharacterSet(charactersIn: ".")).nilIfEmpty ?? "png"
            fileName += ".\(fallback)"
        }
        return fileName
    }

    static func firstBase64ImageData(in value: JSONValue) -> Data? {
        switch value {
        case .object(let object):
            for key in ["b64_json", "base64", "image_base64", "result"] {
                if let data = object[key]?.stringValue.flatMap(decodedBase64ImageData(from:)) {
                    return data
                }
            }
            for nested in object.values {
                if let data = firstBase64ImageData(in: nested) {
                    return data
                }
            }
            return nil
        case .array(let values):
            for nested in values {
                if let data = firstBase64ImageData(in: nested) {
                    return data
                }
            }
            return nil
        case .string(let raw):
            return decodedBase64ImageData(from: raw)
        case .number, .bool, .null:
            return nil
        }
    }

    static func decodedBase64ImageData(from raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64: String
        if let comma = trimmed.firstIndex(of: ","),
           trimmed[..<comma].lowercased().contains("base64") {
            base64 = String(trimmed[trimmed.index(after: comma)...])
        } else {
            base64 = trimmed
        }
        guard base64.count > 128,
              let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]),
              !data.isEmpty
        else {
            return nil
        }
        return data
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
