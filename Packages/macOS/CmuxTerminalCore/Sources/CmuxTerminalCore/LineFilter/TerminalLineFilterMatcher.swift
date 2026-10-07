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
        guard !needle.isEmpty, !text.isEmpty else { return [] }
        var lines: [TerminalLineFilterLine] = []
        var lineIndex = 0
        for piece in text.split(separator: "\n", omittingEmptySubsequences: false) {
            defer { lineIndex += 1 }
            guard let firstMatch = piece.range(of: needle, options: .caseInsensitive) else { continue }
            let lineText = clipped(piece, around: firstMatch)
            let matchRanges = matchRanges(in: lineText)
            guard !matchRanges.isEmpty else { continue }
            lines.append(TerminalLineFilterLine(
                chunkRows: chunkRows,
                lineIndex: lineIndex,
                text: lineText,
                matchRanges: matchRanges
            ))
        }
        return lines
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
        guard !text.isEmpty else { return 0 }
        return text.utf8.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
    }

    /// `line` as a string, cut to a window around `firstMatch` when it is
    /// longer than ``maximumLineLength``.
    private func clipped(_ line: Substring, around firstMatch: Range<Substring.Index>) -> String {
        // The UTF-8 length is cheap and never smaller than the character count.
        guard line.utf8.count > maximumLineLength, line.count > maximumLineLength else {
            return String(line)
        }
        let lead = maximumLineLength / 4
        let start = line.index(firstMatch.lowerBound, offsetBy: -lead, limitedBy: line.startIndex)
            ?? line.startIndex
        let end = line.index(start, offsetBy: maximumLineLength, limitedBy: line.endIndex)
            ?? line.endIndex
        return String(line[start..<max(end, firstMatch.upperBound)])
    }

    private func matchRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                  of: needle,
                  options: .caseInsensitive,
                  range: searchStart..<text.endIndex
              ),
              !range.isEmpty {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}
