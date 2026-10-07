import Testing
@testable import CmuxTerminalCore

@Suite("Terminal line filter row locator")
@MainActor
struct TerminalLineFilterRowLocatorTests {
    private let matcher = TerminalLineFilterMatcher(needle: "target", maximumLineLength: 4_000)

    private func startRow(in grid: FakeTerminalGrid, chunkRows: ClosedRange<UInt64>) throws -> UInt64? {
        let text = try #require(grid.text(rows: chunkRows))
        let line = try #require(matcher.matchingLines(in: text, chunkRows: chunkRows).first)
        return TerminalLineFilterRowLocator(matcher: matcher).startRow(of: line) { grid.text(rows: $0) }
    }

    @Test func locatesALineBelowWrappedLines() throws {
        // Rows: 0-2 one wrapped line, 3 "short", 4-5 the wrapped target line.
        let grid = FakeTerminalGrid(
            lines: [String(repeating: "w", count: 25), "short", "the target is here"],
            columns: 10
        )

        #expect(try startRow(in: grid, chunkRows: 0...5) == 4)
    }

    @Test func locatesALineBelowBlankRows() throws {
        let grid = FakeTerminalGrid(lines: ["first", "", "", "target"], columns: 10)

        #expect(try startRow(in: grid, chunkRows: 0...3) == 3)
    }

    @Test func locatesALineInAChunkThatStartsMidScrollback() throws {
        let grid = FakeTerminalGrid(lines: ["a", "b", "c", "d", "target", "e"], columns: 10)

        #expect(try startRow(in: grid, chunkRows: 3...5) == 4)
    }
}
