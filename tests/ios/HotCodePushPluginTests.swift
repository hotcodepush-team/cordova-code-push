import XCTest
@testable import HotCodePushCordova

final class HotCodePushPluginTests: XCTestCase {
    func testShouldRejectTheAttributesWhenTheOptionsCarryNoAttributesField() {
        XCTAssertThrowsError(try HotCodePushPlugin.attributeChanges(from: ["plan": "pro"])) { error in
            XCTAssertEqual(error.localizedDescription, "attributes must be an object of string or null values")
        }
    }
}
