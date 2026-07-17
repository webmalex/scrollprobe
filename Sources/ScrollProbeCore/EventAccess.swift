import ApplicationServices
import CoreGraphics
import Foundation

public enum EventAccess {
    public static var accessibilityEnabled: Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false,
        ] as CFDictionary)
    }

    @discardableResult
    public static func requestAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true,
        ] as CFDictionary)
    }

    public static var listenEnabled: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    public static func requestListenAccess() -> Bool {
        CGRequestListenEventAccess()
    }
}
