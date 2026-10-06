import AppKit

@MainActor
extension FileExplorerPanelView.Coordinator {
    /// The selected rows as Quick Look items, or `nil` when nothing previewable is selected.
    func quickLookItems(in outlineView: NSOutlineView) -> FileExplorerQuickLookItems? {
        let selectedPaths = outlineView.selectedRowIndexes.compactMap { row in
            (outlineView.item(atRow: row) as? FileExplorerNode)?.path
        }
        return FileExplorerQuickLookItems(
            selectedPaths: selectedPaths,
            anchorPath: store.selectedPath,
            isLocal: store.provider is LocalFileExplorerProvider
        )
    }

    func toggleQuickLook(in outlineView: NSOutlineView) {
        quickLook.toggle(quickLookItems(in: outlineView))
    }

    /// Keeps an open Quick Look panel on the tree's selection.
    func quickLookSelectionDidChange(in outlineView: NSOutlineView) {
        guard quickLook.isPresenting else { return }
        quickLook.selectionDidChange(quickLookItems(in: outlineView))
    }

    /// Lets the arrow keys move the tree's selection while the Quick Look panel is the key window.
    func handleQuickLookKeyDown(_ event: NSEvent) -> Bool {
        guard let outlineView,
              let delta = RightSidebarKeyboardNavigation.moveDelta(for: event) else { return false }
        moveSelection(in: outlineView, by: delta)
        return true
    }

    @objc func contextMenuQuickLook(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? FileExplorerNode else { return }
        quickLook.show(
            FileExplorerQuickLookItems(
                selectedPaths: [node.path],
                anchorPath: node.path,
                isLocal: store.provider is LocalFileExplorerProvider
            )
        )
    }
}
