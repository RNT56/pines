import Foundation
import XCTest
import PinesCore
@testable import pines

final class BoundedHTTPResponseTests: XCTestCase {
    func testDeclaredResponseSizeFailsBeforeBodyIngestion() {
        XCTAssertThrowsError(
            try BoundedHTTPResponse.validate(expectedContentLength: 11, maxBytes: 10)
        ) { error in
            XCTAssertEqual(error as? CloudProviderError, .responseTooLarge(maxBytes: 10))
        }
    }

    func testStreamingAccumulatorAllowsExactLimitAndRejectsNextByte() throws {
        var data = Data()
        try BoundedHTTPResponse.append(1, to: &data, maxBytes: 3)
        try BoundedHTTPResponse.append(2, to: &data, maxBytes: 3)
        try BoundedHTTPResponse.append(3, to: &data, maxBytes: 3)
        XCTAssertEqual(data, Data([1, 2, 3]))

        XCTAssertThrowsError(try BoundedHTTPResponse.append(4, to: &data, maxBytes: 3)) { error in
            XCTAssertEqual(error as? CloudProviderError, .responseTooLarge(maxBytes: 3))
        }
    }
}
