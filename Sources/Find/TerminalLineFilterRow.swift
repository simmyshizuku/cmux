import SwiftUI
import CmuxTerminalCore

/// One matching line in the terminal find filter. Clicking it reveals the line in the terminal.
///
/// Takes value snapshots plus a closure, never the filter model, so a list
/// update only redraws the rows whose line changed.
struct TerminalLineFilterRow: View, Equatable {
    let line: TerminalLineFilterLine
    let appearance: TerminalLineFilterAppearance
    let accent: Color
    let onReveal: () -> Void
    @State private var isHovered = false

    static func == (lhs: TerminalLineFilterRow, rhs: TerminalLineFilterRow) -> Bool {
        lhs.line == rhs.line && lhs.appearance == rhs.appearance && lhs.accent == rhs.accent
    }

    var body: some View {
        Text(highlightedText)
            .lineLimit(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 1)
            .background(Color(nsColor: appearance.foreground).opacity(isHovered ? 0.1 : 0))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: onReveal)
            .backport.pointerStyle(.link)
            .accessibilityAddTraits(.isButton)
    }

    private var highlightedText: AttributedString {
        var text = AttributedString(line.text)
        text.font = Font(appearance.font)
        text.foregroundColor = Color(nsColor: appearance.foreground)
        for range in line.matchRanges {
            guard let lowerBound = AttributedString.Index(range.lowerBound, within: text),
                  let upperBound = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[lowerBound..<upperBound].backgroundColor = accent.opacity(0.4)
        }
        return text
    }
}
