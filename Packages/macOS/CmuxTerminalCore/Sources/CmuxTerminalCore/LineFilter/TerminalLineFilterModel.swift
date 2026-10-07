public import Observation

/// The find filter's list of matching terminal lines.
///
/// The model scans the terminal newest rows first, in bounded chunks, so the
/// most recent matches appear immediately and typing never waits on a large
/// scrollback. Call ``update(needle:)`` when the needle changes and
/// ``refresh()`` when the terminal may have printed more.
@MainActor
@Observable
public final class TerminalLineFilterModel {
    /// The matching lines, oldest first.
    public private(set) var lines: [TerminalLineFilterLine] = []
    /// Whether older rows are still being scanned.
    public private(set) var isScanning = false
    /// Whether older matching lines were dropped to stay within the line limit.
    public private(set) var isTruncated = false

    /// Creates a model over a terminal.
    ///
    /// - Parameters:
    ///   - source: The terminal to read and scroll.
    ///   - limits: Bounds on how much is read and kept.
    public init(
        source: any TerminalLineFilterSource,
        limits: TerminalLineFilterLimits = TerminalLineFilterLimits()
    ) {
    }

    /// Starts applying needle changes and refreshes as they arrive.
    public func start() {
    }

    /// Stops scanning and clears the list.
    public func stop() {
    }

    /// Replaces the needle and rescans.
    public func update(needle: String) {
    }

    /// Rescans the part of the terminal that can have changed.
    public func refresh() {
    }

    /// Scrolls the terminal to `line`.
    ///
    /// - Returns: Whether the terminal scrolled. False means the scrollback
    ///   changed underneath the list, which is rescanned.
    @discardableResult
    public func reveal(_ line: TerminalLineFilterLine) -> Bool {
        false
    }

    /// Runs queued needle changes and refreshes until none are left.
    func processPendingWork() async {
    }
}
