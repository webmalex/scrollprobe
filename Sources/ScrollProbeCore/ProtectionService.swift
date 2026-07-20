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
    public let userInputRecoveryCount: UInt64

    public init(
        observed: UInt64 = 0,
        passed: UInt64 = 0,
        dropped: UInt64 = 0,
        timeoutRecoveryCount: UInt64 = 0,
        healthRecoveryCount: UInt64 = 0,
        userInputRecoveryCount: UInt64 = 0
    ) {
        self.observed = observed
        self.passed = passed
        self.dropped = dropped
        self.timeoutRecoveryCount = timeoutRecoveryCount
        self.healthRecoveryCount = healthRecoveryCount
        self.userInputRecoveryCount = userInputRecoveryCount
    }
}

public enum ProtectionRecoveryReason: String, Equatable, Sendable {
    case timeout
    case healthCheck
    case userInput
    case tapFault
}

public struct ProtectionRecovery: Equatable, Sendable {
    public let reason: ProtectionRecoveryReason
    public let date: Date
    public let detail: String?

    public init(reason: ProtectionRecoveryReason, date: Date, detail: String? = nil) {
        self.reason = reason
        self.date = date
        self.detail = detail
    }
}

public struct ProtectionSnapshot: Equatable, Sendable {
    public let counters: ProtectionCounters
    public let tapActiveSince: Date?
    public let tapGeneration: UInt64
    public let tapRecreationCount: UInt64
    public let lastRecovery: ProtectionRecovery?
    public let lastError: String?

    public init(
        counters: ProtectionCounters = ProtectionCounters(),
        tapActiveSince: Date? = nil,
        tapGeneration: UInt64 = 0,
        tapRecreationCount: UInt64 = 0,
        lastRecovery: ProtectionRecovery? = nil,
        lastError: String? = nil
    ) {
        self.counters = counters
        self.tapActiveSince = tapActiveSince
        self.tapGeneration = tapGeneration
        self.tapRecreationCount = tapRecreationCount
        self.lastRecovery = lastRecovery
        self.lastError = lastError
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
    private var observed: UInt64 = 0
    private var passed: UInt64 = 0
    private var dropped: UInt64 = 0
    private var timeoutRecoveryCount: UInt64 = 0
    private var healthRecoveryCount: UInt64 = 0
    private var userInputRecoveryCount: UInt64 = 0
    private var tapActiveSince: Date?
    private var tapGeneration: UInt64 = 0
    private var tapRecreationCount: UInt64 = 0
    private var lastRecovery: ProtectionRecovery?
    private var lastError: String?
    private var recreationAttempt = 0
    private var recreationWorkItem: DispatchWorkItem?

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

        resetCounters()
        lastError = nil
        recreationAttempt = 0
        updateState(.starting)
        do {
            try installTapThread()
        } catch {
            _ = cleanupTapThread()
            lastError = error.localizedDescription
            updateState(.failed(error.localizedDescription))
            return false
        }

        tapGeneration &+= 1
        tapActiveSince = Date()
        updateState(.protected)
        return true
    }

    public func stop() {
        guard state != .disabled else {
            return
        }
        recreationWorkItem?.cancel()
        recreationWorkItem = nil
        recreationAttempt = 0
        let didCleanUp = cleanupTapThread()
        updateState(didCleanUp ? .disabled : .failed("Protection tap teardown could not be confirmed."))
    }

    public func snapshot() -> ProtectionSnapshot {
        let counters: ProtectionCounters
        if let eventThread,
           let currentCounters = try? eventThread.performSync({ [self] in makeCounters() }) {
            counters = currentCounters
        } else {
            counters = makeCounters()
        }
        return ProtectionSnapshot(
            counters: counters,
            tapActiveSince: tapActiveSince,
            tapGeneration: tapGeneration,
            tapRecreationCount: tapRecreationCount,
            lastRecovery: lastRecovery,
            lastError: lastError
        )
    }

