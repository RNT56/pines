import CryptoKit
import Foundation
import OSLog
import PinesCore

private let modelLifecycleLogger = Logger(subsystem: "com.schtack.pines", category: "ModelLifecycle")

private struct ModelDownloadProgressWriteGate {
    private static let minimumInterval: TimeInterval = 1.25
    private static let minimumFractionDelta = 0.01
    private static let minimumByteDelta: Int64 = 16 * 1024 * 1024

    private var lastPersistedAt = Date.distantPast
    private var lastPersistedBytes: Int64 = 0
    private var lastPersistedFraction: Double?
    private var lastPersistedTotalBytes: Int64?

    mutating func shouldPersist(_ progress: ModelDownloadProgress, now: Date = Date()) -> Bool {
        guard progress.status == .downloading else { return true }

        let elapsed = now.timeIntervalSince(lastPersistedAt)
        guard elapsed >= Self.minimumInterval else { return false }

        let byteDelta = progress.bytesReceived - lastPersistedBytes
        if byteDelta < 0 {
            return true
        }
        guard byteDelta >= Self.minimumByteDelta else {
            if progress.totalBytes != lastPersistedTotalBytes {
                return true
            }

            guard let fraction = fraction(for: progress) else {
                return byteDelta > 0
            }
            return abs(fraction - (lastPersistedFraction ?? 0)) >= Self.minimumFractionDelta
        }

        return true
    }

    mutating func record(_ progress: ModelDownloadProgress, now: Date = Date()) {
        lastPersistedAt = now
        lastPersistedBytes = progress.bytesReceived
        lastPersistedFraction = fraction(for: progress)
        lastPersistedTotalBytes = progress.totalBytes
    }

    private func fraction(for progress: ModelDownloadProgress) -> Double? {
        guard let totalBytes = progress.totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(progress.bytesReceived) / Double(totalBytes)))
    }
}

struct ModelLifecycleService: Sendable {
    private static let downloadTasks = ModelDownloadTaskCoordinator()
    private static let maxDownloadAttempts = 4
    private static let baseDownloadRetryDelayNanoseconds: UInt64 = 750_000_000

    private struct StagingRecoveryState {
        static let empty = StagingRecoveryState(reusableBytes: 0)

        var reusableBytes: Int64

        var hasReusableBytes: Bool {
            reusableBytes > 0
        }
    }

    let catalog: HuggingFaceModelCatalogService
    let classifier: ModelPreflightClassifier
    let installRepository: any ModelInstallRepository
    let downloadRepository: any ModelDownloadRepository
    let auditRepository: (any AuditEventRepository)?
    let secretStore: (any SecretStore)?
    let resourcePolicy: ModelDiscoveryResourcePolicy?

    func preflight(repository: String, revision: String = "main") async throws -> ModelPreflightResult {
        let token = try await huggingFaceToken()
        let input = try await catalog.preflight(repository: repository, revision: revision, accessToken: token)
        return classify(input)
    }

