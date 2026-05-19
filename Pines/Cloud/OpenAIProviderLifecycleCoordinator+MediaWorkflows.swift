import Foundation
import PinesCore

struct OpenAISpeechArtifactRequest: Sendable {
    var model: String
    var input: String
    var voice: String
    var responseFormat: String?
    var speed: Double?
    var fileName: String?
    var rawFields: [String: JSONValue]

    init(
        model: String,
        input: String,
        voice: String,
        responseFormat: String? = nil,
        speed: Double? = nil,
        fileName: String? = nil,
        rawFields: [String: JSONValue] = [:]
    ) {
        self.model = model
        self.input = input
        self.voice = voice
        self.responseFormat = responseFormat
        self.speed = speed
        self.fileName = fileName
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        fields["model"] = .string(model)
        fields["input"] = .string(input)
        fields["voice"] = .string(voice)
        if let responseFormat {
            fields["response_format"] = .string(responseFormat)
        }
        if let speed {
            fields["speed"] = .number(speed)
        }
        return .object(fields)
    }

    var resolvedFileName: String {
        fileName ?? "speech.\(responseFormat ?? "mp3")"
    }

    var contentType: String {
        switch responseFormat {
        case "wav":
            "audio/wav"
        case "opus":
            "audio/ogg; codecs=opus"
        case "aac":
            "audio/aac"
        case "flac":
            "audio/flac"
        case "pcm":
            "audio/L16"
        default:
            "audio/mpeg"
        }
    }
}

struct OpenAIAudioFileArtifactRequest: Sendable {
    var fileName: String
    var contentType: String
    var data: Data
    var model: String
    var language: String?
    var prompt: String?
    var responseFormat: String?
    var temperature: Double?
    var timestampGranularities: [String]
    var fields: [String: String]

    init(
        fileName: String,
        contentType: String,
        data: Data,
        model: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: Double? = nil,
        timestampGranularities: [String] = [],
        fields: [String: String] = [:]
    ) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
        self.model = model
        self.language = language
        self.prompt = prompt
        self.responseFormat = responseFormat
        self.temperature = temperature
        self.timestampGranularities = timestampGranularities
        self.fields = fields
    }

    var multipart: OpenAIMultipartForm {
        var resolvedFields = fields
        resolvedFields["model"] = model
        if let language {
            resolvedFields["language"] = language
        }
        if let prompt {
            resolvedFields["prompt"] = prompt
        }
        if let responseFormat {
            resolvedFields["response_format"] = responseFormat
        }
        if let temperature {
            resolvedFields["temperature"] = String(temperature)
        }
        for granularity in timestampGranularities {
            resolvedFields["timestamp_granularities[]"] = granularity
        }
        return OpenAIMultipartForm(
            fields: resolvedFields,
            files: [
                OpenAIMultipartFile(name: "file", fileName: fileName, contentType: contentType, data: data),
            ]
        )
    }
}

struct OpenAIVideoArtifactRequest: Sendable {
    var prompt: String
    var model: String?
    var fields: [String: JSONValue]

    init(prompt: String, model: String? = nil, fields: [String: JSONValue] = [:]) {
        self.prompt = prompt
        self.model = model
        self.fields = fields
    }
}

struct OpenAIRealtimeSessionWorkflowRequest: Sendable {
    enum Kind: Sendable {
        case clientSecret(OpenAIRealtimeClientSecretRequest, modalities: [String])
        case translationClientSecret(body: JSONValue)
        case session(body: JSONValue)
        case transcriptionSession(body: JSONValue)
    }

    var kind: Kind
    var fallbackModelID: ModelID

    init(kind: Kind, fallbackModelID: ModelID) {
        self.kind = kind
        self.fallbackModelID = fallbackModelID
    }
}

extension OpenAIProviderService {
    func cancelVideo(_ videoID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "videos/\(videoID)/cancel")
    }

    func deleteVideo(_ videoID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .delete, path: "videos/\(videoID)")
    }
}

extension OpenAIProviderLifecycleCoordinator {
    func createSpeechArtifact(_ request: OpenAISpeechArtifactRequest) async throws -> ProviderArtifactRecord {
        try await createSpeechArtifact(
            body: request.body,
            fileName: request.resolvedFileName,
            contentType: request.contentType
        )
    }

