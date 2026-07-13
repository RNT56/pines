import Foundation
import PinesCore

@MainActor
extension PinesAppModel {
    func enqueueProviderFileTransfer(
        provider: CloudProviderConfiguration,
        fileURL: URL,
        purpose: String?,
        services: PinesAppServices
    ) async throws {
        guard [.openAI, .anthropic, .gemini].contains(provider.kind) else {
            throw InferenceError.invalidRequest("\(provider.kind.pinesLifecycleTitle) file upload is not supported.")
        }
        guard let repository = services.providerTransferRepository else {
            throw InferenceError.invalidRequest("Transfer persistence is unavailable.")
        }

        let transferID = UUID()
        let stagedURL = try stageProviderTransferSource(fileURL, transferID: transferID)
        let values = try stagedURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let transfer = ProviderTransferRecord(
            id: transferID,
            providerID: provider.id,
            providerKind: provider.kind,
            source: .localFile,
            sourceReference: fileURL.lastPathComponent,
            stagedLocalURL: stagedURL,
            fileName: fileURL.lastPathComponent,
            contentType: values.contentType?.preferredMIMEType,
            purpose: purpose,
            totalBytes: values.fileSize.map(Int64.init)
        )
        try await repository.upsertProviderTransfer(transfer)
        await refreshProviderTransfers(services: services)
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
        let transfer = ProviderTransferRecord(
            providerID: provider.id,
            providerKind: provider.kind,
            source: .vaultDocument,
            sourceReference: documentID.uuidString,
            fileName: documentTitle,
            contentType: "text/plain",
            purpose: purpose
        )
        try await repository.upsertProviderTransfer(transfer)
        await refreshProviderTransfers(services: services)
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
        await refreshProviderTransfers(services: services)
    }

    func retryProviderTransfer(id: UUID, services: PinesAppServices) async {
        guard var transfer = providerTransfers.first(where: { $0.id == id }), transfer.status.canRetry else { return }
        if transfer.source == .localFile,
           transfer.stagedLocalURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
            transfer.lastError = "The staged source is no longer available. Choose the file again to create a new transfer."
            transfer.status = .failed
            transfer.updatedAt = Date()
            try? await services.providerTransferRepository?.upsertProviderTransfer(transfer)
            await refreshProviderTransfers(services: services)
            return
        }
        transfer.retryCount += 1
        transfer.status = .queued
        transfer.completedBytes = 0
        transfer.completedAt = nil
        transfer.updatedAt = Date()
        transfer.lastError = nil
        try? await services.providerTransferRepository?.upsertProviderTransfer(transfer)
        await refreshProviderTransfers(services: services)
        startProviderTransfer(transfer, services: services)
    }

    func removeProviderTransfer(id: UUID, services: PinesAppServices) async {
        guard let transfer = providerTransfers.first(where: { $0.id == id }), !transfer.status.isActive else { return }
        if let stagedURL = transfer.stagedLocalURL {
            try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent())
        }
        try? await services.providerTransferRepository?.deleteProviderTransfer(id: id)
        await refreshProviderTransfers(services: services)
    }

    func refreshProviderTransfers(services: PinesAppServices) async {
        guard let repository = services.providerTransferRepository else { return }
        do {
            setIfChanged(\.providerTransfers, try await repository.listProviderTransfers(providerID: nil))
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
            await refreshProviderTransfers(services: services)
            try Task.checkCancellation()

            transfer.status = .transferring
            transfer.updatedAt = Date()
            try await repository.upsertProviderTransfer(transfer)
            await refreshProviderTransfers(services: services)

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
            await refreshProviderLifecycleState(services: services)

            transfer.status = .completed
            transfer.completedAt = Date()
            transfer.updatedAt = transfer.completedAt ?? Date()
            transfer.lastError = nil
            try await repository.upsertProviderTransfer(transfer)
        } catch is CancellationError {
            transfer.status = .cancelled
            transfer.lastError = "Cancelled by you. Retry when you are ready."
            transfer.updatedAt = Date()
            try? await repository.upsertProviderTransfer(transfer)
        } catch {
            transfer.status = .failed
            transfer.lastError = error.localizedDescription
            transfer.updatedAt = Date()
            try? await repository.upsertProviderTransfer(transfer)
        }
        await refreshProviderTransfers(services: services)
    }

    private func providerTransferProgressHandler(
        transferID: UUID,
        fileByteCount: Int64?,
        services: PinesAppServices
    ) -> ProviderUploadProgress {
        { [weak self] sent, expected in
            guard let fileByteCount, fileByteCount > 0, expected > 0 else { return }
            let fraction = min(1, max(0, Double(sent) / Double(expected)))
            let completed = min(fileByteCount, Int64(Double(fileByteCount) * fraction))
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
            await refreshProviderTransfers(services: services)
        } catch {
            setIfChanged(\.providerLifecycleError, error.localizedDescription)
        }
    }

    private func stageProviderTransferSource(_ sourceURL: URL, transferID: UUID) throws -> URL {
        let hasScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasScope { sourceURL.stopAccessingSecurityScopedResource() } }
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Pines/ProviderTransfers/\(transferID.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appending(path: sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
