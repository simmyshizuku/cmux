import AppKit
import Bonsplit

/// Swaps a native workspace drag's row images for a tear-off thumbnail while
/// the pointer is outside every cmux window, and puts them back when it
/// returns. The row image grows into the thumbnail around the pointer, the
/// same transition pane tab drags use. One instance serves one native drag.
@MainActor
final class SidebarWorkspaceDragImageSwap {
    private struct SavedItem {
        let originFromPointer: CGVector
        let size: NSSize
        let imageComponentsProvider: (() -> [NSDraggingImageComponent])?
    }

    private var savedItems: [SavedItem]?
    private var savedAnimatesToStart: Bool?
    private let resizeAnimation = DraggingImageResizeAnimation()

    /// Shows `preview` as the drag image, or restores the rows' own images
    /// when `preview` is `nil`. Repeated calls in the same state are no-ops,
    /// so it is safe to call on every pointer move.
    func update(
        session: NSDraggingSession,
        screenPoint: NSPoint,
        preview: (image: NSImage, size: NSSize)?
    ) {
        if let preview {
            guard savedItems == nil else { return }
            var saved: [SavedItem] = []
            // Frames are in screen coordinates when no view is given.
            enumerateItems(of: session) { item, index in
                let frame = item.draggingFrame
                saved.append(SavedItem(
                    originFromPointer: CGVector(dx: frame.minX - screenPoint.x, dy: frame.minY - screenPoint.y),
                    size: frame.size,
                    imageComponentsProvider: item.imageComponentsProvider
                ))
                if index > 0 {
                    // Extra selected rows fold into the one thumbnail.
                    item.setDraggingFrame(NSRect(origin: screenPoint, size: .zero), contents: nil)
                }
            }
            savedItems = saved
            // A release out here tears off; AppKit's failed-drop slide back to
            // the row would play before the window appears.
            savedAnimatesToStart = session.animatesToStartingPositionsOnCancelOrFail
            session.animatesToStartingPositionsOnCancelOrFail = false
            resizeAnimation.start(
                session: session,
                image: preview.image,
                from: saved.first?.size ?? preview.size,
                to: preview.size
            )
        } else if let savedItems {
            resizeAnimation.cancel()
            enumerateItems(of: session) { item, index in
                guard savedItems.indices.contains(index) else { return }
                let saved = savedItems[index]
                item.draggingFrame = NSRect(
                    x: screenPoint.x + saved.originFromPointer.dx,
                    y: screenPoint.y + saved.originFromPointer.dy,
                    width: saved.size.width,
                    height: saved.size.height
                )
                item.imageComponentsProvider = saved.imageComponentsProvider
            }
            self.savedItems = nil
            if let savedAnimatesToStart {
                session.animatesToStartingPositionsOnCancelOrFail = savedAnimatesToStart
                self.savedAnimatesToStart = nil
            }
        }
    }

    /// Stops a running transition when the drag ends.
    func cancel() {
        resizeAnimation.cancel()
    }

    private func enumerateItems(
        of session: NSDraggingSession,
        _ body: (NSDraggingItem, Int) -> Void
    ) {
        session.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSPasteboardItem.self],
            searchOptions: [:]
        ) { item, index, _ in
            body(item, index)
        }
    }
}
