import CmuxCommandPalette
import SwiftUI

/// Positions the command palette without moving its search field when results change height.
struct CommandPaletteFloatingPanel<Content: View>: View {
    private struct PanelHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat { 0 }

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    let containerSize: CGSize
    let width: CGFloat
    let content: Content

    @AppStorage("commandPalette.floatingPanel.centerX") private var savedCenterX = 0.5
    @AppStorage("commandPalette.floatingPanel.topY") private var savedTopY = 0.22
    @GestureState private var dragTranslation = CGSize.zero
    @State private var panelHeight: CGFloat = 0

    init(containerSize: CGSize, width: CGFloat, @ViewBuilder content: () -> Content) {
        self.containerSize = containerSize
        self.width = width
        self.content = content()
    }

    var body: some View {
        let panelSize = CGSize(width: width, height: panelHeight)
        let origin = Self.clampedOrigin(
            containerSize: containerSize,
            panelSize: panelSize,
            centerX: savedCenterX,
            topY: savedTopY,
            translation: dragTranslation
        )

        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let finalOrigin = Self.clampedOrigin(
                                containerSize: containerSize,
                                panelSize: CGSize(width: width, height: panelHeight),
                                centerX: savedCenterX,
                                topY: savedTopY,
                                translation: value.translation
                            )
                            let normalized = Self.normalizedPosition(
                                origin: finalOrigin,
                                containerSize: containerSize,
                                panelWidth: width
                            )
                            savedCenterX = normalized.centerX
                            savedTopY = normalized.topY
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "commandPalette.moveHandle", defaultValue: "Drag to move command palette"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("CommandPaletteDragHandle")

            content
        }
        .frame(width: width)
        .background(CommandPalettePanelHitRegion())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 10, x: 0, y: 5)
        .background(
            GeometryReader { panel in
                Color.clear.preference(key: PanelHeightPreferenceKey.self, value: panel.size.height)
            }
        )
        .onPreferenceChange(PanelHeightPreferenceKey.self) { height in
            if abs(panelHeight - height) > 0.5 {
                panelHeight = height
            }
        }
        .offset(x: origin.x, y: origin.y)
    }

    static func clampedOrigin(
        containerSize: CGSize,
        panelSize: CGSize,
        centerX: Double,
        topY: Double,
        translation: CGSize = .zero
    ) -> CGPoint {
        let width = max(containerSize.width, 0)
        let height = max(containerSize.height, 0)
        let panelWidth = max(panelSize.width, 0)
        let panelHeight = max(panelSize.height, 0)
        let x = width * CGFloat(min(max(centerX, 0), 1)) - panelWidth / 2 + translation.width
        let y = height * CGFloat(min(max(topY, 0), 1)) + translation.height
        return CGPoint(
            x: min(max(x, 0), max(width - panelWidth, 0)),
            y: min(max(y, 0), max(height - panelHeight, 0))
        )
    }

    static func normalizedPosition(
        origin: CGPoint,
        containerSize: CGSize,
        panelWidth: CGFloat
    ) -> (centerX: Double, topY: Double) {
        (
            centerX: Double((origin.x + panelWidth / 2) / max(containerSize.width, 1)),
            topY: Double(origin.y / max(containerSize.height, 1))
        )
    }
}
