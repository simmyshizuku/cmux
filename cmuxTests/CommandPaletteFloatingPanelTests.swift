import AppKit
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Command palette placement")
struct CommandPaletteFloatingPanelTests {
    private typealias Panel = CommandPaletteFloatingPanel<EmptyView>

    @Test func defaultPositionKeepsAFullPaletteNearWindowCenter() {
        let window = CGSize(width: 1_000, height: 800)
        let panel = CGSize(width: 560, height: 520)
        let origin = Panel.clampedOrigin(
            containerSize: window,
            panelSize: panel,
            centerX: 0.5,
            topY: 0.22
        )

        #expect(origin.x == 220)
        #expect(origin.y == 176)
        #expect(abs(origin.y + panel.height / 2 - window.height / 2) < 40)
    }

    @Test func dragClampsEveryEdgeAndRoundTripsAfterResize() {
        let window = CGSize(width: 1_000, height: 800)
        let panel = CGSize(width: 560, height: 520)
        let topLeft = Panel.clampedOrigin(
            containerSize: window,
            panelSize: panel,
            centerX: 0.5,
            topY: 0.22,
            translation: CGSize(width: -2_000, height: -2_000)
        )
        let bottomRight = Panel.clampedOrigin(
            containerSize: window,
            panelSize: panel,
            centerX: 0.5,
            topY: 0.22,
            translation: CGSize(width: 2_000, height: 2_000)
        )

        #expect(topLeft == .zero)
        #expect(bottomRight == CGPoint(x: 440, y: 280))

        let saved = Panel.normalizedPosition(
            origin: bottomRight,
            containerSize: window,
            panelWidth: panel.width
        )
        let resized = Panel.clampedOrigin(
            containerSize: CGSize(width: 800, height: 600),
            panelSize: panel,
            centerX: saved.centerX,
            topY: saved.topY
        )
        #expect(resized.x == 240)
        #expect(resized.y == 80)
    }

    @Test func resultHeightChangesDoNotMoveTheSearchInputWhenThePanelFits() {
        let window = CGSize(width: 1_000, height: 800)
        let short = Panel.clampedOrigin(
            containerSize: window,
            panelSize: CGSize(width: 560, height: 120),
            centerX: 0.5,
            topY: 0.22
        )
        let tall = Panel.clampedOrigin(
            containerSize: window,
            panelSize: CGSize(width: 560, height: 520),
            centerX: 0.5,
            topY: 0.22
        )
        #expect(short == tall)
    }
}
