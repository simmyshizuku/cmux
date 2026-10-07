public import Observation

/// The find filter's list of matching terminal lines.
///
/// The model scans the terminal newest rows first, in bounded chunks, so the
/// most recent matches appear immediately and typing never waits on a large
/// scrollback. Call ``update(needle:)`` when the needle changes and
/// ``refresh()`` when the terminal may have printed more.
///
/// Rows above the active screen never change while the row-space revision
/// holds, so a refresh rereads only the tail. A logical line that straddles a
/// chunk boundary is read as two lines; chunks are large enough that this is
/// rare.
@MainActor
@Observable
public final class TerminalLineFilterModel {
    /// The matching lines, oldest first.
    public private(set) var lines: [TerminalLineFilterLine] = []
    /// Whether older rows are still being scanned.
    public private(set) var isScanning = false
    /// Whether older matching lines were left out to stay within the line limit.
    public private(set) var isTruncated = false

    /// The matching lines read from one inclusive range of rows.
    private struct Chunk {
        let rows: ClosedRange<UInt64>
        var lines: [TerminalLineFilterLine]
    }

    @ObservationIgnored private let source: any TerminalLineFilterSource
    @ObservationIgnored private let limits: TerminalLineFilterLimits
    @ObservationIgnored private var needle = ""
    @ObservationIgnored private var needsRestart = false
    @ObservationIgnored private var needsRefresh = false
    /// Scanned chunks, oldest first.
    @ObservationIgnored private var chunks: [Chunk] = []
    /// The row space the chunks were read from; nil when nothing is scanned.
    @ObservationIgnored private var revision: UInt64?
    @ObservationIgnored private var rowsPerChunk: UInt64 = 1
    /// Rows below this one are scanned; rows above it are still to scan.
    @ObservationIgnored private var olderRowsEnd: UInt64 = 0
    /// Rows from this one down are reread on every refresh.
    @ObservationIgnored private var tailStart: UInt64 = 0
    @ObservationIgnored private var reachedLineLimit = false
    /// Bumped by ``stop()`` so a scan suspended in a background match gives up.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wake: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var pump: Task<Void, Never>?

    /// Creates a model over a terminal.
    ///
    /// - Parameters:
    ///   - source: The terminal to read and scroll.
    ///   - limits: Bounds on how much is read and kept.
    public init(
        source: any TerminalLineFilterSource,
        limits: TerminalLineFilterLimits = TerminalLineFilterLimits()
    ) {
        self.source = source
        self.limits = limits
    }

    /// Starts applying needle changes and refreshes as they arrive.
    public func start() {
        guard pump == nil else { return }
        let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        pump = Task { [weak self] in
            for await _ in signals {
                guard let self else { return }
                await self.processPendingWork()
            }
        }
        if needsRestart || needsRefresh {
            continuation.yield()
        }
    }

    /// Stops scanning and clears the list.
    public func stop() {
        generation += 1
        pump?.cancel()
        pump = nil
        wake?.finish()
        wake = nil
        needle = ""
        needsRestart = false
        needsRefresh = false
        resetScan()
        publish()
        setScanning(false)
    }

    /// Replaces the needle and rescans.
    public func update(needle: String) {
        guard needle != self.needle else { return }
        self.needle = needle
        scheduleRestart()
    }

    /// Rescans the part of the terminal that can have changed.
    public func refresh() {
        guard !needle.isEmpty else { return }
        needsRefresh = true
        wake?.yield()
    }

    /// Scrolls the terminal to `line`.
    ///
    /// - Returns: Whether the terminal scrolled. False means the scrollback
    ///   changed underneath the list, which is rescanned.
    @discardableResult
    public func reveal(_ line: TerminalLineFilterLine) -> Bool {
        guard let revision,
              let space = source.rowSpace(),
              space.revision == revision,
              let row = TerminalLineFilterRowLocator(matcher: matcher).startRow(
                  of: line,
                  text: { self.source.text(rows: $0) }
              ) else {
            scheduleRestart()
            return false
        }
        // Leave a few rows of context above the line.
        let context = min(row, space.viewportRows / 3)
        guard source.scroll(toRow: row - context, revision: revision) else {
            scheduleRestart()
            return false
        }
        return true
    }

