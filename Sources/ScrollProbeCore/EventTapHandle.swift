import CoreGraphics
import Foundation

enum EventTapHandleError: LocalizedError {
    case creationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .creationFailed(name):
            return "Failed to create the \(name) event tap. Check Accessibility and Input Monitoring permissions."
        }
    }
}

final class EventTapHandle {
    typealias EventHandler = (CGEvent) -> TapDecision
    typealias DisabledHandler = (TapDisableReason) -> Void
    typealias FaultHandler = (String) -> Void

    let name: String
    let stage: TapStage

    private let context: CallbackContext
    private let tap: CFMachPort
    private let runLoop: CFRunLoop
    private let runLoopSource: CFRunLoopSource
    private var healthTimer: Timer?
    private var isInvalidated = false

    init(
        name: String,
        stage: TapStage,
        location: CGEventTapLocation,
        placement: CGEventTapPlacement,
        options: CGEventTapOptions,
        runLoop: CFRunLoop = CFRunLoopGetCurrent(),
        eventHandler: @escaping EventHandler,
        disabledHandler: @escaping DisabledHandler,
        faultHandler: @escaping FaultHandler
    ) throws {
        self.name = name
        self.stage = stage
        self.runLoop = runLoop
        context = CallbackContext(
            eventHandler: eventHandler,
            disabledHandler: disabledHandler,
            faultHandler: faultHandler
        )

        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: placement,
            options: options,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            throw EventTapHandleError.creationFailed(name)
        }
        self.tap = tap
        context.tap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw EventTapHandleError.creationFailed(name)
        }
        runLoopSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let timer = Timer(timeInterval: 5, repeats: true) { [weak context] _ in
            guard let context, let tap = context.tap else {
                return
            }
            guard CFMachPortIsValid(tap) else {
                context.faultHandler("Event tap became invalid.")
                return
            }
            if !CGEvent.tapIsEnabled(tap: tap), !context.wasDisabledByUserInput {
                context.disabledHandler(.healthCheck)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        healthTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        healthTimer?.invalidate()
        healthTimer = nil
        context.tap = nil
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        CFMachPortInvalidate(tap)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let context = Unmanaged<CallbackContext>.fromOpaque(userInfo).takeUnretainedValue()

        switch type {
        case .tapDisabledByTimeout:
            context.disabledHandler(.timeout)
            if let tap = context.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)

        case .tapDisabledByUserInput:
            context.wasDisabledByUserInput = true
            context.disabledHandler(.userInput)
            context.faultHandler("Event tap was disabled by user input.")
            return Unmanaged.passUnretained(event)

        case .scrollWheel:
            switch context.eventHandler(event) {
            case .pass:
                return Unmanaged.passUnretained(event)
            case .drop:
                return nil
            }

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private final class CallbackContext {
    let eventHandler: EventTapHandle.EventHandler
    let disabledHandler: EventTapHandle.DisabledHandler
    let faultHandler: EventTapHandle.FaultHandler
    var tap: CFMachPort?
    var wasDisabledByUserInput = false

    init(
        eventHandler: @escaping EventTapHandle.EventHandler,
        disabledHandler: @escaping EventTapHandle.DisabledHandler,
        faultHandler: @escaping EventTapHandle.FaultHandler
    ) {
        self.eventHandler = eventHandler
        self.disabledHandler = disabledHandler
        self.faultHandler = faultHandler
    }
}
