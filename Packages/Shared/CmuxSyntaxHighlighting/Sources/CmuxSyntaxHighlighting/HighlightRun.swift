/// A styled range of a source buffer, in UTF-16 code units.
///
/// Text not covered by any run renders with the palette foreground.
public struct HighlightRun: Sendable, Equatable {
    /// Start offset in UTF-16 code units (`NSString` indexing).
    public let location: Int
    /// Length in UTF-16 code units. Always greater than zero.
    public let length: Int
    /// Appearance of the range.
    public let style: TokenStyle

    /// Creates a run.
    ///
    /// - Parameters:
    ///   - location: Start offset in UTF-16 code units.
    ///   - length: Length in UTF-16 code units.
    ///   - style: Appearance of the range.
    public init(location: Int, length: Int, style: TokenStyle) {
        self.location = location
        self.length = length
        self.style = style
    }

    /// One past the last UTF-16 offset covered by the run.
    public var end: Int { location + length }
}
