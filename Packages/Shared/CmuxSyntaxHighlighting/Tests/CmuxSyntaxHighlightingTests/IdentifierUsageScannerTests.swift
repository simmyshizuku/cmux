import CmuxSyntaxHighlighting
import Testing

@Suite("Identifier usage scanner")
struct IdentifierUsageScannerTests {
    private let scanner = IdentifierUsageScanner()

    @Test("Call sites become functions and member accesses become properties")
    func colorsCallsAndMembers() {
        let source = "let s = track.naturalSize.applying(t)"
        let runs = scanner.addingUsageRuns(to: [], source: source, language: "swift")
        #expect(runs == [
            HighlightRun(location: 14, length: 11, style: TokenStyle(role: .property)),
            HighlightRun(location: 26, length: 8, style: TokenStyle(role: .function)),
        ])
    }

    @Test("Existing runs are kept and never recolored")
    func keepsExistingRuns() {
        let source = "URL(x).path"
        let typeRun = HighlightRun(location: 0, length: 3, style: TokenStyle(role: .type))
        let runs = scanner.addingUsageRuns(to: [typeRun], source: source, language: "swift")
        #expect(runs == [
            typeRun,
            HighlightRun(location: 7, length: 4, style: TokenStyle(role: .property)),
        ])
    }

    @Test("PascalCase names are types, including constructor calls")
    func pascalCaseNamesAreTypes() {
        let source = "Widget build(BuildContext c) => Theme.of(c);"
        let runs = scanner.addingUsageRuns(to: [], source: source, language: "dart")
        #expect(runs == [
            HighlightRun(location: 0, length: 6, style: TokenStyle(role: .type)),
            HighlightRun(location: 7, length: 5, style: TokenStyle(role: .function)),
            HighlightRun(location: 13, length: 12, style: TokenStyle(role: .type)),
            HighlightRun(location: 32, length: 5, style: TokenStyle(role: .type)),
            HighlightRun(location: 38, length: 2, style: TokenStyle(role: .function)),
        ])
    }

    @Test("Constants and PascalCase-method languages keep call and member roles")
    func pascalCaseRuleSkipsConstantsAndMethodCaseLanguages() {
        let kotlin = scanner.addingUsageRuns(to: [], source: "Color.RED", language: "kotlin")
        #expect(kotlin == [
            HighlightRun(location: 0, length: 5, style: TokenStyle(role: .type)),
            HighlightRun(location: 6, length: 3, style: TokenStyle(role: .property)),
        ])
        let csharp = scanner.addingUsageRuns(to: [], source: "Console.WriteLine(x)", language: "csharp")
        #expect(csharp == [
            HighlightRun(location: 8, length: 9, style: TokenStyle(role: .function)),
        ])
    }

    @Test("Dollar signs are identifier characters")
    func dollarSignsAreIdentifierCharacters() {
        let runs = scanner.addingUsageRuns(to: [], source: "$state.value", language: "javascript")
        #expect(runs == [HighlightRun(location: 7, length: 5, style: TokenStyle(role: .property))])
    }

    @Test("Range operands are not member accesses")
    func ignoresRangeOperands() {
        let runs = scanner.addingUsageRuns(to: [], source: "a...b; c..<d", language: "swift")
        #expect(runs.isEmpty)
    }

    @Test("Prose and data languages are left alone")
    func skipsUnsupportedLanguages() {
        let runs = scanner.addingUsageRuns(to: [], source: "see foo(bar) and x.y", language: "markdown")
        #expect(runs.isEmpty)
    }
}
