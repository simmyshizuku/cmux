import AppKit
import ObjectiveC
import Quartz

/// Drives the shared Quick Look panel for the file tree: Space opens and closes
/// it, and it follows the tree's selection while it is open.
@MainActor
final class FileExplorerQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var items: FileExplorerQuickLookItems?

    /// Offered key presses the panel receives while it is the key window, so
    /// the arrow keys keep moving the tree's selection. Returns whether the
    /// key was handled.
    var onKeyDown: ((NSEvent) -> Bool)?

    /// Whether the panel is on screen showing this controller's items.
    var isPresenting: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return false }
        return panel.isVisible && (panel.dataSource as AnyObject?) === self
    }

    /// Opens the panel on `items`, or closes it when it is already showing.
    func toggle(_ items: FileExplorerQuickLookItems?) {
        if isPresenting {
            dismiss()
        } else {
            show(items)
        }
    }

    /// Opens the panel on `items`, replacing whatever it shows.
    func show(_ items: FileExplorerQuickLookItems?) {
        guard let items else {
            NSSound.beep()
            return
        }
        present(items)
    }

    /// Points an open panel at a new selection. Does nothing while the panel is closed.
    func selectionDidChange(_ items: FileExplorerQuickLookItems?) {
        guard isPresenting, let items, items != self.items, let panel = QLPreviewPanel.shared() else { return }
        self.items = items
        panel.reloadData()
        panel.currentPreviewItemIndex = items.currentIndex
    }

    private func present(_ items: FileExplorerQuickLookItems) {
        guard let panel = QLPreviewPanel.shared() else { return }
        self.items = items
        // The panel does not retain its data source; keep this controller alive
        // for as long as the panel shows its items.
        objc_setAssociatedObject(
            panel as Any,
            &fileExplorerQuickLookControllerAssociationKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = items.currentIndex
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        QLPreviewPanel.shared()?.close()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            items?.urls.count ?? 0
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let urls = MainActor.assumeIsolated {
            items?.urls ?? []
        }
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return MainActor.assumeIsolated {
            onKeyDown?(event) ?? false
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel else { return }
        objc_setAssociatedObject(
            panel,
            &fileExplorerQuickLookControllerAssociationKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

// Never read or written: only its address is used, as the association key.
private nonisolated(unsafe) var fileExplorerQuickLookControllerAssociationKey: UInt8 = 0
