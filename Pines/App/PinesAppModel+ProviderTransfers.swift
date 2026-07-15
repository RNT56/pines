import Foundation
import PinesCore

struct PinesStagedVaultProviderDocument: Sendable {
    let document: VaultDocumentRecord
    let file: ProviderTransferStagedFile
}

final class ProviderTransferProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmittedBytes: Int64 = 0

    func shouldEmit(completedBytes: Int64, totalBytes: Int64) -> Bool {
        guard totalBytes > 0, completedBytes > 0 else { return false }
        return lock.withLock {
            let boundedCompleted = min(totalBytes, completedBytes)
            guard boundedCompleted > lastEmittedBytes else { return false }
            let minimumStep = max(Int64(64 * 1_024), totalBytes / 100)
            guard boundedCompleted == totalBytes
                || boundedCompleted - lastEmittedBytes >= minimumStep
            else { return false }
            lastEmittedBytes = boundedCompleted
            return true
        }
    }
}

@MainActor
extension PinesAppModel {
    func enqueueProviderFileTransfer(
        provider: CloudProviderConfiguration,
        fileURL: URL,
        purpose: String?,
        services: PinesAppServices
    ) async throws {
        let enqueueInterval = services.runtimeMetrics.begin(.transferEnqueued)
        defer { services.runtimeMetrics.end(enqueueInterval) }
        guard [.openAI, .anthropic, .gemini].contains(provider.kind) else {
            throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) file upload is not supported.")
        }
        guard let repository = services.providerTransferRepository else {
            throw InferenceError.invalidRequest("Transfer persistence is unavailable.")
        }

