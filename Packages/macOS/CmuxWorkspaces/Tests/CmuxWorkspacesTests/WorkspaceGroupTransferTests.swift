import Foundation
import Testing
@testable import CmuxWorkspaces

@MainActor
@Suite("Cross-window workspace group transfer")
struct WorkspaceGroupTransferTests {
    private func makeGroup(
        anchor: CoordinatorStubTab,
        isPinned: Bool = false,
        name: String = "Build"
    ) -> WorkspaceGroup {
        WorkspaceGroup(
            id: UUID(),
            name: name,
            isCollapsed: true,
            isPinned: isPinned,
            anchorWorkspaceId: anchor.id,
            customColor: "#FF8800",
            iconSymbol: "hammer.fill",
            externalID: "ci"
        )
    }

    /// Simulates the window move: detach every transferred member from the
    /// source (as TabManager does) and attach it to the destination.
    private func moveMembers(
        _ transfer: WorkspaceGroupTransfer,
        from source: WorkspacesModel<CoordinatorStubTab>,
        to destination: WorkspacesModel<CoordinatorStubTab>
    ) {
        for id in transfer.memberIds {
            guard let index = source.tabs.firstIndex(where: { $0.id == id }) else { continue }
            let tab = source.tabs.remove(at: index)
            source.dissolveGroupsAnchoredBy(closedWorkspaceId: tab.id)
            destination.tabs.append(tab)
        }
    }

    @Test("A released group keeps its record and anchor-first members")
    func releaseReturnsGroupAndMembers() throws {
        let source = WorkspacesModel<CoordinatorStubTab>()
        let other = CoordinatorStubTab()
        let anchor = CoordinatorStubTab()
        let member = CoordinatorStubTab()
        let group = makeGroup(anchor: anchor)
        anchor.groupId = group.id
        member.groupId = group.id
        source.tabs = [other, member, anchor]
        source.workspaceGroups = [group]

        let transfer = try #require(source.releaseWorkspaceGroupForTransfer(groupId: group.id))

        #expect(transfer.group == group)
        #expect(transfer.memberIds == [anchor.id, member.id])
        #expect(source.workspaceGroups.isEmpty)
        #expect(anchor.groupId == nil)
        #expect(member.groupId == nil)
    }

    @Test("An unpinned group arrives intact instead of dissolving")
    func unpinnedGroupSurvivesMove() throws {
        let source = WorkspacesModel<CoordinatorStubTab>()
        let destination = WorkspacesModel<CoordinatorStubTab>()
        let anchor = CoordinatorStubTab()
        let member = CoordinatorStubTab()
        let stay = CoordinatorStubTab()
        let resident = CoordinatorStubTab()
        let group = makeGroup(anchor: anchor)
        anchor.groupId = group.id
        member.groupId = group.id
        source.tabs = [anchor, member, stay]
        source.workspaceGroups = [group]
        destination.tabs = [resident]

        let transfer = try #require(source.releaseWorkspaceGroupForTransfer(groupId: group.id))
        moveMembers(transfer, from: source, to: destination)
        #expect(destination.adoptTransferredWorkspaceGroup(transfer))

        #expect(source.tabs.map(\.id) == [stay.id])
        #expect(source.workspaceGroups.isEmpty)
        let adopted = try #require(destination.workspaceGroups.first)
        #expect(adopted == group)
        #expect(anchor.groupId == group.id)
        #expect(member.groupId == group.id)
        let run = destination.tabs.map(\.id).filter { [anchor.id, member.id].contains($0) }
        #expect(run == [anchor.id, member.id])
    }

    @Test("A pinned group keeps its anchor rather than promoting a member")
    func pinnedGroupKeepsAnchor() throws {
        let source = WorkspacesModel<CoordinatorStubTab>()
        let destination = WorkspacesModel<CoordinatorStubTab>()
        let anchor = CoordinatorStubTab()
        let member = CoordinatorStubTab()
        let group = makeGroup(anchor: anchor, isPinned: true)
        anchor.groupId = group.id
        member.groupId = group.id
        source.tabs = [anchor, member]
        source.workspaceGroups = [group]
        destination.tabs = [CoordinatorStubTab()]

        let transfer = try #require(source.releaseWorkspaceGroupForTransfer(groupId: group.id))
        moveMembers(transfer, from: source, to: destination)
        destination.adoptTransferredWorkspaceGroup(transfer)

        #expect(source.workspaceGroups.isEmpty)
        #expect(destination.workspaceGroups.first?.liveAnchorWorkspaceId == anchor.id)
        #expect(destination.workspaceGroups.first?.isPinned == true)
        // The pinned group's run leads the destination's sidebar.
        #expect(destination.tabs.prefix(2).map(\.id) == [anchor.id, member.id])
    }

    @Test("A missing anchor promotes the first member that arrived")
    func missingAnchorPromotesArrivedMember() throws {
        let destination = WorkspacesModel<CoordinatorStubTab>()
        let anchor = CoordinatorStubTab()
        let member = CoordinatorStubTab()
        let group = makeGroup(anchor: anchor)
        destination.tabs = [member]
        let transfer = WorkspaceGroupTransfer(group: group, memberIds: [anchor.id, member.id])

        #expect(destination.adoptTransferredWorkspaceGroup(transfer))

        #expect(destination.workspaceGroups.first?.liveAnchorWorkspaceId == member.id)
        #expect(member.groupId == group.id)
    }

    @Test("A group with no arrived members survives only when pinned")
    func emptyGroupSurvivesOnlyWhenPinned() {
        let destination = WorkspacesModel<CoordinatorStubTab>()
        destination.tabs = [CoordinatorStubTab()]
        let anchor = CoordinatorStubTab()
        let unpinned = WorkspaceGroupTransfer(group: makeGroup(anchor: anchor), memberIds: [anchor.id])
        let pinned = WorkspaceGroupTransfer(group: makeGroup(anchor: anchor, isPinned: true), memberIds: [anchor.id])

        #expect(!destination.adoptTransferredWorkspaceGroup(unpinned))
        #expect(destination.adoptTransferredWorkspaceGroup(pinned))

        #expect(destination.workspaceGroups.count == 1)
        #expect(destination.workspaceGroups.first?.isEmpty == true)
    }
}
