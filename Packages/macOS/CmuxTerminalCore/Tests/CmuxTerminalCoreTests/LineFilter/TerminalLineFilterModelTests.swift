import Testing
@testable import CmuxTerminalCore

@Suite("Terminal line filter model")
@MainActor
struct TerminalLineFilterModelTests {
    /// Small chunks, so every test crosses several chunk boundaries.
    private let limits = TerminalLineFilterLimits(
        maximumLines: 100,
        maximumRowsPerChunk: 3,
        maximumCellsPerChunk: 1_000_000,
        maximumLineLength: 4_000
    )

    private func numberedLines(_ range: ClosedRange<Int>, marking marked: Set<Int>) -> [String] {
        range.map { marked.contains($0) ? "line \($0) ERROR" : "line \($0) ok" }
    }

    @Test func listsMatchingLinesOldestFirstAcrossChunks() async {
        let grid = FakeTerminalGrid(lines: numberedLines(0...19, marking: [1, 8, 9, 17]))
        let model = TerminalLineFilterModel(source: grid, limits: limits)

        model.update(needle: "error")
        await model.processPendingWork()

        #expect(model.lines.map(\.text) == ["line 1 ERROR", "line 8 ERROR", "line 9 ERROR", "line 17 ERROR"])
        #expect(!model.isScanning)
        #expect(!model.isTruncated)
    }

    @Test func matchesANeedleThatSpansASoftWrap() async {
        // "disk-full" straddles the 10-column wrap of the second line.
        let grid = FakeTerminalGrid(lines: ["ok", "abcdefdisk-full!", "ok"], columns: 10)
        let model = TerminalLineFilterModel(source: grid, limits: limits)

        model.update(needle: "disk-full")
        await model.processPendingWork()

        #expect(model.lines.map(\.text) == ["abcdefdisk-full!"])
    }

    @Test func keepsOnlyTheNewestLinesAtTheLimit() async {
        var limits = limits
        limits.maximumLines = 5
        let grid = FakeTerminalGrid(lines: numberedLines(0...29, marking: Set(0...29)))
        let model = TerminalLineFilterModel(source: grid, limits: limits)

        model.update(needle: "error")
        await model.processPendingWork()

        #expect(model.lines.map(\.text) == (25...29).map { "line \($0) ERROR" })
        #expect(model.isTruncated)
    }

    @Test func changingTheNeedleReplacesTheList() async {
        let grid = FakeTerminalGrid(lines: ["alpha one", "beta two", "alpha three"])
        let model = TerminalLineFilterModel(source: grid, limits: limits)

        model.update(needle: "alpha")
        await model.processPendingWork()
        model.update(needle: "beta")
        await model.processPendingWork()
        #expect(model.lines.map(\.text) == ["beta two"])

        model.update(needle: "")
        await model.processPendingWork()
        #expect(model.lines.isEmpty)
    }

    @Test func refreshAddsNewOutputWithoutDisturbingOlderLines() async {
        let grid = FakeTerminalGrid(lines: numberedLines(0...11, marking: [2, 10]))
        let model = TerminalLineFilterModel(source: grid, limits: limits)
        model.update(needle: "error")
        await model.processPendingWork()
        let before = model.lines

        grid.append(numberedLines(12...25, marking: [13, 24]))
        model.refresh()
        await model.processPendingWork()

        #expect(model.lines.map(\.text) == [
            "line 2 ERROR", "line 10 ERROR", "line 13 ERROR", "line 24 ERROR",
        ])
        #expect(model.lines.first?.id == before.first?.id)
    }

    @Test func refreshSeesTextRewrittenOnTheActiveScreen() async {
        let grid = FakeTerminalGrid(lines: ["one", "two", "three"], viewportRows: 4)
        let model = TerminalLineFilterModel(source: grid, limits: limits)
        model.update(needle: "done")
        await model.processPendingWork()
        #expect(model.lines.isEmpty)

        grid.append(["build done"])
        model.refresh()
        await model.processPendingWork()

        #expect(model.lines.map(\.text) == ["build done"])
    }

    @Test func refreshRescansWhenScrollbackIsPruned() async throws {
        let grid = FakeTerminalGrid(lines: numberedLines(0...19, marking: [1, 15]))
        let model = TerminalLineFilterModel(source: grid, limits: limits)
        model.update(needle: "error")
        await model.processPendingWork()

        grid.pruneOldest(5)
        model.refresh()
        await model.processPendingWork()

        #expect(model.lines.map(\.text) == ["line 15 ERROR"])
        let line = try #require(model.lines.first)
        #expect(model.reveal(line))
        // Line 15 is row 10 after pruning; the viewport is 4 rows, so one row
        // of context sits above it.
        #expect(grid.scrolledRows == [9])
    }

    @Test func revealScrollsToTheRowTheLineStartsOn() async throws {
        // Rows 0-2 are one wrapped line, so the target's line index (2) is not its row (4).
        let grid = FakeTerminalGrid(
            lines: [String(repeating: "w", count: 25), "short", "the target is here", "tail", "tail"],
            columns: 10,
            viewportRows: 6
        )
        var limits = limits
        limits.maximumRowsPerChunk = 50
        let model = TerminalLineFilterModel(source: grid, limits: limits)
        model.update(needle: "target")
        await model.processPendingWork()

        let line = try #require(model.lines.first)
        #expect(model.reveal(line))
        #expect(grid.scrolledRows == [2])
    }

    @Test func revealRefusesAStaleLineAndRescans() async throws {
        let grid = FakeTerminalGrid(lines: numberedLines(0...19, marking: [15]))
        let model = TerminalLineFilterModel(source: grid, limits: limits)
        model.update(needle: "error")
        await model.processPendingWork()
        let stale = try #require(model.lines.first)

        grid.pruneOldest(5)

        #expect(!model.reveal(stale))
        #expect(grid.scrolledRows.isEmpty)
        await model.processPendingWork()
        #expect(model.lines.map(\.text) == ["line 15 ERROR"])
        #expect(model.lines.first?.id != stale.id)
    }

    @Test func stopClearsTheList() async {
        let grid = FakeTerminalGrid(lines: ["an ERROR"])
        let model = TerminalLineFilterModel(source: grid, limits: limits)
        model.update(needle: "error")
        await model.processPendingWork()

        model.stop()

        #expect(model.lines.isEmpty)
        #expect(!model.isScanning)
    }

    @Test func aVanishedTerminalLeavesAnEmptyList() async {
        let grid = FakeTerminalGrid(lines: ["an ERROR"])
        let model = TerminalLineFilterModel(source: grid, limits: limits)
        grid.isGone = true

        model.update(needle: "error")
        await model.processPendingWork()

        #expect(model.lines.isEmpty)
        #expect(!model.isScanning)
    }
}