    func createTranscriptionArtifact(_ request: OpenAIAudioFileArtifactRequest) async throws -> ProviderArtifactRecord {
        try await createTranscriptionArtifact(multipart: request.multipart)
    }

    func createTranslationArtifact(_ request: OpenAIAudioFileArtifactRequest) async throws -> ProviderArtifactRecord {
        try await createTranslationArtifact(multipart: request.multipart)
    }

    func createRealtimeSessionRecord(_ request: OpenAIRealtimeSessionWorkflowRequest) async throws -> ProviderLiveSessionRecord {
        switch request.kind {
        case let .clientSecret(secretRequest, modalities):
            return try await createRealtimeClientSecret(
                request: secretRequest,
                modelID: request.fallbackModelID,
                modalities: modalities
            )
        case let .translationClientSecret(body):
            let response = try await service.createRealtimeTranslationClientSecret(body: body)
            let record = try await providerLiveSessionRecord(
                from: response,
                fallbackModelID: request.fallbackModelID,
                modalities: ["audio", "translation"],
                storesSecret: true
            )
            try await repositories.liveSessions?.upsertProviderLiveSession(record)
            try await auditMediaWorkflow("Created OpenAI realtime translation client secret", modelID: request.fallbackModelID)
            return record
        case let .session(body):
            return try await createRealtimeSession(body: body, fallbackModelID: request.fallbackModelID)
        case let .transcriptionSession(body):
            let response = try await service.createRealtimeTranscriptionSession(body: body)
            let record = try await providerLiveSessionRecord(
                from: response,
                fallbackModelID: request.fallbackModelID,
                modalities: ["audio", "transcription"],
                storesSecret: false
            )
            try await repositories.liveSessions?.upsertProviderLiveSession(record)
            try await auditMediaWorkflow("Created OpenAI realtime transcription session", modelID: record.modelID)
            return record
        }
    }

    func createVideoArtifact(_ request: OpenAIVideoArtifactRequest) async throws -> ProviderArtifactRecord {
        try await createVideoJob(prompt: request.prompt, model: request.model, fields: request.fields)
    }

    func cancelVideoArtifact(id: String) async throws -> ProviderArtifactRecord {
        let response = try await service.cancelVideo(id)
        let artifact = videoArtifactRecord(from: response.json, fallbackID: id, text: "cancelled")
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        try await auditMediaWorkflow("Cancelled OpenAI video \(id)")
        return artifact
    }

    func deleteVideoArtifact(id: String) async throws {
        _ = try await service.deleteVideo(id)
        try await repositories.artifacts?.deleteProviderArtifact(id: id)
        try await repositories.artifacts?.deleteProviderArtifact(id: "video-content-\(id)-content")
        try await auditMediaWorkflow("Deleted OpenAI video \(id)")
    }

    @discardableResult
    func importBatchResultArtifacts(id: String) async throws -> [ProviderArtifactRecord] {
        let batch = try await refreshBatch(id: id)
        var artifacts = [ProviderArtifactRecord]()
        if let outputFileID = batch.outputFileID {
            let artifact = try await importBatchFileArtifact(
                batchID: batch.id,
                fileID: outputFileID,
                role: "output",
                contentType: "application/x-ndjson"
            )
            artifacts.append(artifact)
        }
        if let errorFileID = batch.errorFileID {
            let artifact = try await importBatchFileArtifact(
                batchID: batch.id,
                fileID: errorFileID,
                role: "error",
                contentType: "application/x-ndjson"
            )
            artifacts.append(artifact)
        }
        try await auditMediaWorkflow("Imported \(artifacts.count) OpenAI batch result artifact(s)")
        return artifacts
    }

    func createBatchFromJSONL(
        fileName: String,
        data: Data,
        endpoint: OpenAIBatchEndpoint,
        completionWindow: String = "24h",
        metadata: [String: String] = [:]
    ) async throws -> ProviderBatchRecord {
        let file = try await uploadFile(
            fileName: fileName,
            contentType: "application/x-ndjson",
            data: data,
            purpose: "batch"
        )
        return try await createBatch(
            inputFileID: file.id,
            endpoint: endpoint,
            completionWindow: completionWindow,
            metadata: metadata
        )
    }

