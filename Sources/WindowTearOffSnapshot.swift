import AppKit

/// Synchronous snapshots for the tear-off preview: the thumbnail a drag
/// shows once it leaves every cmux window, and the image the new window
/// grows out of on release.
///
/// AppKit's view cache cannot see Metal-backed terminal content, so each
/// visible terminal's IOSurface is composited over it, the same way the
/// socket's AppKit screenshot backend does. Neither path needs Screen
/// Recording permission. Web content is left as AppKit draws it.
@MainActor
enum WindowTearOffSnapshot {
    /// Snapshots part of a window.
    ///
    /// - Parameters:
    ///   - window: The window to capture.
    ///   - rectFromTopLeft: The region in window-content points with a
    ///     top-left origin (SwiftUI's global space), or `nil` for the whole
    ///     window.
    /// - Returns: The image, or `nil` when the window has nothing to draw.
    static func image(of window: NSWindow, rectFromTopLeft: CGRect? = nil) -> NSImage? {
        guard let root = WindowAppKitCapture.rootView(for: window) else { return nil }
        let bounds = root.bounds
        guard !bounds.isEmpty,
              let bitmap = root.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        bitmap.size = bounds.size
        root.displayIfNeeded()
        root.cacheDisplay(in: bounds, to: bitmap)

        let terminals = terminalLayers(in: root)
        let crop = rectFromTopLeft
            .map { rootRect(fromTopLeft: $0, in: root) }?
            .intersection(bounds) ?? bounds
        guard !crop.isEmpty else { return nil }

        return NSImage(size: crop.size, flipped: root.isFlipped) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: -crop.minX, y: -crop.minY)
            bitmap.draw(
                in: bounds,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            for terminal in terminals {
                context.saveGState()
                context.clip(to: terminal.clip)
                NSImage(cgImage: terminal.image, size: terminal.rect.size).draw(
                    in: terminal.rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
                context.restoreGState()
            }
            return true
        }
    }

    /// A stand-in thumbnail for content that is not on screen, such as a
    /// background tab or an unselected workspace: a window-shaped card with
    /// the item's title.
    static func placeholder(title: String, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let card = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            NSColor.windowBackgroundColor.setFill()
            card.fill()
            NSColor.separatorColor.setStroke()
            card.lineWidth = 1
            card.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(rect.height * 0.07, 13), weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let text = title as NSString
            let textHeight = text.size(withAttributes: attributes).height
            text.draw(
                in: NSRect(
                    x: rect.minX + 16,
                    y: rect.midY - textHeight / 2,
                    width: rect.width - 32,
                    height: textHeight
                ),
                withAttributes: attributes
            )
            return true
        }
    }

    private struct TerminalLayer {
        let image: CGImage
        let rect: NSRect
        let clip: NSRect
    }

    private static func terminalLayers(in root: NSView) -> [TerminalLayer] {
        var layers: [TerminalLayer] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            guard !view.isHidden, view.alphaValue > 0 else { continue }
            if let terminal = view as? GhosttySurfaceScrollView {
                let surface = terminal.surfaceView
                if let clip = WindowAppKitCapture.visibleRect(of: surface, through: root),
                   let image = terminal.debugCopyIOSurfaceCGImage() {
                    layers.append(TerminalLayer(
                        image: image,
                        rect: surface.convert(surface.bounds, to: root),
                        clip: clip
                    ))
                }
                continue
            }
            stack.append(contentsOf: view.subviews)
        }
        return layers
    }

    private static func rootRect(fromTopLeft rect: CGRect, in root: NSView) -> NSRect {
        guard !root.isFlipped else { return rect }
        return NSRect(x: rect.minX, y: root.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
