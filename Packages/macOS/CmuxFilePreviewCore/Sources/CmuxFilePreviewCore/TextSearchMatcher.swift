public import Foundation

/// Finds and replaces a query in text under a set of ``TextSearchOptions``.
///
/// Literal queries are escaped, so only a regular-expression query can fail
/// to compile. Whole-word matching refuses a match that touches a letter,
/// digit, or underscore on either side, which also works for queries that
/// start or end with punctuation (`-flag`, `foo(`). Regular expressions use
/// ICU syntax with `^` and `$` anchoring at line breaks, and replacement
/// templates accept `$0`–`$9`, `$&`, `\n`, and `\t`, as VS Code does.
///
/// ```swift
/// let matcher = try TextSearchMatcher(query: "foo", options: TextSearchOptions(matchWholeWord: true))
/// let ranges = matcher.matches(in: "foo food foo")   // [{0, 3}, {9, 3}]
/// ```
public struct TextSearchMatcher {
    /// Why a query could not be turned into a matcher.
    public enum Failure: Error, Equatable {
        /// The regular expression does not compile.
        case invalidRegularExpression
    }

    /// The query as the user typed it.
    public let query: String
    /// The options the query was compiled with.
    public let options: TextSearchOptions
    private let expression: NSRegularExpression

    /// Compiles a query.
    ///
    /// - Parameters:
    ///   - query: The search text or pattern; must not be empty.
    ///   - options: Case, whole-word, and regular-expression switches.
    /// - Throws: ``Failure/invalidRegularExpression`` when a regular-expression query does not compile.
    /// - Returns: `nil` for an empty query.
    public init?(query: String, options: TextSearchOptions) throws {
        guard !query.isEmpty else { return nil }
        var pattern = options.useRegularExpression
            ? query
            : NSRegularExpression.escapedPattern(for: query)
        if options.matchWholeWord {
            pattern = "(?<![\\p{L}\\p{N}_])(?:\(pattern))(?![\\p{L}\\p{N}_])"
        }
        var expressionOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.matchCase {
            expressionOptions.insert(.caseInsensitive)
        }
        do {
            expression = try NSRegularExpression(pattern: pattern, options: expressionOptions)
        } catch {
            throw Failure.invalidRegularExpression
        }
        self.query = query
        self.options = options
    }

    /// Returns every non-empty match, in order.
    ///
    /// - Parameters:
    ///   - text: The text to search.
    ///   - limit: Stops after this many matches; `nil` finds them all.
    /// - Returns: Match ranges in UTF-16 units of `text`.
    public func matches(in text: String, limit: Int? = nil) -> [NSRange] {
        var ranges: [NSRange] = []
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        expression.enumerateMatches(in: text, range: fullRange) { result, _, stop in
            guard let range = result?.range, range.length > 0 else { return }
            ranges.append(range)
            if let limit, ranges.count >= limit {
                stop.pointee = true
            }
        }
        return ranges
    }

    /// Returns the replacement text for the match at `range`.
    ///
    /// A literal query returns `template` unchanged. A regular expression
    /// re-matches `range`, with the surrounding text visible to lookaround,
    /// and expands groups in `template`.
    ///
    /// - Parameters:
    ///   - range: A range previously returned by ``matches(in:limit:)`` for `text`.
    ///   - text: The searched text.
    ///   - template: The replace-field text.
    /// - Returns: The text to insert, or `nil` when `range` no longer matches.
    public func replacement(forMatchAt range: NSRange, in text: String, template: String) -> String? {
        let bounds: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]
        guard let result = expression.firstMatch(in: text, options: bounds, range: range),
              result.range == range else {
            return nil
        }
        guard options.useRegularExpression else { return template }
        return expression.replacementString(
            for: result,
            in: text,
            offset: 0,
            template: Self.expressionTemplate(from: template)
        )
    }

    /// Plans a replace-all: every match paired with its replacement text, in order.
    ///
    /// - Parameters:
    ///   - text: The searched text.
    ///   - template: The replace-field text.
    /// - Returns: One ``TextSearchReplacement`` per match.
    public func replacements(in text: String, template: String) -> [TextSearchReplacement] {
        matches(in: text).compactMap { range in
            replacement(forMatchAt: range, in: text, template: template).map {
                TextSearchReplacement(range: range, replacement: $0)
            }
        }
    }

    /// Converts VS Code replace syntax (`\n`, `\t`, `\\`, `$&`) to an `NSRegularExpression` template.
    static func expressionTemplate(from template: String) -> String {
        var output = ""
        var characters = template.makeIterator()
        while let character = characters.next() {
            switch character {
            case "\\":
                switch characters.next() {
                case "n": output += "\n"
                case "t": output += "\t"
                case "\\": output += "\\\\"
                case let next?: output += "\\" + String(next)
                case nil: output += "\\\\"
                }
            case "$":
                output += "$"
                var lookahead = characters
                if lookahead.next() == "&" {
                    characters = lookahead
                    output += "0"
                }
            default:
                output.append(character)
            }
        }
        return output
    }
}
