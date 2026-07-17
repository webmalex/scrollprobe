import CoreGraphics
import Darwin
import Foundation

public enum TapInventoryError: LocalizedError {
    case queryFailed(CGError)
    case listChangedDuringQuery

    public var errorDescription: String? {
        switch self {
        case let .queryFailed(error):
            return "CGGetEventTapList failed with CGError \(error.rawValue)."
        case .listChangedDuringQuery:
            return "The event tap list changed repeatedly while it was being captured."
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

        var capacity = count
        for _ in 0 ..< 3 {
            let buffer = UnsafeMutablePointer<CGEventTapInformation>.allocate(capacity: numericCast(capacity))
            defer { buffer.deallocate() }

            var actualCount = capacity
            let listResult = CGGetEventTapList(capacity, buffer, &actualCount)
            guard listResult == .success else {
                throw TapInventoryError.queryFailed(listResult)
            }
            guard actualCount <= capacity else {
                capacity = actualCount
                continue
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
        throw TapInventoryError.listChangedDuringQuery
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