    func install(repository: String, revision: String = "main", mode: ModelInstallMode = .automatic) async throws {
        let taskID = UUID()
        guard let task = await Self.downloadTasks.start(repository: repository, id: taskID, operation: { [self] in
            try await performInstall(repository: repository, revision: revision, mode: mode)
        }) else {
            return
        }

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            await Self.downloadTasks.finish(repository: repository, id: taskID)
        } catch {
            await Self.downloadTasks.finish(repository: repository, id: taskID)
            throw error
        }
    }

    func cancelDownload(repository: String) async throws {
        if let task = await Self.downloadTasks.cancel(repository: repository) {
            try await markActiveDownloadsCancelled(for: repository)
            do {
                try await task.value
            } catch InferenceError.cancelled {
                return
            } catch is CancellationError {
                return
            }
            return
        }

        await BackgroundModelFileDownloadCenter.shared.cancelBackgroundDownloads(for: repository)
        let cancelled = try await markActiveDownloadsCancelled(for: repository)
        guard cancelled else { return }
        try Self.removeStagingDirectory(for: repository)
        try await installRepository.deleteInstall(repository: repository)
        try await auditRepository?.append(
            AuditEvent(category: .modelDownload, summary: "Cancelled \(repository)", modelID: ModelID(rawValue: repository))
        )
    }

    @discardableResult
    func validateInstalledModels() async throws -> Int {
        let installs = try await installRepository.listInstalledAndCuratedModels()
        var repairedCount = 0
        for install in installs where install.state == .installed {
            guard let resolvedURL = try Self.installedModelDirectory(for: install) else {
                var failed = install
                failed.state = .failed
                failed.localURL = nil
                try await installRepository.upsertInstall(failed)
                repairedCount += 1
                try await auditRepository?.append(
                    AuditEvent(
                        category: .modelDownload,
                        summary: "Marked incomplete install failed: \(install.repository)",
                        modelID: install.modelID
                    )
                )
                continue
            }

            if resolvedURL != install.localURL {
                var repaired = install
                repaired.localURL = resolvedURL
                try await installRepository.upsertInstall(repaired)
                repairedCount += 1
                try await auditRepository?.append(
                    AuditEvent(
                        category: .modelDownload,
                        summary: "Repaired installed model path: \(install.repository)",
                        modelID: install.modelID
                    )
                )
            }
        }
        return repairedCount
    }

    func reconcileInterruptedDownloads() async throws {
        await BackgroundModelFileDownloadCenter.shared.recoverBackgroundTasks()
        let downloads = try await downloadRepository.listDownloads()
        var failedInstallRepositories: [String: String] = [:]
        var cleanupRepositories = Set<String>()
        var interruptedDownloadByRepository: [String: ModelDownloadProgress] = [:]
        var activeDownloadByRepository: [String: ModelDownloadProgress] = [:]

        for download in downloads where download.status.isActive {
            let key = download.repository.lowercased()
            let hasActiveTask = await Self.downloadTasks.hasActiveDownload(for: download.repository)
            let hasBackgroundTask = await BackgroundModelFileDownloadCenter.shared.hasBackgroundDownload(for: download.repository)
            guard !hasActiveTask, !hasBackgroundTask else { continue }
            activeDownloadByRepository[key] = download
        }

        let installs = try await installRepository.listInstalledAndCuratedModels()
        let installByRepository = Dictionary(uniqueKeysWithValues: installs.map { ($0.repository.lowercased(), $0) })

        for (key, download) in activeDownloadByRepository {
            if let install = installByRepository[key],
               install.state == .installed,
               let resolvedURL = try Self.installedModelDirectory(for: install) {
                var completed = download
                completed.status = .installed
                completed.bytesReceived = completed.totalBytes ?? completed.bytesReceived
                completed.localURL = resolvedURL
                completed.errorMessage = nil
                completed.updatedAt = Date()
                try await upsertDownloadProgress(completed)
                continue
            }
            if let install = installByRepository[key],
               try await promoteCompletedStagingDownloadIfPossible(repository: download.repository, install: install, download: download) {
                continue
            }

            let recovery = (try? Self.stagingRecoveryState(for: download.repository)) ?? .empty

            var failed = download
            failed.status = .failed
            failed.bytesReceived = max(failed.bytesReceived, recovery.reusableBytes)
            failed.errorMessage = recovery.hasReusableBytes
                ? "Download was interrupted. Resume to continue."
                : "Download was interrupted."
            failed.updatedAt = Date()
            interruptedDownloadByRepository[key] = failed
            failedInstallRepositories[key] = download.repository
            if !recovery.hasReusableBytes {
                cleanupRepositories.insert(key)
            }
            try await upsertDownloadProgress(failed)
        }

        for install in installs where install.state == .downloading {
            let key = install.repository.lowercased()
            let hasActiveTask = await Self.downloadTasks.hasActiveDownload(for: install.repository)
            let hasBackgroundTask = await BackgroundModelFileDownloadCenter.shared.hasBackgroundDownload(for: install.repository)
            guard !hasActiveTask, !hasBackgroundTask else { continue }
            if try await promoteCompletedStagingDownloadIfPossible(
                repository: install.repository,
                install: install,
                download: interruptedDownloadByRepository[key]
            ) {
                continue
            }
            let recovery = (try? Self.stagingRecoveryState(for: install.repository)) ?? .empty
            failedInstallRepositories[key] = install.repository
            if !recovery.hasReusableBytes {
                cleanupRepositories.insert(key)
            }
        }

        for install in installs where install.state == .installed {
            guard let resolvedURL = try Self.installedModelDirectory(for: install) else {
                var failed = install
                failed.state = .failed
                failed.localURL = nil
                try await installRepository.upsertInstall(failed)
                try await auditRepository?.append(
                    AuditEvent(
                        category: .modelDownload,
                        summary: "Marked incomplete install failed: \(install.repository)",
                        modelID: install.modelID
                    )
                )
                continue
            }

            if resolvedURL != install.localURL {
                var repaired = install
                repaired.localURL = resolvedURL
                try await installRepository.upsertInstall(repaired)
            }
        }

        for (key, repository) in failedInstallRepositories {
            if cleanupRepositories.contains(key) {
                do {
                    try Self.removeStagingDirectory(for: repository)
                } catch {
                    modelLifecycleLogger.warning("Failed to remove interrupted staging directory for \(repository, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            let failed = Self.failedInstall(
                repository: repository,
                existing: installByRepository[key],
                download: interruptedDownloadByRepository[key]
            )
            try await installRepository.upsertInstall(failed)
            try await auditRepository?.append(
                AuditEvent(category: .modelDownload, summary: "Interrupted \(repository)", modelID: ModelID(rawValue: repository))
            )
        }
    }

    private func promoteCompletedStagingDownloadIfPossible(
        repository: String,
        install: ModelInstall,
        download: ModelDownloadProgress?
    ) async throws -> Bool {
        let stagingURL = try Self.stagingDirectory(for: repository)
        guard FileManager.default.fileExists(atPath: stagingURL.path),
              Self.resolvedModelDirectory(from: stagingURL, modalities: install.modalities) != nil,
              try Self.validateStagedChecksumsIfPresent(stagingURL)
        else {
            return false
        }

        let finalURL = try Self.finalDirectory(for: repository)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: stagingURL, to: finalURL)
        try? FileManager.default.removeItem(at: ModelDownloadStagingManifestStore.manifestURL(in: finalURL))
        let resolvedURL = try Self.validateModelDirectory(
            finalURL,
            repository: repository,
            modalities: install.modalities
        )

        var installed = install
        installed.localURL = resolvedURL
        installed.state = .installed
        try await installRepository.upsertInstall(installed)

        if var completed = download {
            completed.status = .installed
            completed.bytesReceived = completed.totalBytes ?? (try? Self.directoryByteCount(finalURL)) ?? completed.bytesReceived
            completed.localURL = resolvedURL
            completed.errorMessage = nil
            completed.updatedAt = Date()
            try await upsertDownloadProgress(completed)
        }

        try await auditRepository?.append(
            AuditEvent(category: .modelDownload, summary: "Recovered completed download \(repository)", modelID: install.modelID)
        )
        return true
    }

    private func performInstall(repository: String, revision: String = "main", mode: ModelInstallMode = .automatic) async throws {
        try await markInterruptedActiveDownloadsCancelled(for: repository)
        let existingInstalls = try await installRepository.listInstalledAndCuratedModels()
        if let existing = existingInstalls
            .first(where: { $0.repository.caseInsensitiveCompare(repository) == .orderedSame }) {
            switch existing.state {
            case .installed:
                if let resolvedURL = try Self.installedModelDirectory(for: existing) {
                    if mode == .full, !existing.modalities.contains(.vision) {
                        try Self.removeInstalledDirectory(for: repository, localURL: existing.localURL)
                    } else {
                        if resolvedURL != existing.localURL {
                            var repaired = existing
                            repaired.localURL = resolvedURL
                            try await installRepository.upsertInstall(repaired)
                        }
                        return
                    }
                }
                try Self.removeInstalledDirectory(for: repository, localURL: existing.localURL)
            case .downloading, .remote, .failed, .unsupported:
                break
            }
        }

        try Task.checkCancellation()
        let accessToken = try await huggingFaceToken()
        let input = try await catalog.preflight(repository: repository, revision: revision, accessToken: accessToken)
        var result = classify(input)
        guard result.verification != .unsupported else {
            throw InferenceError.unsupportedCapability(result.reasons.joined(separator: "\n"))
        }
        result.modalities = try mode.resolvedModalities(from: result.modalities)
        try Task.checkCancellation()
        try Self.validateAvailableDiskSpace(for: result.estimatedBytes)

        let files = input.files.filter { Self.shouldDownload($0, modalities: result.modalities) }
        try Self.validateDownloadManifest(files, repository: repository, modalities: result.modalities)
        var resolvedFileSizes = Dictionary(
            uniqueKeysWithValues: files.compactMap { file -> (String, Int64)? in
                guard let size = file.size, size > 0 else { return nil }
                return (file.path, size)
            }
        )
        for file in files where resolvedFileSizes[file.path] == nil {
            do {
                if let size = try await Self.remoteFileSize(
                    repository: repository,
                    revision: revision,
                    file: file,
                    accessToken: accessToken
                ) {
                    resolvedFileSizes[file.path] = size
                }
            } catch {
                modelLifecycleLogger.warning("Failed to resolve remote file size for \(repository, privacy: .public)/\(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        let totalBytes = Self.totalDownloadBytes(
            for: files,
            fileSizes: resolvedFileSizes,
            fallback: result.estimatedBytes > 0 ? result.estimatedBytes : nil
        )
        if let totalBytes,
           let reason = resourcePolicy?.rejectionReason(repository: repository, knownDownloadBytes: totalBytes) {
            throw InferenceError.unsupportedCapability(reason)
        }
        if let totalBytes {
            try Self.validateAvailableDiskSpace(for: totalBytes)
        }
        let downloadID = UUID()
        var progress = ModelDownloadProgress(
            id: downloadID,
            repository: repository,
            revision: revision,
            status: .queued,
            totalBytes: totalBytes
        )
        try await upsertDownloadProgress(progress)

        let stagingURL = try Self.stagingDirectory(for: repository)
        let finalURL = try Self.finalDirectory(for: repository)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let plannedFiles = files.map { file in
            ModelFileInfo(path: file.path, size: resolvedFileSizes[file.path] ?? file.size, oid: file.oid)
        }
        var manifest = try ModelDownloadStagingManifestStore.read(from: stagingURL)
            ?? ModelDownloadStagingManifest(repository: repository, revision: revision, totalBytes: totalBytes)
        manifest.mergeDownloadPlan(
            repository: repository,
            revision: revision,
            totalBytes: totalBytes,
            files: plannedFiles
        )
        try ModelDownloadStagingManifestStore.write(manifest, to: stagingURL)

        let install = ModelInstall(
            modelID: ModelID(rawValue: repository),
            displayName: repository.components(separatedBy: "/").last ?? repository,
            repository: repository,
            revision: revision,
            localURL: finalURL,
            modalities: result.modalities,
            verification: result.verification,
            state: .downloading,
            parameterCount: result.parameterCount,
            estimatedBytes: result.estimatedBytes,
            license: result.license,
            modelType: result.modelType,
            processorClass: result.processorClass
        )
        try await installRepository.upsertInstall(install)

        do {
            var received: Int64 = 0
            var progressWriteGate = ModelDownloadProgressWriteGate()

            for file in plannedFiles {
                try Task.checkCancellation()
                progress.status = .downloading
                progress.currentFile = file.path
                progress.bytesReceived = received
                progress.updatedAt = Date()
                try await upsertDownloadProgress(progress, gate: &progressWriteGate, force: true)

                let destination = stagingURL.appending(path: file.path)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if try Self.isUsableDownloadedFile(file, at: destination) {
                    let fileBytes = try Self.byteCount(for: destination)
                    received += fileBytes
                    try ModelDownloadStagingManifestStore.update(
                        in: stagingURL,
                        path: file.path,
                        expectedBytes: file.size,
                        checksum: file.oid,
                        receivedBytes: fileBytes,
                        status: .complete
                    )
                    continue
                }

                var currentFileBytes = try Self.reusablePartialByteCount(file, at: destination)
                if currentFileBytes > 0 {
                    progress.bytesReceived = received + currentFileBytes
                    progress.updatedAt = Date()
                    try await upsertDownloadProgress(progress, gate: &progressWriteGate, force: true)
                }

                try await Self.downloadFile(
                    repository: repository,
                    revision: revision,
                    file: file,
                    destination: destination,
                    stagingDirectory: stagingURL,
                    resumeOffset: currentFileBytes,
                    accessToken: accessToken
                ) { fileBytes, expectedFileSize in
                    try Task.checkCancellation()
                    currentFileBytes = max(0, fileBytes)
                    progress.bytesReceived = received + currentFileBytes
                    if let expectedFileSize {
                        resolvedFileSizes[file.path] = expectedFileSize
                        if let inferredTotal = Self.totalDownloadBytes(
                            for: plannedFiles,
                            fileSizes: resolvedFileSizes,
                            fallback: progress.totalBytes
                        ) {
                            progress.totalBytes = inferredTotal
                        }
                    }
                    let now = Date()
                    progress.updatedAt = now
                    try await upsertDownloadProgress(progress, gate: &progressWriteGate)
                }
                currentFileBytes = try Self.byteCount(for: destination)
                received += currentFileBytes
                try ModelDownloadStagingManifestStore.update(
                    in: stagingURL,
                    path: file.path,
                    expectedBytes: resolvedFileSizes[file.path] ?? file.size,
                    checksum: file.oid,
                    receivedBytes: currentFileBytes,
                    status: .complete
                )

                if let oid = file.oid, oid.count == 64 {
                    try Task.checkCancellation()
                    progress.status = .verifying
                    progress.checksum = oid
                    progress.updatedAt = Date()
                    try await upsertDownloadProgress(progress, gate: &progressWriteGate, force: true)
                    let digest = try await Task.detached(priority: .utility) {
                        try Self.sha256Hex(url: destination)
                    }.value
                    guard digest.caseInsensitiveCompare(oid) == .orderedSame else {
                        throw URLError(.cannotDecodeContentData)
                    }
                }
            }

            progress.status = .installing
            progress.bytesReceived = received
            progress.localURL = finalURL
            progress.updatedAt = Date()
            try await upsertDownloadProgress(progress, gate: &progressWriteGate, force: true)

            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)
            let resolvedURL = try Self.validateModelDirectory(
                finalURL,
                repository: repository,
                modalities: result.modalities
            )
            try? FileManager.default.removeItem(at: ModelDownloadStagingManifestStore.manifestURL(in: finalURL))

            var installed = install
            installed.localURL = resolvedURL
            installed.state = .installed
            try await installRepository.upsertInstall(installed)

            progress.status = .installed
            progress.bytesReceived = progress.totalBytes ?? received
            progress.updatedAt = Date()
            try await upsertDownloadProgress(progress, gate: &progressWriteGate, force: true)
            try await auditRepository?.append(
                AuditEvent(category: .modelDownload, summary: "Installed \(repository)", modelID: ModelID(rawValue: repository))
            )
        } catch is CancellationError {
            try await finalizeCancelledDownload(progress: progress, repository: repository)
            throw InferenceError.cancelled
        } catch InferenceError.cancelled {
            try await finalizeCancelledDownload(progress: progress, repository: repository)
            throw InferenceError.cancelled
        } catch {
            progress.status = .failed
            progress.errorMessage = Self.downloadFailureMessage(for: error)
            progress.updatedAt = Date()
            try await upsertDownloadProgress(progress)
            try await installRepository.updateInstallState(.failed, for: repository)
            throw error
        }
    }

    func delete(repository: String) async throws {
        let hasRunningDownload = await Self.downloadTasks.hasActiveDownload(for: repository)
        let hasPersistedActiveDownload = try await hasActiveDownload(for: repository)
        if hasRunningDownload || hasPersistedActiveDownload {
            try await cancelDownload(repository: repository)
        }

        let directory = try Self.modelsDirectory().appending(path: Self.safeDirectoryName(repository), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        let legacyDirectory = try Self.modelsDirectory().appending(path: Self.legacySafeDirectoryName(repository), directoryHint: .isDirectory)
        if legacyDirectory != directory, FileManager.default.fileExists(atPath: legacyDirectory.path) {
            try FileManager.default.removeItem(at: legacyDirectory)
        }
        let stagingDirectory = try Self.modelsDirectory()
            .appending(path: "staging", directoryHint: .isDirectory)
            .appending(path: Self.safeDirectoryName(repository), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: stagingDirectory.path) {
            try FileManager.default.removeItem(at: stagingDirectory)
        }
        try await installRepository.deleteInstall(repository: repository)
        let downloads = try await downloadRepository.listDownloads()
        for download in downloads where download.repository.caseInsensitiveCompare(repository) == .orderedSame {
            try await downloadRepository.deleteDownload(id: download.id)
        }
        await ModelDownloadLiveActivityController.end(repository: repository)
        try await auditRepository?.append(
            AuditEvent(category: .modelDownload, summary: "Deleted \(repository)", modelID: ModelID(rawValue: repository))
        )
    }

    func deleteAllLocalModelData() async throws {
        let downloads = try await downloadRepository.listDownloads()
        let installs = try await installRepository.listInstalledAndCuratedModels()
        let repositories = Set(downloads.map(\.repository) + installs.map(\.repository))

        for repository in repositories {
            if await Self.downloadTasks.hasActiveDownload(for: repository) {
                try? await cancelDownload(repository: repository)
            } else {
                await BackgroundModelFileDownloadCenter.shared.cancelBackgroundDownloads(for: repository)
            }
            await ModelDownloadLiveActivityController.end(repository: repository)
        }

        let directory = try Self.modelsDirectory()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        for install in installs {
            try await installRepository.deleteInstall(repository: install.repository)
        }
        for download in downloads {
            try await downloadRepository.deleteDownload(id: download.id)
        }
        try await auditRepository?.append(
            AuditEvent(category: .modelDownload, summary: "Deleted all local model data.")
        )
    }

    private static func shouldDownload(_ file: ModelFileInfo) -> Bool {
        let components = file.path.split(separator: "/")
        guard !components.contains(where: { $0.hasPrefix(".") }) else { return false }
        let filename = components.last.map { String($0).lowercased() } ?? file.path.lowercased()
        let pathExtension = filename.split(separator: ".").last.map(String.init) ?? ""

        // Keep this in sync with mlx-swift-lm's model snapshot patterns:
        // ["*.safetensors", "*.json", "*.jinja"]. The extra tokenizer extensions
        // are retained for imported or legacy local repositories.
        return ["safetensors", "json", "jinja", "model", "txt", "tiktoken"].contains(pathExtension)
    }

    private static func shouldDownload(_ file: ModelFileInfo, modalities: Set<ModelModality>) -> Bool {
        guard shouldDownload(file) else { return false }
        guard !modalities.contains(.vision) else { return true }

        switch filename(file.path) {
        case "processor_config.json", "preprocessor_config.json", "image_processor_config.json", "video_preprocessor_config.json":
            return false
        default:
            return true
        }
    }

    private func hasActiveDownload(for repository: String) async throws -> Bool {
        try await downloadRepository.listDownloads().contains { download in
            guard download.repository.caseInsensitiveCompare(repository) == .orderedSame else { return false }
            return download.status.isActive
        }
    }

    private func upsertDownloadProgress(_ progress: ModelDownloadProgress) async throws {
        try await downloadRepository.upsertDownload(progress)
        await ModelDownloadLiveActivityController.update(progress: progress)
    }

    private func upsertDownloadProgress(
        _ progress: ModelDownloadProgress,
        gate: inout ModelDownloadProgressWriteGate,
        force: Bool = false
    ) async throws {
        guard force || gate.shouldPersist(progress) else { return }
        gate.record(progress)
        try await upsertDownloadProgress(progress)
    }

    @discardableResult
    private func markActiveDownloadsCancelled(for repository: String) async throws -> Bool {
        let downloads = try await downloadRepository.listDownloads()
        var didCancel = false
        for download in downloads where download.repository.caseInsensitiveCompare(repository) == .orderedSame && download.status.isActive {
            didCancel = true
            var cancelled = download
            cancelled.status = .cancelled
            cancelled.errorMessage = nil
            cancelled.updatedAt = Date()
            try await upsertDownloadProgress(cancelled)
        }
        return didCancel
    }

    private func markInterruptedActiveDownloadsCancelled(for repository: String) async throws {
        let downloads = try await downloadRepository.listDownloads()
        for download in downloads where download.repository.caseInsensitiveCompare(repository) == .orderedSame && download.status.isActive {
            var cancelled = download
            cancelled.status = .cancelled
            cancelled.errorMessage = "Download was interrupted."
            cancelled.updatedAt = Date()
            try await upsertDownloadProgress(cancelled)
        }
    }

    private func finalizeCancelledDownload(progress: ModelDownloadProgress, repository: String) async throws {
        var cancelled = progress
        var cleanupError: Error?
        do {
            try Self.removeStagingDirectory(for: repository)
        } catch {
            cleanupError = error
        }

        cancelled.status = .cancelled
        cancelled.errorMessage = cleanupError?.localizedDescription
        cancelled.updatedAt = Date()
        try await upsertDownloadProgress(cancelled)
        try await installRepository.deleteInstall(repository: repository)
        try await auditRepository?.append(
            AuditEvent(category: .modelDownload, summary: "Cancelled \(repository)", modelID: ModelID(rawValue: repository))
        )

        if let cleanupError {
            throw cleanupError
        }
    }

    private func huggingFaceToken() async throws -> String? {
        try await secretStore?.read(
            service: HuggingFaceCredentialService.keychainService,
            account: HuggingFaceCredentialService.tokenAccount
        )
    }

    private func classify(_ input: ModelPreflightInput) -> ModelPreflightResult {
        var result = classifier.classify(input)
        guard let resourcePolicy else { return result }
        let decision = resourcePolicy.evaluate(input, modalities: result.modalities)
        if let knownDownloadBytes = decision.knownDownloadBytes, knownDownloadBytes > result.estimatedBytes {
            result.estimatedBytes = knownDownloadBytes
        } else if let estimatedWeightBytes = decision.estimatedWeightBytes, result.estimatedBytes == 0 {
            result.estimatedBytes = estimatedWeightBytes
        }
        result.parameterCount = decision.inferredParameterCount ?? result.parameterCount
        guard decision.isRejected else { return result }
        result.verification = .unsupported
        if let reason = decision.reason, !result.reasons.contains(reason) {
            result.reasons.append(reason)
        }
        return result
    }

    private static func downloadFile(
        repository: String,
        revision: String,
        file: ModelFileInfo,
        destination: URL,
        stagingDirectory: URL,
        resumeOffset: Int64,
        accessToken: String?,
        progress: (Int64, Int64?) async throws -> Void
    ) async throws {
        let encodedRepository = repository
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "https://huggingface.co/\(encodedRepository)/resolve/\(revision)/\(encodedPath(file.path))") else {
            throw URLError(.badURL)
        }

        var attempt = 1
        while true {
            try Task.checkCancellation()
            let persistedBytes = (try? byteCount(for: destination)) ?? max(0, resumeOffset)
            let plan = ModelDownloadResumePlan(expectedBytes: file.size, existingBytes: persistedBytes)
            guard !plan.isComplete else { return }

            var request = authorizedRequest(url: url, accessToken: accessToken)
            if let rangeHeader = plan.rangeHeader {
                request.addValue(rangeHeader, forHTTPHeaderField: "Range")
            }
            let metadata = BackgroundModelFileDownloadMetadata(
                repository: repository,
                revision: revision,
                filePath: file.path,
                destinationPath: destination.path,
                stagingDirectoryPath: stagingDirectory.path,
                declaredSize: plan.expectedBytes,
                checksum: file.oid,
                resumeOffset: plan.resumeOffset,
                rangeEnd: nil
            )

            do {
                try await progress(plan.resumeOffset, plan.expectedBytes)
                try await downloadRequest(request, metadata: metadata, progress: progress)
                try validateCompletedDownload(repository: repository, file: file, destination: destination)
                return
            } catch {
                guard shouldRetryDownload(error, attempt: attempt) else {
                    throw error
                }

                let diskBytes = (try? byteCount(for: destination)) ?? plan.resumeOffset
                try await progress(diskBytes, plan.expectedBytes)
                let delay = retryDelayNanoseconds(forAttempt: attempt)
                modelLifecycleLogger.warning("Retrying model download for \(repository, privacy: .public)/\(file.path, privacy: .public) after attempt \(attempt, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(nanoseconds: delay)
                attempt += 1
            }
        }
    }

    private static func authorizedRequest(url: URL, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty {
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func downloadRequest(
        _ request: URLRequest,
        metadata: BackgroundModelFileDownloadMetadata,
        progress: (Int64, Int64?) async throws -> Void
    ) async throws {
        let events = BackgroundModelFileDownloadCenter.shared.downloadEvents(
            request: request,
            metadata: metadata
        )
        for try await event in events {
            switch event {
            case let .progress(_, totalBytesWritten, expectedFileSize):
                try await progress(metadata.resumeOffset + totalBytesWritten, expectedFileSize)
            }
        }
    }

    private static func validateCompletedDownload(
        repository: String,
        file: ModelFileInfo,
        destination: URL
    ) throws {
        guard let expectedBytes = file.size, expectedBytes > 0 else { return }
        let actualBytes = try byteCount(for: destination)
        if actualBytes < expectedBytes {
            throw ModelDownloadTransferError.incompleteFile(
                repository: repository,
                filePath: file.path,
                expectedBytes: expectedBytes,
                actualBytes: actualBytes
            )
        }
        if actualBytes > expectedBytes {
            throw ModelDownloadTransferError.unexpectedFileSize(
                repository: repository,
                filePath: file.path,
                expectedBytes: expectedBytes,
                actualBytes: actualBytes
            )
        }
    }

    private static func shouldRetryDownload(_ error: Error, attempt: Int) -> Bool {
        guard attempt < maxDownloadAttempts else { return false }
        if error is CancellationError {
            return false
        }
        if let inferenceError = error as? InferenceError {
            if case .cancelled = inferenceError {
                return false
            }
        }
        if let transferError = error as? ModelDownloadTransferError {
            return transferError.isRetryable
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed,
             .badServerResponse:
            return true
        case .cancelled:
            return false
        default:
            return false
        }
    }

    private static func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let clampedAttempt = UInt64(max(1, min(attempt, 6)))
        return baseDownloadRetryDelayNanoseconds * (UInt64(1) << (clampedAttempt - 1))
    }

    private static func remoteFileSize(
        repository: String,
        revision: String,
        file: ModelFileInfo,
        accessToken: String?
    ) async throws -> Int64? {
        let encodedRepository = repository
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "https://huggingface.co/\(encodedRepository)/resolve/\(revision)/\(encodedPath(file.path))") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        if let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty {
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (_, http) = try await URLSession.shared.data(for: request)
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ModelDownloadTransferError.httpStatus(
                code: http.statusCode,
                repository: repository,
                filePath: file.path,
                url: url,
                requestID: http.value(forHTTPHeaderField: "X-Request-Id"),
                contentRange: http.value(forHTTPHeaderField: "Content-Range")
            )
        }
        return Self.expectedFileSize(from: http, http: http, offset: 0, declaredSize: file.size)
    }

    private static func removeStagingDirectory(for repository: String) throws {
        let stagingDirectory = try stagingDirectory(for: repository)
        if FileManager.default.fileExists(atPath: stagingDirectory.path) {
            try FileManager.default.removeItem(at: stagingDirectory)
        }
    }

    private static func stagingDirectory(for repository: String) throws -> URL {
        try modelsDirectory()
            .appending(path: "staging", directoryHint: .isDirectory)
            .appending(path: safeDirectoryName(repository), directoryHint: .isDirectory)
    }

    private static func finalDirectory(for repository: String) throws -> URL {
        try modelsDirectory()
            .appending(path: safeDirectoryName(repository), directoryHint: .isDirectory)
    }

    private static func stagingRecoveryState(for repository: String) throws -> StagingRecoveryState {
        let stagingDirectory = try stagingDirectory(for: repository)
        guard FileManager.default.fileExists(atPath: stagingDirectory.path) else {
            return .empty
        }

        let manifestReusableBytes = (try? ModelDownloadStagingManifestStore.read(from: stagingDirectory)?.reusableBytes) ?? 0
        guard let enumerator = FileManager.default.enumerator(
            at: stagingDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return StagingRecoveryState(reusableBytes: manifestReusableBytes)
        }

        var fileBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            fileBytes += Int64(values.fileSize ?? 0)
        }
        return StagingRecoveryState(reusableBytes: fileBytes)
    }

    private static func validateStagedChecksumsIfPresent(_ stagingDirectory: URL) throws -> Bool {
        guard let manifest = try ModelDownloadStagingManifestStore.read(from: stagingDirectory) else {
            return true
        }

        for file in manifest.files where file.status == .complete {
            guard let checksum = file.checksum, checksum.count == 64 else { continue }
            let fileURL = stagingDirectory.appending(path: file.path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return false
            }
            let digest = try sha256Hex(url: fileURL)
            if digest.caseInsensitiveCompare(checksum) != .orderedSame {
                try? FileManager.default.removeItem(at: fileURL)
                try? ModelDownloadStagingManifestStore.update(
                    in: stagingDirectory,
                    path: file.path,
                    expectedBytes: file.expectedBytes,
                    checksum: checksum,
                    receivedBytes: 0,
                    status: .failed,
                    errorMessage: "Checksum mismatch."
                )
                return false
            }
        }
        return true
    }

    private static func removeInstalledDirectory(for repository: String, localURL: URL?) throws {
        let modelsDirectory = try modelsDirectory()
        let currentDirectory = modelsDirectory.appending(path: safeDirectoryName(repository), directoryHint: .isDirectory)
        let legacyDirectory = modelsDirectory.appending(path: legacySafeDirectoryName(repository), directoryHint: .isDirectory)
        let candidates = [localURL, currentDirectory, legacyDirectory]
            .compactMap(\.self)
            .uniquedByPath()

        for candidate in candidates where candidate.isDescendant(of: modelsDirectory) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                try FileManager.default.removeItem(at: candidate)
            }
        }
    }

    private static func validateDownloadManifest(
        _ files: [ModelFileInfo],
        repository: String,
        modalities: Set<ModelModality>
    ) throws {
        guard downloadableModelRoot(in: files, modalities: modalities) != nil else {
            var required = ["config.json", "tokenizer.json", "*.safetensors"]
            if modalities.contains(.vision) {
                required.append("processor_config.json or preprocessor_config.json")
            }
            throw InferenceError.unsupportedCapability(
                "The Hugging Face repository \(repository) does not expose the files Pines needs for local MLX loading: \(required.joined(separator: ", "))."
            )
        }
    }

    private static func failedInstall(
        repository: String,
        existing: ModelInstall?,
        download: ModelDownloadProgress?
    ) -> ModelInstall {
        if var existing {
            existing.state = .failed
            existing.revision = existing.revision ?? download?.revision
            existing.localURL = existing.localURL ?? download?.localURL
            existing.estimatedBytes = existing.estimatedBytes ?? download?.totalBytes
            return existing
        }

        let curatedEntry = CuratedModelManifest.default.entries.first {
            $0.repository.caseInsensitiveCompare(repository) == .orderedSame
        }
        return ModelInstall(
            modelID: ModelID(rawValue: repository),
            displayName: curatedEntry?.displayName ?? repository.components(separatedBy: "/").last ?? repository,
            repository: repository,
            revision: download?.revision,
            localURL: download?.localURL,
            modalities: curatedEntry?.modalities ?? [.text],
            verification: curatedEntry == nil ? .installable : .verified,
            state: .failed,
            estimatedBytes: download?.totalBytes
        )
    }

    private static func downloadFailureMessage(for error: Error) -> String {
        if let inferenceError = error as? InferenceError {
            return inferenceError.localizedDescription
        }
        if let transferError = error as? ModelDownloadTransferError {
            switch transferError {
            case let .httpStatus(code, _, _, _, _, _):
                switch code {
                case 401, 403:
                    return "Hugging Face rejected access for this model file. Check the Hub token or request access for the model."
                case 404:
                    return "Hugging Face could not find a required model file. Refresh the model metadata and retry."
                case 408, 425, 429, 500...599:
                    return "The model host throttled or interrupted the download. Resume to continue."
                default:
                    return "The model host returned HTTP \(code). Resume to retry."
                }
            case .incompleteFile:
                return "The model file download ended before all bytes arrived. Resume to continue."
            case .unexpectedFileSize:
                return "The downloaded model file size did not match Hugging Face metadata. Resume to retry the file."
            case .destinationSizeMismatch:
                return "The staged partial file no longer matches the resume point. Resume to retry from the bytes on disk."
            case .missingHTTPResponse:
                return "The model host returned a response without HTTP metadata. Resume to retry."
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotWriteToFile, .cannotCreateFile, .noPermissionsToReadFile:
                return "Not enough writable storage is available for this model download."
            case .cannotDecodeContentData:
                return "The downloaded model file did not match its expected checksum. Resume to retry the invalid file."
            case .networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return "The network connection was interrupted. Resume to continue."
            case .badServerResponse:
                return "The model host returned an unexpected response. Resume to retry."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func validateModelDirectory(
        _ directory: URL,
        repository: String,
        modalities: Set<ModelModality>
    ) throws -> URL {
        guard let resolved = resolvedModelDirectory(from: directory, modalities: modalities) else {
            throw InferenceError.invalidRequest(
                "The downloaded model \(repository) is incomplete. Delete it and download it again."
            )
        }
        return resolved
    }

    static func resolvedModelDirectory(from directory: URL, modalities: Set<ModelModality> = []) -> URL? {
        if hasRequiredModelFiles(in: directory, modalities: modalities) {
            return directory
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "config.json" {
            let candidate = fileURL.deletingLastPathComponent()
            if hasRequiredModelFiles(in: candidate, modalities: modalities) {
                return candidate
            }
        }

        return nil
    }

    static func installedModelDirectory(for install: ModelInstall) throws -> URL? {
        let modelsDirectory = try modelsDirectory()
        let currentDirectory = modelsDirectory.appending(path: safeDirectoryName(install.repository), directoryHint: .isDirectory)
        let legacyDirectory = modelsDirectory.appending(path: legacySafeDirectoryName(install.repository), directoryHint: .isDirectory)
        let candidates = [install.localURL, currentDirectory, legacyDirectory]
            .compactMap(\.self)
            .uniquedByPath()

        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            if let resolved = resolvedModelDirectory(from: candidate, modalities: install.modalities) {
                return resolved
            }
        }
        return nil
    }

    private static func hasRequiredModelFiles(in directory: URL, modalities: Set<ModelModality>) -> Bool {
        let fileManager = FileManager.default
        let configURL = directory.appending(path: "config.json")
        guard isNonEmptyRegularFile(configURL) else {
            return false
        }

        guard isNonEmptyRegularFile(directory.appending(path: "tokenizer.json")) else {
            return false
        }

        if modalities.contains(.vision) {
            let processorFiles = ["preprocessor_config.json", "processor_config.json"]
            guard processorFiles.contains(where: { isNonEmptyRegularFile(directory.appending(path: $0)) }) else {
                return false
            }
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator
            where fileURL.pathExtension.lowercased() == "safetensors" && isNonEmptyRegularFile(fileURL) {
            return true
        }
        return false
    }

    private static func isNonEmptyRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) > 0
        else {
            return false
        }
        return true
    }

    private static func downloadableModelRoot(
        in files: [ModelFileInfo],
        modalities: Set<ModelModality>
    ) -> String? {
        let paths = Set(files.map(\.path))
        for configPath in paths where filename(configPath) == "config.json" {
            let root = directoryPath(configPath)
            guard paths.contains(path("tokenizer.json", in: root)) else { continue }
            if modalities.contains(.vision) {
                let hasProcessorConfig = paths.contains(path("preprocessor_config.json", in: root))
                    || paths.contains(path("processor_config.json", in: root))
                guard hasProcessorConfig else { continue }
            }
            let hasSafetensors = paths.contains { candidate in
                candidate.lowercased().hasSuffix(".safetensors") && isPath(candidate, inOrBelow: root)
            }
            if hasSafetensors {
                return root
            }
        }
        return nil
    }

    private static func filename(_ path: String) -> String {
        path.split(separator: "/").last.map { String($0).lowercased() } ?? path.lowercased()
    }

    private static func directoryPath(_ path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    private static func path(_ filename: String, in directory: String) -> String {
        directory.isEmpty ? filename : "\(directory)/\(filename)"
    }

    private static func isPath(_ path: String, inOrBelow directory: String) -> Bool {
        directory.isEmpty || path == directory || path.hasPrefix(directory + "/")
    }

    private static func totalDownloadBytes(
        for files: [ModelFileInfo],
        fileSizes: [String: Int64],
        fallback: Int64?
    ) -> Int64? {
        guard !files.isEmpty else { return nil }
        var total: Int64 = 0
        var hasUnknownSize = false
        for file in files {
            guard let size = fileSizes[file.path], size > 0 else {
                hasUnknownSize = true
                continue
            }
            total += size
        }
        guard total > 0 else { return fallback }
        if hasUnknownSize, let fallback, fallback > total {
            return fallback
        }
        return total
    }

    private static func byteCount(for url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        return Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    private static func directoryByteCount(_ directory: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func expectedFileSize(
        from response: URLResponse,
        http: HTTPURLResponse,
        offset: Int64,
        declaredSize: Int64?
    ) -> Int64? {
        if let declaredSize, declaredSize > 0 {
            return declaredSize
        }
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let total = contentRange.split(separator: "/").last,
           let parsed = Int64(total),
           parsed > 0 {
            return parsed
        }
        guard response.expectedContentLength > 0 else { return nil }
        return http.statusCode == 206 ? offset + response.expectedContentLength : response.expectedContentLength
    }

    private static func isUsableDownloadedFile(_ file: ModelFileInfo, at destination: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        if let oid = file.oid, oid.count == 64 {
            return try sha256Hex(url: destination).caseInsensitiveCompare(oid) == .orderedSame
        }
        if let size = file.size {
            return try byteCount(for: destination) == size
        }
        return false
    }

    private static func reusablePartialByteCount(_ file: ModelFileInfo, at destination: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: destination.path) else { return 0 }
        let count = try byteCount(for: destination)
        guard count > 0 else { return 0 }
        guard let size = file.size, size > 0 else { return 0 }
        if count < size {
            return count
        }
        try FileManager.default.removeItem(at: destination)
        return 0
    }

    private static func validateAvailableDiskSpace(for estimatedBytes: Int64) throws {
        guard estimatedBytes > 0 else { return }
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let values = try base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let transientHeadroom = Int64(Double(estimatedBytes) * 0.5)
        let required = estimatedBytes + max(transientHeadroom, 2_000_000_000)
        guard available > required else {
            throw URLError(.cannotWriteToFile)
        }
    }

    private static func modelsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Pines/Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func safeDirectoryName(_ repository: String) -> String {
        repository.replacingOccurrences(of: "/", with: "__")
    }

    private static func legacySafeDirectoryName(_ repository: String) -> String {
        repository.replacingOccurrences(of: "/", with: "_")
    }

    private static func encodedPath(_ path: String) -> String {
        path.split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    private static func sha256Hex(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            do {
                try handle.close()
            } catch {
                modelLifecycleLogger.warning("Failed to close model file handle for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
