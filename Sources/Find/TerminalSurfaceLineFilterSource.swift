import Foundation
import CmuxTerminal
import CmuxTerminalCore

/// Reads a live Ghostty surface for the terminal find filter.
@MainActor
final class TerminalSurfaceLineFilterSource: TerminalLineFilterSource {
    private weak var terminalSurface: TerminalSurface?

    /// Bound on one chunk's formatted text. Ghostty also allows a read to walk
    /// at most a quarter of this many cells, which is well above
    /// `TerminalLineFilterLimits.maximumCellsPerChunk`.
    private static let maximumChunkBytes: UInt = 2 * 1024 * 1024

    init(terminalSurface: TerminalSurface?) {
        self.terminalSurface = terminalSurface
    }

    func rowSpace() -> TerminalLineFilterRowSpace? {
        guard let surface = liveSurface() else { return nil }
        var scrollbar = ghostty_surface_scrollbar_s()
        guard ghostty_surface_scrollbar(surface, &scrollbar) else { return nil }
        return TerminalLineFilterRowSpace(
            totalRows: scrollbar.total,
            viewportRows: scrollbar.len,
            columns: Int(ghostty_surface_size(surface).columns),
            revision: scrollbar.row_space_revision
        )
    }

    func text(rows: ClosedRange<UInt64>) -> String? {
        guard let surface = liveSurface(),
              let top = UInt32(exactly: rows.lowerBound),
              let bottom = UInt32(exactly: rows.upperBound) else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_screen_clipboard_text(
            surface,
            top,
            bottom,
            Self.maximumChunkBytes,
            &text
        ) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text, text.text_len > 0 else { return "" }
        return String(
            decoding: Data(bytes: pointer, count: Int(text.text_len)),
            as: UTF8.self
        )
    }

    func scroll(toRow row: UInt64, revision: UInt64) -> Bool {
        guard let terminalSurface, rowSpace()?.revision == revision else { return false }
        // The same action a scroll-wheel drag sends, so the scroll view follows
        // Ghostty's scrollbar update exactly as it does for find next.
        return terminalSurface.performExplicitInputBindingAction("scroll_to_row:\(row)")
    }

    private func liveSurface() -> ghostty_surface_t? {
        terminalSurface?.liveSurfaceForGhosttyAccess(reason: "find.filter")
    }
}
