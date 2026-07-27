import XCTest

@testable import Cove

/// What the Vault Safety row is allowed to say.
///
/// The state matters more than it looks: "Ready" is what the row said while
/// recovered drafts sat unreviewed in Application Support, and alert red is
/// what it would have said if recovery were folded in with the faults. Both
/// readings are wrong in opposite directions, which is why there are three
/// states and why the boundaries are pinned here.
final class CoveStorageHealthTests: XCTestCase {

    private func health(
        lastIssue: String? = nil,
        unavailableNotes: Int = 0,
        taskDiagnostics: Int = 0,
        subscriptionDiagnostics: Int = 0,
        conflicts: [URL] = [],
        conflictCopies: [URL] = [],
        bookmarkIsPersisted: Bool = true,
        recoveryItems: Int = 0,
        recoveryDrafts: Int = 0
    ) -> CoveStorageHealth {
        CoveStorageHealth(
            lastIssue: lastIssue,
            unavailableNoteCount: unavailableNotes,
            taskDiagnosticCount: taskDiagnostics,
            subscriptionDiagnosticCount: subscriptionDiagnostics,
            unresolvedConflictURLs: conflicts,
            conflictReviewURLs: conflictCopies,
            bookmarkIsPersisted: bookmarkIsPersisted,
            accessState: .securityScoped,
            recoveryItemCount: recoveryItems,
            recoveryDraftCount: recoveryDrafts)
    }

    func testHealthyVaultIsReady() {
        XCTAssertEqual(health().attention, .ready)
    }

    /// A draft is a crash-recovered buffer: the note it belongs to is not
    /// being written until it is accepted or discarded, so "Ready" is a lie.
    func testARecoveredDraftRaisesTheRecoveryState() {
        XCTAssertEqual(health(recoveryDrafts: 1).attention, .recovery)
    }

    /// The deliberate exclusion. Deleted items live in the recovery area for a
    /// week by design, so counting them would leave any vault where something
    /// was recently deleted permanently out of `ready` — a signal that is
    /// always on is not a signal.
    func testDeletedItemsAloneDoNotRaiseAnything() {
        XCTAssertEqual(health(recoveryItems: 12).attention, .ready)
    }

    /// Recovery is not a fault, so a real fault outranks it — one banner, and
    /// it should be the one that says something is wrong.
    func testAFaultOutranksRecovery() {
        XCTAssertEqual(
            health(taskDiagnostics: 2, recoveryDrafts: 3).attention,
            .needsAttention)
    }

    func testEveryFaultRaisesAttention() {
        XCTAssertEqual(health(lastIssue: "Something failed").attention, .needsAttention)
        XCTAssertEqual(health(unavailableNotes: 1).attention, .needsAttention)
        XCTAssertEqual(health(taskDiagnostics: 1).attention, .needsAttention)
        XCTAssertEqual(health(subscriptionDiagnostics: 1).attention, .needsAttention)
        XCTAssertEqual(
            health(conflicts: [URL(fileURLWithPath: "/vault/A.md")]).attention,
            .needsAttention)
        XCTAssertEqual(
            health(conflictCopies: [URL(fileURLWithPath: "/vault/B.md")]).attention,
            .needsAttention)
        XCTAssertEqual(health(bookmarkIsPersisted: false).attention, .needsAttention)
    }
}
