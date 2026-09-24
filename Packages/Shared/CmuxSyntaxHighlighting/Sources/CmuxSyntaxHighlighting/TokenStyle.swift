/// Resolved appearance of one highlighted run: a palette role plus font traits.
public struct TokenStyle: Sendable, Equatable, Hashable {
    /// Palette role that supplies the run's color.
    public let role: TokenRole
    /// Whether the run renders bold (doc tags, Markdown strong).
    public let isBold: Bool
    /// Whether the run renders italic (Markdown emphasis, formulas).
    public let isItalic: Bool

    /// Creates a style.
    ///
    /// - Parameters:
    ///   - role: Palette role that supplies the color.
    ///   - isBold: Bold trait. Defaults to `false`.
    ///   - isItalic: Italic trait. Defaults to `false`.
    public init(role: TokenRole, isBold: Bool = false, isItalic: Bool = false) {
        self.role = role
        self.isBold = isBold
        self.isItalic = isItalic
    }
}
