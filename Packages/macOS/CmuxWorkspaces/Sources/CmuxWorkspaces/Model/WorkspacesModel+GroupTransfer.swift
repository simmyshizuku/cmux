public import Foundation

/// A workspace group lifted out of one window so another window can adopt
/// it with its identity, name, color, icon, pin and collapse state intact.
public struct WorkspaceGroupTransfer: Equatable, Sendable {
    /// The group record as it was in the source window.
    public let group: WorkspaceGroup
    /// The member workspaces, anchor first, then in sidebar order.
    public let memberIds: [UUID]
}

// Cross-window group moves. Detaching a group anchor normally dissolves an
// unpinned group or promotes a member of a pinned one; a transfer instead
// releases the group record first, so the members can be detached as plain
// workspaces and the destination re-forms the same group around them.
extension WorkspacesModel {
    /// Removes a group from this window for transfer to another.
    ///
    /// The group record is removed and its members become ungrouped, but they
    /// stay in `tabs`; the caller detaches them. Nothing else is renormalized,
    /// since the members are about to leave.
    ///
    /// - Parameter groupId: The group to release.
    /// - Returns: The transfer, or `nil` if no such group exists.
    public func releaseWorkspaceGroupForTransfer(groupId: UUID) -> WorkspaceGroupTransfer? {
        guard let group = workspaceGroups.first(where: { $0.id == groupId }) else { return nil }
        let members = anchorFirst(tabs.filter { $0.groupId == groupId }, anchorId: group.anchorWorkspaceId)
        workspaceGroups.removeAll { $0.id == groupId }
        for member in members {
            member.groupId = nil
        }
        return WorkspaceGroupTransfer(group: group, memberIds: members.map(\.id))
    }

    /// Re-forms a transferred group around member workspaces already
    /// attached to this window.
    ///
    /// Members that did not arrive are left out. When the original anchor is
    /// missing, the first arrived member becomes the anchor. A group whose
    /// members all failed to arrive survives only if it is pinned, as an
    /// empty header, matching how a pinned group outlives its last member.
    ///
    /// - Parameter transfer: The transfer released by the source window.
    /// - Returns: `true` when the group now exists in this window.
    @discardableResult
    public func adoptTransferredWorkspaceGroup(_ transfer: WorkspaceGroupTransfer) -> Bool {
        guard !workspaceGroups.contains(where: { $0.id == transfer.group.id }) else { return false }
        let tabsById = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let arrived = transfer.memberIds.compactMap { tabsById[$0] }
        var group = transfer.group
        if let firstArrived = arrived.first {
            if !arrived.contains(where: { $0.id == group.liveAnchorWorkspaceId }) {
                group.anchor = .workspace(firstArrived.id)
                group.anchorWorkspaceProvenance = .user
            }
        } else {
            guard group.isPinned else { return false }
            group.anchor = .empty(group.id)
            group.anchorWorkspaceProvenance = .unknown
        }
        workspaceGroups.append(group)
        for member in arrived {
            member.groupId = group.id
        }
        normalizeWorkspaceGroupContiguity()
        return true
    }
}
