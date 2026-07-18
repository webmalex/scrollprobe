import AppKit
import ScrollProbeCore
import ServiceManagement

final class AppCoordinator: NSObject, NSMenuDelegate {
    private static let protectionEnabledKey = "protectionEnabled"

    private let protectionService = ProtectionService()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var diagnosticsWindowController: MainWindowController?
    private var permissionTimer: Timer?
    private var counterMenuItem: NSMenuItem?
    private var loginItemMenuItem: NSMenuItem?
    private var loginItemApprovalMenuItem: NSMenuItem?
    private var counters = ProtectionCounters()
    private var diagnosticsRunning = false
    private var loginItemStatus = SMAppService.mainApp.status

    private var protectionDesired: Bool {
        UserDefaults.standard.bool(forKey: Self.protectionEnabledKey)
    }

    func start(launchedAsLoginItem: Bool = false) {
        configureProtectionCallbacks()
        configureStatusButton()
        rebuildMenu()

        let isFirstLaunch = UserDefaults.standard.object(forKey: Self.protectionEnabledKey) == nil
        if protectionDesired {
            protectionService.start()
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshProtectionAccess()
        }

        if !launchedAsLoginItem,
           isFirstLaunch || protectionService.state == .permissionMissing {
            showDiagnostics()
        }
    }

