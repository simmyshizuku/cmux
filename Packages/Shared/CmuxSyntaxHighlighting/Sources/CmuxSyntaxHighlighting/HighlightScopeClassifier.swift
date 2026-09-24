/// Maps a highlight.js span `class` attribute to a ``TokenStyle``.
///
/// highlight.js 11 emits one span per scope, e.g. `hljs-type`, and encodes
/// sub-scopes as extra classes with one trailing underscore per depth:
/// `title.function` becomes `hljs-title function_` and
/// `title.class.inherited` becomes `hljs-title class_ inherited__`. Each
/// scope is classified directly, so no CSS theme sits between the tokenizer
/// and the palette.
///
/// ```swift
/// let classifier = HighlightScopeClassifier()
/// classifier.style(forClassAttribute: "hljs-title function_") // .function
/// ```
public struct HighlightScopeClassifier: Sendable {
    /// Creates a classifier with the built-in scope table.
    public init() {}

    /// Returns the style for a span's `class` attribute.
    ///
    /// Older grammars such as Dart wrap a declaration in a `hljs-class` or
    /// `hljs-function` container holding a bare `hljs-title`; the container
    /// decides whether that title names a type or a function.
    ///
    /// - Parameters:
    ///   - classAttribute: The raw attribute value, e.g. `hljs-title function_`.
    ///   - insideClassDeclaration: Whether the span's direct parent is a
    ///     `hljs-class` container. Defaults to `false`.
    /// - Returns: The scope's style, or `nil` for an unknown scope, which
    ///   callers treat as inheriting the enclosing span's style.
    public func style(
        forClassAttribute classAttribute: String,
        insideClassDeclaration: Bool = false
    ) -> TokenStyle? {
        var components = classAttribute.split(separator: " ").makeIterator()
        guard let first = components.next(), first.hasPrefix("hljs-") else { return nil }
        let scope = first.dropFirst("hljs-".count)
        let subScope = components.next().map { component -> Substring in
            var trimmed = component
            while trimmed.last == "_" {
                trimmed = trimmed.dropLast()
            }
            return trimmed
        }

        switch scope {
        case "title":
            // A bare `title` is a function name unless a class container holds it.
            let namesType = subScope == "class" || (subScope == nil && insideClassDeclaration)
            return TokenStyle(role: namesType ? .type : .function)
        case "variable":
            // `this`, `self`, `console` render like keywords, as in Xcode.
            return TokenStyle(role: subScope == "language" ? .keyword : .variable)
        case "keyword", "literal", "section", "tag", "name", "selector-tag", "attribute":
            return TokenStyle(role: .keyword)
        case "type", "built_in", "builtin-name":
            return TokenStyle(role: .type)
        case "string", "code", "char":
            return TokenStyle(role: .string)
        case "number", "symbol", "bullet":
            return TokenStyle(role: .number)
        case "comment", "quote":
            return TokenStyle(role: .comment)
        case "doctag":
            return TokenStyle(role: .comment, isBold: true)
        case "meta", "attr", "selector-id", "selector-class", "selector-attr", "selector-pseudo":
            return TokenStyle(role: .attribute)
        case "template-variable", "template-tag":
            return TokenStyle(role: .variable)
        case "regexp", "link":
            return TokenStyle(role: .regexp)
        case "property":
            return TokenStyle(role: .property)
        case "strong":
            return TokenStyle(role: .foreground, isBold: true)
        case "emphasis", "formula":
            return TokenStyle(role: .foreground, isItalic: true)
        case "params", "subst", "operator", "punctuation", "class", "function":
            // Containers and punctuation reset to plain text. Nested scopes
            // (a type inside `params`, an expression inside `subst`) still win.
            return TokenStyle(role: .foreground)
        default:
            return nil
        }
    }
}
