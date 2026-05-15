import CryptoKit
import Foundation
import PinesCore

struct ModelLifecycleService {
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
        if try await hasActiveDownload(for: repository) {
            return
        }
        let existingInstalls = try await installRepository.listInstalledAndCuratedModels()
        if let existing = existingInstalls
            .first(where: { $0.repository.caseInsensitiveCompare(repository) == .orderedSame }) {
            switch existing.state {
            case .installed, .downloading:
                return
            case .remote, .failed, .unsupported:
                break
            }
        }

        let accessToken = try await huggingFaceToken()
        let input = try await catalog.preflight(repository: repository, revision: revision, accessToken: accessToken)
        let result = classifier.classify(input)
        guard result.verification != .unsupported else {
            throw InferenceError.unsupportedCapability(result.reasons.joined(separator: "\n"))
        }
        try Self.validateAvailableDiskSpace(for: result.estimatedBytes)

        let downloadID = UUID()
        var progress = ModelDownloadProgress(
            id: downloadID,
            repository: repository,
            revision: revision,
            status: .queued,
            totalBytes: result.estimatedBytes
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
            let files = input.files.filter(Self.shouldDownload)
            var received: Int64 = 0
            var lastProgressWrite = Date.distantPast

            for file in files {
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

                received += Self.partialByteCount(for: destination)
                try await Self.downloadFile(
                    repository: repository,
                    revision: revision,
                    file: file,
                    destination: destination,
                    accessToken: accessToken
                ) { bytes in
                    received += bytes
                    let now = Date()
                    guard now.timeIntervalSince(lastProgressWrite) > 0.4 else { return }
                    lastProgressWrite = now
                    var updatedProgress = progress
                    updatedProgress.bytesReceived = received
                    updatedProgress.updatedAt = now
                    Task {
                        try? await downloadRepository.upsertDownload(updatedProgress)
                    }
                }

                if let oid = file.oid, oid.count == 64 {
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

            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)

            var installed = install
            installed.localURL = finalURL
            installed.state = .installed
            try await installRepository.upsertInstall(installed)

            progress.status = .installed
            progress.updatedAt = Date()
            try await downloadRepository.upsertDownload(progress)
            try await auditRepository?.append(
                AuditEvent(category: .modelDownload, summary: "Installed \(repository)", modelID: ModelID(rawValue: repository))
            )
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
        if try await hasActiveDownload(for: repository) {
            throw InferenceError.invalidRequest("Wait for the active model download to finish before deleting \(repository).")
        }

        let directory = try Self.modelsDirectory().appending(path: Self.safeDirectoryName(repository), directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
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
        let path = file.path.lowercased()
        return path.hasSuffix(".safetensors")
            || path.hasSuffix(".json")
            || path.hasSuffix(".model")
            || path.hasSuffix(".txt")
            || path.hasSuffix(".tiktoken")
    }

    private func hasActiveDownload(for repository: String) async throws -> Bool {
        try await downloadRepository.listDownloads().contains { download in
            guard download.repository.caseInsensitiveCompare(repository) == .orderedSame else { return false }
            switch download.status {
            case .queued, .downloading, .verifying, .installing:
                return true
            case .installed, .failed, .cancelled:
                return false
            }
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
        progress: (Int64) -> Void
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

        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        try handle.seekToEnd()
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                progress(Int64(buffer.count))
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            progress(Int64(buffer.count))
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    private static func partialByteCount(for destination: URL) -> Int64 {
        let partial = destination.appendingPathExtension("part")
        return byteCount(for: partial)
    }

    private static func byteCount(for url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
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

    private static func encodedPath(_ path: String) -> String {
        path.split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    private static func sha256Hex(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
