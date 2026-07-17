import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
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
}
