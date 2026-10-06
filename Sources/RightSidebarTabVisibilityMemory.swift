import Foundation

/// Remembers, per tab (panel id), whether the right sidebar is shown.
///
/// Owned by the tab's `Workspace`, so the memory is saved with the session and
/// dropped when the tab closes. A reference type so the window's
/// `FileExplorerState` can record a toggle against the focused tab the moment
/// it happens instead of waiting for a view update.
final class RightSidebarTabVisibilityMemory {
    private var visibilityByPanelId: [UUID: Bool] = [:]

    /// The remembered state for `panelId`, or `nil` when the tab has never been
    /// focused with a right sidebar state to remember.
    func visibility(forPanelId panelId: UUID) -> Bool? {
        visibilityByPanelId[panelId]
    }

    func record(_ isVisible: Bool, forPanelId panelId: UUID) {
        visibilityByPanelId[panelId] = isVisible
    }

    func forget(panelId: UUID) {
        visibilityByPanelId.removeValue(forKey: panelId)
    }
}