    func shutdown() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        diagnosticsWindowController?.stopMonitoring()
        protectionService.stop()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func showDiagnostics() {
        let controller: MainWindowController
        if let diagnosticsWindowController {
            controller = diagnosticsWindowController
        } else {
            controller = MainWindowController()
            controller.onProtectionAction = { [weak self] in
                self?.performPrimaryProtectionAction()
            }
            controller.onAccessibilityRequest = { [weak self] in
                self?.promptAccessibility()
            }
            controller.onDiagnosticsActivityChange = { [weak self] isRunning in
                guard let self else {
                    return
                }
                self.diagnosticsRunning = isRunning
                self.rebuildMenu()
                self.updateDiagnosticsProtectionStatus()
            }
            diagnosticsWindowController = controller
        }

        updateDiagnosticsProtectionStatus()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func configureProtectionCallbacks() {
        protectionService.onStateChange = { [weak self] _ in
            guard let self else {
                return
            }
            self.updateStatusButton()
            self.rebuildMenu()
            self.updateDiagnosticsProtectionStatus()
        }
        protectionService.onCounters = { [weak self] counters in
            guard let self else {
                return
            }
            let previousCounters = self.counters
            self.counters = counters
            self.counterMenuItem?.title = Self.counterTitle(counters)
            if self.diagnosticsRunning,
               counters.timeoutRecoveryCount != previousCounters.timeoutRecoveryCount ||
               counters.healthRecoveryCount != previousCounters.healthRecoveryCount {
                self.diagnosticsWindowController?.recordProtectionRecovery(counters)
            }
            self.updateDiagnosticsProtectionStatus()
        }
    }

    private func configureStatusButton() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else {
            return
        }
        let symbolName: String
        switch protectionService.state {
        case .protected:
            symbolName = "shield.fill"
        case .starting:
            symbolName = "shield.lefthalf.filled"
        case .disabled:
            symbolName = "shield.slash"
        case .permissionMissing, .failed:
            symbolName = "exclamationmark.shield.fill"
        }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ScrollProbe")
        button.toolTip = Self.stateTitle(protectionService.state)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let stateItem = NSMenuItem(title: Self.stateTitle(protectionService.state), action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let counterItem = NSMenuItem(title: Self.counterTitle(counters), action: nil, keyEquivalent: "")
        counterItem.isEnabled = false
        counterMenuItem = counterItem
        menu.addItem(counterItem)
        menu.addItem(.separator())

        let primaryItem = NSMenuItem(
            title: diagnosticsRunning
                ? "Stop Diagnostics Before Changing Protection"
                : Self.primaryActionTitle(protectionService.state),
            action: #selector(primaryProtectionAction),
            keyEquivalent: ""
        )
        primaryItem.target = self
        primaryItem.isEnabled = !diagnosticsRunning
        menu.addItem(primaryItem)

        if protectionDesired,
           protectionService.state != .protected,
           protectionService.state != .starting {
            let disableItem = NSMenuItem(
                title: "Disable Protection",
                action: #selector(disableProtection),
                keyEquivalent: ""
            )
            disableItem.target = self
            disableItem.isEnabled = !diagnosticsRunning
            menu.addItem(disableItem)
        }

        menu.addItem(.separator())
        let loginItem = NSMenuItem(
            title: Self.loginItemTitle(loginItemStatus),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItemMenuItem = loginItem
        menu.addItem(loginItem)

        let approvalItem = NSMenuItem(
            title: "Allow Launch at Login in System Settings...",
            action: #selector(openLoginItemSettings),
            keyEquivalent: ""
        )
        approvalItem.target = self
        loginItemApprovalMenuItem = approvalItem
        menu.addItem(approvalItem)
        updateLoginItemMenuPresentation()

        menu.addItem(.separator())
        let diagnosticsItem = NSMenuItem(
            title: "Open Diagnostics...",
            action: #selector(openDiagnostics),
            keyEquivalent: "d"
        )
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit ScrollProbe", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func performPrimaryProtectionAction() {
        guard !diagnosticsRunning else {
            NSSound.beep()
            showDiagnostics()
            return
        }
        switch protectionService.state {
        case .disabled:
            enableProtection()
        case .starting, .protected:
            pauseProtection()
        case .permissionMissing:
            requestProtectionAccessibility()
        case .failed:
            retryProtection()
        }
    }

    private func enableProtection() {
        UserDefaults.standard.set(true, forKey: Self.protectionEnabledKey)
        if !EventAccess.accessibilityEnabled {
            EventAccess.requestAccessibility()
        }
        protectionService.start()
        rebuildMenu()
        updateDiagnosticsProtectionStatus()
    }

    private func pauseProtection() {
        UserDefaults.standard.set(false, forKey: Self.protectionEnabledKey)
        protectionService.stop()
        rebuildMenu()
        updateDiagnosticsProtectionStatus()
    }

    private func retryProtection() {
        UserDefaults.standard.set(true, forKey: Self.protectionEnabledKey)
        protectionService.stop()
        protectionService.start()
    }

    private func requestProtectionAccessibility() {
        guard !diagnosticsRunning else {
            NSSound.beep()
            showDiagnostics()
            return
        }
        UserDefaults.standard.set(true, forKey: Self.protectionEnabledKey)
        EventAccess.requestAccessibility()
        protectionService.start()
        showDiagnostics()
    }

    private func promptAccessibility() {
        EventAccess.requestAccessibility()
    }

    private func refreshProtectionAccess() {
        guard protectionDesired, !diagnosticsRunning else {
            return
        }

        if EventAccess.accessibilityEnabled {
            if protectionService.state == .permissionMissing || protectionService.state == .disabled {
                protectionService.start()
            }
        } else {
            switch protectionService.state {
            case .protected, .starting, .failed:
                protectionService.stop()
                protectionService.start()
            case .disabled:
                protectionService.start()
            case .permissionMissing:
                break
            }
        }
    }

    func menuWillOpen(_: NSMenu) {
        loginItemStatus = SMAppService.mainApp.status
        updateLoginItemMenuPresentation()
    }

    private func setLaunchAtLogin() {
        let service = SMAppService.mainApp
        let attemptedRegistration = service.status == .notRegistered || service.status == .notFound
        var operationError: Error?
        do {
            switch service.status {
            case .notRegistered:
                try service.register()
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                try service.unregister()
            case .notFound:
                try service.register()
            @unknown default:
                showLoginItemError("macOS returned an unknown login-item status.")
            }
        } catch {
            operationError = error
        }
        loginItemStatus = service.status
        updateLoginItemMenuPresentation()
        if attemptedRegistration, loginItemStatus == .requiresApproval {
            showLoginItemApprovalRequired()
        } else if let operationError {
            showLoginItemError(operationError.localizedDescription)
        }
    }

    private func updateLoginItemMenuPresentation() {
        loginItemMenuItem?.title = Self.loginItemTitle(loginItemStatus)
        loginItemMenuItem?.state = Self.loginItemMenuState(loginItemStatus)
        loginItemMenuItem?.isEnabled = true
        loginItemApprovalMenuItem?.isHidden = loginItemStatus != .requiresApproval
    }

    private func showLoginItemApprovalRequired() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow ScrollProbe at Login"
        alert.informativeText = "Enable ScrollProbe in System Settings > General > Login Items."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func showLoginItemError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Change Launch at Login"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func updateDiagnosticsProtectionStatus() {
        diagnosticsWindowController?.setProtectionStatus(
            state: protectionService.state,
            desired: protectionDesired,
            counters: counters
        )
    }

    @objc private func primaryProtectionAction() {
        performPrimaryProtectionAction()
    }

    @objc private func disableProtection() {
        guard !diagnosticsRunning else {
            NSSound.beep()
            showDiagnostics()
            return
        }
        pauseProtection()
    }

    @objc private func openDiagnostics() {
        showDiagnostics()
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin()
    }

    @objc private func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private static func stateTitle(_ state: ProtectionState) -> String {
        switch state {
        case .disabled:
            return "Protection: Paused"
        case .starting:
            return "Protection: Starting..."
        case .protected:
            return "Protection: Active"
        case .permissionMissing:
            return "Protection: Accessibility Required"
        case let .failed(message):
            return "Protection failed: \(message)"
        }
    }

    private static func primaryActionTitle(_ state: ProtectionState) -> String {
        switch state {
        case .disabled:
            return "Enable Protection"
        case .starting, .protected:
            return "Pause Protection"
        case .permissionMissing:
            return "Request Accessibility..."
        case .failed:
            return "Retry Protection"
        }
    }

    private static func counterTitle(_ counters: ProtectionCounters) -> String {
        "Filtered: \(counters.dropped)    Passed: \(counters.passed)"
    }

    private static func loginItemTitle(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered, .enabled, .requiresApproval, .notFound:
            return "Launch at Login"
        @unknown default:
            return "Launch at Login (Unknown)"
        }
    }

    private static func loginItemMenuState(_ status: SMAppService.Status) -> NSControl.StateValue {
        switch status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .mixed
        case .notRegistered, .notFound:
            return .off
        @unknown default:
            return .off
        }
    }
}
