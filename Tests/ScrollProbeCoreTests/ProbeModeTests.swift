import CoreGraphics
@testable import ScrollProbeCore
import XCTest

final class ProbeModeTests: XCTestCase {
    func testDropsOnlyZeroDeltaChangedEvents() throws {
        let zeroChanged = try sample(phase: .changed, pointDeltaY: 0)
        let changedWithDelta = try sample(phase: .changed, pointDeltaY: 1)
        let zeroBegan = try sample(phase: .began, pointDeltaY: 0)
        let zeroChangedMomentum = try sample(phase: .changed, momentumPhase: 2, pointDeltaY: 0)

        XCTAssertTrue(zeroChanged.isZeroDeltaChanged)
        XCTAssertEqual(ProbeMode.dropZeroDeltaChanged.decision(for: zeroChanged), .drop)
        XCTAssertEqual(ProbeMode.dropZeroDeltaChanged.decision(for: changedWithDelta), .pass)
        XCTAssertEqual(ProbeMode.dropZeroDeltaChanged.decision(for: zeroBegan), .pass)
        XCTAssertEqual(ProbeMode.dropZeroDeltaChanged.decision(for: zeroChangedMomentum), .pass)
        XCTAssertEqual(ProbeMode.monitor.decision(for: zeroChanged), .pass)
        XCTAssertEqual(ProbeMode.dropAll.decision(for: changedWithDelta), .drop)
    }

    private func sample(
        phase: CGScrollPhase,
        momentumPhase: Int64 = 0,
        pointDeltaY: Double
    ) throws -> ScrollSample {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY)
        return ScrollSample(event: event)
    }
}
