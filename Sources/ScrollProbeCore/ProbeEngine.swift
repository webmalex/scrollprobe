import CoreGraphics
import Foundation

public enum ProbeEngineState: String, Sendable {
    case stopped
    case starting
    case monitoring
    case stopping
    case failed
}

public enum ProbeEngineError: LocalizedError {
    case alreadyRunning
    case accessibilityPermissionMissing
    case internalState

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "ScrollProbe is already monitoring."
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required for the active HID event tap."
        case .internalState:
            return "ScrollProbe reached an invalid internal state."
        }
    }
}

public final class ProbeEngine {
    public private(set) var state: ProbeEngineState = .stopped
    public private(set) var runID: UUID?
    public private(set) var logURL: URL?
    public var onSnapshot: ((ProbeMetricsSnapshot) -> Void)?
    public var onStatus: ((ProbeEngineState, String) -> Void)?

    private var eventThread: EventTapThread?
    private var ingressTap: EventTapHandle?
    private var downstreamTap: EventTapHandle?
    private var snapshotTimer: Timer?
    private var metrics: MetricsAccumulator?
    private var logger: RunLogger?

    public init() {}

    deinit {
        stop()
    }

    public func start() throws {
        guard state == .stopped || state == .failed else {
            throw ProbeEngineError.alreadyRunning
        }
        guard EventAccess.accessibilityEnabled else {
            throw ProbeEngineError.accessibilityPermissionMissing
        }

        updateState(.starting, message: "Creating event taps...")
        let runID = UUID()
        let metrics = MetricsAccumulator(runID: runID)
        let logger = try RunLogger(runID: runID)
        let eventThread = EventTapThread()

        self.runID = runID
        self.metrics = metrics
        self.logger = logger
        self.logURL = logger.fileURL
        self.eventThread = eventThread
        eventThread.start()

        do {
            try eventThread.performSync { [weak self] in
                guard let self else {
                    throw ProbeEngineError.internalState
                }
                try self.installTapsAndTimer()
            }
        } catch {
            cleanupAfterFailedStart(message: error.localizedDescription)
            throw error
        }

        let metadata = ProbeRunMetadata(
            runID: runID,
            startedAt: Date(),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hostName: ProcessInfo.processInfo.hostName,
            processID: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.scrollprobe.ScrollProbe",
            ingressDescription: "kCGHIDEventTap/headInsert/default/pass-through",
            downstreamDescription: "kCGAnnotatedSessionEventTap/tailAppend/listenOnly"
        )
        logger.write(ProbeLogRecord(type: "run-start", runID: runID, metadata: metadata))
        if let taps = try? captureTapInventory(label: "after-start") {
            publishStatus("Monitoring started with \(taps.count) registered event taps.")
        } else {
            publishStatus("Monitoring started; event tap inventory was unavailable.")
        }
        updateState(.monitoring, message: "Monitor-only mode is active.")
    }

    public func stop() {
        guard state == .monitoring || state == .starting || state == .failed else {
            return
        }
        updateState(.stopping, message: "Stopping event taps...")

        if let eventThread {
            try? eventThread.performSync { [weak self] in
                guard let self else {
                    return
                }
                self.snapshotTimer?.invalidate()
                self.snapshotTimer = nil
                self.publishMetricsSnapshot()
                self.downstreamTap?.invalidate()
                self.downstreamTap = nil
                self.ingressTap?.invalidate()
                self.ingressTap = nil
            }
            eventThread.stop()
        }

        if let runID {
            logger?.write(ProbeLogRecord(type: "run-stop", runID: runID, message: "Monitoring stopped."))
        }
        logger?.close()
        logger = nil
        eventThread = nil
        metrics = nil
        runID = nil
        updateState(.stopped, message: "Monitoring stopped.")
    }

    @discardableResult
    public func captureTapInventory(label: String) throws -> [EventTapInfo] {
        let taps = try TapInventory.snapshot()
        if let runID {
            logger?.write(ProbeLogRecord(type: "tap-inventory", runID: runID, taps: taps, label: label))
        }
        return taps
    }

    private func installTapsAndTimer() throws {
        ingressTap = try EventTapHandle(
            name: "ingress",
            stage: .ingress,
            location: .cghidEventTap,
            placement: .headInsertEventTap,
            options: .defaultTap,
            eventHandler: { [weak self] event in
                self?.record(event: event, stage: .ingress, decision: .pass)
                return .pass
            },
            disabledHandler: { [weak self] reason in
                self?.metrics?.recordDisabled(stage: .ingress, reason: reason)
            },
            faultHandler: { [weak self] message in
                self?.publishStatus("Ingress tap fault: \(message)")
            }
        )

        downstreamTap = try EventTapHandle(
            name: "downstream",
            stage: .downstream,
            location: .cgAnnotatedSessionEventTap,
            placement: .tailAppendEventTap,
            options: .listenOnly,
            eventHandler: { [weak self] event in
                self?.record(event: event, stage: .downstream, decision: nil)
                return .pass
            },
            disabledHandler: { [weak self] reason in
                self?.metrics?.recordDisabled(stage: .downstream, reason: reason)
            },
            faultHandler: { [weak self] message in
                self?.publishStatus("Downstream tap fault: \(message)")
            }
        )

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.publishMetricsSnapshot()
        }
        snapshotTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    private func record(event: CGEvent, stage: TapStage, decision: TapDecision?) {
        let callbackStart = DispatchTime.now().uptimeNanoseconds
        let sample = ScrollSample(event: event, receivedUptimeNanos: callbackStart)
        let callbackDuration = DispatchTime.now().uptimeNanoseconds - callbackStart
        metrics?.record(
            stage: stage,
            sample: sample,
            decision: decision,
            callbackDurationNanos: callbackDuration
        )
    }

    private func publishMetricsSnapshot() {
        guard let snapshot = metrics?.takeSnapshot() else {
            return
        }
        logger?.write(ProbeLogRecord(type: "metrics", runID: snapshot.runID, metrics: snapshot))
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot)
        }
    }

    private func cleanupAfterFailedStart(message: String) {
        if let eventThread {
            try? eventThread.performSync { [weak self] in
                self?.snapshotTimer?.invalidate()
                self?.snapshotTimer = nil
                self?.downstreamTap?.invalidate()
                self?.downstreamTap = nil
                self?.ingressTap?.invalidate()
                self?.ingressTap = nil
            }
            eventThread.stop()
        }
        if let runID {
            logger?.write(ProbeLogRecord(type: "error", runID: runID, message: message))
        }
        logger?.close()
        logger = nil
        eventThread = nil
        metrics = nil
        updateState(.failed, message: message)
    }

    private func updateState(_ state: ProbeEngineState, message: String) {
        self.state = state
        publishStatus(message)
    }

    private func publishStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.onStatus?(self.state, message)
        }
    }
}
