/// The geometry of a terminal's scrollback at one instant.
public struct TerminalLineFilterRowSpace: Equatable, Sendable {
    /// The total number of rows, scrollback plus the active screen.
    public let totalRows: UInt64
    /// The height of the active screen, in rows.
    public let viewportRows: UInt64
    /// The grid width, in cells.
    public let columns: Int
    /// Changes whenever absolute row numbers stop meaning what they did:
    /// scrollback was pruned, erased or reflowed.
    public let revision: UInt64

    /// Creates a row-space snapshot.
    ///
    /// - Parameters:
    ///   - totalRows: The total number of rows, scrollback plus the active screen.
    ///   - viewportRows: The height of the active screen, in rows.
    ///   - columns: The grid width, in cells.
    ///   - revision: The identity of the absolute row numbering.
    public init(totalRows: UInt64, viewportRows: UInt64, columns: Int, revision: UInt64) {
        self.totalRows = totalRows
        self.viewportRows = viewportRows
        self.columns = columns
        self.revision = revision
    }

    /// The first row of the active screen; rows above it are immutable history.
    var activeTop: UInt64 {
        totalRows - min(viewportRows, totalRows)
    }
}
