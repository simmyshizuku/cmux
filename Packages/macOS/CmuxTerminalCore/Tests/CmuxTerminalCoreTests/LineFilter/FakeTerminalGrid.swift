@testable import CmuxTerminalCore

/// An in-memory terminal: physical rows with soft-wrap flags, read back the way
/// ``TerminalLineFilterSource/text(rows:)`` documents.
@MainActor
final class FakeTerminalGrid: TerminalLineFilterSource {
    private struct Row {
        var text: String
        var wrapsToNext: Bool
    }

    private var rows: [Row] = []
    let columns: Int
    var viewportRows: UInt64
    private(set) var revision: UInt64 = 1
    private(set) var scrolledRows: [UInt64] = []
    var isGone = false

    init(lines: [String], columns: Int = 80, viewportRows: UInt64 = 4) {
        self.columns = columns
        self.viewportRows = viewportRows
        append(lines)
    }

    var rowCount: Int { rows.count }

    /// Appends logical lines, wrapping each at the grid width.
    func append(_ lines: [String]) {
        for line in lines {
            var remaining = Substring(line)
            repeat {
                let piece = remaining.prefix(columns)
                remaining = remaining.dropFirst(columns)
                rows.append(Row(text: String(piece), wrapsToNext: !remaining.isEmpty))
            } while !remaining.isEmpty
        }
    }

    /// Drops the oldest rows the way a full scrollback does, renumbering the rest.
    func pruneOldest(_ count: Int) {
        rows.removeFirst(count)
        revision += 1
    }

    func rowSpace() -> TerminalLineFilterRowSpace? {
        guard !isGone else { return nil }
        return TerminalLineFilterRowSpace(
            totalRows: UInt64(rows.count),
            viewportRows: viewportRows,
            columns: columns,
            revision: revision
        )
    }

    func text(rows range: ClosedRange<UInt64>) -> String? {
        guard !isGone, range.upperBound < UInt64(rows.count) else { return nil }
        var lines: [String] = []
        var current = ""
        for index in Int(range.lowerBound)...Int(range.upperBound) {
            current += rows[index].text
            if !rows[index].wrapsToNext || index == Int(range.upperBound) {
                lines.append(current)
                current = ""
            }
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    func scroll(toRow row: UInt64, revision: UInt64) -> Bool {
        guard !isGone, revision == self.revision else { return false }
        scrolledRows.append(row)
        return true
    }
}
