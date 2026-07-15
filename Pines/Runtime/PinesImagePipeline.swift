import CoreGraphics
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

enum PinesImageSource: Sendable {
    case data(Data, identity: String, revision: String)
    case file(URL, identity: String, revision: String)
    case remote(URL, identity: String, revision: String)
    case deferred(identity: String, revision: String, loader: @Sendable () async throws -> Data)

    fileprivate var identity: String {
        switch self {
        case let .data(_, identity, _),
             let .file(_, identity, _),
             let .remote(_, identity, _),
             let .deferred(identity, _, _):
            identity
        }
    }

    fileprivate var revision: String {
        switch self {
        case let .data(_, _, revision),
             let .file(_, _, revision),
             let .remote(_, _, revision),
             let .deferred(_, revision, _):
            revision
        }
    }
}

enum PinesImageResizeMode: Hashable, Sendable {
    case aspectFit
    case aspectFill
}

// SAFETY: CGImage instances are immutable after creation and Core Graphics
// permits sharing them across threads. The wrapper exposes no mutable state.
struct PinesDecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    let scale: CGFloat

    var pixelWidth: Int { cgImage.width }
    var pixelHeight: Int { cgImage.height }

    fileprivate var decodedByteCost: Int {
        let (cost, overflowed) = cgImage.bytesPerRow.multipliedReportingOverflow(by: cgImage.height)
        return overflowed ? Int.max : cost
    }
}

enum PinesImagePipelineError: Error, Equatable, LocalizedError {
    case invalidTargetSize
    case emptyImageData
    case invalidImageData
    case invalidHTTPStatus(Int)
    case responseTooLarge(limit: Int)

    var errorDescription: String? {
        switch self {
        case .invalidTargetSize:
            "The requested image size is invalid."
        case .emptyImageData:
            "The image source is empty."
        case .invalidImageData:
            "The image data could not be decoded."
        case let .invalidHTTPStatus(status):
            "The image request returned HTTP status \(status)."
        case let .responseTooLarge(limit):
            "The image response exceeds the \(limit)-byte safety limit."
        }
    }
}

