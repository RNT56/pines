import Foundation
import PinesCore

struct PinesOpenAIProviderStorageConsent: Sendable, Hashable {
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

struct PinesOpenAIProviderUploadResult: Sendable, Hashable {
    var file: ProviderFileRecord
    var attachedVectorStore: ProviderCacheRecord?
}

@MainActor
extension PinesAppModel {
    @discardableResult
    func refreshOpenAIProviderStorage(
        providerID: ProviderID? = nil,
        purpose: String? = nil,
        limit: Int? = 100,
        services: PinesAppServices
    ) async throws -> OpenAIProviderStorageRefreshResult {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let result = try await coordinator.refreshProviderStorage(purpose: purpose, limit: limit)
            upsertProviderStorageRecords(files: result.files, caches: result.vectorStores)
            providerLifecycleError = nil
            return result
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.refresh", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func uploadOpenAILocalFile(
        providerID: ProviderID? = nil,
        fileURL: URL,
        purpose: String = "assistants",
        contentType: String? = nil,
        consent: PinesOpenAIProviderStorageConsent,
        attachToVectorStoreID: String? = nil,
        vectorStoreAttributes: JSONValue? = nil,
        uploadProgress: ProviderUploadProgress? = nil,
        services: PinesAppServices
    ) async throws -> PinesOpenAIProviderUploadResult {
        do {
            try validateOpenAIProviderStorageConsent(consent)
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let source = try await ProviderTransferFileService.shared.inspect(fileURL)
            guard source.byteCount > 0 else {
                throw InferenceError.invalidRequest("OpenAI file upload \(fileURL.lastPathComponent) is empty.")
            }
            let file = try await coordinator.uploadFile(
                fileName: fileURL.lastPathComponent,
                contentType: contentType
                    ?? source.contentType
                    ?? Self.providerStorageContentType(for: fileURL),
                fileURL: fileURL,
                byteCount: source.byteCount,
                purpose: purpose,
                localURL: fileURL,
                uploadProgress: uploadProgress
            )
            let attached: ProviderCacheRecord?
            if let attachToVectorStoreID {
                attached = try await coordinator.attachFile(file.id, toVectorStore: attachToVectorStoreID, attributes: vectorStoreAttributes)
            } else {
                attached = nil
            }
            try await auditOpenAIProviderStorageConsent(consent, providerID: coordinator.providerID, services: services)
            upsertProviderFileRecords([file])
            if let attached {
                upsertProviderCacheRecords([attached])
            }
            providerLifecycleError = nil
            return PinesOpenAIProviderUploadResult(file: file, attachedVectorStore: attached)
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.upload_local_file", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func uploadOpenAIVaultDocument(
        providerID: ProviderID? = nil,
        documentID: UUID,
        purpose: String = "assistants",
        consent: PinesOpenAIProviderStorageConsent,
        attachToVectorStoreID: String? = nil,
        vectorStoreAttributes: JSONValue? = nil,
        uploadProgress: ProviderUploadProgress? = nil,
        services: PinesAppServices
    ) async throws -> PinesOpenAIProviderUploadResult {
        do {
            try validateOpenAIProviderStorageConsent(consent)
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let staged = try await stageVaultDocumentForProviderUpload(documentID: documentID, services: services)
            let file: ProviderFileRecord
            do {
                file = try await coordinator.uploadFile(
                    fileName: staged.file.url.lastPathComponent,
                    contentType: staged.file.contentType ?? "text/plain; charset=utf-8",
                    fileURL: staged.file.url,
                    byteCount: staged.file.byteCount,
                    purpose: purpose,
                    localURL: nil,
                    uploadProgress: uploadProgress
                )
                try? await ProviderTransferFileService.shared.removeStagedTransfer(containing: staged.file.url)
            } catch {
                try? await ProviderTransferFileService.shared.removeStagedTransfer(containing: staged.file.url)
                throw error
            }
            let attached: ProviderCacheRecord?
            if let attachToVectorStoreID {
                attached = try await coordinator.attachFile(file.id, toVectorStore: attachToVectorStoreID, attributes: vectorStoreAttributes)
            } else {
                attached = nil
            }
            try await auditOpenAIProviderStorageConsent(consent, providerID: coordinator.providerID, services: services)
            upsertProviderFileRecords([file])
            if let attached {
                upsertProviderCacheRecords([attached])
            }
            providerLifecycleError = nil
            return PinesOpenAIProviderUploadResult(file: file, attachedVectorStore: attached)
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.upload_vault_document", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func createOpenAIVectorStore(
        providerID: ProviderID? = nil,
        name: String?,
        description: String? = nil,
        fileIDs: [String] = [],
        expiresAfter: JSONValue? = nil,
        metadata: [String: String] = [:],
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let record = try await coordinator.createVectorStore(
                name: name,
                description: description,
                fileIDs: fileIDs,
                expiresAfter: expiresAfter,
                metadata: metadata
            )
            upsertProviderCacheRecords([record])
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.create_vector_store", error: error, services: services)
            throw error
        }
    }

    func deleteOpenAIProviderFile(
        providerID: ProviderID? = nil,
        fileID: String,
        services: PinesAppServices
    ) async throws {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            try await coordinator.deleteFile(id: fileID)
            await refreshProviderFileRecords(services: services)
            providerLifecycleError = nil
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.delete_file", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func updateOpenAIVectorStore(
        providerID: ProviderID? = nil,
        vectorStoreID: String,
        mutation: OpenAIVectorStoreMutation,
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let record = try await coordinator.updateVectorStore(id: vectorStoreID, mutation: mutation)
            upsertProviderCacheRecords([record])
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.update_vector_store", error: error, services: services)
            throw error
        }
    }

