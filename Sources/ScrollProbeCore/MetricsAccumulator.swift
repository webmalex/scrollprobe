import Foundation

public final class MetricsAccumulator {
    public let runID: UUID

    private var windowStartNanos: UInt64
    private var ingress = StageAccumulator(stage: .ingress)
    private var downstream = StageAccumulator(stage: .downstream)

    public init(runID: UUID = UUID(), startUptimeNanos: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        self.runID = runID
        windowStartNanos = startUptimeNanos
    }

    public func record(
        stage: TapStage,
        sample: ScrollSample,
        decision: TapDecision? = nil,
        callbackDurationNanos: UInt64
    ) {
        switch stage {
        case .ingress:
            ingress.record(sample, decision: decision, callbackDurationNanos: callbackDurationNanos)
        case .downstream:
            downstream.record(sample, decision: decision, callbackDurationNanos: callbackDurationNanos)
        }
    }

    public func recordDisabled(stage: TapStage, reason: TapDisableReason) {
        switch stage {
        case .ingress:
            ingress.recordDisabled(reason)
        case .downstream:
            downstream.recordDisabled(reason)
        }
    }

    public func takeSnapshot(
        at timestamp: Date = Date(),
        uptimeNanos: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> ProbeMetricsSnapshot {
        let elapsedNanos = max(1, uptimeNanos - windowStartNanos)
        let elapsedSeconds = Double(elapsedNanos) / 1_000_000_000
        let snapshot = ProbeMetricsSnapshot(
            runID: runID,
            timestamp: timestamp,
            intervalSeconds: elapsedSeconds,
            ingress: ingress.takeSnapshot(elapsedSeconds: elapsedSeconds),
            downstream: downstream.takeSnapshot(elapsedSeconds: elapsedSeconds)
        )
        windowStartNanos = uptimeNanos
        return snapshot
    }
}

private struct StageAccumulator {
    let stage: TapStage

    private(set) var totalObserved = 0
    private(set) var totalReturned = 0
    private(set) var totalDropped = 0

    private var observed = 0
    private var returned = 0
    private var dropped = 0
    private var continuous = 0
    private var zeroDelta = 0
    private var withScrollPhase = 0
    private var withMomentumPhase = 0
    private var integerDeltaXSum: Int64 = 0
    private var integerDeltaYSum: Int64 = 0
    private var fixedDeltaXSum = 0.0
    private var fixedDeltaYSum = 0.0
    private var pointDeltaXSum = 0.0
    private var pointDeltaYSum = 0.0
    private var lastReceivedNanos: UInt64?
    private var interArrivalCount = 0
    private var interArrivalNanosSum: UInt64 = 0
    private var minInterArrivalNanos: UInt64?
    private var maxInterArrivalNanos: UInt64?
    private var callbackCount = 0
    private var callbackNanosSum: UInt64 = 0
    private var maxCallbackNanos: UInt64 = 0
    private var timeoutDisableCount = 0
    private var userInputDisableCount = 0
    private var healthCheckReenableCount = 0
    private var scrollPhaseCounts: [String: Int] = [:]
    private var momentumPhaseCounts: [String: Int] = [:]
    private var sourcePIDCounts: [String: Int] = [:]

    init(stage: TapStage) {
        self.stage = stage
    }

