import Foundation
import PinesCore
import OSLog

private let modelDownloadSupportLogger = Logger(subsystem: "com.schtack.pines", category: "ModelDownloadSupport")

actor ModelDownloadTaskCoordinator {
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
enum ModelInstallMode: Hashable, Sendable {
    case automatic
    case textOnly
    case full

    func resolvedModalities(from available: Set<ModelModality>) throws -> Set<ModelModality> {
        switch self {
        case .automatic, .full:
            return available
        case .textOnly:
            guard available.contains(.text) else {
                throw InferenceError.unsupportedCapability("This model does not expose a text-only runtime path.")
            }
            return [.text]
        }
    }
}

extension Array where Element == URL {
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

extension URL {
    func isDescendant(of directory: URL) -> Bool {
        let path = standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }
}

enum BackgroundModelFileDownloadEvent: Sendable {
    case progress(bytesWritten: Int64, expectedFileSize: Int64?)
}

struct BackgroundModelFileDownloadMetadata: Hashable, Codable, Sendable {
    var repository: String
    var revision: String
    var filePath: String
    var destinationPath: String
    var stagingDirectoryPath: String
    var declaredSize: Int64?
    var checksum: String?
    var resumeOffset: Int64
    var rangeEnd: Int64?

    var destination: URL {
        URL(fileURLWithPath: destinationPath)
    }

    var stagingDirectory: URL {
        URL(fileURLWithPath: stagingDirectoryPath)
    }

    func encodedTaskDescription() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return data.base64EncodedString()
    }

    static func decodeTaskDescription(_ value: String?) -> BackgroundModelFileDownloadMetadata? {
        guard let value,
              let data = Data(base64Encoded: value)
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

enum ModelDownloadStagingManifestStore {
    private static let manifestFilename = ".pines-download-manifest.json"
    private static let lock = NSLock()

    static func manifestURL(in stagingDirectory: URL) -> URL {
        stagingDirectory.appending(path: manifestFilename)
    }

    static func read(from stagingDirectory: URL) throws -> ModelDownloadStagingManifest? {
        try lock.withLock {
            let url = manifestURL(in: stagingDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ModelDownloadStagingManifest.self, from: data)
        }
    }

    static func write(_ manifest: ModelDownloadStagingManifest, to stagingDirectory: URL) throws {
        try lock.withLock {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL(in: stagingDirectory), options: [.atomic])
        }
    }

    static func update(
        in stagingDirectory: URL,
        repository: String? = nil,
        revision: String? = nil,
        path: String,
        expectedBytes: Int64? = nil,
        checksum: String? = nil,
        receivedBytes: Int64? = nil,
        status: ModelDownloadStagingFileStatus? = nil,
        errorMessage: String? = nil
    ) throws {
        try lock.withLock {
            let url = manifestURL(in: stagingDirectory)
            var manifest: ModelDownloadStagingManifest
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                manifest = try JSONDecoder().decode(ModelDownloadStagingManifest.self, from: data)
            } else {
                manifest = ModelDownloadStagingManifest(repository: repository ?? "", revision: revision)
            }
            if let repository {
                manifest.repository = repository
            }
            if let revision {
                manifest.revision = revision
            }
            manifest.updateFile(
                path: path,
                expectedBytes: expectedBytes,
                checksum: checksum,
                receivedBytes: receivedBytes,
                status: status,
                errorMessage: errorMessage
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        }
    }

    static func update(metadata: BackgroundModelFileDownloadMetadata, receivedBytes: Int64, expectedBytes: Int64?, status: ModelDownloadStagingFileStatus) {
        do {
            try update(
                in: metadata.stagingDirectory,
                repository: metadata.repository,
                revision: metadata.revision,
                path: metadata.filePath,
                expectedBytes: expectedBytes ?? metadata.declaredSize,
                checksum: metadata.checksum,
                receivedBytes: receivedBytes,
                status: status
            )
        } catch {
            modelDownloadSupportLogger.warning("Failed to update download staging manifest for \(metadata.repository, privacy: .public)/\(metadata.filePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func fail(metadata: BackgroundModelFileDownloadMetadata, error: Error) {
        do {
            try update(
                in: metadata.stagingDirectory,
                repository: metadata.repository,
                revision: metadata.revision,
                path: metadata.filePath,
                expectedBytes: metadata.declaredSize,
                checksum: metadata.checksum,
                status: .failed,
                errorMessage: error.localizedDescription
            )
        } catch {
            modelDownloadSupportLogger.warning("Failed to mark staged model file failed for \(metadata.repository, privacy: .public)/\(metadata.filePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// SAFETY: URLSession background delegates require NSObject identity. Shared
// mutable dictionaries are only accessed under `lock`; delegate callbacks hand
// data back through Sendable AsyncThrowingStream continuations.
final class BackgroundModelFileDownloadCenter: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BackgroundModelFileDownloadCenter()
    static let sessionIdentifier = "com.schtack.pines.model-downloads"

    private struct DownloadState: Sendable {
        var token: UUID
        var metadata: BackgroundModelFileDownloadMetadata
        var continuation: AsyncThrowingStream<BackgroundModelFileDownloadEvent, Error>.Continuation?
    }

    private let lock = NSLock()
    private var states: [Int: DownloadState] = [:]
    private var tasksByToken: [UUID: URLSessionDownloadTask] = [:]
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func downloadEvents(
        request: URLRequest,
        metadata: BackgroundModelFileDownloadMetadata
    ) -> AsyncThrowingStream<BackgroundModelFileDownloadEvent, Error> {
        let token = UUID()
        return AsyncThrowingStream { continuation in
            let task = session.downloadTask(with: request)
            task.taskDescription = metadata.encodedTaskDescription()
            let state = DownloadState(
                token: token,
                metadata: metadata,
                continuation: continuation
            )
            continuation.onTermination = { @Sendable _ in
                Self.shared.cancelDownload(token: token)
            }
            lock.withLock {
                states[task.taskIdentifier] = state
                tasksByToken[token] = task
            }
            task.resume()
        }
    }

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void, for identifier: String) {
        lock.withLock {
            backgroundCompletionHandlers[identifier] = completionHandler
        }
        _ = session
    }

    func recoverBackgroundTasks() async {
        let tasks = await allTasks()
        lock.withLock {
            for task in tasks {
                guard states[task.taskIdentifier] == nil,
                      let metadata = BackgroundModelFileDownloadMetadata.decodeTaskDescription(task.taskDescription)
                else {
                    continue
                }
                states[task.taskIdentifier] = DownloadState(
                    token: UUID(),
                    metadata: metadata,
                    continuation: nil
                )
            }
        }
    }

    func hasBackgroundDownload(for repository: String) async -> Bool {
        await recoverBackgroundTasks()
        let key = Self.key(for: repository)
        return lock.withLock {
            states.values.contains { Self.key(for: $0.metadata.repository) == key }
        }
    }

    func cancelBackgroundDownloads(for repository: String) async {
        await recoverBackgroundTasks()
        let key = Self.key(for: repository)
        let tasks = await allTasks()
        for task in tasks {
            let metadata = state(for: task)?.metadata
                ?? BackgroundModelFileDownloadMetadata.decodeTaskDescription(task.taskDescription)
            guard metadata.map({ Self.key(for: $0.repository) == key }) == true else { continue }
            task.cancel()
        }
    }

    private func cancelDownload(token: UUID) {
        let task = lock.withLock {
            tasksByToken[token]
        }
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let state = state(for: downloadTask) else { return }
        let expected = Self.expectedFileSize(
            http: downloadTask.response as? HTTPURLResponse,
            responseExpectedLength: totalBytesExpectedToWrite,
            metadata: state.metadata
        )
        let receivedBytes = state.metadata.resumeOffset + totalBytesWritten
        ModelDownloadStagingManifestStore.update(
            metadata: state.metadata,
            receivedBytes: receivedBytes,
            expectedBytes: expected,
            status: .downloading
        )
        state.continuation?.yield(.progress(bytesWritten: bytesWritten, expectedFileSize: expected))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let state = state(for: downloadTask) else { return }
        do {
            guard let http = downloadTask.response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode)
            else {
                throw URLError(.badServerResponse)
            }
            try Self.persistDownloadedChunk(location: location, metadata: state.metadata, http: http)
            let receivedBytes = try Self.byteCount(for: state.metadata.destination)
            let expected = Self.expectedFileSize(http: http, responseExpectedLength: -1, metadata: state.metadata)
            let isComplete = expected.map { receivedBytes >= $0 } ?? (state.metadata.rangeEnd == nil)
            ModelDownloadStagingManifestStore.update(
                metadata: state.metadata,
                receivedBytes: receivedBytes,
                expectedBytes: expected,
                status: isComplete ? .complete : .downloading
            )
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .success(()))
        } catch {
            ModelDownloadStagingManifestStore.fail(metadata: state.metadata, error: error)
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let state = state(for: task)
        if let metadata = state?.metadata {
            ModelDownloadStagingManifestStore.fail(metadata: metadata, error: error)
        }
        if (error as? URLError)?.code == .cancelled {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(CancellationError()))
        } else {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(error))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completionHandler = lock.withLock {
            backgroundCompletionHandlers.removeValue(forKey: session.configuration.identifier ?? "")
        }
        completionHandler?()
    }

    private func state(for task: URLSessionTask) -> DownloadState? {
        if let state = lock.withLock({ states[task.taskIdentifier] }) {
            return state
        }
        guard let metadata = BackgroundModelFileDownloadMetadata.decodeTaskDescription(task.taskDescription) else {
            return nil
        }
        let recovered = DownloadState(token: UUID(), metadata: metadata, continuation: nil)
        lock.withLock {
            states[task.taskIdentifier] = recovered
        }
        return recovered
    }

    private func complete(taskIdentifier: Int, result: Result<Void, Error>) {
        let state = lock.withLock {
            guard let state = states.removeValue(forKey: taskIdentifier) else { return nil as DownloadState? }
            tasksByToken.removeValue(forKey: state.token)
            return state
        }
        guard let state else { return }

        switch result {
        case .success:
            state.continuation?.finish()
        case let .failure(error):
            state.continuation?.finish(throwing: error)
        }
    }

    private func allTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    private static func persistDownloadedChunk(
        location: URL,
        metadata: BackgroundModelFileDownloadMetadata,
        http: HTTPURLResponse
    ) throws {
        let destination = metadata.destination
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if http.statusCode == 206 {
            if metadata.resumeOffset > 0 {
                let existingSize = try byteCount(for: destination)
                guard existingSize == metadata.resumeOffset else {
                    throw URLError(.cannotWriteToFile)
                }
                try append(contentsOf: location, to: destination)
            } else {
                try replaceItem(at: destination, with: location)
            }
            return
        }

        try replaceItem(at: destination, with: location)
    }

    private static func replaceItem(at destination: URL, with location: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: location, to: destination)
    }

    private static func append(contentsOf location: URL, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: location)
        defer {
            try? input.close()
        }

        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? output.close()
        }

        try output.seekToEnd()
        while true {
            guard let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty else {
                break
            }
            try output.write(contentsOf: data)
        }
    }

    private static func byteCount(for url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        return Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    private static func expectedFileSize(
        http: HTTPURLResponse?,
        responseExpectedLength: Int64,
        metadata: BackgroundModelFileDownloadMetadata
    ) -> Int64? {
        if let declaredSize = metadata.declaredSize, declaredSize > 0 {
            return declaredSize
        }
        if let contentRange = http?.value(forHTTPHeaderField: "Content-Range"),
           let total = contentRange.split(separator: "/").last,
           let parsed = Int64(total),
           parsed > 0 {
            return parsed
        }
        guard responseExpectedLength > 0 else { return nil }
        return metadata.resumeOffset + responseExpectedLength
    }

    private nonisolated static func key(for repository: String) -> String {
        repository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

extension ModelDownloadStatus {
    var isActive: Bool {
        switch self {
        case .queued, .downloading, .verifying, .installing:
            true
        case .installed, .failed, .cancelled:
            false
        }
    }
}
