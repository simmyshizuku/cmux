import Foundation
import Testing

@testable import CmuxFilePreviewCore

@Suite("Text search matcher")
struct TextSearchMatcherTests {
    private func matchedStrings(
        _ query: String,
        in text: String,
        options: TextSearchOptions = TextSearchOptions()
    ) throws -> [String] {
        let matcher = try #require(try TextSearchMatcher(query: query, options: options))
        return matcher.matches(in: text).map { (text as NSString).substring(with: $0) }
    }

    @Test("Empty query produces no matcher")
    func emptyQuery() throws {
        #expect(try TextSearchMatcher(query: "", options: TextSearchOptions()) == nil)
    }

    @Test("Literal search ignores case by default and escapes metacharacters")
    func literalDefault() throws {
        #expect(try matchedStrings("foo", in: "Foo foo FOO") == ["Foo", "foo", "FOO"])
        #expect(try matchedStrings("a.b", in: "a.b axb") == ["a.b"])
        #expect(try matchedStrings("(x)", in: "f(x) (y)") == ["(x)"])
    }

    @Test("Match case keeps only exact-case matches")
    func matchCase() throws {
        #expect(try matchedStrings("Foo", in: "Foo foo FOO", options: TextSearchOptions(matchCase: true)) == ["Foo"])
    }

    @Test("Whole word rejects matches inside identifiers, including punctuation-edged queries")
    func wholeWord() throws {
        let options = TextSearchOptions(matchWholeWord: true)
        #expect(try matchedStrings("foo", in: "foo food _foo foo1 (foo)", options: options) == ["foo", "foo"])
        #expect(try matchedStrings("-v", in: "cmd -v -vv", options: options) == ["-v"])
    }

    @Test("Regular expressions match, anchor at lines, and honor case")
    func regularExpression() throws {
        let options = TextSearchOptions(useRegularExpression: true)
        #expect(try matchedStrings("fo+", in: "f fo foo", options: options) == ["fo", "foo"])
        #expect(try matchedStrings("^let", in: "let a\n  let b\nlet c", options: options) == ["let", "let"])
        let caseOptions = TextSearchOptions(matchCase: true, useRegularExpression: true)
        #expect(try matchedStrings("[A-Z]\\w+", in: "Foo bar Baz", options: caseOptions) == ["Foo", "Baz"])
    }

    @Test("Regular expression with whole word wraps the whole alternation")
    func regularExpressionWholeWord() throws {
        let options = TextSearchOptions(matchWholeWord: true, useRegularExpression: true)
        #expect(try matchedStrings("cat|dog", in: "cat dogs hotdog dog", options: options) == ["cat", "dog"])
    }

    @Test("Invalid regular expression throws; the same text as a literal does not")
    func invalidRegularExpression() throws {
        #expect(throws: TextSearchMatcher.Failure.invalidRegularExpression) {
            _ = try TextSearchMatcher(query: "(", options: TextSearchOptions(useRegularExpression: true))
        }
        #expect(try matchedStrings("(", in: "f(") == ["("])
    }

    @Test("Zero-length regular expression matches are skipped")
    func zeroLengthMatches() throws {
        #expect(try matchedStrings("x*", in: "axxb", options: TextSearchOptions(useRegularExpression: true)) == ["xx"])
    }

    @Test("Match limit stops enumeration")
    func matchLimit() throws {
        let matcher = try #require(try TextSearchMatcher(query: "a", options: TextSearchOptions()))
        #expect(matcher.matches(in: "aaaaa", limit: 2).count == 2)
    }

    @Test("Literal replacement inserts the template verbatim")
    func literalReplacement() throws {
        let matcher = try #require(try TextSearchMatcher(query: "a.b", options: TextSearchOptions()))
        let plan = matcher.replacements(in: "a.b A.B", template: "$1\\n")
        #expect(plan.map(\.replacement) == ["$1\\n", "$1\\n"])
        #expect(plan.map(\.range) == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)])
    }

    @Test("Regular expression replacement expands groups, $&, and escapes", arguments: [
        ("$2 $1", "b a"),
        ("[$&]", "[a=b]"),
        ("$1\\n$2", "a\nb"),
        ("$1\\t$2", "a\tb"),
        ("\\$1", "$1"),
        ("a\\\\b", "a\\b"),
    ] as [(String, String)])
    func regularExpressionReplacement(_ template: String, _ expected: String) throws {
        let matcher = try #require(try TextSearchMatcher(
            query: "(\\w)=(\\w)",
            options: TextSearchOptions(useRegularExpression: true)
        ))
        let plan = matcher.replacements(in: "a=b", template: template)
        #expect(plan.map(\.replacement) == [expected])
    }

    @Test("Replacement for a stale range returns nil")
    func staleRange() throws {
        let matcher = try #require(try TextSearchMatcher(query: "foo", options: TextSearchOptions()))
        #expect(matcher.replacement(forMatchAt: NSRange(location: 0, length: 3), in: "bar", template: "x") == nil)
    }

    @Test("Whole-word replacement sees context outside the match range")
    func lookaroundAtRangeEdges() throws {
        let matcher = try #require(try TextSearchMatcher(query: "foo", options: TextSearchOptions(matchWholeWord: true)))
        #expect(matcher.replacement(forMatchAt: NSRange(location: 1, length: 3), in: "xfoo", template: "y") == nil)
        #expect(matcher.replacement(forMatchAt: NSRange(location: 1, length: 3), in: " foo", template: "y") == "y")
    }
}
