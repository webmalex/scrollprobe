import CoreGraphics
import Darwin
import Foundation

public enum TapInventoryError: LocalizedError {
    case queryFailed(CGError)

    public var errorDescription: String? {
        switch self {
        case let .queryFailed(error):
            return "CGGetEventTapList failed with CGError \(error.rawValue)."
        }
    }
}

public enum TapInventory {
    public static func snapshot() throws -> [EventTapInfo] {
        var count: UInt32 = 0
        let countResult = CGGetEventTapList(0, nil, &count)
        guard countResult == .success else {
            throw TapInventoryError.queryFailed(countResult)
        }
        guard count > 0 else {
            return []
        }

        let buffer = UnsafeMutablePointer<CGEventTapInformation>.allocate(capacity: Int(count))
        defer { buffer.deallocate() }

        var actualCount = count
        let listResult = CGGetEventTapList(count, buffer, &actualCount)
        guard listResult == .success else {
            throw TapInventoryError.queryFailed(listResult)
        }

        let resultCount: Int = numericCast(actualCount)
        return (0 ..< resultCount).map { index in
            let tap = buffer[index]
            let tappingPID = pid_t(tap.tappingProcess)
            let targetPID = pid_t(tap.processBeingTapped)
            return EventTapInfo(
                eventTapID: tap.eventTapID,
                tapPoint: tap.tapPoint.rawValue,
                options: tap.options.rawValue,
                eventsOfInterest: tap.eventsOfInterest,
                tappingProcessID: tappingPID,
                tappingProcessPath: processPath(for: tappingPID),
                processBeingTappedID: targetPID,
                processBeingTappedPath: processPath(for: targetPID),
                enabled: tap.enabled,
                minUsecLatency: tap.minUsecLatency,
                avgUsecLatency: tap.avgUsecLatency,
                maxUsecLatency: tap.maxUsecLatency
            )
        }
    }

    private static func processPath(for pid: pid_t) -> String {
        guard pid > 0 else {
            return ""
        }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else {
            return ""
        }
        return String(cString: path)
    }
}
