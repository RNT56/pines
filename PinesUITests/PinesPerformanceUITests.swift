import XCTest

final class PinesPerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["PINES_RUN_UI_PERFORMANCE_TESTS"] == "1" else {
            throw XCTSkip("Run through scripts/diagnostics/run-ios-ui-performance.sh.")
        }
    }

    @MainActor
    func testWarmLaunchToResponsive() throws {
        let app = configuredApplication(resetStore: true)
        app.launch()
        XCTAssertTrue(mainTabBar(in: app).waitForExistence(timeout: 20))
        app.terminate()
        app.launchEnvironment["PINES_UI_TEST_RESET_STORE"] = "0"

        let options = XCTMeasureOptions()
        options.iterationCount = iterationCount
        measure(
            metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)],
            options: options
        ) {
            app.launch()
            XCTAssertTrue(mainTabBar(in: app).waitForExistence(timeout: 20))
            app.terminate()
        }
    }

    @MainActor
    func testArtifactGalleryScrollHitches() throws {
        let app = configuredApplication(resetStore: true)
        app.launchEnvironment["PINES_UI_TEST_ARTIFACTS_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(mainTabBar(in: app).waitForExistence(timeout: 20))

        let artifactsTab = firstExisting(in: app, candidates: [
            app.tabBars.buttons["Artifacts"],
            app.buttons["Artifacts"],
        ])
        XCTAssertNotNil(artifactsTab)
        artifactsTab?.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["pines.artifacts.library"].waitForExistence(timeout: 20)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "Architectural study of a glass cabin"))
                .firstMatch
                .waitForExistence(timeout: 20),
            "The deterministic artifact performance fixture did not finish loading."
        )

        let options = XCTMeasureOptions()
        options.iterationCount = iterationCount
        measure(
            metrics: [
                XCTClockMetric(),
                XCTOSSignpostMetric.scrollingAndDecelerationMetric,
            ],
            options: options
        ) {
            app.swipeUp()
            app.swipeUp()
            app.swipeDown()
            app.swipeDown()
        }

        app.terminate()
    }

    private var iterationCount: Int {
        let value = ProcessInfo.processInfo.environment["PINES_PERFORMANCE_ITERATIONS"]
            .flatMap(Int.init) ?? 5
        return min(20, max(3, value))
    }

    @MainActor
    private func configuredApplication(resetStore: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "PINES_RUN_UI_PERFORMANCE_TESTS": "1",
            "PINES_UI_TESTING": "1",
            "PINES_UI_TEST_RESET_STORE": resetStore ? "1" : "0",
            "PINES_UI_TEST_DATABASE_FILE": "pines-performance-ui-tests.sqlite",
            "PINES_UI_TEST_DATABASE_PLAINTEXT": "1",
        ]
        return app
    }

    @MainActor
    private func mainTabBar(in app: XCUIApplication) -> XCUIElement {
        app.tabBars.firstMatch
    }

    @MainActor
    private func firstExisting(
        in app: XCUIApplication,
        candidates: [XCUIElement],
        timeout: TimeInterval = 10
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let match = candidates.first(where: \.exists) {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return candidates.first(where: \.exists)
    }
}
