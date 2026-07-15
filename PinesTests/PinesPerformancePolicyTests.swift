import Foundation
import XCTest
@testable import pines

final class PinesPerformancePolicyTests: XCTestCase {
    func testNormalPolicyPreservesHighQualityInteraction() {
        let policy = PinesPerformancePolicy.resolve(
            lowPowerModeEnabled: false,
            thermalState: .nominal,
            reduceMotion: false
        )

        XCTAssertEqual(policy.pressureLevel, .normal)
        XCTAssertTrue(policy.allowsDecorativeMotion)
        XCTAssertTrue(policy.allowsExpressiveHaptics)
        XCTAssertTrue(policy.allowsSpeculativePrefetch)
        XCTAssertFalse(policy.shouldPurgeCaches)
    }

    func testAccessibilityAndLowPowerConstrainOptionalWork() {
        let policy = PinesPerformancePolicy.resolve(
            lowPowerModeEnabled: true,
            thermalState: .nominal,
            reduceMotion: true
        )

        XCTAssertEqual(policy.pressureLevel, .constrained)
        XCTAssertFalse(policy.allowsDecorativeMotion)
        XCTAssertFalse(policy.allowsExpressiveHaptics)
        XCTAssertFalse(policy.allowsSpeculativePrefetch)
        XCTAssertFalse(policy.shouldPurgeCaches)
    }

    func testSeriousThermalPressureRequestsCachePurge() {
        let policy = PinesPerformancePolicy.resolve(
            lowPowerModeEnabled: false,
            thermalState: .serious,
            reduceMotion: false
        )

        XCTAssertEqual(policy.pressureLevel, .critical)
        XCTAssertTrue(policy.shouldPurgeCaches)
        XCTAssertFalse(policy.allowsExpressiveHaptics)
    }
}
