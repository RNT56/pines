import Foundation
import UIKit
import XCTest
@testable import pines

@MainActor
final class PinesImagePipelineTests: XCTestCase {
    func testDownsamplesToRequestedPixelBounds() async throws {
        let data = try XCTUnwrap(makeImageData(size: CGSize(width: 400, height: 200)))
        let source = PinesImageSource.data(data, identity: "wide", revision: "1")
        let pipeline = PinesImagePipeline()

        let image = try await pipeline.image(
            for: source,
            targetSize: CGSize(width: 50, height: 50),
            scale: 2
        )

        XCTAssertEqual(image.pixelWidth, 100)
        XCTAssertEqual(image.pixelHeight, 50)
    }

    func testAspectFillDecodesEnoughPixelsToAvoidUpscalingAfterCrop() async throws {
        let data = try XCTUnwrap(makeImageData(size: CGSize(width: 400, height: 200)))
        let source = PinesImageSource.data(data, identity: "wide-fill", revision: "1")

        let image = try await PinesImagePipeline().image(
            for: source,
            targetSize: CGSize(width: 50, height: 50),
            scale: 2,
            resizeMode: .aspectFill
        )

        XCTAssertEqual(image.pixelWidth, 200)
        XCTAssertEqual(image.pixelHeight, 100)
    }

    func testLoadsAndDownsamplesAFileSource() async throws {
        let data = try XCTUnwrap(makeImageData(size: CGSize(width: 360, height: 240)))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pines-image-pipeline-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "source.png")
        try data.write(to: fileURL)
        let source = PinesImageSource.file(fileURL, identity: "local-file", revision: "1")

        let image = try await PinesImagePipeline().image(
            for: source,
            targetSize: CGSize(width: 90, height: 90),
            scale: 2
        )

