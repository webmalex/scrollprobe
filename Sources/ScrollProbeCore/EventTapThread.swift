import Foundation

public enum EventTapThreadError: LocalizedError, Equatable {
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "The event tap thread is not running."
        }
    }
}

public final class EventTapThread {
    private let stateLock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private var worker: Thread?
    private var runLoop: CFRunLoop?
    private var didStart = false
    private var didStop = false
    private var stopRequested = false

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        stateLock.lock()
        guard !didStart else {
            stateLock.unlock()
            return
        }
        didStart = true
        let worker = Thread { [weak self] in
            self?.threadMain()
        }
        worker.name = "io.github.webmalex.scrollprobe.event-tap"
        worker.qualityOfService = .userInteractive
        self.worker = worker
        stateLock.unlock()

        worker.start()
        ready.wait()
    }

    public func performSync<T>(_ block: @escaping () throws -> T) throws -> T {
        stateLock.lock()
        guard !didStop, let worker, let runLoop else {
            stateLock.unlock()
            throw EventTapThreadError.notRunning
        }
        if Thread.current === worker {
            stateLock.unlock()
            return try block()
        }

        let resultBox = ThreadResultBox<T>()
        let completed = DispatchSemaphore(value: 0)
        // Queue while holding the lifecycle lock so stop cannot overtake this block.
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            resultBox.result = Result { try block() }
            completed.signal()
        }
        stateLock.unlock()
        CFRunLoopWakeUp(runLoop)
        completed.wait()

        guard let result = resultBox.result else {
            throw EventTapThreadError.notRunning
        }
        return try result.get()
    }

    public func stop() {
        stateLock.lock()
        guard didStart, !didStop else {
            stateLock.unlock()
            return
        }
        didStop = true
        stopRequested = true
        let worker = worker
        let runLoop = runLoop
        stateLock.unlock()

        guard let worker else {
            return
        }

        if Thread.current === worker {
            if let runLoop {
                CFRunLoopStop(runLoop)
            }
            return
        }

        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }
        finished.wait()
    }

    private func threadMain() {
        autoreleasepool {
            let keepAlivePort = Port()
            RunLoop.current.add(keepAlivePort, forMode: .common)
            let currentRunLoop = CFRunLoopGetCurrent()

            stateLock.lock()
            runLoop = currentRunLoop
            let shouldStop = stopRequested
            stateLock.unlock()
            ready.signal()

            if !shouldStop {
                CFRunLoopRun()
            }

            stateLock.lock()
            runLoop = nil
            worker = nil
            stateLock.unlock()
            withExtendedLifetime(keepAlivePort) {}
            finished.signal()
        }
    }
}

private final class ThreadResultBox<Value> {
    var result: Result<Value, Error>?
}
