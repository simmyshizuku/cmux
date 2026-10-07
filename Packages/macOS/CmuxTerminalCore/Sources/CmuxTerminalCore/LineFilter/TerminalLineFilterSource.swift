/// The terminal a ``TerminalLineFilterModel`` reads from and scrolls.
///
/// The app conforms a live Ghostty surface; tests conform an in-memory grid.
@MainActor
public protocol TerminalLineFilterSource: AnyObject {
    /// The current scrollback geometry, or nil when the terminal is gone.
    func rowSpace() -> TerminalLineFilterRowSpace?

    /// The plain text of an inclusive range of absolute screen rows.
    ///
    /// Soft-wrapped rows are joined without a newline, blank rows before the
    /// last non-blank row are kept as empty lines, and trailing blank rows are
    /// dropped. Returns nil when the rows cannot be read.
    func text(rows: ClosedRange<UInt64>) -> String?

    /// Scrolls so `row` is the top visible row, if `revision` still identifies
    /// the row space.
    ///
    /// - Returns: Whether the terminal scrolled.
    func scroll(toRow row: UInt64, revision: UInt64) -> Bool
}
