import CoreGraphics
@testable import ScrollProbeCore
import XCTest

final class ScrollSampleTests: XCTestCase {
    func testExtractsIndependentScrollRepresentations() throws {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 3,
            wheel1: 3,
            wheel2: -2,
            wheel3: 0
        ))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 7)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -5)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis3, value: 9)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1.25)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.5)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3, value: 3.75)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 12)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -25)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis3, value: 30)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 4)
        event.setIntegerValueField(.eventSourceUserData, value: 1234)

        let sample = ScrollSample(event: event, receivedUptimeNanos: 42)

        XCTAssertEqual(sample.receivedUptimeNanos, 42)
        XCTAssertEqual(sample.integerDeltaY, 7)
        XCTAssertEqual(sample.integerDeltaX, -5)
        XCTAssertEqual(sample.integerDeltaZ, 9)
        XCTAssertEqual(sample.fixedDeltaY, 1.25)
        XCTAssertEqual(sample.fixedDeltaX, -2.5)
        XCTAssertEqual(sample.fixedDeltaZ, 3.75)
        XCTAssertEqual(sample.pointDeltaY, 12)
        XCTAssertEqual(sample.pointDeltaX, -25)
        XCTAssertEqual(sample.pointDeltaZ, 30)
        XCTAssertTrue(sample.isContinuous)
        XCTAssertEqual(sample.scrollPhase, 2)
        XCTAssertEqual(sample.momentumPhase, 4)
        XCTAssertEqual(sample.sourceUserData, 1234)
        XCTAssertTrue(sample.hasAnyDelta)
    }
}
