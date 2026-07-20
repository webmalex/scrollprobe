@testable import ScrollProbeCore
import XCTest

final class ProtectionLifecycleTests: XCTestCase {
    func testTapRecreationPolicyIsBounded() {
        XCTAssertEqual(TapRecreationPolicy.delay(forAttempt: 0), 0)
        XCTAssertEqual(TapRecreationPolicy.delay(forAttempt: 1), 0.5)
        XCTAssertEqual(TapRecreationPolicy.delay(forAttempt: 2), 1)
        XCTAssertNil(TapRecreationPolicy.delay(forAttempt: 3))
        XCTAssertNil(TapRecreationPolicy.delay(forAttempt: -1))
    }
}
