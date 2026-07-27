import Foundation

/// One note to open, and — when whatever sent the reader here knew it — the
/// line to open it at.
///
/// Every screen that navigates into the editor used to push a bare `URL`, so a
/// search hit, a task row, and a Settings diagnostic that had just printed
/// "line 42" all landed at the top of the file and left the reader to find the
/// line themselves. Carrying the line alongside the URL is what makes "open
/// the editor there" something a caller can actually ask for.
///
/// The line is part of the value's identity, so the same note at two different
/// lines is two distinct navigation values — which is what lets a second
/// diagnostic push rather than being treated as the destination already shown.
struct NoteDestination: Hashable, Sendable {
    let url: URL
    /// Zero-based, matching `TaskItem.lineNumber` and the parsers' diagnostic
    /// line numbers. Nil opens the note at the top.
    var line: Int?

    init(_ url: URL, line: Int? = nil) {
        self.url = url
        self.line = line
    }
}
