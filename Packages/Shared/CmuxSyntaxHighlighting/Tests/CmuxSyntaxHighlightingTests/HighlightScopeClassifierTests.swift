import CmuxSyntaxHighlighting
import Testing

@Suite("highlight.js scope classifier")
struct HighlightScopeClassifierTests {
    private let classifier = HighlightScopeClassifier()

    @Test(
        "Scopes map to palette roles",
        arguments: [
            ("hljs-keyword", TokenRole.keyword),
            ("hljs-type", TokenRole.type),
            ("hljs-built_in", TokenRole.type),
            ("hljs-title class_", TokenRole.type),
            ("hljs-title class_ inherited__", TokenRole.type),
            ("hljs-title function_", TokenRole.function),
            ("hljs-title function_ invoke__", TokenRole.function),
            ("hljs-title", TokenRole.function),
            ("hljs-property", TokenRole.property),
            ("hljs-variable language_", TokenRole.keyword),
            ("hljs-variable", TokenRole.variable),
            ("hljs-string", TokenRole.string),
            ("hljs-number", TokenRole.number),
            ("hljs-comment", TokenRole.comment),
            ("hljs-meta", TokenRole.attribute),
            ("hljs-regexp", TokenRole.regexp),
            ("hljs-params", TokenRole.foreground),
            ("hljs-subst", TokenRole.foreground),
        ]
    )
    func mapsScope(classAttribute: String, role: TokenRole) {
        #expect(classifier.style(forClassAttribute: classAttribute)?.role == role)
    }

    @Test("A bare title names a type inside a legacy class container and a function elsewhere")
    func bareTitleFollowsItsContainer() {
        #expect(classifier.style(forClassAttribute: "hljs-title", insideClassDeclaration: true)?.role == .type)
        #expect(classifier.style(forClassAttribute: "hljs-title", insideClassDeclaration: false)?.role == .function)
        #expect(classifier.style(forClassAttribute: "hljs-class")?.role == .foreground)
        #expect(classifier.style(forClassAttribute: "hljs-function")?.role == .foreground)
    }

    @Test("Doc tags are bold comments and Markdown emphasis is italic")
    func mapsFontTraits() {
        #expect(classifier.style(forClassAttribute: "hljs-doctag") == TokenStyle(role: .comment, isBold: true))
        #expect(classifier.style(forClassAttribute: "hljs-emphasis") == TokenStyle(role: .foreground, isItalic: true))
    }

    @Test("Unknown and non-hljs classes inherit the enclosing style")
    func unknownScopesInherit() {
        #expect(classifier.style(forClassAttribute: "hljs-something-new") == nil)
        #expect(classifier.style(forClassAttribute: "language-swift") == nil)
        #expect(classifier.style(forClassAttribute: "") == nil)
    }
}
