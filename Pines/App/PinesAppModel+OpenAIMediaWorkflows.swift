import Foundation
import PinesCore

extension PinesAppModel {
    @discardableResult
    func createOpenAISpeechArtifact(
        _ request: OpenAISpeechArtifactRequest,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        let artifact = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .createSpeechArtifact(request)
        upsertProviderArtifactRecords([artifact])
        return artifact
    }

    @discardableResult
    func createOpenAITranscriptionArtifact(
        _ request: OpenAIAudioFileArtifactRequest,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        let artifact = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .createTranscriptionArtifact(request)
        upsertProviderArtifactRecords([artifact])
        return artifact
    }

    @discardableResult
    func createOpenAITranslationArtifact(
        _ request: OpenAIAudioFileArtifactRequest,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        let artifact = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .createTranslationArtifact(request)
        upsertProviderArtifactRecords([artifact])
        return artifact
    }

    @discardableResult
    func createOpenAIRealtimeSessionRecord(
        _ request: OpenAIRealtimeSessionWorkflowRequest,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderLiveSessionRecord {
        let session = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .createRealtimeSessionRecord(request)
        upsertProviderLiveSessionRecords([session])
        return session
    }

    @discardableResult
    func createOpenAIVideoArtifact(
        _ request: OpenAIVideoArtifactRequest,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        let artifact = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .createVideoArtifact(request)
        upsertProviderArtifactRecords([artifact])
        return artifact
    }

    @discardableResult
    func refreshOpenAIVideoArtifact(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        let artifact = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .refreshVideoJob(id: id)
        let preserved = try await preserveProviderArtifactCreationMetadata(in: artifact, services: services)
        return preserved
    }

    @discardableResult
    func cancelOpenAIVideoArtifact(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        let artifact = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .cancelVideoArtifact(id: id)
        upsertProviderArtifactRecords([artifact])
        return artifact
    }

    func deleteOpenAIVideoArtifact(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws {
        try await openAIMediaLifecycle(providerID: providerID, services: services)
            .deleteVideoArtifact(id: id)
        removeProviderArtifactRecords(ids: [id, "video-content-\(id)-content"])
    }

    @discardableResult
    func downloadOpenAIVideoContentArtifact(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices,
        variant: String = "content",
        contentType: String = "video/mp4"
    ) async throws -> ProviderArtifactRecord {
        let artifact = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .downloadVideoContent(videoID: id, variant: variant, contentType: contentType)
        upsertProviderArtifactRecords([artifact])
        return artifact
    }

    @discardableResult
    func createOpenAIBatchFromJSONL(
        fileName: String,
        data: Data,
        endpoint: OpenAIBatchEndpoint,
        providerID: ProviderID,
        services: PinesAppServices,
        completionWindow: String = "24h",
        metadata: [String: String] = [:]
    ) async throws -> ProviderBatchRecord {
        let batch = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .createBatchFromJSONL(
                fileName: fileName,
                data: data,
                endpoint: endpoint,
                completionWindow: completionWindow,
                metadata: metadata
            )
        upsertProviderBatchRecords([batch])
        await refreshProviderFileRecords(services: services)
        return batch
    }

    @discardableResult
    func createOpenAIBatch(
        inputFileID: String,
        endpoint: OpenAIBatchEndpoint,
        providerID: ProviderID,
        services: PinesAppServices,
        completionWindow: String = "24h",
        metadata: [String: String] = [:]
    ) async throws -> ProviderBatchRecord {
        let batch = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .createBatch(
                inputFileID: inputFileID,
                endpoint: endpoint,
                completionWindow: completionWindow,
                metadata: metadata
            )
        upsertProviderBatchRecords([batch])
        return batch
    }

    @discardableResult
    func refreshOpenAIBatch(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices,
        importsResults: Bool = false
    ) async throws -> ProviderBatchRecord {
        let lifecycle = try await openAIMediaLifecycle(providerID: providerID, services: services)
        let batch = try await lifecycle.refreshBatch(id: id)
        var importedArtifacts: [ProviderArtifactRecord] = []
        if importsResults {
            importedArtifacts = try await lifecycle.importBatchResultArtifacts(id: id)
        }
        upsertProviderBatchRecords([batch])
        upsertProviderArtifactRecords(importedArtifacts)
        return batch
    }

    @discardableResult
    func cancelOpenAIBatch(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        let batch = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .cancelBatch(id: id)
        upsertProviderBatchRecords([batch])
        return batch
    }

    @discardableResult
    func importOpenAIBatchResultArtifacts(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> [ProviderArtifactRecord] {
        let artifacts = try await openAIMediaLifecycle(providerID: providerID, services: services)
            .importBatchResultArtifacts(id: id)
        upsertProviderArtifactRecords(artifacts)
        return artifacts
    }

    private func openAIMediaLifecycle(
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> OpenAIProviderLifecycleCoordinator {
        guard let cloudProviderService = services.cloudProviderService else {
            throw InferenceError.providerUnavailable(providerID)
        }
        guard let provider = try await openAIProvider(providerID: providerID, services: services) else {
            throw InferenceError.providerUnavailable(providerID)
        }
        guard provider.kind == .openAI else {
            throw InferenceError.invalidRequest("Provider \(provider.displayName) is not an OpenAI provider.")
        }
        return cloudProviderService.openAILifecycleCoordinator(
            for: provider,
            repositories: services.openAIProviderLifecycleRepositories
        )
    }

    private func openAIProvider(
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> CloudProviderConfiguration? {
        if let provider = cloudProviders.first(where: { $0.id == providerID }) {
            return provider
        }
        guard let repository = services.cloudProviderRepository else {
            return nil
        }
        return try await repository.listProviders().first(where: { $0.id == providerID })
    }
}
