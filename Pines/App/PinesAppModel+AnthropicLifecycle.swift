import Foundation
import PinesCore

struct AnthropicProviderStorageRefreshResult: Sendable {
    var files: [ProviderFileRecord]
    var batches: [ProviderBatchRecord]
    var modelCapabilities: [ProviderModelCapabilityRecord]
}

struct PinesAnthropicProviderStorageConsent: Sendable, Hashable {
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

struct PinesAnthropicProviderUploadResult: Sendable, Hashable {
    var file: ProviderFileRecord
}

struct PinesAnthropicTokenCountPreflightResult: Sendable, Hashable {
    var modelID: ModelID
    var inputTokens: Int
    var requestBody: JSONValue
}

@MainActor
extension PinesAppModel {
    @discardableResult
    func refreshAnthropicProviderStorage(
        providerID: ProviderID,
        services: PinesAppServices,
        limit: Int? = 100
    ) async throws -> AnthropicProviderStorageRefreshResult {
        do {
            let coordinator = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
            let files = try await coordinator.refreshFiles(limit: limit)
            let batches = try await coordinator.refreshBatches(limit: limit)
            let capabilities = try await coordinator.refreshModelCapabilities(limit: limit)
            let result = AnthropicProviderStorageRefreshResult(files: files, batches: batches, modelCapabilities: capabilities)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return result
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("anthropic_provider_storage.refresh", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func uploadAnthropicLocalFile(
        providerID: ProviderID,
        fileURL: URL,
        contentType: String? = nil,
        consent: PinesAnthropicProviderStorageConsent,
        services: PinesAppServices
    ) async throws -> PinesAnthropicProviderUploadResult {
        do {
            try validateAnthropicProviderStorageConsent(consent)
            let coordinator = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
            let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                throw InferenceError.invalidRequest("Anthropic file upload \(fileURL.lastPathComponent) is empty.")
            }
            let file = try await coordinator.uploadFile(
                fileName: fileURL.lastPathComponent,
                contentType: contentType ?? Self.providerStorageContentType(for: fileURL),
                data: data,
                localURL: fileURL
            )
            try await auditAnthropicProviderStorageConsent(consent, providerID: coordinator.providerID, services: services)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return PinesAnthropicProviderUploadResult(file: file)
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("anthropic_provider_storage.upload_local_file", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func uploadAnthropicVaultDocument(
        providerID: ProviderID,
        documentID: UUID,
        consent: PinesAnthropicProviderStorageConsent,
        services: PinesAppServices
    ) async throws -> PinesAnthropicProviderUploadResult {
        do {
            try validateAnthropicProviderStorageConsent(consent)
            guard let vaultRepository = services.vaultRepository else {
                throw InferenceError.invalidRequest("Vault storage is unavailable.")
            }
            let coordinator = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
            let documents = try await vaultRepository.listDocuments()
            guard let document = documents.first(where: { $0.id == documentID }) else {
                throw InferenceError.invalidRequest("Vault document \(documentID.uuidString) was not found.")
            }
            let chunks = try await vaultRepository.chunks(documentID: documentID)
            let text = chunks
                .sorted { $0.ordinal < $1.ordinal }
                .map(\.text)
                .joined(separator: "\n\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InferenceError.invalidRequest("Vault document \(document.title) has no text to upload.")
            }

            let data = Data(text.utf8)
            let file = try await coordinator.uploadFile(
                fileName: Self.providerStorageSafeFileName(document.title, fallbackExtension: "txt"),
                contentType: "text/plain; charset=utf-8",
                data: data,
                localURL: nil
            )
            try await auditAnthropicProviderStorageConsent(consent, providerID: coordinator.providerID, services: services)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return PinesAnthropicProviderUploadResult(file: file)
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("anthropic_provider_storage.upload_vault_document", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func refreshAnthropicProviderFile(
        providerID: ProviderID,
        fileID: String,
        services: PinesAppServices
    ) async throws -> ProviderFileRecord {
        do {
            let record = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .refreshFile(id: fileID)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    func deleteAnthropicProviderFile(
        providerID: ProviderID,
        fileID: String,
        services: PinesAppServices
    ) async throws {
        do {
            try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .deleteFile(id: fileID)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func downloadAnthropicProviderFileContent(
        providerID: ProviderID,
        fileID: String,
        fileName: String? = nil,
        contentType: String? = nil,
        services: PinesAppServices
    ) async throws -> ProviderArtifactRecord {
        do {
            let record = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .downloadFileContent(id: fileID, fileName: fileName, contentType: contentType)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("anthropic_provider_storage.download_file", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func createAnthropicBatch(
        providerID: ProviderID,
        body: JSONValue,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        do {
            let record = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .createBatch(body: body)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("anthropic_provider_storage.create_batch", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func createAnthropicMessageBatch(
        providerID: ProviderID,
        modelID: ModelID,
        prompt: String,
        customID: String? = nil,
        maxTokens: Int = 1024,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw InferenceError.invalidRequest("Anthropic batch prompt cannot be empty.")
        }
        let normalizedMaxTokens = min(max(maxTokens, 1), 8192)
        let requestID = customID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCustomID: String
        if let requestID, !requestID.isEmpty {
            resolvedCustomID = requestID
        } else {
            resolvedCustomID = "pines-\(UUID().uuidString)"
        }
        let params: JSONValue = .object([
            "model": .string(modelID.rawValue),
            "max_tokens": .number(Double(normalizedMaxTokens)),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(trimmedPrompt),
                        ]),
                    ]),
                ]),
            ]),
        ])
        let request = AnthropicMessageBatchCreateRequest(
            requests: [
                AnthropicMessageBatchRequest(
                    customID: resolvedCustomID,
                    params: params
                ),
            ],
            metadata: [
                "source": "pines",
                "workflow": "manual_provider_batch",
            ]
        )
        return try await createAnthropicBatch(providerID: providerID, body: request.body, services: services)
    }

    @discardableResult
    func refreshAnthropicBatch(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        do {
            let record = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .refreshBatch(id: id)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func cancelAnthropicBatch(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        do {
            let record = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .cancelBatch(id: id)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func importAnthropicBatchResults(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> [ProviderArtifactRecord] {
        do {
            let records = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .importBatchResults(id: id)
            await refreshProviderLifecycleState(services: services)
            providerLifecycleError = nil
            return records
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("anthropic_provider_storage.import_batch_results", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func preflightAnthropicCountTokens(
        providerID: ProviderID,
        modelID: ModelID,
        body: JSONValue,
        services: PinesAppServices
    ) async throws -> PinesAnthropicTokenCountPreflightResult {
        do {
            let inputTokens = try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
                .countTokens(modelID: modelID, body: body)
            providerLifecycleError = nil
            return PinesAnthropicTokenCountPreflightResult(
                modelID: modelID,
                inputTokens: inputTokens,
                requestBody: body
            )
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("anthropic_provider_storage.count_tokens", error: error, services: services)
            throw error
        }
    }

    func countAnthropicTokens(
        providerID: ProviderID,
        modelID: ModelID,
        text: String,
        services: PinesAppServices
    ) async throws -> Int {
        let body = AnthropicProviderLifecycleCoordinator.countTokensBody(messages: [
            .object([
                "role": .string("user"),
                "content": .array([.object([
                    "type": .string("text"),
                    "text": .string(text),
                ])]),
            ]),
        ])
        return try await anthropicLifecycleCoordinator(providerID: providerID, services: services)
            .countTokens(modelID: modelID, body: body)
    }

    private func anthropicLifecycleCoordinator(
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> AnthropicProviderLifecycleCoordinator {
        guard let provider = try await anthropicProvider(id: providerID, services: services) else {
            throw InferenceError.invalidRequest("Anthropic provider \(providerID.rawValue) was not found.")
        }
        return try services.anthropicLifecycleCoordinator(for: provider)
    }

    private func anthropicProvider(id providerID: ProviderID, services: PinesAppServices) async throws -> CloudProviderConfiguration? {
        if let provider = cloudProviders.first(where: { $0.id == providerID && $0.kind == .anthropic }) {
            return provider
        }
        guard let repository = services.cloudProviderRepository else { return nil }
        return try await repository.listProviders().first { provider in
            provider.id == providerID && provider.kind == .anthropic
        }
    }

    private func validateAnthropicProviderStorageConsent(_ consent: PinesAnthropicProviderStorageConsent) throws {
        guard consent.isGranted else {
            throw InferenceError.cloudNotAllowed
        }
        guard !consent.sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !consent.destinationDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw InferenceError.invalidRequest("Anthropic Files uploads require explicit source and destination consent descriptions.")
        }
    }

    private func auditAnthropicProviderStorageConsent(
        _ consent: PinesAnthropicProviderStorageConsent,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws {
        try await services.auditRepository?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: "User consented to Anthropic provider storage upload from \(consent.sourceDescription) to \(consent.destinationDescription)",
                providerID: providerID,
                networkDomains: ["api.anthropic.com"]
            )
        )
    }
}
