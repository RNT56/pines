import Foundation
import PinesCore

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

final class BackgroundModelFileDownloadCenter: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BackgroundModelFileDownloadCenter()
    static let sessionIdentifier = "com.schtack.pines.model-downloads"

    private struct DownloadState: Sendable {
        var token: UUID
        var destination: URL
        var declaredSize: Int64?
        var continuation: AsyncThrowingStream<BackgroundModelFileDownloadEvent, Error>.Continuation
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
        destination: URL,
        declaredSize: Int64?
    ) -> AsyncThrowingStream<BackgroundModelFileDownloadEvent, Error> {
        let token = UUID()
        return AsyncThrowingStream { continuation in
            let task = session.downloadTask(with: request)
            let state = DownloadState(
                token: token,
                destination: destination,
                declaredSize: declaredSize,
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
        guard let state = state(for: downloadTask.taskIdentifier) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : state.declaredSize
        state.continuation.yield(.progress(bytesWritten: bytesWritten, expectedFileSize: expected))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let state = state(for: downloadTask.taskIdentifier) else { return }
        do {
            guard let http = downloadTask.response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode)
            else {
                throw URLError(.badServerResponse)
            }
            if FileManager.default.fileExists(atPath: state.destination.path) {
                try FileManager.default.removeItem(at: state.destination)
            }
            try FileManager.default.moveItem(at: location, to: state.destination)
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .success(()))
        } catch {
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
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

    private func state(for taskIdentifier: Int) -> DownloadState? {
        lock.withLock {
            states[taskIdentifier]
        }
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
            state.continuation.finish()
        case let .failure(error):
            state.continuation.finish(throwing: error)
        }
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
