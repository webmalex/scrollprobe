import AppKit
import ScrollProbeCore

final class MainWindowController: NSWindowController, NSWindowDelegate {
    var onProtectionAction: (() -> Void)?
    var onAccessibilityRequest: (() -> Void)?
    var onDiagnosticsActivityChange: ((Bool) -> Void)?

    private let engine = ProbeEngine()
    private let protectionLabel = NSTextField(labelWithString: "Protection: Paused")
    private let protectionButton = NSButton()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "Stopped")
    private let logPathLabel = NSTextField(labelWithString: "No active log")
    private let logDirectoryLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(wrappingLabelWithString: "")
    private let modeDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let detailsTextView = NSTextView()
    private let scenarioPopup = NSPopUpButton()
    private let physicalInputPopup = NSPopUpButton()
    private let utmPointerPopup = NSPopUpButton()
    private let modePopup = NSPopUpButton()
    private let startButton = NSButton()
    private let stopButton = NSButton()
    private let chooseLogDirectoryButton = NSButton()
    private var selectedLogDirectory = MainWindowController.savedLogDirectory
    private var protectionState: ProtectionState = .disabled
    private var protectionDesired = false
    private var protectionCounters = ProtectionCounters()
    private var backgroundProtectionActive = false
    private var runningDiagnosticMode: ProbeMode?
    private var permissionTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScrollProbe \(Self.versionText)"
        window.center()
        window.minSize = NSSize(width: 800, height: 740)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        configureUI()
        configureEngineCallbacks()
        refreshPermissionStatus()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        permissionTimer?.invalidate()
        engine.stop()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshPermissionStatus()
        startPermissionPolling()
    }

    func stopMonitoring() {
        engine.stop()
    }

    var isMonitoring: Bool {
        engine.state == .starting || engine.state == .monitoring || engine.state == .stopping
    }

    func setProtectionStatus(
        state: ProtectionState,
        desired: Bool,
        counters: ProtectionCounters
    ) {
        let stateChanged = protectionState != state
        protectionState = state
        protectionDesired = desired
        protectionCounters = counters
        backgroundProtectionActive = state == .protected
        updateProtectionUI()
        updateModeAvailability()
        updateGuidance()
        if stateChanged, isMonitoring {
            engine.recordRuntimeEvent(
                type: "protection-state",
                message: Self.protectionStateDescription(state)
            )
        }
    }

    func windowWillClose(_: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        engine.stop()
    }

    func recordProtectionRecovery(_ counters: ProtectionCounters) {
        guard isMonitoring else {
            return
        }
        engine.recordRuntimeEvent(
            type: "protection-recovery",
            message: "timeout=\(counters.timeoutRecoveryCount) health=\(counters.healthRecoveryCount)"
        )
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

        let protectionRow = NSStackView()
        protectionRow.orientation = .horizontal
        protectionRow.alignment = .centerY
        protectionRow.spacing = 8
        protectionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        protectionLabel.lineBreakMode = .byTruncatingMiddle
        protectionRow.addArrangedSubview(protectionLabel)
        protectionButton.title = "Enable Protection"
        protectionButton.target = self
        protectionButton.action = #selector(protectionAction)
        protectionButton.bezelStyle = .rounded
        protectionRow.addArrangedSubview(protectionButton)
        root.addArrangedSubview(protectionRow)
        protectionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 540).isActive = true

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
        let legacyScenario = UserDefaults.standard.string(forKey: Self.scenarioDefaultsKey)
        let savedScenario = Self.currentScenarioID(for: legacyScenario)
        let selectedIndex = ScenarioPreset.all.firstIndex { $0.id == savedScenario } ?? 0
        scenarioPopup.selectItem(at: selectedIndex)
        if savedScenario != legacyScenario {
            UserDefaults.standard.set(savedScenario, forKey: Self.scenarioDefaultsKey)
        }
        scenarioPopup.target = self
        scenarioPopup.action = #selector(scenarioChanged)
        scenarioRow.addArrangedSubview(scenarioPopup)
        scenarioPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 500).isActive = true
        root.addArrangedSubview(scenarioRow)

        let pointerRow = NSStackView()
        pointerRow.orientation = .horizontal
        pointerRow.alignment = .centerY
        pointerRow.spacing = 8
        pointerRow.addArrangedSubview(NSTextField(labelWithString: "Physical input:"))
        physicalInputPopup.addItems(withTitles: PhysicalInputChoice.allCases.map(\.title))
        let savedPhysicalInput = UserDefaults.standard.string(forKey: Self.physicalInputDefaultsKey)
        let physicalInputIndex = PhysicalInputChoice.allCases.firstIndex {
            $0.rawValue == savedPhysicalInput
        } ?? 0
        physicalInputPopup.selectItem(at: physicalInputIndex)
        physicalInputPopup.target = self
        physicalInputPopup.action = #selector(physicalInputChanged)
        pointerRow.addArrangedSubview(physicalInputPopup)
        physicalInputPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        pointerRow.addArrangedSubview(NSTextField(labelWithString: "UTM pointer:"))
        utmPointerPopup.autoenablesItems = false
        utmPointerPopup.addItems(withTitles: UTMPointerChoice.allCases.map(\.title))
        let storedPointer = UserDefaults.standard.string(forKey: Self.utmPointerDefaultsKey)
        let savedPointer = storedPointer ?? Self.legacyUTMPointer(for: legacyScenario)?.rawValue
        let pointerIndex = UTMPointerChoice.allCases.firstIndex { $0.rawValue == savedPointer } ?? 1
        utmPointerPopup.selectItem(at: pointerIndex)
        if storedPointer == nil, let savedPointer {
            UserDefaults.standard.set(savedPointer, forKey: Self.utmPointerDefaultsKey)
        }
        utmPointerPopup.target = self
        utmPointerPopup.action = #selector(utmPointerChanged)
        pointerRow.addArrangedSubview(utmPointerPopup)
        utmPointerPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        root.addArrangedSubview(pointerRow)

        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 8
        modeRow.addArrangedSubview(NSTextField(labelWithString: "Mode:"))
        modePopup.autoenablesItems = false
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
        root.addArrangedSubview(logDirectoryRow)
        logDirectoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        logDirectoryLabel.widthAnchor.constraint(
            lessThanOrEqualTo: root.widthAnchor,
            constant: -220
        ).isActive = true

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
        updateUTMPointerAvailability()
        updateGuidance()
        updateProtectionUI()
    }

    private func configureEngineCallbacks() {
        engine.onStatus = { [weak self] state, message in
            guard let self else {
                return
            }
            self.stateLabel.stringValue = "\(state.rawValue): \(message)"
            self.updateButtons(for: state)
            let isRunning = state == .starting || state == .monitoring || state == .stopping
            self.onDiagnosticsActivityChange?(isRunning)
            if state == .stopped || state == .failed {
                self.runningDiagnosticMode = nil
                self.updateGuidance()
            }
            if let logURL = self.engine.logURL {
                self.logPathLabel.stringValue = logURL.path
            }
        }
        engine.onSnapshot = { [weak self] snapshot in
            self?.runningDiagnosticMode = snapshot.mode
            self?.detailsTextView.string = Self.format(snapshot)
            self?.updateGuidance()
        }
    }

    private func refreshPermissionStatus() {
        let accessibility = EventAccess.accessibilityEnabled ? "granted" : "missing"
        permissionLabel.stringValue = "Accessibility: \(accessibility)    Input Monitoring: not required"
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else {
            return
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    private func updateButtons(for state: ProbeEngineState) {
        let isActive = state == .starting || state == .monitoring || state == .stopping
        startButton.isEnabled = !isActive
        stopButton.isEnabled = state == .monitoring
        scenarioPopup.isEnabled = !isActive
        physicalInputPopup.isEnabled = !isActive
        utmPointerPopup.isEnabled = !isActive && selectedScenario.role != .standalone
        modePopup.isEnabled = !isActive
        chooseLogDirectoryButton.isEnabled = !isActive
        updateProtectionUI()
    }

    @objc private func requestAccessibility() {
        if let onAccessibilityRequest {
            onAccessibilityRequest()
        } else {
            EventAccess.requestAccessibility()
        }
        refreshPermissionStatus()
    }

    @objc private func protectionAction() {
        onProtectionAction?()
    }

    @objc private func startMonitoring() {
        let mode = selectedMode
        if selectedScenario.role != .standalone, selectedUTMPointer == .notApplicable {
            stateLabel.stringValue = "failed: Select Mac Trackpad or Generic Mouse for a guest profile."
            return
        }
        if backgroundProtectionActive, mode != .monitor {
            stateLabel.stringValue = "failed: Pause background protection before using a diagnostic drop mode."
            modePopup.selectItem(at: ProbeMode.allCases.firstIndex(of: .monitor) ?? 0)
            updateGuidance()
            return
        }
        if selectedScenario.role != .guest, mode != .monitor {
            stateLabel.stringValue = "failed: Drop modes are available only for guest profiles."
            modePopup.selectItem(at: ProbeMode.allCases.firstIndex(of: .monitor) ?? 0)
            updateGuidance()
            return
        }
        if mode == .dropAll, !confirmDropAll() {
            return
        }
        do {
            try engine.start(
                scenario: selectedScenario.id,
                physicalInput: selectedPhysicalInput.rawValue,
                utmPointerDevice: selectedUTMPointer.rawValue,
                mode: mode,
                backgroundProtectionActive: backgroundProtectionActive,
                logDirectory: selectedLogDirectory
            )
            runningDiagnosticMode = mode
            updateGuidance()
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
        updateUTMPointerAvailability()
        updateModeAvailability()
        updateGuidance()
    }

    @objc private func utmPointerChanged() {
        updateUTMPointerAvailability()
        if selectedUTMPointer != .notApplicable {
            UserDefaults.standard.set(selectedUTMPointer.rawValue, forKey: Self.utmPointerDefaultsKey)
        }
        updateGuidance()
    }

    @objc private func physicalInputChanged() {
        UserDefaults.standard.set(selectedPhysicalInput.rawValue, forKey: Self.physicalInputDefaultsKey)
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

    private var selectedUTMPointer: UTMPointerChoice {
        let index = utmPointerPopup.indexOfSelectedItem
        guard UTMPointerChoice.allCases.indices.contains(index) else {
            return .notApplicable
        }
        return UTMPointerChoice.allCases[index]
    }

    private var selectedPhysicalInput: PhysicalInputChoice {
        let index = physicalInputPopup.indexOfSelectedItem
        guard PhysicalInputChoice.allCases.indices.contains(index) else {
            return .trackpad
        }
        return PhysicalInputChoice.allCases[index]
    }

    private func updateGuidance() {
        let scenario = selectedScenario
        instructionLabel.stringValue = scenario.instructions(
            physicalInput: selectedPhysicalInput.title,
            utmPointer: selectedUTMPointer.title
        )
        let displayedMode = runningDiagnosticMode ?? selectedMode
        modeDescriptionLabel.stringValue = backgroundProtectionActive
            ? "Background protection is active. Diagnostics records the stream before and after the production filter."
            : Self.modeDescription(displayedMode)
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
        let guestModeAllowed = selectedScenario.role == .guest && !backgroundProtectionActive
        for index in ProbeMode.allCases.indices where index > 0 {
            modePopup.item(at: index)?.isEnabled = guestModeAllowed
        }
        if !isMonitoring, !guestModeAllowed, selectedMode != .monitor {
            modePopup.selectItem(at: ProbeMode.allCases.firstIndex(of: .monitor) ?? 0)
        }
    }

    private func updateUTMPointerAvailability() {
        let isGuestPath = selectedScenario.role != .standalone
        utmPointerPopup.isEnabled = isGuestPath && !isMonitoring
        utmPointerPopup.item(at: 0)?.isEnabled = !isGuestPath
        utmPointerPopup.item(at: 1)?.isEnabled = isGuestPath
        utmPointerPopup.item(at: 2)?.isEnabled = isGuestPath
        if isGuestPath, selectedUTMPointer == .notApplicable {
            let savedValue = UserDefaults.standard.string(forKey: Self.utmPointerDefaultsKey)
            let savedChoice = UTMPointerChoice(rawValue: savedValue ?? "") ?? .macTrackpad
            let choice = savedChoice == .notApplicable ? UTMPointerChoice.macTrackpad : savedChoice
            utmPointerPopup.selectItem(at: UTMPointerChoice.allCases.firstIndex(of: choice) ?? 1)
        } else if !isGuestPath {
            utmPointerPopup.selectItem(at: UTMPointerChoice.allCases.firstIndex(of: .notApplicable) ?? 0)
        }
    }

    private func updateProtectionUI() {
        let stateText: String
        let actionTitle: String
        let actionEnabled: Bool

        switch protectionState {
        case .disabled:
            stateText = "Protection: Paused"
            actionTitle = "Enable Protection"
            actionEnabled = true
        case .starting:
            stateText = "Protection: Starting..."
            actionTitle = "Pause Protection"
            actionEnabled = true
        case .protected:
            stateText = "Protection: Active | filtered=\(protectionCounters.dropped) passed=\(protectionCounters.passed)"
            actionTitle = "Pause Protection"
            actionEnabled = true
        case .permissionMissing:
            stateText = "Protection: Accessibility Required"
            actionTitle = "Request Accessibility"
            actionEnabled = true
        case let .failed(message):
            stateText = "Protection: Failed | \(message)"
            actionTitle = "Retry Protection"
            actionEnabled = protectionDesired
        }

        protectionLabel.stringValue = stateText
        protectionButton.title = actionTitle
        protectionButton.isEnabled = actionEnabled && !isMonitoring
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
    private static let physicalInputDefaultsKey = "physicalInput"
    private static let utmPointerDefaultsKey = "utmPointerDevice"
    private static let logDirectoryDefaultsKey = "logDirectory"

    private static func currentScenarioID(for savedID: String?) -> String? {
        guard let savedID else {
            return nil
        }
        if ScenarioPreset.all.contains(where: { $0.id == savedID }) {
            return savedID
        }
        for suffix in ["-trackpad-linearmouse", "-trackpad", "-mouse"] where savedID.hasSuffix(suffix) {
            let candidate = String(savedID.dropLast(suffix.count))
            if ScenarioPreset.all.contains(where: { $0.id == candidate }) {
                return candidate
            }
        }
        return nil
    }

    private static func legacyUTMPointer(for savedID: String?) -> UTMPointerChoice? {
        guard let savedID else {
            return nil
        }
        return savedID.hasSuffix("-mouse") ? .genericMouse : .macTrackpad
    }

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

    private static func protectionStateDescription(_ state: ProtectionState) -> String {
        switch state {
        case .disabled:
            return "disabled"
        case .starting:
            return "starting"
        case .protected:
            return "protected"
        case .permissionMissing:
            return "permission-missing"
        case let .failed(message):
            return "failed: \(message)"
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

private enum ScenarioRole: Equatable {
    case standalone
    case hostForGuest
    case guest
}

private enum PhysicalInputChoice: String, CaseIterable {
    case trackpad
    case mouse

    var title: String {
        switch self {
        case .trackpad:
            return "Trackpad"
        case .mouse:
            return "Mouse"
        }
    }
}

private enum UTMPointerChoice: String, CaseIterable {
    case notApplicable = "not-applicable"
    case macTrackpad = "mac-trackpad"
    case genericMouse = "generic-mouse"

    var title: String {
        switch self {
        case .notApplicable:
            return "Not applicable (host only)"
        case .macTrackpad:
            return "Mac Trackpad"
        case .genericMouse:
            return "Generic Mouse"
        }
    }
}

private struct ScenarioPreset {
    let id: String
    let title: String
    let role: ScenarioRole
    let pairedID: String?

    func instructions(physicalInput: String, utmPointer: String) -> String {
        switch role {
        case .standalone:
            return "Physical input: \(physicalInput). Start here, wait 2 seconds, perform one scroll gesture, " +
                "wait for momentum plus 2 seconds, then Stop."
        case .hostForGuest:
            return "Physical input: \(physicalInput). UTM pointer: \(utmPointer). Step 1: start here. In guest select " +
                "\(pairedID ?? "the paired profile") and start Step 2. " +
                "Wait 2 seconds, perform one gesture, wait for momentum plus 2 seconds, stop guest, then host."
        case .guest:
            return "Physical input: \(physicalInput). UTM pointer: \(utmPointer). Step 2: first start " +
                "\(pairedID ?? "the paired profile") on host, then start here. " +
                "Wait 2 seconds, perform one gesture, wait for momentum plus 2 seconds, stop here, then host."
        }
    }

    static let all: [ScenarioPreset] = [
        .init(id: "host-native", title: "Host: native app", role: .standalone, pairedID: nil),
        .init(id: "host-horizon", title: "Host: direct Horizon", role: .standalone, pairedID: nil),
        .init(id: "host-to-guest-native", title: "Host side: guest native app", role: .hostForGuest, pairedID: "guest-native"),
        .init(id: "guest-native", title: "Guest: native app", role: .guest, pairedID: "host-to-guest-native"),
        .init(id: "host-to-guest-horizon-ubuntu", title: "Host side: guest Horizon Ubuntu", role: .hostForGuest, pairedID: "guest-horizon-ubuntu"),
        .init(id: "guest-horizon-ubuntu", title: "Guest: Horizon Ubuntu", role: .guest, pairedID: "host-to-guest-horizon-ubuntu"),
        .init(id: "host-to-guest-horizon-windows", title: "Host side: guest Horizon Windows", role: .hostForGuest, pairedID: "guest-horizon-windows"),
        .init(id: "guest-horizon-windows", title: "Guest: Horizon Windows", role: .guest, pairedID: "host-to-guest-horizon-windows"),
    ]
}