    mutating func record(
        _ sample: ScrollSample,
        decision: TapDecision?,
        callbackDurationNanos: UInt64
    ) {
        observed += 1
        totalObserved += 1

        if decision == .pass {
            returned += 1
            totalReturned += 1
        } else if decision == .drop {
            dropped += 1
            totalDropped += 1
        }

        if sample.isContinuous {
            continuous += 1
        }
        if !sample.hasAnyDelta {
            zeroDelta += 1
        }
        if sample.scrollPhase != 0 {
            withScrollPhase += 1
        }
        if sample.momentumPhase != 0 {
            withMomentumPhase += 1
        }

        integerDeltaXSum += sample.integerDeltaX
        integerDeltaYSum += sample.integerDeltaY
        fixedDeltaXSum += sample.fixedDeltaX
        fixedDeltaYSum += sample.fixedDeltaY
        pointDeltaXSum += sample.pointDeltaX
        pointDeltaYSum += sample.pointDeltaY

        if let lastReceivedNanos, sample.receivedUptimeNanos >= lastReceivedNanos {
            let interval = sample.receivedUptimeNanos - lastReceivedNanos
            interArrivalCount += 1
            interArrivalNanosSum += interval
            minInterArrivalNanos = min(minInterArrivalNanos ?? interval, interval)
            maxInterArrivalNanos = max(maxInterArrivalNanos ?? interval, interval)
        }
        lastReceivedNanos = sample.receivedUptimeNanos

        callbackCount += 1
        callbackNanosSum += callbackDurationNanos
        maxCallbackNanos = max(maxCallbackNanos, callbackDurationNanos)

        scrollPhaseCounts[String(sample.scrollPhase), default: 0] += 1
        momentumPhaseCounts[String(sample.momentumPhase), default: 0] += 1
        sourcePIDCounts[String(sample.sourcePID), default: 0] += 1
    }

    mutating func recordDisabled(_ reason: TapDisableReason) {
        switch reason {
        case .timeout:
            timeoutDisableCount += 1
        case .userInput:
            userInputDisableCount += 1
        case .healthCheck:
            healthCheckReenableCount += 1
        }
    }

    mutating func takeSnapshot(elapsedSeconds: Double) -> StageMetrics {
        let snapshot = StageMetrics(
            stage: stage,
            observed: observed,
            returned: returned,
            dropped: dropped,
            totalObserved: totalObserved,
            totalReturned: totalReturned,
            totalDropped: totalDropped,
            eventsPerSecond: Double(observed) / elapsedSeconds,
            continuous: continuous,
            zeroDelta: zeroDelta,
            withScrollPhase: withScrollPhase,
            withMomentumPhase: withMomentumPhase,
            integerDeltaXSum: integerDeltaXSum,
            integerDeltaYSum: integerDeltaYSum,
            fixedDeltaXSum: fixedDeltaXSum,
            fixedDeltaYSum: fixedDeltaYSum,
            pointDeltaXSum: pointDeltaXSum,
            pointDeltaYSum: pointDeltaYSum,
            minInterArrivalUsec: minInterArrivalNanos.map(Self.microseconds),
            avgInterArrivalUsec: interArrivalCount == 0
                ? nil
                : Self.microseconds(interArrivalNanosSum / UInt64(interArrivalCount)),
            maxInterArrivalUsec: maxInterArrivalNanos.map(Self.microseconds),
            avgCallbackUsec: callbackCount == 0
                ? nil
                : Self.microseconds(callbackNanosSum / UInt64(callbackCount)),
            maxCallbackUsec: callbackCount == 0 ? nil : Self.microseconds(maxCallbackNanos),
            timeoutDisableCount: timeoutDisableCount,
            userInputDisableCount: userInputDisableCount,
            healthCheckReenableCount: healthCheckReenableCount,
            scrollPhaseCounts: scrollPhaseCounts,
            momentumPhaseCounts: momentumPhaseCounts,
            sourcePIDCounts: sourcePIDCounts
        )
        resetWindow()
        return snapshot
    }

    private mutating func resetWindow() {
        observed = 0
        returned = 0
        dropped = 0
        continuous = 0
        zeroDelta = 0
        withScrollPhase = 0
        withMomentumPhase = 0
        integerDeltaXSum = 0
        integerDeltaYSum = 0
        fixedDeltaXSum = 0
        fixedDeltaYSum = 0
        pointDeltaXSum = 0
        pointDeltaYSum = 0
        lastReceivedNanos = nil
        interArrivalCount = 0
        interArrivalNanosSum = 0
        minInterArrivalNanos = nil
        maxInterArrivalNanos = nil
        callbackCount = 0
        callbackNanosSum = 0
        maxCallbackNanos = 0
        timeoutDisableCount = 0
        userInputDisableCount = 0
        healthCheckReenableCount = 0
        scrollPhaseCounts.removeAll(keepingCapacity: true)
        momentumPhaseCounts.removeAll(keepingCapacity: true)
        sourcePIDCounts.removeAll(keepingCapacity: true)
    }

    private static func microseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000
    }
}
