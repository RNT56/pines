import Foundation
import UniformTypeIdentifiers

struct ProviderTransferStagedFile: Sendable, Equatable {
    let url: URL
    let byteCount: Int64
    let contentType: String?
}

/// Owns potentially blocking provider-transfer file work so the app model can
/// remain main-actor isolated without performing filesystem I/O there.
actor ProviderTransferFileService {
    static let shared = ProviderTransferFileService()

    private let fileManager: FileManager
    private let configuredRootURL: URL?
    private let copyChunkSize: Int

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        copyChunkSize: Int = 1_048_576
    ) {
        configuredRootURL = rootURL
        self.fileManager = fileManager
        self.copyChunkSize = max(64 * 1_024, copyChunkSize)
    }

    func stage(sourceURL: URL, transferID: UUID) throws -> ProviderTransferStagedFile {
        try Task.checkCancellation()
        let hasScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceValues = try sourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .contentTypeKey,
        ])
        guard sourceValues.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let directory = try transferDirectoryURL(transferID: transferID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceName = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = sourceName.isEmpty ? "upload" : sourceName
        let destination = directory.appending(path: fileName, directoryHint: .notDirectory)
        let partial = directory.appending(path: ".\(fileName).partial", directoryHint: .notDirectory)
        try? fileManager.removeItem(at: partial)
        try? fileManager.removeItem(at: destination)

        guard fileManager.createFile(atPath: partial.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            let destinationHandle = try FileHandle(forWritingTo: partial)
            defer {
                try? sourceHandle.close()
                try? destinationHandle.close()
            }

            while true {
                try Task.checkCancellation()
                guard let chunk = try sourceHandle.read(upToCount: copyChunkSize), !chunk.isEmpty else {
                    break
                }
                try destinationHandle.write(contentsOf: chunk)
            }
            try destinationHandle.synchronize()
            try Task.checkCancellation()
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }

        let stagedValues = try destination.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        return ProviderTransferStagedFile(
            url: destination,
            byteCount: Int64(stagedValues.fileSize ?? sourceValues.fileSize ?? 0),
            contentType: stagedValues.contentType?.preferredMIMEType
                ?? sourceValues.contentType?.preferredMIMEType
                ?? UTType(filenameExtension: destination.pathExtension)?.preferredMIMEType
        )
    }

    func readData(from url: URL, maximumBytes: Int? = nil) throws -> Data {
        try Task.checkCancellation()
        let hasScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let maximumBytes {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > maximumBytes {
                throw CocoaError(.fileReadTooLarge)
            }
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try Task.checkCancellation()
        return data
    }

    func inspect(_ url: URL) throws -> ProviderTransferStagedFile {
        try Task.checkCancellation()
        let hasScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .contentTypeKey,
        ])
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return ProviderTransferStagedFile(
            url: url,
            byteCount: Int64(values.fileSize ?? 0),
            contentType: values.contentType?.preferredMIMEType
                ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        )
    }

    /// Materializes a text export one repository page at a time. This keeps a
    /// large Vault document out of the main actor and avoids joining every
    /// chunk into one String/Data allocation before upload.
    func stageTextPages(
        transferID: UUID,
        fileName: String,
        contentType: String = "text/plain; charset=utf-8",
        pageSize: Int = 128,
        loadPage: @Sendable (_ limit: Int, _ offset: Int) async throws -> [String]
    ) async throws -> ProviderTransferStagedFile {
        let limit = max(1, pageSize)
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        let resolvedName = safeName.isEmpty ? "vault-export.txt" : safeName
        let directory = try transferDirectoryURL(transferID: transferID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appending(path: resolvedName, directoryHint: .notDirectory)
        guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            var offset = 0
            var wroteChunk = false
            var containsText = false

            while true {
                try Task.checkCancellation()
                let page = try await loadPage(limit, offset)
                guard !page.isEmpty else { break }
                for text in page {
                    try Task.checkCancellation()
                    if wroteChunk {
                        try output.write(contentsOf: Data("\n\n".utf8))
                    }
                    try output.write(contentsOf: Data(text.utf8))
                    wroteChunk = true
                    if !containsText,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        containsText = true
                    }
                }
                offset += page.count
                if page.count < limit { break }
            }

            guard containsText else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try output.synchronize()
            try Task.checkCancellation()
            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
            return ProviderTransferStagedFile(
                url: outputURL,
                byteCount: Int64(values.fileSize ?? 0),
                contentType: contentType
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func removeStagedTransfer(containing stagedURL: URL) throws {
        let root = try providerRootURL().standardizedFileURL
        let directory = stagedURL.deletingLastPathComponent().standardizedFileURL
        guard directory.path.hasPrefix(root.path + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    @discardableResult
    func removeStaleTransfers(olderThan cutoff: Date) throws -> Int {
        let root = try providerRootURL()
        guard fileManager.fileExists(atPath: root.path) else { return 0 }
        let directories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        for directory in directories {
            try Task.checkCancellation()
            let values = try directory.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values.isDirectory == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff
            else { continue }
            try fileManager.removeItem(at: directory)
            removed += 1
        }
        return removed
    }

    private func transferDirectoryURL(transferID: UUID) throws -> URL {
        try providerRootURL().appending(path: transferID.uuidString, directoryHint: .isDirectory)
    }

    private func providerRootURL() throws -> URL {
        if let configuredRootURL {
            return configuredRootURL
        }
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Pines/ProviderTransfers", directoryHint: .isDirectory)
    }
}
