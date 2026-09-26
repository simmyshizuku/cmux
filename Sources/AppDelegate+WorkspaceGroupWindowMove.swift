import AppKit
import CmuxWorkspaces
import Foundation

/// Moving a whole workspace group between windows: dropping a group header
/// on another window's sidebar, or tearing it off into a new window.
///
/// Detaching a group anchor on its own would dissolve an unpinned group or
/// promote a member of a pinned one, so the source releases the group record
/// first, the members move as plain workspaces, and the destination re-forms
/// the same group (identity, name, color, icon, pin and collapse state)
/// around them.
@MainActor
extension AppDelegate {
    /// The window manager that owns a group, including an empty pinned group
    /// that no workspace index can locate.
    func tabManagerFor(workspaceGroupId groupId: UUID) -> TabManager? {
        mainWindowContexts.values
            .map(\.tabManager)
            .first { $0.workspaceGroups.contains { $0.id == groupId } }
    }

    /// The group a sidebar drag represents when it started on a group header:
    /// the header carries its live anchor's id, or the group's own id when
    /// the group is empty. `nil` for an ordinary workspace row.
    func workspaceGroupIdForHeaderDrag(_ draggedId: UUID) -> UUID? {
        for manager in mainWindowContexts.values.map(\.tabManager) {
            if let group = manager.workspaceGroups.first(where: {
                $0.liveAnchorWorkspaceId == draggedId || ($0.isEmpty && $0.id == draggedId)
            }) {
                return group.id
            }
        }
        return nil
    }

    /// Moves a group and all its members to another window.
    ///
    /// - Parameters:
    ///   - groupId: The group to move.
    ///   - windowId: The destination main window.
    ///   - atIndex: Where the members are inserted in the destination's
    ///     workspace list, or `nil` for the end. Pinned groups still lead.
    ///   - focus: Whether to select the group's anchor and focus the window.
    /// - Returns: `true` when the group now lives in the destination.
    @discardableResult
    func moveWorkspaceGroupToWindow(
        groupId: UUID,
        windowId: UUID,
        atIndex: Int? = nil,
        focus: Bool = true
    ) -> Bool {
        guard let sourceManager = tabManagerFor(workspaceGroupId: groupId),
              let destinationManager = tabManagerFor(windowId: windowId) else {
            return false
        }
        guard sourceManager !== destinationManager else { return true }
        guard let transfer = sourceManager.workspaces.releaseWorkspaceGroupForTransfer(groupId: groupId) else {
            return false
        }

        var offset = 0
        for workspaceId in transfer.memberIds where moveWorkspaceToWindow(
            workspaceId: workspaceId,
            windowId: windowId,
            atIndex: atIndex.map { $0 + offset },
            focus: false
        ) {
            offset += 1
        }
        guard destinationManager.workspaces.adoptTransferredWorkspaceGroup(transfer) else {
            return false
        }
#if DEBUG
        cmuxDebugLog(
            "workspaceGroup.moveToWindow group=\(groupId.uuidString.prefix(5)) members=\(offset) " +
            "to=\(windowId.uuidString.prefix(5))"
        )
#endif
        if focus {
            if let anchorId = destinationManager.workspaceGroupAnchor(for: groupId)?.id {
                _ = moveWorkspaceToWindow(workspaceId: anchorId, windowId: windowId, focus: true)
            } else {
                _ = focusMainWindow(windowId: windowId)
            }
        }
        return true
    }
}
