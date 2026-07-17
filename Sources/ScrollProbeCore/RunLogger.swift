import Foundation

public enum RunLoggerError: LocalizedError {
    case cannotCreateLogFile(URL)
    case writeFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case let .cannotCreateLogFile(url):
            return "Cannot create log file at \(url.path)."
        case let .writeFailed(url, message):
            return "Cannot write log file at \(url.path): \(message)"
        }
    }
}

public final class RunLogger {
    public static var defaultLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ScrollProbe", isDirectory: true)
    }

    public let fileURL: URL

    private let queue = DispatchQueue(label: "dev.scrollprobe.log-writer", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private let fileHandle: FileHandle
    private let errorHandler: (Error) -> Void
    private var isClosed = false
    private var didReportWriteFailure = false
    private var firstWriteFailure: Error?

    public init(
        runID: UUID,
        directory: URL = RunLogger.defaultLogDirectory,
        errorHandler: @escaping (Error) -> Void = { _ in }
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let fileName = "scrollprobe-\(formatter.string(from: Date()))-\(runID.uuidString).jsonl"
        fileURL = directory.appendingPathComponent(fileName)

        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: fileURL) else {
            throw RunLoggerError.cannotCreateLogFile(fileURL)
        }
        fileHandle = handle
        self.errorHandler = errorHandler
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        try? close()
    }

    public func write(_ record: ProbeLogRecord) {
        queue.async { [weak self] in
            guard let self, !self.isClosed else {
                return
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            var data: Data
            do {
                data = try encoder.encode(record)
            } catch {
                self.reportWriteFailure(error)
                return
            }
            data.append(0x0A)
            do {
                try self.fileHandle.write(contentsOf: data)
            } catch {
                self.reportWriteFailure(error)
            }
        }
    }

    public func close() throws {
        let error: Error?
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeOnQueue()
            error = firstWriteFailure
        } else {
            error = queue.sync {
                closeOnQueue()
                return firstWriteFailure
            }
        }
        if let error {
            throw error
        }
    }

    private func closeOnQueue() {
        guard !isClosed else {
            return
        }
        isClosed = true
        do {
            try fileHandle.synchronize()
        } catch {
            reportWriteFailure(error)
        }
        do {
            try fileHandle.close()
        } catch {
            reportWriteFailure(error)
        }
    }

    private func reportWriteFailure(_ error: Error) {
        let failure = RunLoggerError.writeFailed(fileURL, error.localizedDescription)
        if firstWriteFailure == nil {
            firstWriteFailure = failure
        }
        guard !didReportWriteFailure else {
            return
        }
        didReportWriteFailure = true
        errorHandler(failure)
    }
}
