import CoreGraphics
import Foundation

public enum ProtectionState: Equatable, Sendable {
    case disabled
    case starting
    case protected
    case permissionMissing
    case failed(String)
}

public struct ProtectionCounters: Equatable, Sendable {
    public let observed: UInt64
    public let passed: UInt64
    public let dropped: UInt64
    public let timeoutRecoveryCount: UInt64
    public let healthRecoveryCount: UInt64

    public init(
        observed: UInt64 = 0,
        passed: UInt64 = 0,
        dropped: UInt64 = 0,
        timeoutRecoveryCount: UInt64 = 0,
        healthRecoveryCount: UInt64 = 0
    ) {
        self.observed = observed
        self.passed = passed
        self.dropped = dropped
        self.timeoutRecoveryCount = timeoutRecoveryCount
        self.healthRecoveryCount = healthRecoveryCount
    }
}

public enum ZeroDeltaChangedPolicy {
    public static func decision(for event: CGEvent) -> TapDecision {
        guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) ==
              Int64(CGScrollPhase.changed.rawValue) else {
            return .pass
        }

        let hasDelta =
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1) != 0 ||
            event.getIntegerValueField(.scrollWheelEventDeltaAxis2) != 0 ||
            event.getIntegerValueField(.scrollWheelEventDeltaAxis3) != 0 ||
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) != 0 ||
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) != 0 ||
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3) != 0 ||
            event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) != 0 ||
            event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) != 0 ||
            event.getDoubleValueField(.scrollWheelEventPointDeltaAxis3) != 0

        return hasDelta ? .pass : .drop
    }
}

public final class ProtectionService {
    public private(set) var state: ProtectionState = .disabled
    public var onStateChange: ((ProtectionState) -> Void)?
    public var onCounters: ((ProtectionCounters) -> Void)?

    private var eventThread: EventTapThread?
    private var eventTap: EventTapHandle?
    private var countersTimer: Timer?
    private var observed: UInt64 = 0
    private var passed: UInt64 = 0
    private var dropped: UInt64 = 0
    private var timeoutRecoveryCount: UInt64 = 0
    private var healthRecoveryCount: UInt64 = 0

    public init() {}

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        guard state != .protected, state != .starting else {
            return true
        }
        guard EventAccess.accessibilityEnabled else {
            updateState(.permissionMissing)
            return false
        }

        updateState(.starting)
        resetCounters()

        let eventThread = EventTapThread()
        self.eventThread = eventThread
        eventThread.start()

        do {
            try eventThread.performSync { [weak self] in
                guard let self else {
                    throw EventTapThreadError.notRunning
                }
                try self.installTapAndTimer()
            }
        } catch {
            _ = cleanupTapThread()
            updateState(.failed(error.localizedDescription))
            return false
        }

        updateState(.protected)
        return true
    }

    public func stop() {
        guard state != .disabled else {
            return
        }
        let didCleanUp = cleanupTapThread()
        updateState(didCleanUp ? .disabled : .failed("Protection tap teardown could not be confirmed."))
    }

    private func installTapAndTimer() throws {
        eventTap = try EventTapHandle(
            name: "protection",
            stage: .ingress,
            location: .cghidEventTap,
            placement: .headInsertEventTap,
            options: .defaultTap,
            eventHandler: { [weak self] event in
                self?.handle(event) ?? .pass
            },
            disabledHandler: { [weak self] reason in
                self?.recordRecovery(reason)
            },
            faultHandler: { [weak self] message in
                self?.handleFault(message)
            }
        )

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            autoreleasepool {
                self?.publishCounters()
            }
        }
        countersTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    private func handle(_ event: CGEvent) -> TapDecision {
        let decision = ZeroDeltaChangedPolicy.decision(for: event)
        observed &+= 1
        switch decision {
        case .pass:
            passed &+= 1
        case .drop:
            dropped &+= 1
        }
        return decision
    }

    private func recordRecovery(_ reason: TapDisableReason) {
        switch reason {
        case .timeout:
            timeoutRecoveryCount &+= 1
        case .healthCheck:
            healthRecoveryCount &+= 1
        case .userInput:
            break
        }
    }

    private func handleFault(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .protected || self.state == .starting else {
                return
            }
            _ = self.cleanupTapThread()
            self.updateState(.failed(message))
        }
    }

    @discardableResult
    private func cleanupTapThread() -> Bool {
        var didInvalidate = true
        if let eventThread {
            do {
                try eventThread.performSync { [weak self] in
                    self?.countersTimer?.invalidate()
                    self?.countersTimer = nil
                    self?.eventTap?.invalidate()
                    self?.eventTap = nil
                }
            } catch {
                didInvalidate = false
                countersTimer?.invalidate()
                countersTimer = nil
                eventTap?.invalidate()
                eventTap = nil
            }
            eventThread.stop()
            self.eventThread = nil
            return didInvalidate
        }
        countersTimer?.invalidate()
        countersTimer = nil
        eventTap?.invalidate()
        eventTap = nil
        return didInvalidate
    }

    private func resetCounters() {
        observed = 0
        passed = 0
        dropped = 0
        timeoutRecoveryCount = 0
        healthRecoveryCount = 0
        publishCounters()
    }

    private func publishCounters() {
        let counters = ProtectionCounters(
            observed: observed,
            passed: passed,
            dropped: dropped,
            timeoutRecoveryCount: timeoutRecoveryCount,
            healthRecoveryCount: healthRecoveryCount
        )
        DispatchQueue.main.async { [weak self] in
            self?.onCounters?(counters)
        }
    }

    private func updateState(_ state: ProtectionState) {
        self.state = state
        let publish: () -> Void = { [weak self] in
            self?.onStateChange?(state)
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }
}