actor PinesImagePipeline {
    struct Configuration: Sendable {
        var decodedCostLimit: Int
        var decodedCountLimit: Int
        var remoteByteLimit: Int

        init(
            decodedCostLimit: Int = 64 * 1_024 * 1_024,
            decodedCountLimit: Int = 256,
            remoteByteLimit: Int = 64 * 1_024 * 1_024
        ) {
            self.decodedCostLimit = max(1, decodedCostLimit)
            self.decodedCountLimit = max(1, decodedCountLimit)
            self.remoteByteLimit = max(1, remoteByteLimit)
        }
    }

    typealias RemoteDataLoader = @Sendable (_ url: URL, _ byteLimit: Int) async throws -> Data

    static let shared = PinesImagePipeline()

    private struct CacheKey: Hashable, Sendable {
        let sourceIdentity: String
        let sourceRevision: String
        let targetPixelWidth: Int
        let targetPixelHeight: Int
        let displayScaleBits: UInt64
        let resizeMode: PinesImageResizeMode
    }

    private struct InFlightRequest {
        let id: UUID
        let cacheGeneration: UInt64
        let task: Task<PinesDecodedImage, Error>
    }

    private let configuration: Configuration
    private let cache: PinesDecodedImageCache
    private let remoteDataLoader: RemoteDataLoader
    private var inFlightRequests = [CacheKey: InFlightRequest]()

    init(
        configuration: Configuration = Configuration(),
        remoteDataLoader: RemoteDataLoader? = nil
    ) {
        self.configuration = configuration
        cache = PinesDecodedImageCache(
            totalCostLimit: configuration.decodedCostLimit,
            countLimit: configuration.decodedCountLimit
        )
        self.remoteDataLoader = remoteDataLoader ?? Self.loadRemoteImageData
    }

    func image(
        for source: PinesImageSource,
        targetSize: CGSize,
        scale: CGFloat,
        resizeMode: PinesImageResizeMode = .aspectFit,
        priority: TaskPriority = .userInitiated
    ) async throws -> PinesDecodedImage {
        try Task.checkCancellation()
        let key = try Self.cacheKey(
            for: source,
            targetSize: targetSize,
            scale: scale,
            resizeMode: resizeMode
        )
        if let cached = cache.image(for: key) {
            return cached
        }

        let request: InFlightRequest
        if let existing = inFlightRequests[key] {
            request = existing
        } else {
            let generation = cache.generation
            let targetPixelSize = CGSize(
                width: key.targetPixelWidth,
                height: key.targetPixelHeight
            )
            let remoteDataLoader = remoteDataLoader
            let remoteByteLimit = configuration.remoteByteLimit
            let task = Task.detached(priority: priority) {
                let interval = PinesRuntimeMetrics.shared.begin(.thumbnailDecode)
                defer { PinesRuntimeMetrics.shared.end(interval) }
                let data = try await Self.loadData(
                    for: source,
                    remoteByteLimit: remoteByteLimit,
                    remoteDataLoader: remoteDataLoader
                )
                try Task.checkCancellation()
                return try Self.downsample(
                    data,
                    targetPixelSize: targetPixelSize,
                    displayScale: scale,
                    resizeMode: key.resizeMode
                )
            }
            request = InFlightRequest(id: UUID(), cacheGeneration: generation, task: task)
            inFlightRequests[key] = request
        }

        do {
            let decoded = try await request.task.value
            complete(request, for: key, result: .success(decoded))
            try Task.checkCancellation()
            return decoded
        } catch {
            complete(request, for: key, result: .failure(error))
            throw error
        }
    }

    func purge() {
        for request in inFlightRequests.values {
            request.task.cancel()
        }
        inFlightRequests.removeAll(keepingCapacity: false)
        cache.removeAll()
    }

    func isCached(
        for source: PinesImageSource,
        targetSize: CGSize,
        scale: CGFloat,
        resizeMode: PinesImageResizeMode = .aspectFit
    ) -> Bool {
        guard let key = try? Self.cacheKey(
            for: source,
            targetSize: targetSize,
            scale: scale,
            resizeMode: resizeMode
        ) else {
            return false
        }
        return cache.image(for: key) != nil
    }

    private func complete(
        _ request: InFlightRequest,
        for key: CacheKey,
        result: Result<PinesDecodedImage, Error>
    ) {
        guard inFlightRequests[key]?.id == request.id else { return }
        inFlightRequests.removeValue(forKey: key)
        guard case let .success(image) = result else { return }
        cache.insert(image, for: key, generation: request.cacheGeneration)
    }

    private nonisolated static func cacheKey(
        for source: PinesImageSource,
        targetSize: CGSize,
        scale: CGFloat,
        resizeMode: PinesImageResizeMode
    ) throws -> CacheKey {
        guard targetSize.width.isFinite,
              targetSize.height.isFinite,
              scale.isFinite,
              targetSize.width > 0,
              targetSize.height > 0,
              scale > 0
        else {
            throw PinesImagePipelineError.invalidTargetSize
        }

        let pixelWidth = targetSize.width * scale
        let pixelHeight = targetSize.height * scale
        guard pixelWidth <= CGFloat(Int.max), pixelHeight <= CGFloat(Int.max) else {
            throw PinesImagePipelineError.invalidTargetSize
        }

        return CacheKey(
            sourceIdentity: source.identity,
            sourceRevision: source.revision,
            targetPixelWidth: max(1, Int(ceil(pixelWidth))),
            targetPixelHeight: max(1, Int(ceil(pixelHeight))),
            displayScaleBits: Double(scale).bitPattern,
            resizeMode: resizeMode
        )
    }

    private nonisolated static func loadData(
        for source: PinesImageSource,
        remoteByteLimit: Int,
        remoteDataLoader: RemoteDataLoader
    ) async throws -> Data {
        let data: Data
        switch source {
        case let .data(sourceData, _, _):
            data = sourceData
        case let .file(url, _, _):
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        case let .remote(url, _, _):
            data = try await remoteDataLoader(url, remoteByteLimit)
        case let .deferred(_, _, loader):
            data = try await loader()
        }
        guard !data.isEmpty else {
            throw PinesImagePipelineError.emptyImageData
        }
        return data
    }

    private nonisolated static func loadRemoteImageData(url: URL, byteLimit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 60
        let (data, response) = try await BoundedHTTPResponse.data(
            for: request,
            session: .shared,
            maxBytes: byteLimit,
            redirectScope: .publicHTTPS
        )
        guard (200..<300).contains(response.statusCode) else {
            throw PinesImagePipelineError.invalidHTTPStatus(response.statusCode)
        }
        return data
    }

    private nonisolated static func downsample(
        _ data: Data,
        targetPixelSize: CGSize,
        displayScale: CGFloat,
        resizeMode: PinesImageResizeMode
    ) throws -> PinesDecodedImage {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            throw PinesImagePipelineError.invalidImageData
        }

        let maximumPixelSize = thumbnailMaximumPixelSize(
            for: source,
            targetPixelSize: targetPixelSize,
            resizeMode: resizeMode
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PinesImagePipelineError.invalidImageData
        }
        return PinesDecodedImage(cgImage: image, scale: displayScale)
    }

    private nonisolated static func thumbnailMaximumPixelSize(
        for source: CGImageSource,
        targetPixelSize: CGSize,
        resizeMode: PinesImageResizeMode
    ) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = numberValue(properties[kCGImagePropertyPixelWidth]),
              let rawHeight = numberValue(properties[kCGImagePropertyPixelHeight]),
              rawWidth > 0,
              rawHeight > 0
        else {
            return max(1, Int(ceil(max(targetPixelSize.width, targetPixelSize.height))))
        }

        let orientation = numberValue(properties[kCGImagePropertyOrientation]).map(Int.init) ?? 1
        let swapsDimensions = [5, 6, 7, 8].contains(orientation)
        let sourceWidth = swapsDimensions ? rawHeight : rawWidth
        let sourceHeight = swapsDimensions ? rawWidth : rawHeight
        let widthScale = targetPixelSize.width / sourceWidth
        let heightScale = targetPixelSize.height / sourceHeight
        let requestedScale: CGFloat
        switch resizeMode {
        case .aspectFit:
            requestedScale = min(widthScale, heightScale)
        case .aspectFill:
            requestedScale = max(widthScale, heightScale)
        }
        return max(1, Int(ceil(max(sourceWidth, sourceHeight) * min(1, requestedScale))))
    }

    private nonisolated static func numberValue(_ value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            CGFloat(number.doubleValue)
        case let value as CGFloat:
            value
        default:
            nil
        }
    }
}

