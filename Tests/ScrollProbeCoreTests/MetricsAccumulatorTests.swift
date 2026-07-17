import CoreGraphics
@testable import ScrollProbeCore
import XCTest

final class MetricsAccumulatorTests: XCTestCase {
    func testSeparatesIngressAndDownstreamAndPreservesTotals() throws {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 1)
        let accumulator = MetricsAccumulator(startUptimeNanos: 1_000_000_000)

        accumulator.record(
            stage: .ingress,
            sample: ScrollSample(event: event, receivedUptimeNanos: 1_100_000_000),
            decision: .pass
        )
        accumulator.recordCallbackDuration(stage: .ingress, nanoseconds: 10_000)
        accumulator.record(
            stage: .ingress,
            sample: ScrollSample(event: event, receivedUptimeNanos: 1_200_000_000),
            decision: .drop
        )
        accumulator.recordCallbackDuration(stage: .ingress, nanoseconds: 20_000)
        accumulator.record(
            stage: .downstream,
            sample: ScrollSample(event: event, receivedUptimeNanos: 1_210_000_000)
        )
        accumulator.recordCallbackDuration(stage: .downstream, nanoseconds: 5_000)
        accumulator.recordDisabled(stage: .ingress, reason: .timeout)

        let first = accumulator.takeSnapshot(mode: .dropZeroDeltaChanged, uptimeNanos: 2_000_000_000)

        XCTAssertEqual(first.mode, .dropZeroDeltaChanged)
        XCTAssertEqual(first.ingress.observed, 2)
        XCTAssertEqual(first.ingress.returned, 1)
        XCTAssertEqual(first.ingress.dropped, 1)
        XCTAssertEqual(first.ingress.totalObserved, 2)
        XCTAssertEqual(first.ingress.integerDeltaYSum, 2)
        XCTAssertEqual(first.ingress.minInterArrivalUsec, 100_000)
        XCTAssertEqual(first.ingress.avgCallbackUsec, 15)
        XCTAssertEqual(first.ingress.timeoutDisableCount, 1)
        XCTAssertEqual(first.downstream.observed, 1)
        XCTAssertEqual(first.downstream.returned, 0)

        let second = accumulator.takeSnapshot(uptimeNanos: 3_000_000_000)
        XCTAssertEqual(second.ingress.observed, 0)
        XCTAssertEqual(second.ingress.totalObserved, 2)
        XCTAssertEqual(second.ingress.timeoutDisableCount, 0)
    }
}
