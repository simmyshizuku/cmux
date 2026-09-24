import CmuxSyntaxHighlighting
import Testing

@Suite("highlight.js HTML parser")
struct HighlightHTMLParserTests {
    private let parser = HighlightHTMLParser()

    @Test("Runs use source UTF-16 offsets after entity decoding")
    func decodesEntitiesIntoSourceOffsets() throws {
        let source = #"a < "b" & 'c' é"#
        let html = #"a &lt; <span class="hljs-string">&quot;b&quot;</span> &amp; &#x27;c&#x27; <span class="hljs-type">é</span>"#
        let runs = try #require(parser.parse(html: html, source: source))
        #expect(runs == [
            HighlightRun(location: 4, length: 3, style: TokenStyle(role: .string)),
            HighlightRun(location: 14, length: 1, style: TokenStyle(role: .type)),
        ])
    }

    @Test("Innermost classified span wins and plain containers emit no run")
    func innermostScopeWins() throws {
        let source = "f(a: Int)"
        let html = #"<span class="hljs-title function_">f</span>(<span class="hljs-params">a: <span class="hljs-type">Int</span></span>)"#
        let runs = try #require(parser.parse(html: html, source: source))
        #expect(runs == [
            HighlightRun(location: 0, length: 1, style: TokenStyle(role: .function)),
            HighlightRun(location: 5, length: 3, style: TokenStyle(role: .type)),
        ])
    }

    @Test("Legacy class containers turn their bare titles into types")
    func legacyClassTitlesAreTypes() throws {
        let source = "class A extends B {}"
        let html = #"<span class="hljs-class"><span class="hljs-keyword">class</span> <span class="hljs-title">A</span> <span class="hljs-keyword">extends</span> <span class="hljs-title">B</span> </span>{}"#
        let runs = try #require(parser.parse(html: html, source: source))
        #expect(runs == [
            HighlightRun(location: 0, length: 5, style: TokenStyle(role: .keyword)),
            HighlightRun(location: 6, length: 1, style: TokenStyle(role: .type)),
            HighlightRun(location: 8, length: 7, style: TokenStyle(role: .keyword)),
            HighlightRun(location: 16, length: 1, style: TokenStyle(role: .type)),
        ])
    }

    @Test("Unknown scopes inherit the enclosing style")
    func unknownScopeInherits() throws {
        let source = #""a\(b)c""#
        let html = #"<span class="hljs-string">&quot;a<span class="hljs-unknown">\(b)</span>c&quot;</span>"#
        let runs = try #require(parser.parse(html: html, source: source))
        #expect(runs == [HighlightRun(location: 0, length: 8, style: TokenStyle(role: .string))])
    }

    @Test(
        "Markup that does not reproduce the source is rejected",
        arguments: [
            #"<span class="hljs-type">Int</span>"#,
            #"<span class="hljs-type">Str"#,
            #"Str</span>"#,
            #"<b>Str</b>"#,
            #"Str&bogus;"#,
        ]
    )
    func rejectsMismatchedMarkup(html: String) {
        #expect(parser.parse(html: html, source: "Str") == nil)
    }
}
