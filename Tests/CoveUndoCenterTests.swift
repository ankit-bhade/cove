import XCTest

@testable import Cove

/// The bar is the only route to Undo on a phone, so "it was registered" and
/// "it can be reached" are two different claims and both have to hold.
///
/// This exists because they came apart: four destructive actions registered
/// their reversal with `UndoManager` alone, which SwiftUI leaves nil on iOS
/// outside a `DocumentGroup`. Every one of them was covered by tests that
/// checked the *reversal* — `restoreDeletedList` and friends all work — and
/// none that checked anything could invoke it. The dialogs said "you can undo
/// the deletion" over changes a phone could not take back.
@MainActor
final class CoveUndoCenterTests: XCTestCase {

    private final class Target {}

    func testAnnouncingRaisesANoticeCarryingTheMessage() {
        let center = CoveUndoCenter()
        XCTAssertNil(center.notice)

        center.announce("List deleted.") {}

        XCTAssertEqual(center.notice?.message, "List deleted.")
    }

    func testDismissingClearsTheNotice() {
        let center = CoveUndoCenter()
        center.announce("List deleted.") {}

        center.dismiss()

        XCTAssertNil(center.notice)
    }

    /// A second action replaces the first rather than queueing behind it —
    /// the bar shows one thing, and it is the most recent.
    func testASecondNoticeReplacesTheFirst() {
        let center = CoveUndoCenter()
        center.announce("Task deleted.") {}
        center.announce("List deleted.") {}

        XCTAssertEqual(center.notice?.message, "List deleted.")
    }

    // MARK: - Registration

    /// The case that matters on iPhone: no undo manager, so the notice has to
    /// carry the reversal itself. Registering only with the manager is exactly
    /// the bug this guards.
    func testWithoutAnUndoManagerTheNoticeInvokesTheReversal() {
        let center = CoveUndoCenter()
        let target = Target()
        var reversed = false

        center.register(
            named: "Delete List",
            announcing: "List deleted.",
            withTarget: target,
            undoManager: nil
        ) { reversed = true }

        XCTAssertEqual(center.notice?.message, "List deleted.")
        XCTAssertFalse(reversed)

        center.notice?.undo()

        XCTAssertTrue(reversed, "The bar is the only route to Undo on iOS.")
    }

    /// A Mac has a real manager, so the bar goes through it rather than
    /// reversing directly — otherwise the Edit menu and the bar would each
    /// undo once and the change would be reversed twice.
    func testWithAnUndoManagerTheNoticeDrivesTheManager() {
        let center = CoveUndoCenter()
        let target = Target()
        let undoManager = manualUndoManager()
        var reversalCount = 0

        undoManager.beginUndoGrouping()
        center.register(
            named: "Delete List",
            announcing: "List deleted.",
            withTarget: target,
            undoManager: undoManager
        ) { reversalCount += 1 }
        undoManager.endUndoGrouping()

        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Delete List")

        center.notice?.undo()

        XCTAssertEqual(reversalCount, 1, "Undone once, not once per route.")
        XCTAssertFalse(undoManager.canUndo)
    }

    /// Registering always does both halves, so a caller cannot express the
    /// manager-only form that left the bar empty.
    func testRegisteringAlwaysDoesBothHalves() {
        let center = CoveUndoCenter()
        let target = Target()
        let undoManager = manualUndoManager()

        undoManager.beginUndoGrouping()
        center.register(
            named: "Delete Subscription",
            announcing: "Subscription deleted.",
            withTarget: target,
            undoManager: undoManager
        ) {}
        undoManager.endUndoGrouping()

        XCTAssertNotNil(center.notice, "The bar half.")
        XCTAssertTrue(undoManager.canUndo, "The manager half.")
    }

    /// A manager the test drives itself rather than one that groups off the
    /// run loop, so registration and undo are ordered rather than whenever the
    /// event ends. `groupsByEvent = false` means a group has to be opened by
    /// hand — without one, `registerUndo` throws "must begin a group before
    /// registering undo" rather than recording anything.
    private func manualUndoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }
}
