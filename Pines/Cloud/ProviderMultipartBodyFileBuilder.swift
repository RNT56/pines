import Foundation

struct ProviderPreparedUploadBody: Sendable, Equatable {
    let url: URL
    let byteCount: Int64
}

/// Builds multipart request bodies incrementally on disk so a large provider
/// upload does not require both the source and encoded body in resident memory.
actor ProviderMultipartBodyFileBuilder {
    static let shared = ProviderMultipartBodyFileBuilder()

    private let fileManager: FileManager
    private let rootURL: URL
    private let copyChunkSize: Int

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        copyChunkSize: Int = 1_048_576
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.temporaryDirectory
            .appending(path: "PinesProviderUploadBodies", directoryHint: .isDirectory)
        self.copyChunkSize = max(64 * 1_024, copyChunkSize)
    }

    func build(
        boundary: String,
        fields: [String: String],
        fileFieldName: String = "file",
        fileName: String,
        contentType: String,
        sourceURL: URL
    ) throws -> ProviderPreparedUploadBody {
        try Task.checkCancellation()
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let outputURL = rootURL.appending(
            path: "\(UUID().uuidString).multipart",
            directoryHint: .notDirectory
        )
        guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let hasScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
                try write("--\(boundary)\r\n", to: output)
                try write(
                    "Content-Disposition: form-data; name=\"\(Self.headerToken(name))\"\r\n\r\n",
                    to: output
                )
                try write("\(value)\r\n", to: output)
            }

            try write("--\(boundary)\r\n", to: output)
            try write(
                "Content-Disposition: form-data; name=\"\(Self.headerToken(fileFieldName))\"; filename=\"\(Self.headerToken(fileName))\"\r\n",
                to: output
            )
            try write("Content-Type: \(Self.headerValue(contentType))\r\n\r\n", to: output)

            let source = try FileHandle(forReadingFrom: sourceURL)
            defer { try? source.close() }
            while true {
                try Task.checkCancellation()
                guard let chunk = try source.read(upToCount: copyChunkSize), !chunk.isEmpty else {
                    break
                }
                try output.write(contentsOf: chunk)
            }
            try write("\r\n--\(boundary)--\r\n", to: output)
            try output.synchronize()
            try Task.checkCancellation()

            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
            return ProviderPreparedUploadBody(
                url: outputURL,
                byteCount: Int64(values.fileSize ?? 0)
            )
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    func remove(_ body: ProviderPreparedUploadBody) {
        try? fileManager.removeItem(at: body.url)
    }

    @discardableResult
    func purge(olderThan cutoff: Date = .distantFuture) throws -> Int {
        guard fileManager.fileExists(atPath: rootURL.path) else { return 0 }
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        for url in contents {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) < cutoff
            else { continue }
            try fileManager.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    private func write(_ string: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data(string.utf8))
    }

    private static func headerToken(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
    }

    private static func headerValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
