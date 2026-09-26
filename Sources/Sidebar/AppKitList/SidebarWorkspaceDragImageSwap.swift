import AppKit

/// Swaps a native workspace drag's row images for a tear-off thumbnail while
/// the pointer is outside every cmux window, and puts them back when it
/// returns. One instance serves one native drag session.
@MainActor
final class SidebarWorkspaceDragImageSwap {
    private struct SavedItem {
        let originFromPointer: CGVector
        let size: NSSize
        let imageComponentsProvider: (() -> [NSDraggingImageComponent])?
    }

    private var savedItems: [SavedItem]?

    /// Shows `preview` as the drag image, or restores the rows' own images
    /// when `preview` is `nil`. Repeated calls in the same state are no-ops,
    /// so it is safe to call on every pointer move.
    func update(
        session: NSDraggingSession,
        screenPoint: NSPoint,
        preview: (image: NSImage, frame: NSRect)?
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
                if index == 0 {
                    item.setDraggingFrame(preview.frame, contents: preview.image)
                } else {
                    // Extra selected rows fold into the one thumbnail.
                    item.setDraggingFrame(NSRect(origin: preview.frame.origin, size: .zero), contents: nil)
                }
            }
            savedItems = saved
        } else if let savedItems {
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
        }
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
