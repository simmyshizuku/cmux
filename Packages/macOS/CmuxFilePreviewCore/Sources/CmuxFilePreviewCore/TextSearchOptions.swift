/// The match-case, whole-word, and regular-expression toggles of a text search.
///
/// Find in the File Preview editor and Find in Directory share these three
/// switches, matching the `Aa`, `ab`, and `.*` toggles in VS Code's find
/// widget. The default, all off, is a case-insensitive literal search.
public struct TextSearchOptions: Equatable, Hashable, Sendable {
    /// Whether letter case must match exactly. Off means case-insensitive.
    public var matchCase: Bool
    /// Whether a match must not touch a letter, digit, or underscore on either side.
    public var matchWholeWord: Bool
    /// Whether the query is a regular expression rather than literal text.
    public var useRegularExpression: Bool

    /// Creates search options.
    ///
    /// - Parameters:
    ///   - matchCase: Match letter case exactly. Defaults to `false`.
    ///   - matchWholeWord: Only match whole words. Defaults to `false`.
    ///   - useRegularExpression: Treat the query as a regular expression. Defaults to `false`.
    public init(
        matchCase: Bool = false,
        matchWholeWord: Bool = false,
        useRegularExpression: Bool = false
    ) {
        self.matchCase = matchCase
        self.matchWholeWord = matchWholeWord
        self.useRegularExpression = useRegularExpression
    }
}
