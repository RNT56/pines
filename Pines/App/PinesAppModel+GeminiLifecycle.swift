import Foundation
import PinesCore
import UniformTypeIdentifiers

struct GeminiProviderStorageRefreshResult: Sendable {
    var files: [ProviderFileRecord]
    var cachedContents: [ProviderCacheRecord]
    var modelCapabilities: [ProviderModelCapabilityRecord]
}

struct GeminiDeepResearchResumeResult: Sendable {
    var refreshedRuns: [ProviderResearchRunRecord]
    var failedRuns: [ProviderResearchRunRecord]
    var errors: [String: String]
}

struct PinesGeminiProviderStorageConsent: Sendable, Hashable {
    var isGranted: Bool
    var sourceDescription: String
    var destinationDescription: String
    var byteCount: Int64?
    var confirmedAt: Date

    init(
        isGranted: Bool,
        sourceDescription: String,
        destinationDescription: String,
        byteCount: Int64? = nil,
        confirmedAt: Date = Date()
    ) {
        self.isGranted = isGranted
        self.sourceDescription = sourceDescription
        self.destinationDescription = destinationDescription
        self.byteCount = byteCount
        self.confirmedAt = confirmedAt
    }
}

struct PinesGeminiProviderUploadResult: Sendable, Hashable {
    var file: ProviderFileRecord
    var disposition: PinesGeminiMediaDisposition
    var fileDataPart: JSONValue
}

struct PinesGeminiTokenCountPreflightResult: Sendable, Hashable {
    var modelID: ModelID
    var totalTokens: Int
    var requestBody: JSONValue
}

