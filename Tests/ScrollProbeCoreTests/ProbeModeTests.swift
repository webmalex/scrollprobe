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

    func testProductionPolicyPreservesAllMeaningfulEvents() throws {
        let zeroChanged = try event(phase: .changed)
        let verticalPointDelta = try event(phase: .changed, pointDeltaY: 1)
        let horizontalFixedDelta = try event(phase: .changed, fixedDeltaX: -0.25)
        let thirdAxisPointDelta = try event(phase: .changed, pointDeltaZ: 1)
        let verticalIntegerDelta = try event(phase: .changed, integerDeltaY: 1)
        let momentum = try event(phase: .changed, momentumPhase: 2)
        let began = try event(phase: .began)
        let ended = try event(phase: .ended)
        let cancelled = try event(phase: .cancelled)

        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: zeroChanged), .drop)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: verticalPointDelta), .pass)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: horizontalFixedDelta), .pass)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: thirdAxisPointDelta), .pass)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: verticalIntegerDelta), .pass)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: momentum), .pass)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: began), .pass)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: ended), .pass)
        XCTAssertEqual(ZeroDeltaChangedPolicy.decision(for: cancelled), .pass)
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

    private func event(
        phase: CGScrollPhase,
        momentumPhase: Int64 = 0,
        integerDeltaY: Int64 = 0,
        fixedDeltaX: Double = 0,
        pointDeltaY: Double = 0,
        pointDeltaZ: Double = 0
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: integerDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedDeltaX)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis3, value: pointDeltaZ)
        return event
    }
}
