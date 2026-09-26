import AppKit
import Bonsplit
import Foundation

extension Workspace {
    /// Tears a pane tab off into a new window when it is released outside
    /// every cmux window.
    func splitTabBar(
        _ controller: BonsplitController,
        didEndTabDragWithoutDrop tab: Bonsplit.Tab,
        fromPane pane: PaneID,
        atScreenPoint point: NSPoint
    ) {
        guard let app = AppDelegate.shared,
              app.shouldTearOffDrag(atScreenPoint: point) else { return }
        let tabId = tab.id.uuid
        // Bonsplit reports from AppKit's drag-source completion; build the new
        // window after that callback has fully unwound.
        DispatchQueue.main.async {
            _ = AppDelegate.shared?.tearOffBonsplitTab(tabId: tabId, atScreenPoint: point)
        }
    }
}
