/// Semantic highlight.js token role used to paint a ``TokenPalette``.
public enum TokenRole: Sendable, Equatable, Hashable {
    /// Default / unsubstituted text.
    case foreground
    /// Comments and quotes.
    case comment
    /// Keywords, tags, literals (`true`, `func`, JSX tags).
    case keyword
    /// Types, class names, builtins.
    case type
    /// String literals.
    case string
    /// Numbers, symbols, and list bullets.
    case number
    /// Function and method names, at declarations and call sites.
    case function
    /// Member accesses such as `.count` or `.preferredTransform`.
    case property
    /// Attributes, JSON keys, selectors.
    case attribute
    /// Variables and template variables.
    case variable
    /// Regular expressions and links.
    case regexp
}