        XCTAssertEqual(image.pixelWidth, 180)
        XCTAssertEqual(image.pixelHeight, 120)
    }

    func testCoalescesConcurrentRequestsAndCachesTheResult() async throws {
        let data = try XCTUnwrap(makeImageData(size: CGSize(width: 320, height: 180)))
        let counter = RemoteLoadCounter(data: data)
        let pipeline = PinesImagePipeline(remoteDataLoader: { url, limit in
            try await counter.load(url: url, limit: limit)
        })
        let source = PinesImageSource.remote(
            try XCTUnwrap(URL(string: "https://example.invalid/image.png")),
            identity: "remote",
            revision: "1"
        )
        let targetSize = CGSize(width: 160, height: 90)

        async let first = pipeline.image(for: source, targetSize: targetSize, scale: 2)
        async let second = pipeline.image(for: source, targetSize: targetSize, scale: 2)
        _ = try await (first, second)
        _ = try await pipeline.image(for: source, targetSize: targetSize, scale: 2)

        let loadCount = await counter.loadCount
        XCTAssertEqual(loadCount, 1)
        let isCached = await pipeline.isCached(for: source, targetSize: targetSize, scale: 2)
        XCTAssertTrue(isCached)
    }

    func testCancellingOneWaiterDoesNotCancelACoalescedRequest() async throws {
        let data = try XCTUnwrap(makeImageData(size: CGSize(width: 320, height: 180)))
        let counter = RemoteLoadCounter(data: data)
        let pipeline = PinesImagePipeline(remoteDataLoader: { url, limit in
            try await counter.load(url: url, limit: limit)
        })
        let source = PinesImageSource.remote(
            try XCTUnwrap(URL(string: "https://example.invalid/shared.png")),
            identity: "shared",
            revision: "1"
        )
        let targetSize = CGSize(width: 160, height: 90)

        let cancelledWaiter = Task {
            try await pipeline.image(for: source, targetSize: targetSize, scale: 2)
        }
        try await Task.sleep(for: .milliseconds(10))
        let survivingWaiter = Task {
            try await pipeline.image(for: source, targetSize: targetSize, scale: 2)
        }
        cancelledWaiter.cancel()

        let image = try await survivingWaiter.value
        XCTAssertEqual(image.pixelWidth, 320)
        do {
            _ = try await cancelledWaiter.value
            XCTFail("Expected the cancelled waiter to throw CancellationError.")
        } catch is CancellationError {
            // Expected. The shared decode remains available to the surviving waiter.
        }
        let loadCount = await counter.loadCount
        XCTAssertEqual(loadCount, 1)
    }

    func testCacheKeyIncludesRevisionTargetSizeAndDisplayScale() async throws {
        let data = try XCTUnwrap(makeImageData(size: CGSize(width: 400, height: 200)))
        let counter = RemoteLoadCounter(data: data)
        let pipeline = PinesImagePipeline(remoteDataLoader: { url, limit in
            try await counter.load(url: url, limit: limit)
        })
        let url = try XCTUnwrap(URL(string: "https://example.invalid/revisioned.png"))
        let revisionOne = PinesImageSource.remote(url, identity: "revisioned", revision: "1")
        let revisionTwo = PinesImageSource.remote(url, identity: "revisioned", revision: "2")

        _ = try await pipeline.image(for: revisionOne, targetSize: CGSize(width: 100, height: 50), scale: 1)
        _ = try await pipeline.image(for: revisionOne, targetSize: CGSize(width: 100, height: 50), scale: 1)
        _ = try await pipeline.image(for: revisionTwo, targetSize: CGSize(width: 100, height: 50), scale: 1)
        // This request has the same pixel bounds as the previous request, but a
        // different point size and display scale, so it must not share an entry.
        _ = try await pipeline.image(for: revisionTwo, targetSize: CGSize(width: 50, height: 25), scale: 2)
        _ = try await pipeline.image(
            for: revisionTwo,
            targetSize: CGSize(width: 100, height: 50),
            scale: 1,
            resizeMode: .aspectFill
        )

        let loadCount = await counter.loadCount
        XCTAssertEqual(loadCount, 4)
    }

    func testCorruptDataFailsWithoutCaching() async throws {
        let pipeline = PinesImagePipeline()
        let source = PinesImageSource.data(Data("not an image".utf8), identity: "corrupt", revision: "1")
        let targetSize = CGSize(width: 80, height: 80)

        do {
            _ = try await pipeline.image(for: source, targetSize: targetSize, scale: 2)
            XCTFail("Expected corrupt data to fail.")
        } catch let error as PinesImagePipelineError {
            XCTAssertEqual(error, .invalidImageData)
        }
        let isCached = await pipeline.isCached(for: source, targetSize: targetSize, scale: 2)
        XCTAssertFalse(isCached)
    }

    func testMemoryWarningPurgesDecodedImages() async throws {
        let data = try XCTUnwrap(makeImageData(size: CGSize(width: 240, height: 120)))
        let source = PinesImageSource.data(data, identity: "memory-warning", revision: "1")
        let pipeline = PinesImagePipeline()
        let targetSize = CGSize(width: 120, height: 60)

        _ = try await pipeline.image(for: source, targetSize: targetSize, scale: 2)
        var isCached = await pipeline.isCached(for: source, targetSize: targetSize, scale: 2)
        XCTAssertTrue(isCached)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        isCached = await pipeline.isCached(for: source, targetSize: targetSize, scale: 2)
        XCTAssertFalse(isCached)
    }

    private func makeImageData(size: CGSize) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()
    }
}

private actor RemoteLoadCounter {
    private let data: Data
    private(set) var loadCount = 0

    init(data: Data) {
        self.data = data
    }

    func load(url _: URL, limit: Int) async throws -> Data {
        loadCount += 1
        try await Task.sleep(for: .milliseconds(75))
        guard data.count <= limit else {
            throw PinesImagePipelineError.responseTooLarge(limit: limit)
        }
        return data
    }
}
