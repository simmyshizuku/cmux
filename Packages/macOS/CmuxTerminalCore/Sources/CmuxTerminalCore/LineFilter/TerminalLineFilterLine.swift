/// One terminal line that matched the find filter.
///
/// A line is a logical line: soft-wrapped rows are already joined. Its position
/// is recorded as the row chunk it was read from plus its index inside that
/// chunk, because the text alone does not say which physical row it starts on.
public struct TerminalLineFilterLine: Identifiable, Equatable, Sendable {
    /// Identity that stays stable while the row space is unchanged.
    public struct ID: Hashable, Sendable {
        /// The first absolute screen row of the chunk the line was read from.
        public let chunkTop: UInt64
        /// The line's zero-based index inside that chunk's text.
        public let lineIndex: Int
    }

    /// The line's stable identity.
    public let id: ID
    /// The line text, clipped around the first match when the line is very long.
    public let text: String
    /// The matches inside ``text``, in order and never overlapping.
    public let matchRanges: [Range<String.Index>]
    /// The inclusive absolute screen rows of the chunk the line was read from.
    public let chunkRows: ClosedRange<UInt64>

    /// The line's zero-based index inside its chunk's text.
    public var lineIndex: Int { id.lineIndex }

    /// Creates a matched line.
    ///
    /// - Parameters:
    ///   - chunkRows: The inclusive absolute screen rows the chunk covers.
    ///   - lineIndex: The line's zero-based index inside the chunk's text.
    ///   - text: The line text.
    ///   - matchRanges: The matches inside `text`.
    public init(
        chunkRows: ClosedRange<UInt64>,
        lineIndex: Int,
        text: String,
        matchRanges: [Range<String.Index>]
    ) {
        self.id = ID(chunkTop: chunkRows.lowerBound, lineIndex: lineIndex)
        self.text = text
        self.matchRanges = matchRanges
        self.chunkRows = chunkRows
    }
}
