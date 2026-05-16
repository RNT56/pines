import CryptoKit
import Foundation
import PinesCore

private actor ModelDownloadTaskCoordinator {
    private struct ActiveDownload {
        var id: UUID
        var task: Task<Void, Error>
    }

    private var downloads: [String: ActiveDownload] = [:]

    func start(
        repository: String,
        id: UUID,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Task<Void, Error>? {
        let key = Self.key(for: repository)
        guard downloads[key] == nil else { return nil }
        let task = Task {
            try await operation()
        }
        downloads[key] = ActiveDownload(id: id, task: task)
        return task
    }

    func cancel(repository: String) -> Task<Void, Error>? {
        let task = downloads[Self.key(for: repository)]?.task
        task?.cancel()
        return task
    }

    func hasActiveDownload(for repository: String) -> Bool {
        downloads[Self.key(for: repository)] != nil
    }

    func finish(repository: String, id: UUID) {
        let key = Self.key(for: repository)
        guard downloads[key]?.id == id else { return }
        downloads[key] = nil
    }

    private nonisolated static func key(for repository: String) -> String {
        repository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct ModelLifecycleService: Sendable {
    private static let downloadTasks = ModelDownloadTaskCoordinator()

    let catalog: HuggingFaceModelCatalogService
    let classifier: ModelPreflightClassifier
    let installRepository: any ModelInstallRepository
    let downloadRepository: any ModelDownloadRepository
    let auditRepository: (any AuditEventRepository)?
    let secretStore: (any SecretStore)?

    func preflight(repository: String, revision: String = "main") async throws -> ModelPreflightResult {
        let token = try await huggingFaceToken()
        return classifier.classify(try await catalog.preflight(repository: repository, revision: revision, accessToken: token))
    }

    func install(repository: String, revision: String = "main") async throws {
        let taskID = UUID()
        guard let task = await Self.downloadTasks.start(repository: repository, id: taskID, operation: { [self] in
            try await performInstall(repository: repository, revision: revision)
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

        let cancelled = try await markActiveDownloadsCancelled(for: repository)
        guard cancelled else { return }
        try Self.removeStagingDirectory(for: repository)
        try await installRepository.deleteInstall(repository: repository)
        try await auditRepository?.append(
            AuditEvent(category: .modelDownload, summary: "Cancelled \(repository)", modelID: ModelID(rawValue: repository))
        )
    }

    func reconcileInterruptedDownloads() async throws {
        let downloads = try await downloadRepository.listDownloads()
        var interruptedRepositories: [String: String] = [:]

        for download in downloads where download.status.isActive {
            let key = download.repository.lowercased()
            let hasActiveTask = await Self.downloadTasks.hasActiveDownload(for: download.repository)
            guard !hasActiveTask else { continue }
            interruptedRepositories[key] = download.repository

            var cancelled = download
            cancelled.status = .cancelled
            cancelled.errorMessage = "Download was interrupted."
            cancelled.updatedAt = Date()
            try await downloadRepository.upsertDownload(cancelled)
        }

        let installs = try await installRepository.listInstalledAndCuratedModels()
        for install in installs where install.state == .downloading {
            let key = install.repository.lowercased()
            let hasActiveTask = await Self.downloadTasks.hasActiveDownload(for: install.repository)
            guard !hasActiveTask else { continue }
            interruptedRepositories[key] = install.repository
        }

        for install in installs where install.state == .installed {
            guard let localURL = install.localURL,
                  let resolvedURL = Self.resolvedModelDirectory(from: localURL, modalities: install.modalities)
            else {
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

            if resolvedURL != localURL {
                var repaired = install
                repaired.localURL = resolvedURL
                try await installRepository.upsertInstall(repaired)
            }
        }

        for repository in interruptedRepositories.values {
            try? Self.removeStagingDirectory(for: repository)
            try await installRepository.deleteInstall(repository: repository)
            try await auditRepository?.append(
                AuditEvent(category: .modelDownload, summary: "Interrupted \(repository)", modelID: ModelID(rawValue: repository))
            )
        }
    }

    private func performInstall(repository: String, revision: String = "main") async throws {
        try await markInterruptedActiveDownloadsCancelled(for: repository)
        let existingInstalls = try await installRepository.listInstalledAndCuratedModels()
        if let existing = existingInstalls
            .first(where: { $0.repository.caseInsensitiveCompare(repository) == .orderedSame }) {
            switch existing.state {
            case .installed:
                if let localURL = existing.localURL,
                   let resolvedURL = Self.resolvedModelDirectory(from: localURL, modalities: existing.modalities) {
                    if resolvedURL != localURL {
                        var repaired = existing
                        repaired.localURL = resolvedURL
                        try await installRepository.upsertInstall(repaired)
                    }
                    return
                }
                try? Self.removeInstalledDirectory(for: repository, localURL: existing.localURL)
            case .downloading, .remote, .failed, .unsupported:
                break
            }
        }

        try Task.checkCancellation()
        let accessToken = try await huggingFaceToken()
        let input = try await catalog.preflight(repository: repository, revision: revision, accessToken: accessToken)
        let result = classifier.classify(input)
        guard result.verification != .unsupported else {
            throw InferenceError.unsupportedCapability(result.reasons.joined(separator: "\n"))
        }
        try Task.checkCancellation()
        try Self.validateAvailableDiskSpace(for: result.estimatedBytes)

        let files = input.files.filter(Self.shouldDownload)
        try Self.validateDownloadManifest(files, repository: repository, modalities: result.modalities)
        var resolvedFileSizes = Dictionary(
            uniqueKeysWithValues: files.compactMap { file -> (String, Int64)? in
                guard let size = file.size, size > 0 else { return nil }
                return (file.path, size)
            }
        )
        for file in files where resolvedFileSizes[file.path] == nil {
            if let size = try? await Self.remoteFileSize(
                repository: repository,
                revision: revision,
                file: file,
                accessToken: accessToken
            ) {
                resolvedFileSizes[file.path] = size
            }
        }
        let totalBytes = Self.totalDownloadBytes(
            for: files,
            fileSizes: resolvedFileSizes,
            fallback: result.estimatedBytes > 0 ? result.estimatedBytes : nil
        )
        let downloadID = UUID()
        var progress = ModelDownloadProgress(
            id: downloadID,
            repository: repository,
            revision: revision,
            status: .queued,
            totalBytes: totalBytes
        )
        try await downloadRepository.upsertDownload(progress)

        let stagingURL = try Self.modelsDirectory()
            .appending(path: "staging", directoryHint: .isDirectory)
            .appending(path: Self.safeDirectoryName(repository), directoryHint: .isDirectory)
        let finalURL = try Self.modelsDirectory()
            .appending(path: Self.safeDirectoryName(repository), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        let install = ModelInstall(
            modelID: ModelID(rawValue: repository),
            displayName: repository.components(separatedBy: "/").last ?? repository,
            repository: repository,
            revision: revision,
            localURL: finalURL,
            modalities: result.modalities,
            verification: result.verification,
            state: .downloading,
            estimatedBytes: result.estimatedBytes,
            license: result.license,
            modelType: result.modelType,
            processorClass: result.processorClass
        )
        try await installRepository.upsertInstall(install)

        do {
            var received: Int64 = 0
            var lastProgressWrite = Date.distantPast

            for file in files {
                try Task.checkCancellation()
                progress.status = .downloading
                progress.currentFile = file.path
                progress.bytesReceived = received
                progress.updatedAt = Date()
                try await downloadRepository.upsertDownload(progress)

                let destination = stagingURL.appending(path: file.path)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if try Self.isUsableDownloadedFile(file, at: destination) {
                    received += Self.byteCount(for: destination)
                    continue
                }

                try await Self.downloadFile(
                    repository: repository,
                    revision: revision,
                    file: file,
                    destination: destination,
                    accessToken: accessToken
                ) { bytes, expectedFileSize in
                    try Task.checkCancellation()
                    received += bytes
                    progress.bytesReceived = received
                    if let expectedFileSize {
                        resolvedFileSizes[file.path] = expectedFileSize
                        if let inferredTotal = Self.totalDownloadBytes(
                            for: files,
                            fileSizes: resolvedFileSizes,
                            fallback: progress.totalBytes
                        ) {
                            progress.totalBytes = inferredTotal
                        }
                    }
                    let now = Date()
                    guard now.timeIntervalSince(lastProgressWrite) > 0.4 else { return }
                    lastProgressWrite = now
                    progress.updatedAt = now
                    try await downloadRepository.upsertDownload(progress)
                }

                if let oid = file.oid, oid.count == 64 {
                    try Task.checkCancellation()
                    progress.status = .verifying
                    progress.checksum = oid
                    progress.updatedAt = Date()
                    try await downloadRepository.upsertDownload(progress)
                    let digest = try Self.sha256Hex(url: destination)
                    guard digest.caseInsensitiveCompare(oid) == .orderedSame else {
                        throw URLError(.cannotDecodeContentData)
                    }
                }
            }

            progress.status = .installing
            progress.bytesReceived = received
            progress.localURL = finalURL
            progress.updatedAt = Date()
            try await downloadRepository.upsertDownload(progress)

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

            var installed = install
            installed.localURL = resolvedURL
            installed.state = .installed
            try await installRepository.upsertInstall(installed)

            progress.status = .installed
            progress.bytesReceived = progress.totalBytes ?? received
            progress.updatedAt = Date()
            try await downloadRepository.upsertDownload(progress)
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
            progress.errorMessage = error.localizedDescription
            progress.updatedAt = Date()
            try await downloadRepository.upsertDownload(progress)
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
        try await auditRepository?.append(
            AuditEvent(category: .modelDownload, summary: "Deleted \(repository)", modelID: ModelID(rawValue: repository))
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

    private func hasActiveDownload(for repository: String) async throws -> Bool {
        try await downloadRepository.listDownloads().contains { download in
            guard download.repository.caseInsensitiveCompare(repository) == .orderedSame else { return false }
            return download.status.isActive
        }
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
            try await downloadRepository.upsertDownload(cancelled)
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
            try await downloadRepository.upsertDownload(cancelled)
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
        try await downloadRepository.upsertDownload(cancelled)
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

    private static func downloadFile(
        repository: String,
        revision: String,
        file: ModelFileInfo,
        destination: URL,
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

        let partial = destination.appendingPathExtension("part")
        let offset = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        var request = URLRequest(url: url)
        if let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty {
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if offset > 0 {
            request.addValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if offset > 0, http.statusCode == 200 {
            try? FileManager.default.removeItem(at: partial)
        }
        let resumedBytes = http.statusCode == 206 ? offset : 0
        let expectedFileSize = Self.expectedFileSize(from: response, http: http, offset: offset, declaredSize: file.size)
        try await progress(resumedBytes, expectedFileSize)

        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        try handle.seekToEnd()
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                try await progress(Int64(buffer.count), expectedFileSize)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try Task.checkCancellation()
            try handle.write(contentsOf: buffer)
            try await progress(Int64(buffer.count), expectedFileSize)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
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

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return Self.expectedFileSize(from: response, http: http, offset: 0, declaredSize: file.size)
    }

    private static func removeStagingDirectory(for repository: String) throws {
        let stagingDirectory = try modelsDirectory()
            .appending(path: "staging", directoryHint: .isDirectory)
            .appending(path: safeDirectoryName(repository), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: stagingDirectory.path) {
            try FileManager.default.removeItem(at: stagingDirectory)
        }
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

    private static func hasRequiredModelFiles(in directory: URL, modalities: Set<ModelModality>) -> Bool {
        let fileManager = FileManager.default
        let configURL = directory.appending(path: "config.json")
        guard fileManager.fileExists(atPath: configURL.path) else {
            return false
        }

        guard fileManager.fileExists(atPath: directory.appending(path: "tokenizer.json").path) else {
            return false
        }

        if modalities.contains(.vision) {
            let processorFiles = ["preprocessor_config.json", "processor_config.json"]
            guard processorFiles.contains(where: { fileManager.fileExists(atPath: directory.appending(path: $0).path) }) else {
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

        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "safetensors" {
            return true
        }
        return false
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

    private static func byteCount(for url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
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
            return byteCount(for: destination) == size
        }
        return byteCount(for: destination) > 0
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
        let required = Int64(Double(estimatedBytes) * 1.15)
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
        defer { try? handle.close() }

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

private extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in self {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

private extension URL {
    func isDescendant(of directory: URL) -> Bool {
        let path = standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }
}

private extension ModelDownloadStatus {
    var isActive: Bool {
        switch self {
        case .queued, .downloading, .verifying, .installing:
            true
        case .installed, .failed, .cancelled:
            false
        }
    }
}
