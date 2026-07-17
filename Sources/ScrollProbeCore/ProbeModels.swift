import CoreGraphics
import Foundation

public enum TapStage: String, Codable, CaseIterable, Sendable {
    case ingress
    case downstream
}

public enum TapDecision: String, Codable, Sendable {
    case pass
    case drop
}

public enum ProbeMode: String, Codable, CaseIterable, Sendable {
    case monitor
    case dropZeroDeltaChanged = "drop-zero-delta-changed"
    case dropAll = "drop-all"

    public static let dropAllDurationSeconds = 10

    public func decision(for sample: ScrollSample) -> TapDecision {
        switch self {
        case .monitor:
            return .pass
        case .dropZeroDeltaChanged:
            return sample.isZeroDeltaChanged ? .drop : .pass
        case .dropAll:
            return .drop
        }
    }
}

public enum TapDisableReason: String, Codable, Sendable {
    case timeout
    case userInput
    case healthCheck
}

public struct ScrollSample: Codable, Equatable, Sendable {
    public let receivedUptimeNanos: UInt64
    public let eventTimestamp: UInt64
    public let integerDeltaX: Int64
    public let integerDeltaY: Int64
    public let fixedDeltaX: Double
    public let fixedDeltaY: Double
    public let pointDeltaX: Double
    public let pointDeltaY: Double
    public let isContinuous: Bool
    public let scrollCount: Int64
    public let scrollPhase: Int64
    public let momentumPhase: Int64
    public let sourcePID: Int64
    public let targetPID: Int64
    public let sourceUserData: Int64
    public let flags: UInt64

    public init(event: CGEvent, receivedUptimeNanos: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        self.receivedUptimeNanos = receivedUptimeNanos
        eventTimestamp = event.timestamp
        integerDeltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        integerDeltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        fixedDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        fixedDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        scrollCount = event.getIntegerValueField(.scrollWheelEventScrollCount)
        scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        targetPID = event.getIntegerValueField(.eventTargetUnixProcessID)
        sourceUserData = event.getIntegerValueField(.eventSourceUserData)
        flags = event.flags.rawValue
    }

    public var hasAnyDelta: Bool {
        integerDeltaX != 0 || integerDeltaY != 0 ||
            fixedDeltaX != 0 || fixedDeltaY != 0 ||
            pointDeltaX != 0 || pointDeltaY != 0
    }

    public var isZeroDeltaChanged: Bool {
        !hasAnyDelta && scrollPhase == Int64(CGScrollPhase.changed.rawValue)
    }
}

public struct StageMetrics: Codable, Equatable, Sendable {
    public let stage: TapStage
    public let observed: Int
    public let returned: Int
    public let dropped: Int
    public let totalObserved: Int
    public let totalReturned: Int
    public let totalDropped: Int
    public let eventsPerSecond: Double
    public let continuous: Int
    public let zeroDelta: Int
    public let withScrollPhase: Int
    public let withMomentumPhase: Int
    public let integerDeltaXSum: Int64
    public let integerDeltaYSum: Int64
    public let fixedDeltaXSum: Double
    public let fixedDeltaYSum: Double
    public let pointDeltaXSum: Double
    public let pointDeltaYSum: Double
    public let minInterArrivalUsec: Double?
    public let avgInterArrivalUsec: Double?
    public let maxInterArrivalUsec: Double?
    public let avgCallbackUsec: Double?
    public let maxCallbackUsec: Double?
    public let timeoutDisableCount: Int
    public let userInputDisableCount: Int
    public let healthCheckReenableCount: Int
    public let scrollPhaseCounts: [String: Int]
    public let momentumPhaseCounts: [String: Int]
    public let sourcePIDCounts: [String: Int]
}

public struct ProbeMetricsSnapshot: Codable, Equatable, Sendable {
    public let runID: UUID
    public let timestamp: Date
    public let intervalSeconds: Double
    public let ingress: StageMetrics
    public let downstream: StageMetrics
}

public struct EventTapInfo: Codable, Equatable, Sendable {
    public let eventTapID: UInt32
    public let tapPoint: UInt32
    public let options: UInt32
    public let eventsOfInterest: UInt64
    public let tappingProcessID: Int32
    public let tappingProcessPath: String
    public let processBeingTappedID: Int32
    public let processBeingTappedPath: String
    public let enabled: Bool
    public let minUsecLatency: Float
    public let avgUsecLatency: Float
    public let maxUsecLatency: Float
}

public struct ProbeRunMetadata: Codable, Equatable, Sendable {
    public let runID: UUID
    public let startedAt: Date
    public let operatingSystemVersion: String
    public let hostName: String
    public let processID: Int32
    public let bundleIdentifier: String
    public let applicationVersion: String
    public let applicationBuild: String
    public let scenario: String
    public let mode: ProbeMode
    public let ingressDescription: String
    public let downstreamDescription: String
}

public struct ProbeLogRecord: Codable, Sendable {
    public let type: String
    public let timestamp: Date
    public let runID: UUID
    public let metadata: ProbeRunMetadata?
    public let metrics: ProbeMetricsSnapshot?
    public let taps: [EventTapInfo]?
    public let label: String?
    public let message: String?

    public init(
        type: String,
        timestamp: Date = Date(),
        runID: UUID,
        metadata: ProbeRunMetadata? = nil,
        metrics: ProbeMetricsSnapshot? = nil,
        taps: [EventTapInfo]? = nil,
        label: String? = nil,
        message: String? = nil
    ) {
        self.type = type
        self.timestamp = timestamp
        self.runID = runID
        self.metadata = metadata
        self.metrics = metrics
        self.taps = taps
        self.label = label
        self.message = message
    }
}
