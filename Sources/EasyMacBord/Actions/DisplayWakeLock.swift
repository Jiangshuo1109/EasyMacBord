import Foundation
import IOKit.pwr_mgt

final class DisplayWakeLock {
    private var assertionID: IOPMAssertionID?

    var isActive: Bool {
        assertionID != nil
    }

    func toggle() -> Bool {
        isActive ? release() : acquire()
    }

    @discardableResult
    private func acquire() -> Bool {
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "EasyMacBord 保持亮屏" as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = identifier
        return true
    }

    @discardableResult
    private func release() -> Bool {
        guard let assertionID else { return true }
        let result = IOPMAssertionRelease(assertionID)
        guard result == kIOReturnSuccess else { return false }
        self.assertionID = nil
        return true
    }

    deinit {
        _ = release()
    }
}
