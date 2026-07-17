import Foundation

public enum RunLoggerError: LocalizedError {
    case cannotCreateLogFile(URL)

    public var errorDescription: String? {
        switch self {
        case let .cannotCreateLogFile(url):
            return "Cannot create log file at \(url.path)."
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
    private var isClosed = false

    public init(runID: UUID, directory: URL = RunLogger.defaultLogDirectory) throws {
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
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        close()
    }

    public func write(_ record: ProbeLogRecord) {
        queue.async { [weak self] in
            guard let self, !self.isClosed else {
                return
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard var data = try? encoder.encode(record) else {
                return
            }
            data.append(0x0A)
            try? self.fileHandle.write(contentsOf: data)
        }
    }

    public func close() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeOnQueue()
        } else {
            queue.sync {
                closeOnQueue()
            }
        }
    }

    private func closeOnQueue() {
        guard !isClosed else {
            return
        }
        isClosed = true
        try? fileHandle.synchronize()
        try? fileHandle.close()
    }
}
