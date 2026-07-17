import Foundation
import XCTest

final class RefreshScopeTests: XCTestCase {
    func testBroadRefreshIsReservedForBootstrapAndDestructiveRecovery() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(path: "Pines/App/PinesAppModel.swift"),
            encoding: .utf8
        )
        let broadRefreshCalls = source.components(separatedBy: "await refreshAll(services: services)").count - 1

        XCTAssertEqual(broadRefreshCalls, 2)
        XCTAssertTrue(source.contains("await refreshSynchronizedState(services: services)"))
        XCTAssertTrue(source.contains("await refreshProjects(services: services)"))
        XCTAssertTrue(source.contains("await refreshVaultDocuments(services: services)"))
        XCTAssertTrue(source.contains("await refreshMCPState(services: services)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