    private func installTapThread() throws {
        let eventThread = EventTapThread()
        self.eventThread = eventThread
        eventThread.start()
        guard state == .starting, self.eventThread === eventThread else {
            throw EventTapThreadError.notRunning
        }
        do {
            try eventThread.performSync { [weak self] in
                guard let self else {
                    throw EventTapThreadError.notRunning
                }
                try self.installTap()
            }
        } catch {
            _ = cleanupTapThread()
            throw error
        }
    }

    private func installTap() throws {
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
            userInputRecoveryCount &+= 1
        }
        publishCounters(recovery: ProtectionRecovery(reason: reason.recoveryReason, date: Date()))
    }

    private func handleFault(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .protected || self.state == .starting else {
                return
            }
            self.lastError = message
            let recentlyRecordedDisable = self.lastRecovery.map {
                Date().timeIntervalSince($0.date) <= 1
            } ?? false
            if !recentlyRecordedDisable {
                self.lastRecovery = ProtectionRecovery(reason: .tapFault, date: Date(), detail: message)
            }
            _ = self.cleanupTapThread()
            self.updateState(.starting)
            self.scheduleRecreation()
        }
    }

    private func scheduleRecreation() {
        guard let delay = TapRecreationPolicy.delay(forAttempt: recreationAttempt) else {
            updateState(.failed(lastError ?? "Protection tap could not be recovered."))
            return
        }

        recreationAttempt += 1
        let workItem = DispatchWorkItem { [weak self] in
            self?.performRecreationAttempt()
        }
        recreationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    private func performRecreationAttempt() {
        guard state == .starting else {
            return
        }
        do {
            try installTapThread()
            tapGeneration &+= 1
            tapRecreationCount &+= 1
            tapActiveSince = Date()
            recreationAttempt = 0
            recreationWorkItem = nil
            updateState(.protected)
        } catch {
            lastError = error.localizedDescription
            scheduleRecreation()
        }
    }

    @discardableResult
    private func cleanupTapThread() -> Bool {
        var didInvalidate = true
        if let eventThread {
            do {
                try eventThread.performSync { [weak self] in
                    self?.eventTap?.invalidate()
                    self?.eventTap = nil
                }
            } catch {
                didInvalidate = false
                eventTap?.invalidate()
                eventTap = nil
            }
            eventThread.stop()
            self.eventThread = nil
            tapActiveSince = nil
            return didInvalidate
        }
        eventTap?.invalidate()
        eventTap = nil
        tapActiveSince = nil
        return didInvalidate
    }

    private func resetCounters() {
        observed = 0
        passed = 0
        dropped = 0
        timeoutRecoveryCount = 0
        healthRecoveryCount = 0
        userInputRecoveryCount = 0
        tapGeneration = 0
        tapRecreationCount = 0
        tapActiveSince = nil
        lastRecovery = nil
        publishCounters()
    }

    private func makeCounters() -> ProtectionCounters {
        ProtectionCounters(
            observed: observed,
            passed: passed,
            dropped: dropped,
            timeoutRecoveryCount: timeoutRecoveryCount,
            healthRecoveryCount: healthRecoveryCount,
            userInputRecoveryCount: userInputRecoveryCount
        )
    }

    private func publishCounters(recovery: ProtectionRecovery? = nil) {
        let counters = makeCounters()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if let recovery {
                self.lastRecovery = recovery
            }
            self.onCounters?(counters)
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

enum TapRecreationPolicy {
    static let delays: [TimeInterval] = [0, 0.5, 1]

    static func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard delays.indices.contains(attempt) else {
            return nil
        }
        return delays[attempt]
    }
}

private extension TapDisableReason {
    var recoveryReason: ProtectionRecoveryReason {
        switch self {
        case .timeout:
            return .timeout
        case .userInput:
            return .userInput
        case .healthCheck:
            return .healthCheck
        }
    }
}
