public import Foundation

/// One planned edit from a find-and-replace: the matched range and its replacement text.
public struct TextSearchReplacement: Equatable, Sendable {
    /// The matched range, in UTF-16 units of the searched text.
    public let range: NSRange
    /// The text that replaces the match, with any regular-expression groups expanded.
    public let replacement: String

    /// Creates a planned replacement.
    ///
    /// - Parameters:
    ///   - range: The matched range in UTF-16 units.
    ///   - replacement: The text to put in its place.
    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}
