import Foundation
import PinesCore

@MainActor
extension PinesAppModel {
    @discardableResult
    func annotateCreatedProviderArtifacts(
        _ artifacts: [ProviderArtifactRecord],
        prompt: String,
        modelID: ModelID,
        requestedKind: String,
        referenceArtifactID: String?,
        services: PinesAppServices
    ) async throws -> [ProviderArtifactRecord] {
        let annotated = artifacts.map { artifact in
            var updated = artifact
            var object = artifact.content?.objectValue ?? [:]
            if object.isEmpty, let original = artifact.content {
                object["provider_response"] = original
            }
            object["pines_prompt"] = .string(prompt)
            object["pines_model"] = .string(modelID.rawValue)
            object["pines_requested_kind"] = .string(requestedKind)
            if let referenceArtifactID {
                object["pines_reference_artifact_id"] = .string(referenceArtifactID)
            }
            updated.content = .object(object)
            return updated
        }
        for artifact in annotated {
            try await services.providerArtifactRepository?.upsertProviderArtifact(artifact)
        }
        await refreshProviderLifecycleState(services: services)
        return annotated
    }

    @discardableResult
    func preserveProviderArtifactCreationMetadata(
        in artifact: ProviderArtifactRecord,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        guard let previous = providerArtifacts.first(where: { $0.id == artifact.id }),
              let previousObject = previous.content?.objectValue
        else {
            return artifact
        }
        let keys = ["pines_prompt", "pines_model", "pines_requested_kind", "pines_reference_artifact_id"]
        var updated = artifact
        var object = artifact.content?.objectValue ?? [:]
        if object.isEmpty, let original = artifact.content {
            object["provider_response"] = original
        }
        for key in keys where object[key] == nil {
            object[key] = previousObject[key]
        }
        updated.content = .object(object)
        try await services.providerArtifactRepository?.upsertProviderArtifact(updated)
        return updated
    }

    func deleteProviderArtifactRecord(id: String, services: PinesAppServices) async throws {
        guard let repository = services.providerArtifactRepository else {
            throw InferenceError.invalidRequest("Provider artifact storage is unavailable.")
        }
        try await repository.deleteProviderArtifact(id: id)
        await refreshProviderLifecycleState(services: services)
    }

    @discardableResult
    func importProviderArtifactToVault(id: String, services: PinesAppServices) async throws -> VaultDocumentRecord {
        guard let artifactRepository = services.providerArtifactRepository else {
            throw InferenceError.invalidRequest("Provider artifact storage is unavailable.")
        }
        guard let ingestion = services.vaultIngestionService else {
            throw InferenceError.invalidRequest("Vault ingestion service is unavailable.")
        }
        guard let artifact = try await artifactRepository.listProviderArtifacts(responseID: nil).first(where: { $0.id == id }) else {
            throw InferenceError.invalidRequest("Provider artifact \(id) was not found.")
        }

        _ = await ensureVaultEmbeddingProfile(
            services: services,
            reason: "Pines will send imported artifact chunks to this cloud embedding provider to build your private vault index."
        )

        let sourceURL: URL
        let temporaryURL: URL?
        if let localURL = artifact.localURL, FileManager.default.fileExists(atPath: localURL.path) {
            sourceURL = localURL
            temporaryURL = nil
        } else if let text = artifact.text {
            let fileName = Self.artifactImportFileName(
                for: artifact,
                fallbackExtension: Self.artifactTextExtension(contentType: artifact.contentType)
            )
            let url = try Self.materializeProviderArtifactImport(data: Data(text.utf8), fileName: fileName)
            sourceURL = url
            temporaryURL = url
        } else if let content = artifact.content {
            let data = try Self.prettyJSONData(for: content)
            let fileName = Self.artifactImportFileName(for: artifact, fallbackExtension: "json")
            let url = try Self.materializeProviderArtifactImport(data: data, fileName: fileName)
            sourceURL = url
            temporaryURL = url
        } else {
            throw InferenceError.invalidRequest("Artifact \(id) has no local file, text, or JSON content to import into Vault.")
        }
        defer {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let document = try await ingestion.importFile(url: sourceURL)
        await refreshAll(services: services)
        return document
    }

    @discardableResult
    func createOpenAIImageArtifacts(
        providerID: ProviderID,
        modelID: ModelID?,
        prompt: String,
        fields: [String: JSONValue] = [:],
        services: PinesAppServices
    ) async throws -> [ProviderArtifactRecord] {
        let artifacts = try await artifactOpenAILifecycle(providerID: providerID, services: services)
            .createImageArtifacts(prompt: prompt, model: modelID?.rawValue, fields: fields)
        await refreshProviderLifecycleState(services: services)
        return artifacts
    }

    @discardableResult
    func remixOpenAIImageArtifact(
        providerID: ProviderID,
        modelID: ModelID?,
        prompt: String,
        reference: ProviderArtifactRecord,
        fields: [String: JSONValue] = [:],
        services: PinesAppServices
    ) async throws -> [ProviderArtifactRecord] {
        let artifacts = try await artifactOpenAILifecycle(providerID: providerID, services: services)
            .createImageEditArtifacts(
                prompt: prompt,
                model: modelID?.rawValue,
                reference: reference,
                fields: fields
            )
        await refreshProviderLifecycleState(services: services)
        return artifacts
    }

    private func artifactOpenAILifecycle(
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> OpenAIProviderLifecycleCoordinator {
        guard let cloudProviderService = services.cloudProviderService else {
            throw InferenceError.providerUnavailable(providerID)
        }
        guard let provider = try await artifactOpenAIProvider(providerID: providerID, services: services) else {
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

    private func artifactOpenAIProvider(
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

    private static func materializeProviderArtifactImport(data: Data, fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PinesArtifactImports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString)-\(fileName)")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func prettyJSONData(for value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static func artifactImportFileName(
        for artifact: ProviderArtifactRecord,
        fallbackExtension: String
    ) -> String {
        let rawName = artifact.fileName ?? "\(artifact.kind)-\(artifact.id)"
        let name = rawName
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        var resolvedName = name.isEmpty ? "provider-artifact" : name
        if !resolvedName.lowercased().hasSuffix(".\(fallbackExtension.lowercased())") {
            resolvedName += ".\(fallbackExtension)"
        }
        return resolvedName
    }

    private static func artifactTextExtension(contentType: String?) -> String {
        switch contentType?.lowercased() {
        case "text/markdown":
            "md"
        case "application/json":
            "json"
        case "text/csv":
            "csv"
        case "application/jsonl", "application/x-ndjson":
            "jsonl"
        default:
            "txt"
        }
    }
}
