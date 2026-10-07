import AppKit
import CmuxTerminal
import CmuxTerminalCore

/// The terminal's font and colors, so filtered lines read like the terminal they came from.
struct TerminalLineFilterAppearance: Equatable {
    let font: NSFont
    let foreground: NSColor
    let background: NSColor

    @MainActor
    init(terminalSurface: TerminalSurface?) {
        let app = GhosttyApp.shared
        let configuration = GhosttyConfig.loadForCmux(
            globalFontMagnificationPercent: app.appliedGlobalFontMagnificationPercent
        )
        // The surface's live size, so a terminal zoomed with Cmd+= filters at the same size.
        let fontSize = terminalSurface?.surface
            .flatMap { cmuxCurrentSurfaceFontSizePoints($0) }
            .map { CGFloat($0) } ?? configuration.fontSize
        font = NSFont(name: configuration.fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        foreground = app.defaultForegroundColor
        background = app.defaultBackgroundColor
    }
}