    func deleteOpenAIVectorStore(
        providerID: ProviderID? = nil,
        vectorStoreID: String,
        services: PinesAppServices
    ) async throws {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            try await coordinator.deleteVectorStore(id: vectorStoreID)
            await refreshProviderCacheRecords(services: services)
            providerLifecycleError = nil
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.delete_vector_store", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func attachOpenAIFile(
        providerID: ProviderID? = nil,
        fileID: String,
        vectorStoreID: String,
        attributes: JSONValue? = nil,
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let record = try await coordinator.attachFile(fileID, toVectorStore: vectorStoreID, attributes: attributes)
            upsertProviderCacheRecords([record])
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.attach_file", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func refreshOpenAIVectorStoreFiles(
        providerID: ProviderID? = nil,
        vectorStoreID: String,
        limit: Int? = 100,
        services: PinesAppServices
    ) async throws -> [ProviderFileRecord] {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let records = try await coordinator.listVectorStoreFiles(vectorStoreID: vectorStoreID, limit: limit)
            upsertProviderFileRecords(records)
            providerLifecycleError = nil
            return records
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.refresh_vector_store_files", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func detachOpenAIFile(
        providerID: ProviderID? = nil,
        fileID: String,
        vectorStoreID: String,
        services: PinesAppServices
    ) async throws -> ProviderCacheRecord {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let record = try await coordinator.detachFile(fileID, fromVectorStore: vectorStoreID)
            upsertProviderCacheRecords([record])
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.detach_file", error: error, services: services)
            throw error
        }
    }

    @discardableResult
    func attachOpenAIFilesBatch(
        providerID: ProviderID? = nil,
        fileIDs: [String],
        vectorStoreID: String,
        attributes: JSONValue? = nil,
        polling: OpenAIVectorStoreFileBatchPolling? = nil,
        services: PinesAppServices
    ) async throws -> ProviderBatchRecord {
        do {
            let coordinator = try await openAIProviderStorageCoordinator(providerID: providerID, services: services)
            let record = try await coordinator.attachFilesBatch(
                fileIDs,
                toVectorStore: vectorStoreID,
                attributes: attributes,
                polling: polling
            )
            upsertProviderBatchRecords([record])
            await refreshProviderCacheRecords(services: services)
            providerLifecycleError = nil
            return record
        } catch {
            providerLifecycleError = error.localizedDescription
            recordRecoverableIssue("openai_provider_storage.attach_files_batch", error: error, services: services)
            throw error
        }
    }

    func openAIFileSearchToolConfiguration(
        vectorStoreIDs: [String],
        maxResults: Int? = nil,
        filters: JSONValue? = nil,
        rankingOptions: JSONValue? = nil
    ) -> JSONValue {
        OpenAIFileSearchToolConfiguration(
            vectorStoreIDs: vectorStoreIDs,
            maxResults: maxResults,
            filters: filters,
            rankingOptions: rankingOptions
        ).responsesTool
    }
}

private extension PinesAppModel {
    func openAIProviderStorageCoordinator(
        providerID: ProviderID?,
        services: PinesAppServices
    ) async throws -> OpenAIProviderLifecycleCoordinator {
        guard let cloudProviderService = services.cloudProviderService,
              let repository = services.cloudProviderRepository
        else {
            throw InferenceError.invalidRequest("Cloud provider storage is unavailable.")
        }
        let providers = try await repository.listProviders()
        let provider: CloudProviderConfiguration?
        if let providerID {
            provider = providers.first { $0.id == providerID }
        } else if let defaultProviderID,
                  let defaultProvider = providers.first(where: { $0.id == defaultProviderID && $0.kind == .openAI }) {
            provider = defaultProvider
        } else {
            provider = providers.first { $0.kind == .openAI }
        }
        guard let provider else {
            throw InferenceError.providerUnavailable(providerID ?? defaultProviderID ?? ProviderID(rawValue: "openai"))
        }
        guard provider.kind == .openAI else {
            throw InferenceError.invalidRequest("Provider \(provider.displayName) does not support OpenAI provider storage workflows.")
        }
        return cloudProviderService.openAILifecycleCoordinator(
            for: provider,
            repositories: services.openAIProviderLifecycleRepositories
        )
    }

    func validateOpenAIProviderStorageConsent(_ consent: PinesOpenAIProviderStorageConsent) throws {
        guard consent.isGranted else {
            throw InferenceError.cloudNotAllowed
        }
        guard !consent.sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !consent.destinationDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw InferenceError.invalidRequest("Provider storage uploads require explicit source and destination consent descriptions.")
        }
    }

    func auditOpenAIProviderStorageConsent(
        _ consent: PinesOpenAIProviderStorageConsent,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws {
        try await services.auditRepository?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: "User consented to OpenAI provider storage upload from \(consent.sourceDescription) to \(consent.destinationDescription)",
                providerID: providerID,
                networkDomains: ["api.openai.com"]
            )
        )
    }
}

extension PinesAppModel {
    static func providerStorageContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jsonl":
            "application/jsonl"
        case "json":
            "application/json"
        case "md", "markdown":
            "text/markdown"
        case "pdf":
            "application/pdf"
        case "csv":
            "text/csv"
        case "html", "htm":
            "text/html"
        case "txt":
            "text/plain"
        default:
            "application/octet-stream"
        }
    }

    static func providerStorageSafeFileName(_ title: String, fallbackExtension: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        let sanitized = String(title.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = sanitized.isEmpty ? "vault-document" : sanitized
        return URL(fileURLWithPath: base).pathExtension.isEmpty ? "\(base).\(fallbackExtension)" : base
    }
}
