/// Bounds that keep a find-filter scan cheap on a large scrollback.
public struct TerminalLineFilterLimits: Equatable, Sendable {
    /// The most matching lines kept; older ones are dropped first.
    public var maximumLines: Int
    /// The most rows read in one chunk.
    public var maximumRowsPerChunk: Int
    /// The most cells read in one chunk, which bounds a single read's work.
    public var maximumCellsPerChunk: Int
    /// The longest line text kept; longer lines are clipped around their first match.
    public var maximumLineLength: Int

    /// Creates scan limits.
    ///
    /// - Parameters:
    ///   - maximumLines: The most matching lines kept.
    ///   - maximumRowsPerChunk: The most rows read in one chunk.
    ///   - maximumCellsPerChunk: The most cells read in one chunk.
    ///   - maximumLineLength: The longest line text kept.
    public init(
        maximumLines: Int = 5_000,
        maximumRowsPerChunk: Int = 1_000,
        maximumCellsPerChunk: Int = 200_000,
        maximumLineLength: Int = 4_000
    ) {
        self.maximumLines = maximumLines
        self.maximumRowsPerChunk = maximumRowsPerChunk
        self.maximumCellsPerChunk = maximumCellsPerChunk
        self.maximumLineLength = maximumLineLength
    }

    /// The rows read per chunk for a grid `columns` cells wide.
    func rowsPerChunk(columns: Int) -> UInt64 {
        let byCells = maximumCellsPerChunk / max(columns, 1)
        return UInt64(max(1, min(maximumRowsPerChunk, byCells)))
    }
}