        let transferID = UUID()
        let stageInterval = services.runtimeMetrics.begin(.transferStage)
        let stagedFile: ProviderTransferStagedFile
        do {
            stagedFile = try await ProviderTransferFileService.shared.stage(
                sourceURL: fileURL,
                transferID: transferID
            )
            services.runtimeMetrics.end(stageInterval)
        } catch {
            services.runtimeMetrics.end(stageInterval)
            throw error
        }
        let transfer = ProviderTransferRecord(
            id: transferID,
            providerID: provider.id,
            providerKind: provider.kind,
            source: .localFile,
            sourceReference: fileURL.lastPathComponent,
            stagedLocalURL: stagedFile.url,
            fileName: fileURL.lastPathComponent,
            contentType: stagedFile.contentType,
            purpose: purpose,
            totalBytes: stagedFile.byteCount
        )
        try await repository.upsertProviderTransfer(transfer)
        upsertProviderTransferRecords([transfer])
        startProviderTransfer(transfer, services: services)
    }

    func enqueueVaultProviderTransfer(
        provider: CloudProviderConfiguration,
        documentID: UUID,
        documentTitle: String,
        purpose: String?,
        services: PinesAppServices
    ) async throws {
        guard [.openAI, .anthropic].contains(provider.kind) else {
            throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) Vault upload is not supported.")
        }
        guard let repository = services.providerTransferRepository else {
            throw InferenceError.invalidRequest("Transfer persistence is unavailable.")
        }
        var totalBytes: Int64?
        if let vaultRepository = services.vaultRepository {
            async let textBytes = vaultRepository.chunkUTF8ByteCount(documentID: documentID)
            async let document = vaultRepository.document(id: documentID)
            do {
                let bytes = try await textBytes
                if let record = try await document {
                    totalBytes = bytes + Int64(max(0, record.chunkCount - 1) * 2)
                }
            } catch {
                totalBytes = nil
            }
        }
        let transfer = ProviderTransferRecord(
            providerID: provider.id,
            providerKind: provider.kind,
            source: .vaultDocument,
            sourceReference: documentID.uuidString,
            fileName: documentTitle,
            contentType: "text/plain",
            purpose: purpose,
            totalBytes: totalBytes
        )
        try await repository.upsertProviderTransfer(transfer)
        upsertProviderTransferRecords([transfer])
        startProviderTransfer(transfer, services: services)
    }

    func cancelProviderTransfer(id: UUID, services: PinesAppServices) async {
        providerTransferTasks[id]?.cancel()
        providerTransferTasks[id] = nil
        guard var transfer = providerTransfers.first(where: { $0.id == id }), transfer.status.isActive else { return }
        transfer.status = .cancelled
        transfer.updatedAt = Date()
        transfer.lastError = "Cancelled by you. The staged source is retained so this transfer can be retried."
        try? await services.providerTransferRepository?.upsertProviderTransfer(transfer)
        upsertProviderTransferRecords([transfer])
    }

    func retryProviderTransfer(id: UUID, services: PinesAppServices) async {
        guard var transfer = providerTransfers.first(where: { $0.id == id }), transfer.status.canRetry else { return }
        if transfer.source == .localFile {
            let stagedFileExists: Bool
            if let stagedURL = transfer.stagedLocalURL {
                stagedFileExists = await ProviderTransferFileService.shared.fileExists(at: stagedURL)
            } else {
                stagedFileExists = false
            }
            if !stagedFileExists {
                transfer.lastError = "The staged source is no longer available. Choose the file again to create a new transfer."
                transfer.status = .failed
                transfer.updatedAt = Date()
                try? await services.providerTransferRepository?.upsertProviderTransfer(transfer)
                upsertProviderTransferRecords([transfer])
                return
            }
        }
        transfer.retryCount += 1
        transfer.status = .queued
        transfer.completedBytes = 0
        transfer.completedAt = nil
        transfer.updatedAt = Date()
        transfer.lastError = nil
        try? await services.providerTransferRepository?.upsertProviderTransfer(transfer)
        upsertProviderTransferRecords([transfer])
        startProviderTransfer(transfer, services: services)
    }

    func removeProviderTransfer(id: UUID, services: PinesAppServices) async {
        guard let transfer = providerTransfers.first(where: { $0.id == id }),
              !transfer.status.isActive,
              let repository = services.providerTransferRepository
        else { return }
        do {
            try await repository.deleteProviderTransfer(id: id)
            removeProviderTransferRecord(id: id)
            if let stagedURL = transfer.stagedLocalURL {
                try? await ProviderTransferFileService.shared.removeStagedTransfer(containing: stagedURL)
            }
        } catch {
            setIfChanged(\.providerLifecycleError, error.localizedDescription)
        }
    }

    func refreshProviderTransfers(services: PinesAppServices) async {
        guard let repository = services.providerTransferRepository else { return }
        do {
            setIfChanged(
                \.providerTransfers,
                try await repository.listProviderTransfers(
                    providerID: nil,
                    limit: ProviderLifecyclePerformance.retainedRecordLimit
                )
            )
        } catch {
            setIfChanged(\.providerLifecycleError, error.localizedDescription)
        }
    }

    private func startProviderTransfer(_ transfer: ProviderTransferRecord, services: PinesAppServices) {
        providerTransferTasks[transfer.id]?.cancel()
        providerTransferTasks[transfer.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performProviderTransfer(transfer, services: services)
            self.providerTransferTasks[transfer.id] = nil
        }
    }

    private func performProviderTransfer(_ initialTransfer: ProviderTransferRecord, services: PinesAppServices) async {
        guard let repository = services.providerTransferRepository else { return }
        var transfer = initialTransfer
        do {
            transfer.status = .preparing
            transfer.updatedAt = Date()
            try await repository.upsertProviderTransfer(transfer)
            upsertProviderTransferRecords([transfer])
            try Task.checkCancellation()

            transfer.status = .transferring
            transfer.updatedAt = Date()
            try await repository.upsertProviderTransfer(transfer)
            upsertProviderTransferRecords([transfer])

            let providerObjectID: String
            switch (transfer.providerKind, transfer.source) {
            case (.openAI, .localFile):
                guard let url = transfer.stagedLocalURL else { throw InferenceError.invalidRequest("The staged upload source is missing.") }
                let consent = PinesOpenAIProviderStorageConsent(
                    isGranted: true,
                    sourceDescription: transfer.fileName,
                    destinationDescription: "OpenAI Files API",
                    byteCount: transfer.totalBytes
                )
                providerObjectID = try await uploadOpenAILocalFile(
                    providerID: transfer.providerID,
                    fileURL: url,
                    purpose: transfer.purpose ?? "assistants",
                    contentType: transfer.contentType,
                    consent: consent,
                    uploadProgress: providerTransferProgressHandler(
                        transferID: transfer.id,
                        fileByteCount: transfer.totalBytes,
                        services: services
                    ),
                    services: services
                ).file.id
            case (.anthropic, .localFile):
                guard let url = transfer.stagedLocalURL else { throw InferenceError.invalidRequest("The staged upload source is missing.") }
                let consent = PinesAnthropicProviderStorageConsent(
                    isGranted: true,
                    sourceDescription: transfer.fileName,
                    destinationDescription: "Anthropic Files API",
                    byteCount: transfer.totalBytes
                )
                providerObjectID = try await uploadAnthropicLocalFile(
                    providerID: transfer.providerID,
                    fileURL: url,
                    contentType: transfer.contentType,
                    consent: consent,
                    uploadProgress: providerTransferProgressHandler(
                        transferID: transfer.id,
                        fileByteCount: transfer.totalBytes,
                        services: services
                    ),
                    services: services
                ).file.id
            case (.gemini, .localFile):
                guard let url = transfer.stagedLocalURL else { throw InferenceError.invalidRequest("The staged upload source is missing.") }
                let consent = PinesGeminiProviderStorageConsent(
                    isGranted: true,
                    sourceDescription: transfer.fileName,
                    destinationDescription: "Gemini Files API",
                    byteCount: transfer.totalBytes
                )
                providerObjectID = try await uploadGeminiLocalFile(
                    providerID: transfer.providerID,
                    fileURL: url,
                    contentType: transfer.contentType,
                    consent: consent,
                    uploadProgress: providerTransferProgressHandler(
                        transferID: transfer.id,
                        fileByteCount: transfer.totalBytes,
                        services: services
                    ),
                    services: services
                ).file.id
            case (.openAI, .vaultDocument):
                guard let id = UUID(uuidString: transfer.sourceReference) else { throw InferenceError.invalidRequest("The Vault source is invalid.") }
                let consent = PinesOpenAIProviderStorageConsent(
                    isGranted: true,
                    sourceDescription: transfer.fileName,
                    destinationDescription: "OpenAI Files API"
                )
                providerObjectID = try await uploadOpenAIVaultDocument(
                    providerID: transfer.providerID,
                    documentID: id,
                    purpose: transfer.purpose ?? "assistants",
                    consent: consent,
                    uploadProgress: providerTransferProgressHandler(
                        transferID: transfer.id,
                        fileByteCount: transfer.totalBytes,
                        services: services
                    ),
                    services: services
                ).file.id
            case (.anthropic, .vaultDocument):
                guard let id = UUID(uuidString: transfer.sourceReference) else { throw InferenceError.invalidRequest("The Vault source is invalid.") }
                let consent = PinesAnthropicProviderStorageConsent(
                    isGranted: true,
                    sourceDescription: transfer.fileName,
                    destinationDescription: "Anthropic Files API"
                )
                providerObjectID = try await uploadAnthropicVaultDocument(
                    providerID: transfer.providerID,
                    documentID: id,
                    consent: consent,
                    uploadProgress: providerTransferProgressHandler(
                        transferID: transfer.id,
                        fileByteCount: transfer.totalBytes,
                        services: services
                    ),
                    services: services
                ).file.id
            default:
                throw InferenceError.invalidRequest("This provider/source transfer combination is unsupported.")
            }

            try Task.checkCancellation()
            transfer.status = .verifying
            transfer.providerObjectID = providerObjectID
            transfer.completedBytes = transfer.totalBytes ?? transfer.completedBytes
            transfer.updatedAt = Date()
            try await repository.upsertProviderTransfer(transfer)
            upsertProviderTransferRecords([transfer])

            transfer.status = .completed
            transfer.completedAt = Date()
            transfer.updatedAt = transfer.completedAt ?? Date()
            transfer.lastError = nil
            try await repository.upsertProviderTransfer(transfer)
            upsertProviderTransferRecords([transfer])
        } catch is CancellationError {
            transfer.status = .cancelled
            transfer.lastError = "Cancelled by you. Retry when you are ready."
            transfer.updatedAt = Date()
            try? await repository.upsertProviderTransfer(transfer)
            upsertProviderTransferRecords([transfer])
        } catch {
            transfer.status = .failed
            transfer.lastError = error.localizedDescription
            transfer.updatedAt = Date()
            try? await repository.upsertProviderTransfer(transfer)
            upsertProviderTransferRecords([transfer])
        }
    }

    private func providerTransferProgressHandler(
        transferID: UUID,
        fileByteCount: Int64?,
        services: PinesAppServices
    ) -> ProviderUploadProgress {
        let gate = ProviderTransferProgressGate()
        return { [weak self] sent, expected in
            guard let fileByteCount, fileByteCount > 0, expected > 0 else { return }
            let fraction = min(1, max(0, Double(sent) / Double(expected)))
            let completed = min(fileByteCount, Int64(Double(fileByteCount) * fraction))
            guard gate.shouldEmit(completedBytes: completed, totalBytes: fileByteCount) else { return }
            Task { @MainActor [weak self] in
                await self?.recordProviderTransferProgress(
                    transferID: transferID,
                    completedBytes: completed,
                    totalBytes: fileByteCount,
                    services: services
                )
            }
        }
    }

    private func recordProviderTransferProgress(
        transferID: UUID,
        completedBytes: Int64,
        totalBytes: Int64,
        services: PinesAppServices
    ) async {
        guard let repository = services.providerTransferRepository,
              var transfer = providerTransfers.first(where: { $0.id == transferID }),
              transfer.status == .transferring,
              completedBytes > transfer.completedBytes
        else { return }
        let minimumStep = max(Int64(64 * 1_024), totalBytes / 100)
        guard completedBytes == totalBytes || completedBytes - transfer.completedBytes >= minimumStep else { return }
        transfer.completedBytes = completedBytes
        transfer.totalBytes = totalBytes
        transfer.updatedAt = Date()
        do {
            try await repository.upsertProviderTransfer(transfer)
            upsertProviderTransferRecords([transfer])
        } catch {
            setIfChanged(\.providerLifecycleError, error.localizedDescription)
        }
    }

    func stageVaultDocumentForProviderUpload(
        documentID: UUID,
        services: PinesAppServices
    ) async throws -> PinesStagedVaultProviderDocument {
        guard let repository = services.vaultRepository else {
            throw InferenceError.invalidRequest("Vault storage is unavailable.")
        }
        guard let document = try await repository.document(id: documentID) else {
            throw InferenceError.invalidRequest("Vault document \(documentID.uuidString) was not found.")
        }
        let staged = try await ProviderTransferFileService.shared.stageTextPages(
            transferID: UUID(),
            fileName: Self.providerStorageSafeFileName(document.title, fallbackExtension: "txt")
        ) { limit, offset in
            try await repository.chunks(documentID: documentID, limit: limit, offset: offset).map(\.text)
        }
        return PinesStagedVaultProviderDocument(document: document, file: staged)
    }

}
