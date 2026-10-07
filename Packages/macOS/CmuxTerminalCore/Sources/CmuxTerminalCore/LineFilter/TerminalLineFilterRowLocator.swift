/// Resolves the physical row a filtered line starts on.
///
/// A chunk's text joins soft-wrapped rows, so a line's index in the text is not
/// its row offset. The number of lines in a prefix of the chunk never
/// decreases as the prefix grows, which makes the start row a binary search
/// over prefix reads.
struct TerminalLineFilterRowLocator {
    /// Counts the logical lines in a chunk of terminal text.
    let matcher: TerminalLineFilterMatcher

    /// The absolute row `line` starts on, or nil when its chunk cannot be read.
    ///
    /// - Parameters:
    ///   - line: The line to locate.
    ///   - text: Reads the plain text of an inclusive range of absolute rows.
    func startRow(
        of line: TerminalLineFilterLine,
        text: (ClosedRange<UInt64>) -> String?
    ) -> UInt64? {
        nil
    }
}
