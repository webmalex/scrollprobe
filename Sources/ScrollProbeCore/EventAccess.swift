import ApplicationServices
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
}
