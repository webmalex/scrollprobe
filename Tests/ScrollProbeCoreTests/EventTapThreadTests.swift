@testable import ScrollProbeCore
import XCTest

final class EventTapThreadTests: XCTestCase {
    func testPerformsWorkAndRejectsCommandsAfterStop() throws {
        let eventThread = EventTapThread()
        let caller = Thread.current

        eventThread.start()
        let ranOnWorker = try eventThread.performSync {
            Thread.current !== caller
        }
        eventThread.stop()

        XCTAssertTrue(ranOnWorker)
        XCTAssertThrowsError(try eventThread.performSync { true }) { error in
            XCTAssertEqual(error as? EventTapThreadError, .notRunning)
        }
    }
}
