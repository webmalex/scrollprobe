import AppKit
import ScrollProbeCore

final class MainWindowController: NSWindowController {
    private let engine = ProbeEngine()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "Stopped")
    private let logPathLabel = NSTextField(labelWithString: "No active log")
    private let detailsTextView = NSTextView()
    private let startButton = NSButton()
    private let stopButton = NSButton()
    private var permissionTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScrollProbe"
        window.center()
        window.minSize = NSSize(width: 760, height: 520)
        super.init(window: window)

        configureUI()
        configureEngineCallbacks()
        refreshPermissionStatus()

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
        permissionTimer = timer
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        permissionTimer?.invalidate()
        engine.stop()
    }

    func stopMonitoring() {
        engine.stop()
    }

    private func configureUI() {
        guard let window, let contentView = window.contentView else {
            return
        }

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: "Scroll event monitor")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(title)

        let explanation = wrappingLabel(
            "Monitor-only mode installs an active HID/head pass-through tap and a downstream " +
                "annotated-session listen-only tap. It does not modify or synthesize input."
        )
        root.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true

        permissionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        root.addArrangedSubview(permissionLabel)

        let permissionButtons = NSStackView(views: [
            button("Request Accessibility", action: #selector(requestAccessibility)),
            button("Request Input Monitoring", action: #selector(requestInputMonitoring)),
        ])
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 8
        root.addArrangedSubview(permissionButtons)

        let monitorButtons = NSStackView()
        monitorButtons.orientation = .horizontal
        monitorButtons.spacing = 8
        startButton.title = "Start monitor"
        startButton.target = self
        startButton.action = #selector(startMonitoring)
        startButton.bezelStyle = .rounded
        monitorButtons.addArrangedSubview(startButton)

        stopButton.title = "Stop"
        stopButton.target = self
        stopButton.action = #selector(stopMonitoringAction)
        stopButton.bezelStyle = .rounded
        stopButton.isEnabled = false
        monitorButtons.addArrangedSubview(stopButton)
        monitorButtons.addArrangedSubview(button("Snapshot event taps", action: #selector(snapshotTaps)))
        monitorButtons.addArrangedSubview(button("Open logs", action: #selector(openLogs)))
        root.addArrangedSubview(monitorButtons)

        stateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(stateLabel)

        logPathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logPathLabel.lineBreakMode = .byTruncatingMiddle
        logPathLabel.maximumNumberOfLines = 1
        root.addArrangedSubview(logPathLabel)
        logPathLabel.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        detailsTextView.isEditable = false
        detailsTextView.isSelectable = true
        detailsTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsTextView.textContainerInset = NSSize(width: 10, height: 10)
        detailsTextView.string = "No measurements yet."
        scrollView.documentView = detailsTextView
        root.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
    }

    private func configureEngineCallbacks() {
        engine.onStatus = { [weak self] state, message in
            guard let self else {
                return
            }
            self.stateLabel.stringValue = "\(state.rawValue): \(message)"
            self.updateButtons(for: state)
            if let logURL = self.engine.logURL {
                self.logPathLabel.stringValue = logURL.path
            }
        }
        engine.onSnapshot = { [weak self] snapshot in
            self?.detailsTextView.string = Self.format(snapshot)
        }
    }

    private func refreshPermissionStatus() {
        let accessibility = EventAccess.accessibilityEnabled ? "granted" : "missing"
        let listening = EventAccess.listenEnabled ? "granted" : "missing"
        permissionLabel.stringValue =
            "Accessibility: \(accessibility)    Input Monitoring: \(listening)"
    }

    private func updateButtons(for state: ProbeEngineState) {
        let isActive = state == .starting || state == .monitoring || state == .stopping
        startButton.isEnabled = !isActive
        stopButton.isEnabled = state == .monitoring
    }

    @objc private func requestAccessibility() {
        EventAccess.requestAccessibility()
        refreshPermissionStatus()
    }

    @objc private func requestInputMonitoring() {
        EventAccess.requestListenAccess()
        refreshPermissionStatus()
    }

    @objc private func startMonitoring() {
        do {
            try engine.start()
            if let logURL = engine.logURL {
                logPathLabel.stringValue = logURL.path
            }
        } catch {
            stateLabel.stringValue = "failed: \(error.localizedDescription)"
            updateButtons(for: .failed)
        }
    }

    @objc private func stopMonitoringAction() {
        engine.stop()
    }

    @objc private func snapshotTaps() {
        do {
            let taps = try engine.captureTapInventory(label: "manual")
            detailsTextView.string = Self.format(taps)
            stateLabel.stringValue = "Captured \(taps.count) event taps."
        } catch {
            stateLabel.stringValue = "Tap inventory failed: \(error.localizedDescription)"
        }
    }

    @objc private func openLogs() {
        let directory = RunLogger.defaultLogDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func format(_ snapshot: ProbeMetricsSnapshot) -> String {
        [
            "run: \(snapshot.runID.uuidString)",
            String(format: "interval: %.3f s", snapshot.intervalSeconds),
            "timestamp: \(snapshot.timestamp)",
            "",
            format(snapshot.ingress),
            "",
            format(snapshot.downstream),
            "",
            "ingress - downstream observed: \(snapshot.ingress.observed - snapshot.downstream.observed)",
        ].joined(separator: "\n")
    }

    private static func format(_ metrics: StageMetrics) -> String {
        let minArrival = formatUsec(metrics.minInterArrivalUsec)
        let avgArrival = formatUsec(metrics.avgInterArrivalUsec)
        let maxArrival = formatUsec(metrics.maxInterArrivalUsec)
        let avgCallback = formatUsec(metrics.avgCallbackUsec)
        let maxCallback = formatUsec(metrics.maxCallbackUsec)
        return [
            "[\(metrics.stage.rawValue)]",
            String(
                format: "observed=%d rate=%.1f/s returned=%d dropped=%d total=%d",
                metrics.observed,
                metrics.eventsPerSecond,
                metrics.returned,
                metrics.dropped,
                metrics.totalObserved
            ),
            "continuous=\(metrics.continuous) zeroDelta=\(metrics.zeroDelta) " +
                "scrollPhase=\(metrics.withScrollPhase) momentum=\(metrics.withMomentumPhase)",
            String(
                format: "integer sum x=%lld y=%lld | fixed sum x=%.3f y=%.3f | point sum x=%.3f y=%.3f",
                metrics.integerDeltaXSum,
                metrics.integerDeltaYSum,
                metrics.fixedDeltaXSum,
                metrics.fixedDeltaYSum,
                metrics.pointDeltaXSum,
                metrics.pointDeltaYSum
            ),
            "inter-arrival usec min/avg/max: \(minArrival) / \(avgArrival) / \(maxArrival)",
            "callback usec avg/max: \(avgCallback) / \(maxCallback)",
            "disable timeout/user/health: \(metrics.timeoutDisableCount) / " +
                "\(metrics.userInputDisableCount) / \(metrics.healthCheckReenableCount)",
            "scroll phases: \(metrics.scrollPhaseCounts)",
            "momentum phases: \(metrics.momentumPhaseCounts)",
            "source PIDs: \(metrics.sourcePIDCounts)",
        ].joined(separator: "\n")
    }

    private static func format(_ taps: [EventTapInfo]) -> String {
        taps.map { tap in
            let path = tap.tappingProcessPath.isEmpty ? "(unknown)" : tap.tappingProcessPath
            return String(
                format: "id=%u point=%u options=0x%x enabled=%@ pid=%d avg=%.1fus mask=0x%llx %@",
                tap.eventTapID,
                tap.tapPoint,
                tap.options,
                tap.enabled ? "yes" : "no",
                tap.tappingProcessID,
                tap.avgUsecLatency,
                tap.eventsOfInterest,
                path
            )
        }.joined(separator: "\n")
    }

    private static func formatUsec(_ value: Double?) -> String {
        guard let value else {
            return "n/a"
        }
        return String(format: "%.1f", value)
    }
}
