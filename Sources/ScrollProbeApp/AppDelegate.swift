import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var instanceLock: ApplicationInstanceLock?

    func applicationDidFinishLaunching(_: Notification) {
        guard let instanceLock = ApplicationInstanceLock.acquire() else {
            Self.existingApplication?.activate(options: [.activateAllWindows])
            NSApplication.shared.terminate(nil)
            return
        }
        self.instanceLock = instanceLock

        // Pre-lock builds still need the process-list fallback during upgrade.
        if let existingApplication = Self.existingLegacyApplication {
            existingApplication.activate(options: [.activateAllWindows])
            NSApplication.shared.terminate(nil)
            return
        }

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start(launchedAsLoginItem: Self.launchedAsLoginItem)
    }

    func applicationWillTerminate(_: Notification) {
        coordinator?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        coordinator?.showDiagnostics()
        return true
    }

    private static var existingApplication: NSRunningApplication? {
        runningApplications.first
    }

    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.eventID == kAEOpenApplication &&
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private static var existingLegacyApplication: NSRunningApplication? {
        let currentBuild = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        ) ?? 0
        return runningApplications.first { application in
            guard let bundleURL = application.bundleURL,
                  let bundle = Bundle(url: bundleURL),
                  let build = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") else {
                return false
            }
            return build < currentBuild
        }
    }

    private static var runningApplications: [NSRunningApplication] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return []
        }
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessID && !$0.isTerminated }
    }
}

private final class ApplicationInstanceLock {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    static func acquire() -> ApplicationInstanceLock? {
        guard let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let lockDirectory = cachesDirectory.appendingPathComponent(
            "io.github.webmalex.ScrollProbe",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: lockDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }

        let path = lockDirectory.appendingPathComponent("instance.lock").path
        let fileDescriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            return nil
        }
        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            return nil
        }
        return ApplicationInstanceLock(fileDescriptor: fileDescriptor)
    }
}
