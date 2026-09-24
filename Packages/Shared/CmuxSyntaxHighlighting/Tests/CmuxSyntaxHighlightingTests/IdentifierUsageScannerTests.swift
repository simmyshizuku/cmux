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
