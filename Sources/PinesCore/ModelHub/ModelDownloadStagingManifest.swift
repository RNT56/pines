import Foundation

public enum ModelDownloadStagingFileStatus: String, Hashable, Codable, Sendable {
    case pending
    case downloading
    case complete
    case failed
}

public struct ModelDownloadStagingManifest: Hashable, Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var repository: String
    public var revision: String?
    public var totalBytes: Int64?
    public var files: [File]
    public var updatedAt: Date

    public init(
        version: Int = Self.currentVersion,
        repository: String,
        revision: String? = nil,
        totalBytes: Int64? = nil,
        files: [File] = [],
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.repository = repository
        self.revision = revision
        self.totalBytes = totalBytes
        self.files = files
        self.updatedAt = updatedAt
    }

    public var reusableBytes: Int64 {
        files.reduce(0) { total, file in
            total + max(0, min(file.receivedBytes, file.expectedBytes ?? file.receivedBytes))
        }
    }

    public var hasReusableBytes: Bool {
        reusableBytes > 0
    }

    public mutating func mergeDownloadPlan(
        repository: String,
        revision: String?,
        totalBytes: Int64?,
        files plannedFiles: [ModelFileInfo],
        now: Date = Date()
    ) {
        self.repository = repository
        self.revision = revision
        self.totalBytes = totalBytes
        updatedAt = now

        let existingByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        files = plannedFiles.map { file in
            var record = existingByPath[file.path] ?? File(path: file.path)
            record.expectedBytes = file.size ?? record.expectedBytes
            record.checksum = file.oid ?? record.checksum
            return record
        }
    }

    public mutating func updateFile(
        path: String,
        expectedBytes: Int64? = nil,
        checksum: String? = nil,
        receivedBytes: Int64? = nil,
        status: ModelDownloadStagingFileStatus? = nil,
        errorMessage: String? = nil,
        now: Date = Date()
    ) {
        guard let index = files.firstIndex(where: { $0.path == path }) else {
            var file = File(path: path, expectedBytes: expectedBytes, receivedBytes: receivedBytes ?? 0, checksum: checksum)
            if let status {
                file.status = status
            }
            file.errorMessage = errorMessage
            files.append(file)
            updatedAt = now
            return
        }

        if let expectedBytes {
            files[index].expectedBytes = expectedBytes
        }
        if let checksum {
            files[index].checksum = checksum
        }
        if let receivedBytes {
            files[index].receivedBytes = max(0, receivedBytes)
        }
        if let status {
            files[index].status = status
        }
        files[index].errorMessage = errorMessage
        files[index].updatedAt = now
        updatedAt = now
    }

    public func file(path: String) -> File? {
        files.first { $0.path == path }
    }

    public struct File: Hashable, Codable, Sendable {
        public var path: String
        public var expectedBytes: Int64?
        public var receivedBytes: Int64
        public var checksum: String?
        public var status: ModelDownloadStagingFileStatus
        public var errorMessage: String?
        public var updatedAt: Date

        public init(
            path: String,
            expectedBytes: Int64? = nil,
            receivedBytes: Int64 = 0,
            checksum: String? = nil,
            status: ModelDownloadStagingFileStatus = .pending,
            errorMessage: String? = nil,
            updatedAt: Date = Date()
        ) {
            self.path = path
            self.expectedBytes = expectedBytes
            self.receivedBytes = receivedBytes
            self.checksum = checksum
            self.status = status
            self.errorMessage = errorMessage
            self.updatedAt = updatedAt
        }
    }
}
