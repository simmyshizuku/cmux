import AppKit
import Bonsplit
import Foundation

extension Workspace {
    /// Shows a thumbnail of the tab's pane while its drag is outside every
    /// cmux window.
    func splitTabBar(
        _ controller: BonsplitController,
        detachedPreviewFor context: TabDragDetachContext
    ) -> TabDragDetachedPreview? {
        AppDelegate.shared?.tearOffDragPreview(forBonsplitTab: context)
    }

    /// Tears a pane tab off into a new window when it is released outside
    /// every cmux window.
    func splitTabBar(
        _ controller: BonsplitController,
        didEndTabDragWithoutDrop context: TabDragDetachContext
    ) {
        guard let app = AppDelegate.shared,
              app.shouldTearOffDrag(atScreenPoint: context.screenPoint) else { return }
        // Bonsplit reports from AppKit's drag-source completion; build the new
        // window after that callback has fully unwound.
        DispatchQueue.main.async {
            _ = AppDelegate.shared?.tearOffBonsplitTab(context)
        }
    }
}