@MainActor
extension PinesAppModel {
    @discardableResult
    func refreshGeminiProviderStorage(
        providerID: ProviderID,
        services: PinesAppServices,
        pageSize: Int? = 100
    ) async throws -> GeminiProviderStorageRefreshResult {
        do {
            let coordinator = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
            let files = try await coordinator.refreshFiles(pageSize: pageSize)
            let caches = try await coordinator.refreshCachedContents(pageSize: pageSize)
            let capabilities = try await coordinator.refreshModelCapabilities(pageSize: pageSize)
            let result = GeminiProviderStorageRefreshResult(
                files: files,
                cachedContents: caches,
                modelCapabilities: capabilities
            )
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return result
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func uploadGeminiLocalFile(
        providerID: ProviderID,
        fileURL: URL,
        contentType: String? = nil,
        consent: PinesGeminiProviderStorageConsent,
        poll: GeminiFilePolling? = GeminiFilePolling(),
        services: PinesAppServices
    ) async throws -> PinesGeminiProviderUploadResult {
        do {
            try validateGeminiProviderStorageConsent(consent)
            let coordinator = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
            let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                throw InferenceError.invalidRequest("Gemini file upload \(fileURL.lastPathComponent) is empty.")
            }
            let resolvedContentType = contentType ?? Self.geminiContentType(for: fileURL)
            let disposition = PinesGeminiMediaDisposition.decision(
                contentType: resolvedContentType,
                byteCount: Int64(data.count)
            )
            let file = try await coordinator.uploadFile(
                fileName: fileURL.lastPathComponent,
                contentType: resolvedContentType,
                data: data,
                localURL: fileURL,
                poll: poll
            )
            try await auditGeminiProviderStorageConsent(consent, providerID: coordinator.providerID, services: services)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return PinesGeminiProviderUploadResult(
                file: file,
                disposition: disposition,
                fileDataPart: GeminiProviderLifecycleCoordinator.fileDataPart(
                    fileURI: file.providerMetadata["uri"] ?? file.id,
                    mimeType: file.contentType ?? resolvedContentType,
                    name: file.id
                )
            )
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("gemini_provider_storage.upload_local_file", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func createGeminiCachedContent(
        providerID: ProviderID,
        body: JSONValue,
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .createCachedContent(body: body)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("gemini_provider_storage.create_cached_content", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func updateGeminiCachedContent(
        providerID: ProviderID,
        name: String,
        body: JSONValue,
        updateMask: String? = nil,
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .updateCachedContent(name: name, body: body, updateMask: updateMask)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("gemini_provider_storage.update_cached_content", error: error, services: services)
            throw error
        }
    }

    func deleteGeminiCachedContent(
        providerID: ProviderID,
        name: String,
        services: PinesAppServices
    ) async throws {
        do {
            try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .deleteCachedContent(name: name)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("gemini_provider_storage.delete_cached_content", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func preflightGeminiCountTokens(
        providerID: ProviderID,
        modelID: ModelID,
        body: JSONValue,
        services: PinesAppServices
    ) async throws -> PinesGeminiTokenCountPreflightResult {
        do {
            let totalTokens = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .countTokens(modelID: modelID, body: body)
            providerLifecycleError = nil
            return PinesGeminiTokenCountPreflightResult(
                modelID: modelID,
                totalTokens: totalTokens,
                requestBody: body
            )
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("gemini_provider_storage.count_tokens", error: error, services: services)
            throw error
        }
    }

    func geminiMediaDisposition(for attachment: ChatAttachment) -> PinesGeminiMediaDisposition {
        Self.geminiMediaDisposition(for: attachment)
    }

    static func geminiMediaDisposition(for attachment: ChatAttachment) -> PinesGeminiMediaDisposition {
        PinesGeminiMediaDisposition.decision(for: attachment)
    }

    static func geminiInlineDataPart(data: Data, mimeType: String) -> JSONValue {
        GeminiProviderLifecycleCoordinator.inlineDataPart(data: data, mimeType: mimeType)
    }

    static func geminiFileDataPart(fileURI: String, mimeType: String? = nil, name: String? = nil) -> JSONValue {
        GeminiProviderLifecycleCoordinator.fileDataPart(fileURI: fileURI, mimeType: mimeType, name: name)
    }

    static func geminiCachedContentBody(
        modelID: ModelID,
        contents: [JSONValue],
        displayName: String? = nil,
        systemInstruction: JSONValue? = nil,
        tools: [JSONValue] = [],
        toolConfig: JSONValue? = nil,
        ttl: String? = nil,
        expireTime: String? = nil
    ) -> JSONValue {
        GeminiProviderLifecycleCoordinator.cachedContentBody(
            modelID: modelID,
            contents: contents,
            displayName: displayName,
            systemInstruction: systemInstruction,
            tools: tools,
            toolConfig: toolConfig,
            ttl: ttl,
            expireTime: expireTime
        )
    }

    static func geminiCountTokensBody(
        contents: [JSONValue],
        systemInstruction: JSONValue? = nil,
        tools: [JSONValue] = [],
        toolConfig: JSONValue? = nil,
        cachedContentName: String? = nil
    ) -> JSONValue {
        GeminiProviderLifecycleCoordinator.countTokensBody(
            contents: contents,
            systemInstruction: systemInstruction,
            tools: tools,
            toolConfig: toolConfig,
            cachedContentName: cachedContentName
        )
    }

    @discardableResult
    func refreshGeminiProviderFile(
        providerID: ProviderID,
        fileID: String,
        services: PinesAppServices
    ) async throws -> ProviderFileRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .refreshFile(name: fileID)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    func deleteGeminiProviderFile(
        providerID: ProviderID,
        fileID: String,
        services: PinesAppServices
    ) async throws {
        do {
            try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .deleteFile(name: fileID)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func createGeminiContextCache(
        providerID: ProviderID,
        modelID: ModelID,
        displayName: String,
        text: String,
        ttlSeconds: Int?,
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            var body: [String: JSONValue] = [
                "model": .string(Self.geminiModelName(modelID)),
                "contents": .array([
                    .object([
                        "role": .string("user"),
                        "parts": .array([.object(["text": .string(text)])]),
                    ]),
                ]),
            ]
            if !displayName.isEmpty {
                body["displayName"] = .string(displayName)
            }
            if let ttlSeconds, ttlSeconds > 0 {
                body["ttl"] = .string("\(ttlSeconds)s")
            }
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .createCachedContent(body: .object(body))
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func refreshGeminiContextCache(
        providerID: ProviderID,
        cacheID: String,
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .refreshCachedContent(name: cacheID)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    func deleteGeminiContextCache(
        providerID: ProviderID,
        cacheID: String,
        services: PinesAppServices
    ) async throws {
        do {
            try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .deleteCachedContent(name: cacheID)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    func countGeminiTokens(
        providerID: ProviderID,
        modelID: ModelID,
        text: String,
        services: PinesAppServices
    ) async throws -> Int {
        let body: JSONValue = .object([
            "contents": .array([
                .object([
                    "role": .string("user"),
                    "parts": .array([.object(["text": .string(text)])]),
                ]),
            ]),
        ])
        return try await geminiLifecycleCoordinator(providerID: providerID, services: services)
            .countTokens(modelID: modelID, body: body)
    }

    @discardableResult
    func startGeminiDeepResearch(
        _ request: PinesProviderDeepResearchRequest,
        services: PinesAppServices,
        pollUntilTerminal: Bool = false
    ) async throws -> ProviderResearchRunRecord {
        let geminiRequest = GeminiDeepResearchRequest(
            providerID: request.providerID,
            agentID: request.modelID,
            title: request.title,
            prompt: request.prompt,
            depth: request.depth,
            sourcePolicy: .object([
                "provider_file_ids": .array(request.providerFileIDs.map(JSONValue.string)),
                "cached_content_ids": .array(request.vectorStoreIDs.map(JSONValue.string)),
                "file_search_store_names": .array(request.vectorStoreIDs.map(JSONValue.string)),
            ]),
            reportFormat: request.reportFormat,
            includeCodeInterpreter: true,
            serviceTier: "default",
            metadata: request.metadata.merging(["provider_kind": request.providerKind.rawValue]) { current, _ in current }
        )
        return try await startGeminiDeepResearch(geminiRequest, services: services, pollUntilTerminal: pollUntilTerminal)
    }

    @discardableResult
    func startGeminiDeepResearch(
        _ request: GeminiDeepResearchRequest,
        services: PinesAppServices,
        pollUntilTerminal: Bool = false
    ) async throws -> ProviderResearchRunRecord {
        do {
            let coordinator = try await geminiLifecycleCoordinator(providerID: request.providerID, services: services)
            let run = try await coordinator.createDeepResearchRun(request)
            applyGeminiResearchRun(run)
            guard pollUntilTerminal else { return run }
            let completed = try await pollGeminiResearchRun(run, coordinator: coordinator)
            applyGeminiResearchRun(completed)
            await refreshProviderLifecycleState(services: services)
            return completed
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func startGeminiDeepResearchFollowUp(
        prompt: String,
        previousRunID: String,
        providerID: ProviderID,
        services: PinesAppServices,
        title: String? = nil,
        metadata extraMetadata: [String: String] = [:],
        pollUntilTerminal: Bool = false
    ) async throws -> ProviderResearchRunRecord {
        do {
            let previousRun = try await storedGeminiResearchRun(id: previousRunID, providerID: providerID, services: services)
            guard let previousInteractionID = previousRun.geminiResumeInteractionID else {
                throw InferenceError.invalidRequest("Gemini Deep Research run \(previousRunID) does not have an interaction ID for follow-up.")
            }
            var metadata = Self.geminiDeepResearchResumeMetadata(from: previousRun)
            metadata["gemini.follow_up_of"] = previousRun.id
            metadata.merge(extraMetadata) { _, new in new }
            let request = GeminiDeepResearchRequest(
                providerID: previousRun.providerID,
                agentID: previousRun.modelID,
                title: title ?? previousRun.title,
                prompt: prompt,
                depth: previousRun.depth,
                sourcePolicy: previousRun.sourcePolicy,
                reportFormat: previousRun.reportFormat,
                includeCodeInterpreter: previousRun.includeCodeInterpreter,
                serviceTier: previousRun.serviceTier,
                metadata: metadata,
                previousInteractionID: previousInteractionID,
                lastEventID: previousRun.geminiResumeEventID
            )
            return try await startGeminiDeepResearch(request, services: services, pollUntilTerminal: pollUntilTerminal)
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func refreshGeminiDeepResearchRun(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderResearchRunRecord {
        do {
            let coordinator = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
            let run = try await storedGeminiResearchRun(id: id, providerID: providerID, services: services)
            let refreshed = try await coordinator.refreshDeepResearchRun(run)
            applyGeminiResearchRun(refreshed)
            if refreshed.geminiBackgroundStatusIsTerminal {
                await refreshProviderLifecycleState(services: services)
            }
            return refreshed
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func cancelGeminiDeepResearchRun(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderResearchRunRecord {
        do {
            let coordinator = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
            let run = try await storedGeminiResearchRun(id: id, providerID: providerID, services: services)
            let cancelled = try await coordinator.cancelDeepResearchRun(run)
            applyGeminiResearchRun(cancelled)
            return cancelled
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func resumeGeminiDeepResearchRuns(
        providerID: ProviderID,
        services: PinesAppServices,
        pollUntilTerminal: Bool = false
    ) async throws -> GeminiDeepResearchResumeResult {
        guard let repository = services.providerResearchRunRepository else {
            return GeminiDeepResearchResumeResult(refreshedRuns: [], failedRuns: [], errors: [:])
        }
        let coordinator = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
        let candidates = try await repository
            .listProviderResearchRuns(providerID: providerID, status: nil)
            .filter { $0.providerKind == .gemini && !$0.geminiBackgroundStatusIsTerminal }
        var refreshedRuns = [ProviderResearchRunRecord]()
        var failedRuns = [ProviderResearchRunRecord]()
        var errors = [String: String]()
        for run in candidates {
            do {
                let refreshed = pollUntilTerminal
                    ? try await pollGeminiResearchRun(run, coordinator: coordinator)
                    : try await coordinator.refreshDeepResearchRun(run)
                refreshedRuns.append(refreshed)
                applyGeminiResearchRun(refreshed)
            } catch {
                failedRuns.append(run)
                errors[run.id] = error.localizedDescription
            }
        }
        if pollUntilTerminal || refreshedRuns.contains(where: \.geminiBackgroundStatusIsTerminal) {
            await refreshProviderLifecycleState(services: services)
        }
        return GeminiDeepResearchResumeResult(refreshedRuns: refreshedRuns, failedRuns: failedRuns, errors: errors)
    }

    @discardableResult
    func createGeminiRealtimeSessionRecord(
        _ request: PinesProviderRealtimeSessionRequest,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderLiveSessionRecord {
        do {
            let record = ProviderLiveSessionRecord(
                id: "gemini-live-\(UUID().uuidString)",
                providerID: providerID,
                providerKind: .gemini,
                modelID: request.modelID,
                status: "created",
                modalities: request.modalities,
                providerMetadata: request.session.objectValue?.reduce(into: [String: String]()) { result, item in
                    if let string = item.value.stringValue {
                        result[item.key] = string
                    }
                } ?? [:],
                createdAt: Date()
            )
            try await services.providerLiveSessionRepository?.upsertProviderLiveSession(record)
            try await services.auditRepository?.append(
                AuditEvent(
                    category: .cloudProvider,
                    summary: "Created Gemini Live session record",
                    providerID: providerID,
                    modelID: request.modelID,
                    networkDomains: ["generativelanguage.googleapis.com"]
                )
            )
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func createGeminiLiveSessionRecord(
        _ request: PinesProviderRealtimeSessionRequest,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderLiveSessionRecord {
        try await createGeminiRealtimeSessionRecord(request, providerID: providerID, services: services)
    }

    @discardableResult
    func createGeminiGeneratedMedia(
        providerID: ProviderID,
        modelID: ModelID,
        prompt: String,
        kind: String,
        services: PinesAppServices
    ) async throws -> [ProviderArtifactRecord] {
        do {
            let coordinator = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
            let records: [ProviderArtifactRecord]
            switch kind {
            case "video":
                let operation = try await coordinator.createGeneratedMediaOperation(
                    modelID: modelID,
                    body: .object(["prompt": .string(prompt)]),
                    method: .generateVideos
                )
                records = [operation]
            case "speech":
                records = try await coordinator.createGeneratedMediaArtifacts(
                    modelID: modelID,
                    body: Self.geminiGeneratedMediaBody(prompt: prompt, responseModalities: ["AUDIO"]),
                    method: .generateContent
                )
            default:
                records = try await coordinator.createGeneratedMediaArtifacts(
                    modelID: modelID,
                    body: Self.geminiGeneratedMediaBody(prompt: prompt, responseModalities: ["IMAGE"]),
                    method: .generateContent
                )
            }
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return records
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func remixGeminiImageArtifact(
        providerID: ProviderID,
        modelID: ModelID,
        prompt: String,
        reference: ProviderArtifactRecord,
        services: PinesAppServices
    ) async throws -> [ProviderArtifactRecord] {
        do {
            let referencePart = try await Self.geminiImageReferencePart(from: reference)
            let records = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .createGeneratedMediaArtifacts(
                    modelID: modelID,
                    body: Self.geminiGeneratedMediaBody(
                        prompt: prompt,
                        responseModalities: ["IMAGE"],
                        referenceParts: [referencePart]
                    ),
                    method: .generateContent
                )
            let annotatedRecords = Self.annotatedGeminiRemixArtifacts(
                records,
                reference: reference,
                prompt: prompt,
                modelID: modelID
            )
            for record in annotatedRecords {
                try await services.providerArtifactRepository?.upsertProviderArtifact(record)
            }
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return annotatedRecords
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func createGeminiMediaArtifacts(
        modelID: ModelID,
        body: JSONValue,
        providerID: ProviderID,
        services: PinesAppServices,
        method: GeminiGeneratedMediaMethod = .predict
    ) async throws -> [ProviderArtifactRecord] {
        do {
            let records = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .createGeneratedMediaArtifacts(modelID: modelID, body: body, method: method)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return records
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func refreshGeminiGeneratedMediaOperation(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .refreshGeneratedMediaOperation(operationName: id)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func cancelGeminiGeneratedMediaOperation(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .cancelGeneratedMediaOperation(operationName: id)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func refreshGeminiBatch(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .refreshBatch(operationName: id)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func cancelGeminiBatch(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        do {
            let record = try await geminiLifecycleCoordinator(providerID: providerID, services: services)
                .cancelBatch(operationName: id)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    private func geminiLifecycleCoordinator(
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> GeminiProviderLifecycleCoordinator {
        guard let provider = try await geminiProvider(id: providerID, services: services) else {
            throw InferenceError.invalidRequest("Gemini provider \(providerID.rawValue) was not found.")
        }
        return try services.geminiLifecycleCoordinator(for: provider)
    }

    private func geminiProvider(id providerID: ProviderID, services: PinesAppServices) async throws -> CloudProviderConfiguration? {
        if let provider = cloudProviders.first(where: { $0.id == providerID && $0.kind == .gemini }) {
            return provider
        }
        guard let repository = services.cloudProviderRepository else { return nil }
        return try await repository.listProviders().first { provider in
            provider.id == providerID && provider.kind == .gemini
        }
    }

    private func validateGeminiProviderStorageConsent(_ consent: PinesGeminiProviderStorageConsent) throws {
        guard consent.isGranted else {
            throw InferenceError.cloudNotAllowed
        }
        guard !consent.sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !consent.destinationDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw InferenceError.invalidRequest("Gemini Files uploads require explicit source and destination consent descriptions.")
        }
    }

    private func auditGeminiProviderStorageConsent(
        _ consent: PinesGeminiProviderStorageConsent,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws {
        try await services.auditRepository?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: "User consented to Gemini Files upload from \(consent.sourceDescription) to \(consent.destinationDescription)",
                providerID: providerID,
                networkDomains: ["generativelanguage.googleapis.com"]
            )
        )
    }

    private func storedGeminiResearchRun(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderResearchRunRecord {
        guard let repository = services.providerResearchRunRepository else {
            throw InferenceError.invalidRequest("Gemini Deep Research runs cannot be loaded because no research run repository is configured.")
        }
        guard let run = try await repository
            .listProviderResearchRuns(providerID: providerID, status: nil)
            .first(where: { $0.id == id || $0.responseID == id })
        else {
            throw InferenceError.invalidRequest("Gemini Deep Research run \(id) was not found.")
        }
        return run
    }

    static func geminiDeepResearchResumeMetadata(from run: ProviderResearchRunRecord) -> [String: String] {
        var metadata = run.providerMetadata
        metadata["gemini.resume.run_id"] = run.id
        metadata["gemini.resume.status"] = run.status
        metadata["gemini.resume.citation_count"] = String(run.citationCount)
        metadata["gemini.resume.tool_call_count"] = String(run.toolCallCount)
        if let responseID = run.responseID, !responseID.isEmpty {
            metadata[CloudProviderMetadataKeys.geminiResponseID] = responseID
        }
        if let interactionID = run.geminiResumeInteractionID {
            metadata[CloudProviderMetadataKeys.geminiInteractionID] = interactionID
            metadata["gemini.previous_interaction_id"] = interactionID
        }
        if let eventID = run.geminiResumeEventID {
            metadata["gemini.last_event_id"] = eventID
        }
        if let finalReportArtifactID = run.finalReportArtifactID {
            metadata["gemini.resume.final_report_artifact_id"] = finalReportArtifactID
        }
        return metadata
    }

    private func pollGeminiResearchRun(
        _ run: ProviderResearchRunRecord,
        coordinator: GeminiProviderLifecycleCoordinator
    ) async throws -> ProviderResearchRunRecord {
        var current = run
        while !current.geminiBackgroundStatusIsTerminal {
            try await Task.sleep(for: .seconds(30))
            current = try await coordinator.refreshDeepResearchRun(current)
        }
        return current
    }

    private func applyGeminiResearchRun(_ run: ProviderResearchRunRecord) {
        var runs = providerResearchRuns
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.append(run)
        }
        runs.sort { $0.updatedAt > $1.updatedAt }
        providerResearchRuns = runs
        providerResearchRunPreviews = runs.map(Self.geminiResearchRunPreview)
        providerLifecycleError = nil
    }

    private static func geminiResearchRunPreview(from record: ProviderResearchRunRecord) -> PinesProviderResearchRunPreview {
        let detailParts = [
            record.depth,
            record.reportFormat,
            record.finalReportArtifactID == nil ? nil : "report saved",
        ].compactMap { $0 }
        return PinesProviderResearchRunPreview(
            id: record.id,
            providerID: record.providerID,
            providerKind: record.providerKind,
            title: record.title,
            modelID: record.modelID,
            status: record.status,
            detail: detailParts.joined(separator: " - "),
            activitySummary: "\(record.citationCount) citations, \(record.toolCallCount) tool calls",
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt)
        )
    }

    private static func geminiContentType(for fileURL: URL) -> String {
        if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.preferredMIMEType ?? "application/octet-stream"
        }
        return UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    private static func geminiModelName(_ modelID: ModelID) -> String {
        let raw = modelID.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.hasPrefix("models/") ? raw : "models/\(raw)"
    }

    private static func geminiImageReferencePart(from artifact: ProviderArtifactRecord) async throws -> JSONValue {
        if let localURL = artifact.localURL,
           localURL.isFileURL,
           FileManager.default.fileExists(atPath: localURL.path) {
            let data = try Data(contentsOf: localURL)
            guard !data.isEmpty else {
                throw InferenceError.invalidRequest("Reference image \(artifact.fileName ?? artifact.id) is empty.")
            }
            return GeminiProviderLifecycleCoordinator.inlineDataPart(
                data: data,
                mimeType: geminiImageContentType(for: artifact, fileName: localURL.lastPathComponent)
            )
        }

        if let data = artifact.content.flatMap(Self.firstBase64ImageData(in:)) {
            return GeminiProviderLifecycleCoordinator.inlineDataPart(
                data: data,
                mimeType: geminiImageContentType(for: artifact, fileName: artifact.fileName)
            )
        }

        if let remoteURL = artifact.remoteURL {
            try EndpointSecurityPolicy().validate(remoteURL, useCase: .webTool)
            try EndpointSecurityPolicy.validateResolvedPublicAddresses(for: remoteURL)
            let (data, response) = try await BoundedHTTPResponse.data(
                for: URLRequest(url: remoteURL),
                session: .shared,
                maxBytes: BoundedHTTPResponse.fileLimit,
                redirectScope: .publicHTTPS
            )
            guard !data.isEmpty else {
                throw InferenceError.invalidRequest("Reference image \(artifact.fileName ?? artifact.id) could not be downloaded.")
            }
            let mimeType = response.mimeType?.hasPrefix("image/") == true
                ? response.mimeType
                : geminiImageContentType(for: artifact, fileName: remoteURL.lastPathComponent)
            return GeminiProviderLifecycleCoordinator.inlineDataPart(data: data, mimeType: mimeType ?? "image/png")
        }

        throw InferenceError.invalidRequest("Reference image \(artifact.fileName ?? artifact.id) has no local file, remote URL, or embedded image data.")
    }

    private static func annotatedGeminiRemixArtifacts(
        _ records: [ProviderArtifactRecord],
        reference: ProviderArtifactRecord,
        prompt: String,
        modelID: ModelID
    ) -> [ProviderArtifactRecord] {
        records.map { record in
            var updated = record
            var content = record.content?.objectValue ?? [:]
            if content.isEmpty, let original = record.content {
                content["provider_response"] = original
            }
            content["pines_remix"] = .object([
                "source_artifact_id": .string(reference.id),
                "prompt": .string(prompt),
                "model": .string(modelID.rawValue),
                "mode": .string("image_remix"),
                "provider": .string("gemini"),
            ])
            updated.content = .object(content)
            updated.text = record.text ?? prompt
            return updated
        }
    }

    private static func geminiImageContentType(for artifact: ProviderArtifactRecord, fileName: String?) -> String {
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

    private static func geminiGeneratedMediaBody(
        prompt: String,
        responseModalities: [String],
        referenceParts: [JSONValue] = []
    ) -> JSONValue {
        let parts = [.object(["text": .string(prompt)])] + referenceParts
        return .object([
            "contents": .array([
                .object([
                    "role": .string("user"),
                    "parts": .array(parts),
                ]),
            ]),
            "generationConfig": .object([
                "responseModalities": .array(responseModalities.map(JSONValue.string)),
            ]),
        ])
    }

    private static func firstBase64ImageData(in value: JSONValue) -> Data? {
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

    private static func decodedBase64ImageData(from raw: String) -> Data? {
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

private extension ProviderResearchRunRecord {
    var geminiBackgroundStatusIsTerminal: Bool {
        switch status.lowercased().replacingOccurrences(of: "_", with: "") {
        case "completed", "complete", "failed", "cancelled", "canceled", "expired":
            true
        default:
            false
        }
    }

    var geminiResumeInteractionID: String? {
        providerMetadata[CloudProviderMetadataKeys.geminiInteractionID]
            ?? providerMetadata[CloudProviderMetadataKeys.geminiResponseID]
            ?? responseID
            ?? (id.isEmpty ? nil : id)
    }

    var geminiResumeEventID: String? {
        providerMetadata["gemini.last_event_id"]
            ?? providerMetadata["gemini.event_id"]
    }
}