// SAFETY: NSCache supports concurrent access, while the generation counter is
// protected by `lock`. Cached images are immutable `PinesDecodedImage` values.
private final class PinesDecodedImageCache: @unchecked Sendable {
    private final class ObjectKey: NSObject {
        let value: AnyHashable

        init<Key: Hashable>(_ value: Key) {
            self.value = AnyHashable(value)
        }

        override var hash: Int { value.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ObjectKey else { return false }
            return value == other.value
        }
    }

    private final class ImageBox {
        let image: PinesDecodedImage

        init(_ image: PinesDecodedImage) {
            self.image = image
        }
    }

    private let cache = NSCache<ObjectKey, ImageBox>()
    private let lock = NSLock()
    private var currentGeneration: UInt64 = 0
    #if canImport(UIKit)
    private var memoryWarningObserver: NSObjectProtocol?
    #endif

    init(totalCostLimit: Int, countLimit: Int) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.removeAll()
        }
        #endif
    }

    deinit {
        #if canImport(UIKit)
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        #endif
    }

    var generation: UInt64 {
        lock.withLock { currentGeneration }
    }

    func image<Key: Hashable>(for key: Key) -> PinesDecodedImage? {
        cache.object(forKey: ObjectKey(key))?.image
    }

    func insert<Key: Hashable>(_ image: PinesDecodedImage, for key: Key, generation: UInt64) {
        lock.withLock {
            guard generation == currentGeneration else { return }
            cache.setObject(ImageBox(image), forKey: ObjectKey(key), cost: image.decodedByteCost)
        }
    }

    func removeAll() {
        lock.withLock {
            currentGeneration &+= 1
            cache.removeAllObjects()
        }
    }
}