    /// Runs queued needle changes and refreshes until none are left.
    func processPendingWork() async {
        let generation = generation
        while generation == self.generation {
            if needsRestart {
                needsRestart = false
                beginScan()
            } else if needsRefresh {
                needsRefresh = false
                await scanTail(generation: generation)
            } else if revision != nil, olderRowsEnd > 0, !reachedLineLimit {
                await scanOlderChunk(generation: generation)
            } else {
                setScanning(false)
                return
            }
        }
    }

    private var matcher: TerminalLineFilterMatcher {
        TerminalLineFilterMatcher(needle: needle, maximumLineLength: limits.maximumLineLength)
    }

    private func scheduleRestart() {
        needsRestart = true
        wake?.yield()
    }

    private func resetScan() {
        chunks = []
        revision = nil
        olderRowsEnd = 0
        tailStart = 0
        reachedLineLimit = false
    }

    /// Points the scan at the current row space. The first refresh reads the
    /// active screen, so the list is replaced by results, never blanked first.
    private func beginScan() {
        resetScan()
        guard !needle.isEmpty, let space = source.rowSpace(), space.totalRows > 0 else {
            publish()
            return
        }
        revision = space.revision
        rowsPerChunk = limits.rowsPerChunk(columns: space.columns)
        tailStart = space.activeTop
        olderRowsEnd = space.activeTop
        needsRefresh = true
        setScanning(true)
    }

    /// Rereads every row from ``tailStart`` down and replaces those chunks.
    private func scanTail(generation: Int) async {
        guard let revision else { return }
        guard let space = source.rowSpace() else {
            resetScan()
            publish()
            return
        }
        guard space.revision == revision, space.totalRows >= tailStart else {
            needsRestart = true
            return
        }
        let matcher = matcher
        var tail: [Chunk] = []
        var top = tailStart
        while top < space.totalRows {
            let rows = top...(min(top + rowsPerChunk, space.totalRows) - 1)
            let text = source.text(rows: rows) ?? ""
            let lines = await matcher.matchingLinesInBackground(in: text, chunkRows: rows)
            guard generation == self.generation, !needsRestart else { return }
            tail.append(Chunk(rows: rows, lines: lines))
            top = rows.upperBound + 1
        }
        guard source.rowSpace()?.revision == revision else {
            needsRestart = true
            return
        }
        chunks.removeAll { $0.rows.lowerBound >= tailStart }
        chunks.append(contentsOf: tail)
        // A full chunk that ended above the active screen is history and final.
        for chunk in tail {
            let rowCount = chunk.rows.upperBound - chunk.rows.lowerBound + 1
            guard rowCount == rowsPerChunk, chunk.rows.upperBound < space.activeTop else { break }
            tailStart = chunk.rows.upperBound + 1
        }
        publish()
    }

    /// Reads the next chunk above the scanned rows.
    private func scanOlderChunk(generation: Int) async {
        guard let revision else { return }
        guard let space = source.rowSpace() else {
            resetScan()
            publish()
            return
        }
        guard space.revision == revision else {
            needsRestart = true
            return
        }
        let top = olderRowsEnd > rowsPerChunk ? olderRowsEnd - rowsPerChunk : 0
        let rows = top...(olderRowsEnd - 1)
        let text = source.text(rows: rows) ?? ""
        let lines = await matcher.matchingLinesInBackground(in: text, chunkRows: rows)
        guard generation == self.generation, !needsRestart else { return }
        chunks.insert(Chunk(rows: rows, lines: lines), at: 0)
        olderRowsEnd = top
        publish()
    }

    /// Applies the line limit and publishes the list if it changed.
    private func publish() {
        var lineCount = chunks.reduce(0) { $0 + $1.lines.count }
        var droppedLines = false
        while lineCount > limits.maximumLines, let oldest = chunks.first {
            let excess = lineCount - limits.maximumLines
            if oldest.lines.count <= excess {
                chunks.removeFirst()
                lineCount -= oldest.lines.count
            } else {
                chunks[0].lines.removeFirst(excess)
                lineCount -= excess
            }
            droppedLines = true
        }
        if droppedLines || (lineCount >= limits.maximumLines && olderRowsEnd > 0) {
            reachedLineLimit = true
        }
        let truncated = reachedLineLimit
        if isTruncated != truncated {
            isTruncated = truncated
        }
        let newLines = chunks.flatMap(\.lines)
        if newLines != lines {
            lines = newLines
        }
    }

    private func setScanning(_ scanning: Bool) {
        if isScanning != scanning {
            isScanning = scanning
        }
    }
}
