import Foundation

/// Finds the lines of a chunk of terminal text that contain a needle.
///
/// Matching is plain text and case-insensitive, the same as terminal find.
struct TerminalLineFilterMatcher: Sendable {
    /// The text to look for. An empty needle matches nothing.
    let needle: String
    /// The longest line text kept; longer lines are clipped around their first match.
    let maximumLineLength: Int

    /// The matching lines of `text`, in order.
    ///
    /// - Parameters:
    ///   - text: A chunk of terminal text, one logical line per `\n`.
    ///   - chunkRows: The inclusive absolute screen rows `text` was read from.
    func matchingLines(in text: String, chunkRows: ClosedRange<UInt64>) -> [TerminalLineFilterLine] {
        []
    }

    /// Runs ``matchingLines(in:chunkRows:)`` off the caller's actor, so a scan
    /// never matches a megabyte of text on the main thread.
    func matchingLinesInBackground(
        in text: String,
        chunkRows: ClosedRange<UInt64>
    ) async -> [TerminalLineFilterLine] {
        matchingLines(in: text, chunkRows: chunkRows)
    }

    /// The number of logical lines in a chunk of terminal text.
    func lineCount(in text: String) -> Int {
        0
    }
}
