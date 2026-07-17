import XCTest
@testable import pines

final class PinesRuntimeMetricsTests: XCTestCase {
    func testEveryPerformanceIntervalCanBeginAndEnd() {
        let metrics = PinesRuntimeMetrics()
        let operations: [PinesPerformanceOperation] = [
            .launchToInteractive,
            .threadToFirstMessage,
            .galleryToFirstThumbnail,
            .artifactLibraryDerive,
            .thumbnailDecode,
            .providerLifecycleRefresh,
            .providerPollCycle,
            .vaultDetailReady,
            .transferStage,
            .transferEnqueued,
        ]

        for operation in operations {
            let interval = metrics.begin(operation)
            metrics.end(interval)
        }
    }
}
