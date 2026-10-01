import Foundation
import StoreKitTest
import XCTest

// Developer-only probe, built as an isolated XCTest bundle, never an app target.
final class ConfigurationProbe: XCTestCase {
    func testConfigurationSessionCanBeConstructed() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LAB_COMMERCE_CONFIGURATION"])
        let session = try SKTestSession(contentsOf: URL(fileURLWithPath: path))
        XCTAssertNotNil(session)
    }
}
