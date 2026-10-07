import Testing
@testable import CmuxTerminalCore

@Suite("Terminal line filter matcher")
struct TerminalLineFilterMatcherTests {
    private func matcher(_ needle: String, maximumLineLength: Int = 4_000) -> TerminalLineFilterMatcher {
        TerminalLineFilterMatcher(needle: needle, maximumLineLength: maximumLineLength)
    }

    @Test func keepsOnlyLinesContainingTheNeedle() {
        let text = "boot ok\nERROR: disk full\nidle\nretry after error"
        let lines = matcher("error").matchingLines(in: text, chunkRows: 10...13)

        #expect(lines.map(\.text) == ["ERROR: disk full", "retry after error"])
        #expect(lines.map(\.lineIndex) == [1, 3])
        #expect(lines.map(\.chunkRows) == [10...13, 10...13])
    }

    @Test func reportsEveryMatchInALine() throws {
        let lines = matcher("ab").matchingLines(in: "xAByab-ab", chunkRows: 0...0)

        let line = try #require(lines.first)
        #expect(line.matchRanges.map { String(line.text[$0]) } == ["AB", "ab", "ab"])
    }

    @Test func emptyNeedleMatchesNothing() {
        #expect(matcher("").matchingLines(in: "one\ntwo", chunkRows: 0...1).isEmpty)
    }

    @Test func clipsAVeryLongLineAroundItsFirstMatch() throws {
        let text = String(repeating: "a", count: 500) + "NEEDLE" + String(repeating: "b", count: 500)
        let lines = matcher("needle", maximumLineLength: 100).matchingLines(in: text, chunkRows: 0...12)

        let line = try #require(lines.first)
        #expect(line.text.count <= 100)
        #expect(line.matchRanges.map { String(line.text[$0]) } == ["NEEDLE"])
    }

    @Test(arguments: [("", 0), ("one", 1), ("one\ntwo", 2), ("\n\nthree", 3)])
    func countsLogicalLines(text: String, expected: Int) {
        #expect(matcher("x").lineCount(in: text) == expected)
    }
}
