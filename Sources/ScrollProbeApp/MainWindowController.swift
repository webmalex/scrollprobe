import AppKit
import ScrollProbeCore

final class MainWindowController: NSWindowController {
    private let engine = ProbeEngine()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "Stopped")
    private let logPathLabel = NSTextField(labelWithString: "No active log")
    private let logDirectoryLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(wrappingLabelWithString: "")
    private let modeDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let detailsTextView = NSTextView()
    private let scenarioPopup = NSPopUpButton()
    private let modePopup = NSPopUpButton()
    private let startButton = NSButton()
    private let stopButton = NSButton()
    private let chooseLogDirectoryButton = NSButton()
    private var selectedLogDirectory = MainWindowController.savedLogDirectory
    private var permissionTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScrollProbe \(Self.versionText)"
        window.center()
        window.minSize = NSSize(width: 800, height: 700)
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

        let title = NSTextField(labelWithString: "ScrollProbe \(Self.versionText)")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(title)

        let explanation = wrappingLabel(
            "Measures scroll events before and after the guest event chain. Experimental modes " +
                "can drop a narrowly selected class of events; ScrollProbe never synthesizes input."
        )
        root.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true

        permissionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        root.addArrangedSubview(permissionLabel)

        let permissionButtons = NSStackView(views: [
            button("Request Accessibility", action: #selector(requestAccessibility)),
        ])
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 8
        root.addArrangedSubview(permissionButtons)

        let scenarioRow = NSStackView()
        scenarioRow.orientation = .horizontal
        scenarioRow.alignment = .centerY
        scenarioRow.spacing = 8
        scenarioRow.addArrangedSubview(NSTextField(labelWithString: "Profile:"))
        scenarioPopup.addItems(withTitles: ScenarioPreset.all.map(\.title))
        let savedScenario = UserDefaults.standard.string(forKey: Self.scenarioDefaultsKey)
        let selectedIndex = ScenarioPreset.all.firstIndex { $0.id == savedScenario } ?? 0
        scenarioPopup.selectItem(at: selectedIndex)
        scenarioPopup.target = self
        scenarioPopup.action = #selector(scenarioChanged)
        scenarioRow.addArrangedSubview(scenarioPopup)
        scenarioPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 500).isActive = true
        root.addArrangedSubview(scenarioRow)

        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 8
        modeRow.addArrangedSubview(NSTextField(labelWithString: "Mode:"))
        modePopup.addItems(withTitles: ProbeMode.allCases.map(Self.modeTitle))
        modePopup.selectItem(at: ProbeMode.allCases.firstIndex(of: .monitor) ?? 0)
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modeRow.addArrangedSubview(modePopup)
        modePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        root.addArrangedSubview(modeRow)

        instructionLabel.textColor = .labelColor
        instructionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(instructionLabel)
        instructionLabel.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true

        modeDescriptionLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(modeDescriptionLabel)
        modeDescriptionLabel.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true

        let logDirectoryRow = NSStackView()
        logDirectoryRow.orientation = .horizontal
        logDirectoryRow.alignment = .centerY
        logDirectoryRow.spacing = 8
        chooseLogDirectoryButton.title = "Choose log folder..."
        chooseLogDirectoryButton.target = self
        chooseLogDirectoryButton.action = #selector(chooseLogDirectory)
        chooseLogDirectoryButton.bezelStyle = .rounded
        logDirectoryRow.addArrangedSubview(chooseLogDirectoryButton)
        logDirectoryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logDirectoryLabel.lineBreakMode = .byTruncatingMiddle
        logDirectoryLabel.stringValue = selectedLogDirectory.path
        logDirectoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        logDirectoryRow.addArrangedSubview(logDirectoryLabel)
        logDirectoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        logDirectoryLabel.widthAnchor.constraint(
            lessThanOrEqualTo: root.widthAnchor,
            constant: -220
        ).isActive = true
        root.addArrangedSubview(logDirectoryRow)

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
        detailsTextView.frame = NSRect(x: 0, y: 0, width: 880, height: 280)
        detailsTextView.minSize = NSSize(width: 0, height: 0)
        detailsTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        detailsTextView.isVerticallyResizable = true
        detailsTextView.isHorizontallyResizable = false
        detailsTextView.autoresizingMask = [.width]
        detailsTextView.textContainer?.containerSize = NSSize(
            width: 880,
            height: CGFloat.greatestFiniteMagnitude
        )
        detailsTextView.textContainer?.widthTracksTextView = true
        detailsTextView.string = "No measurements yet."
        scrollView.documentView = detailsTextView
        root.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        updateModeAvailability()
        updateGuidance()
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
        permissionLabel.stringValue = "Accessibility: \(accessibility)    Input Monitoring: not required"
    }

    private func updateButtons(for state: ProbeEngineState) {
        let isActive = state == .starting || state == .monitoring || state == .stopping
        startButton.isEnabled = !isActive
        stopButton.isEnabled = state == .monitoring
        scenarioPopup.isEnabled = !isActive
        modePopup.isEnabled = !isActive
        chooseLogDirectoryButton.isEnabled = !isActive
    }

    @objc private func requestAccessibility() {
        EventAccess.requestAccessibility()
        refreshPermissionStatus()
    }

    @objc private func startMonitoring() {
        let mode = selectedMode
        if mode == .dropAll, !confirmDropAll() {
            return
        }
        do {
            try engine.start(
                scenario: selectedScenario.id,
                mode: mode,
                logDirectory: selectedLogDirectory
            )
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
        stateLabel.stringValue = "Capturing event taps..."
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }
            do {
                let taps = try TapInventory.snapshot()
                DispatchQueue.main.async {
                    self.engine.recordTapInventory(taps, label: "manual")
                    self.detailsTextView.string = Self.format(taps)
                    self.stateLabel.stringValue = "Captured \(taps.count) event taps."
                }
            } catch {
                DispatchQueue.main.async {
                    self.stateLabel.stringValue = "Tap inventory failed: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func openLogs() {
        try? FileManager.default.createDirectory(at: selectedLogDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(selectedLogDirectory)
    }

    @objc private func scenarioChanged() {
        UserDefaults.standard.set(selectedScenario.id, forKey: Self.scenarioDefaultsKey)
        updateModeAvailability()
        updateGuidance()
    }

    @objc private func modeChanged() {
        updateGuidance()
    }

    @objc private func chooseLogDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose ScrollProbe log folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedLogDirectory
        guard panel.runModal() == .OK, let directory = panel.url else {
            return
        }
        selectedLogDirectory = directory
        logDirectoryLabel.stringValue = directory.path
        UserDefaults.standard.set(directory.path, forKey: Self.logDirectoryDefaultsKey)
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

    private var selectedScenario: ScenarioPreset {
        let index = scenarioPopup.indexOfSelectedItem
        guard ScenarioPreset.all.indices.contains(index) else {
            return ScenarioPreset.all[0]
        }
        return ScenarioPreset.all[index]
    }

    private var selectedMode: ProbeMode {
        let index = modePopup.indexOfSelectedItem
        guard ProbeMode.allCases.indices.contains(index) else {
            return .monitor
        }
        return ProbeMode.allCases[index]
    }

    private func updateGuidance() {
        let scenario = selectedScenario
        instructionLabel.stringValue = scenario.instructions
        modeDescriptionLabel.stringValue = Self.modeDescription(selectedMode)
        modeDescriptionLabel.textColor = selectedMode == .monitor ? .secondaryLabelColor : .systemOrange

        switch scenario.role {
        case .standalone:
            startButton.title = "Start monitor"
        case .hostForGuest:
            startButton.title = "1. Start on host"
        case .guest:
            startButton.title = "2. Start in guest"
        }
    }

    private func updateModeAvailability() {
        let guestModeAllowed = selectedScenario.role == .guest
        for index in ProbeMode.allCases.indices where index > 0 {
            modePopup.item(at: index)?.isEnabled = guestModeAllowed
        }
        if !guestModeAllowed, selectedMode != .monitor {
            modePopup.selectItem(at: ProbeMode.allCases.firstIndex(of: .monitor) ?? 0)
        }
    }

    private func confirmDropAll() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Temporarily drop all scroll events?"
        alert.informativeText = "All scroll events will be blocked for the first " +
            "\(ProbeMode.dropAllDurationSeconds) seconds. Keyboard and pointer movement are unaffected."
        alert.addButton(withTitle: "Start Drop-All")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static let scenarioDefaultsKey = "selectedScenario"
    private static let logDirectoryDefaultsKey = "logDirectory"

    private static var savedLogDirectory: URL {
        guard let path = UserDefaults.standard.string(forKey: logDirectoryDefaultsKey), !path.isEmpty else {
            return RunLogger.defaultLogDirectory
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        return "v\(version) (\(build))"
    }

    private static func modeTitle(_ mode: ProbeMode) -> String {
        switch mode {
        case .monitor:
            return "Monitor only"
        case .dropZeroDeltaChanged:
            return "Drop zero-delta changed events"
        case .dropAll:
            return "Drop all scroll for \(ProbeMode.dropAllDurationSeconds) seconds"
        }
    }

    private static func modeDescription(_ mode: ProbeMode) -> String {
        switch mode {
        case .monitor:
            return "Records both taps without changing input."
        case .dropZeroDeltaChanged:
            return "Experimental guest filter: preserves gesture lifecycle, momentum, and every event with real delta."
        case .dropAll:
            return "Diagnostic guest mode: proves whether Horizon obeys the HID head tap, then automatically returns to monitor-only."
        }
    }

    private static func format(_ snapshot: ProbeMetricsSnapshot) -> String {
        [
            "run: \(snapshot.runID.uuidString)",
            "mode: \(snapshot.mode.rawValue)",
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

private enum ScenarioRole {
    case standalone
    case hostForGuest
    case guest
}

private struct ScenarioPreset {
    let id: String
    let title: String
    let role: ScenarioRole
    let pairedID: String?

    var instructions: String {
        switch role {
        case .standalone:
            return "Start here, wait 2 seconds, perform one scroll gesture, wait for momentum plus 2 seconds, then Stop."
        case .hostForGuest:
            return "Step 1: start here. In guest select \(pairedID ?? "the paired profile") and start Step 2. " +
                "Wait 2 seconds, perform one gesture, wait for momentum plus 2 seconds, stop guest, then host."
        case .guest:
            return "Step 2: first start \(pairedID ?? "the paired profile") on host, then start here. " +
                "Wait 2 seconds, perform one gesture, wait for momentum plus 2 seconds, stop here, then host."
        }
    }

    static let all: [ScenarioPreset] = [
        .init(id: "host-native-trackpad", title: "Host: native app, trackpad", role: .standalone, pairedID: nil),
        .init(id: "host-horizon-trackpad", title: "Host: direct Horizon, trackpad", role: .standalone, pairedID: nil),
        .init(id: "host-to-guest-native-trackpad", title: "Host side: guest native app, trackpad", role: .hostForGuest, pairedID: "guest-native-trackpad"),
        .init(id: "guest-native-trackpad", title: "Guest: native app, trackpad", role: .guest, pairedID: "host-to-guest-native-trackpad"),
        .init(id: "host-to-guest-horizon-ubuntu-trackpad", title: "Host side: guest Horizon Ubuntu, trackpad", role: .hostForGuest, pairedID: "guest-horizon-ubuntu-trackpad"),
        .init(id: "guest-horizon-ubuntu-trackpad", title: "Guest: Horizon Ubuntu, trackpad", role: .guest, pairedID: "host-to-guest-horizon-ubuntu-trackpad"),
        .init(id: "host-to-guest-horizon-windows-trackpad", title: "Host side: guest Horizon Windows, trackpad", role: .hostForGuest, pairedID: "guest-horizon-windows-trackpad"),
        .init(id: "guest-horizon-windows-trackpad", title: "Guest: Horizon Windows, trackpad", role: .guest, pairedID: "host-to-guest-horizon-windows-trackpad"),
        .init(id: "host-to-guest-horizon-ubuntu-mouse", title: "Host side: guest Horizon Ubuntu, mouse control", role: .hostForGuest, pairedID: "guest-horizon-ubuntu-mouse"),
        .init(id: "guest-horizon-ubuntu-mouse", title: "Guest: Horizon Ubuntu, mouse control", role: .guest, pairedID: "host-to-guest-horizon-ubuntu-mouse"),
        .init(id: "host-to-guest-horizon-windows-mouse", title: "Host side: guest Horizon Windows, mouse control", role: .hostForGuest, pairedID: "guest-horizon-windows-mouse"),
        .init(id: "guest-horizon-windows-mouse", title: "Guest: Horizon Windows, mouse control", role: .guest, pairedID: "host-to-guest-horizon-windows-mouse"),
        .init(id: "host-to-guest-horizon-ubuntu-trackpad-linearmouse", title: "Host side: guest Ubuntu, trackpad + LinearMouse", role: .hostForGuest, pairedID: "guest-horizon-ubuntu-trackpad-linearmouse"),
        .init(id: "guest-horizon-ubuntu-trackpad-linearmouse", title: "Guest: Horizon Ubuntu, trackpad + LinearMouse", role: .guest, pairedID: "host-to-guest-horizon-ubuntu-trackpad-linearmouse"),
        .init(id: "host-to-guest-horizon-windows-trackpad-linearmouse", title: "Host side: guest Windows, trackpad + LinearMouse", role: .hostForGuest, pairedID: "guest-horizon-windows-trackpad-linearmouse"),
        .init(id: "guest-horizon-windows-trackpad-linearmouse", title: "Guest: Horizon Windows, trackpad + LinearMouse", role: .guest, pairedID: "host-to-guest-horizon-windows-trackpad-linearmouse"),
    ]
}