    private func importBatchFileArtifact(
        batchID: String,
        fileID: String,
        role: String,
        contentType: String
    ) async throws -> ProviderArtifactRecord {
        let response = try await service.retrieveFileContent(fileID)
        let fileName = "\(batchID)-\(role).jsonl"
        let localURL = try artifactStore.write(data: response.data, fileName: fileName)
        let artifact = ProviderArtifactRecord(
            id: "batch-\(batchID)-\(role)-\(fileID)",
            providerID: providerID,
            providerKind: .openAI,
            providerFileID: fileID,
            kind: "batch_\(role)",
            fileName: fileName,
            contentType: contentType,
            byteCount: Int64(response.data.count),
            text: String(data: Data(response.data.prefix(4096)), encoding: .utf8),
            content: .object([
                "batch_id": .string(batchID),
                "file_id": .string(fileID),
                "role": .string(role),
                "request_id": response.requestID.map(JSONValue.string) ?? .null,
            ]),
            localURL: localURL
        )
        try await repositories.artifacts?.upsertProviderArtifact(artifact)
        return artifact
    }

    private func videoArtifactRecord(from json: JSONValue?, fallbackID: String, text: String?) -> ProviderArtifactRecord {
        let fields = json?.objectValue ?? [:]
        let id = fields.string(forMediaWorkflowKey: "id") ?? fallbackID
        return ProviderArtifactRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            providerFileID: id,
            kind: "video_job",
            contentType: "application/json",
            text: fields.string(forMediaWorkflowKey: "status") ?? text,
            content: json,
            remoteURL: fields.string(forMediaWorkflowKey: "url").flatMap(URL.init(string:))
        )
    }

    private func providerLiveSessionRecord(
        from response: OpenAIProviderResponse,
        fallbackModelID: ModelID,
        modalities: [String],
        storesSecret: Bool
    ) async throws -> ProviderLiveSessionRecord {
        let fields = response.json?.objectValue ?? [:]
        let session = fields["session"]?.objectValue
        let sessionID = fields.string(forMediaWorkflowKey: "id")
            ?? session?.string(forMediaWorkflowKey: "id")
            ?? "realtime-\(UUID().uuidString)"
        var credentialAccount: String?
        if storesSecret, let secretValue = fields.string(forMediaWorkflowKey: "client_secret.value") {
            credentialAccount = "openai-realtime-\(providerID.rawValue)-\(sessionID)"
            try await service.secretStore.write(secretValue, service: service.configuration.keychainService, account: credentialAccount!)
        }
        let model = fields.string(forMediaWorkflowKey: "model")
            ?? session?.string(forMediaWorkflowKey: "model")
            ?? fallbackModelID.rawValue
        return ProviderLiveSessionRecord(
            id: sessionID,
            providerID: providerID,
            providerKind: .openAI,
            modelID: ModelID(rawValue: model),
            status: fields.string(forMediaWorkflowKey: "status")
                ?? session?.string(forMediaWorkflowKey: "status")
                ?? OpenAIRealtimeSessionStatus.created.rawValue,
            modalities: fields.arrayStrings(forMediaWorkflowKey: "modalities")
                ?? session?.arrayStrings(forMediaWorkflowKey: "modalities")
                ?? modalities,
            credentialKeychainAccount: credentialAccount,
            expiresAt: Self.mediaWorkflowDate(from: fields["expires_at"] ?? fields["expires"]),
            providerMetadata: [
                "request_id": response.requestID,
                "stores_client_secret": storesSecret ? "true" : "false",
            ].compactMapValues { $0 },
            createdAt: Self.mediaWorkflowDate(from: fields["created_at"]) ?? Date(),
            lastError: fields.string(forMediaWorkflowKey: "error")
        )
    }

    private func auditMediaWorkflow(_ summary: String, modelID: ModelID? = nil) async throws {
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

    private static func mediaWorkflowDate(from value: JSONValue?) -> Date? {
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

private extension [String: JSONValue] {
    func string(forMediaWorkflowKey key: String) -> String? {
        if key.contains(".") {
            return nestedMediaWorkflowValue(for: key)?.stringValue
        }
        return self[key]?.stringValue
    }

    func arrayStrings(forMediaWorkflowKey key: String) -> [String]? {
        guard let value = self[key], case let .array(values) = value else { return nil }
        return values.compactMap(\.stringValue)
    }

    private func nestedMediaWorkflowValue(for key: String) -> JSONValue? {
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
