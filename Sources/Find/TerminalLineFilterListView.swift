import SwiftUI
import CmuxTerminalCore

/// The terminal find filter: only the lines that match, covering the terminal pane.
///
/// Lines are in terminal order with the newest at the bottom, and the list
/// stays pinned to the bottom as output arrives unless it is scrolled up.
struct TerminalLineFilterListView: View {
    let lines: [TerminalLineFilterLine]
    let isNeedleEmpty: Bool
    let isScanning: Bool
    let isTruncated: Bool
    let appearance: TerminalLineFilterAppearance
    let accent: Color
    /// The edge the find bar floats over; rows can scroll clear of it.
    let findBarEdge: Edge.Set
    let onReveal: (TerminalLineFilterLine) -> Void

    private static let findBarClearance: CGFloat = 52

    var body: some View {
        ZStack {
            Color(nsColor: appearance.background)
            if lines.isEmpty {
                placeholder
            } else {
                list
            }
        }
        .accessibilityIdentifier("TerminalFindFilterList")
    }

    private var secondaryColor: Color {
        Color(nsColor: appearance.foreground).opacity(0.55)
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isTruncated {
                    Text(String(
                        localized: "search.filter.truncated",
                        defaultValue: "Showing only the most recent matching lines"
                    ))
                    .cmuxFont(.caption)
                    .foregroundStyle(secondaryColor)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
                ForEach(lines) { line in
                    TerminalLineFilterRow(
                        line: line,
                        appearance: appearance,
                        accent: accent,
                        onReveal: { onReveal(line) }
                    )
                    .equatable()
                }
            }
            .padding(.vertical, 6)
        }
        .defaultScrollAnchor(.bottom)
        .contentMargins(findBarEdge, Self.findBarClearance, for: .scrollContent)
    }

    @ViewBuilder
    private var placeholder: some View {
        if isNeedleEmpty {
            Text(String(
                localized: "search.filter.empty.prompt",
                defaultValue: "Type to show only matching lines"
            ))
            .cmuxFont(.body)
            .foregroundStyle(secondaryColor)
        } else if !isScanning {
            Text(String(
                localized: "search.filter.empty.noMatches",
                defaultValue: "No matching lines"
            ))
            .cmuxFont(.body)
            .foregroundStyle(secondaryColor)
        }
    }
}
