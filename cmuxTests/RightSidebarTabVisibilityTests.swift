import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The right sidebar's show/hide state belongs to the focused tab.
/// Serialized because `FileExplorerState` persists its last value to `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct RightSidebarTabVisibilityTests {
    private static let visibilityKey = "fileExplorer.isVisible"

    private func withState(initiallyVisible: Bool, _ body: (FileExplorerState) -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Self.visibilityKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: Self.visibilityKey)
            } else {
                defaults.removeObject(forKey: Self.visibilityKey)
            }
        }
        defaults.set(initiallyVisible, forKey: Self.visibilityKey)
        body(FileExplorerState())
    }

    @Test func togglingOnlyAffectsTheFocusedTab() {
        withState(initiallyVisible: true) { state in
            let memory = RightSidebarTabVisibilityMemory()
            let first = UUID()
            let second = UUID()

            state.activateTab(panelId: first, memory: memory)
            state.activateTab(panelId: second, memory: memory)
            state.toggle()
            #expect(state.isVisible == false)

            state.activateTab(panelId: first, memory: memory)
            #expect(state.isVisible == true)

            state.activateTab(panelId: second, memory: memory)
            #expect(state.isVisible == false)
        }
    }

    @Test func newTabInheritsTheStateShowingWhenItIsFirstFocused() {
        withState(initiallyVisible: false) { state in
            let memory = RightSidebarTabVisibilityMemory()
            let opener = UUID()
            let opened = UUID()

            state.activateTab(panelId: opener, memory: memory)
            state.setVisible(true)
            state.activateTab(panelId: opened, memory: memory)

            #expect(state.isVisible == true)
            #expect(memory.visibility(forPanelId: opened) == true)
        }
    }

    @Test func focusingATabAppliesWhatItsWorkspaceRemembers() {
        withState(initiallyVisible: true) { state in
            let restored = RightSidebarTabVisibilityMemory()
            let tab = UUID()
            restored.record(false, forPanelId: tab)

            state.activateTab(panelId: tab, memory: restored)

            #expect(state.isVisible == false)
        }
    }

    @Test func everyVisibilityWriteIsRecordedForTheFocusedTab() {
        withState(initiallyVisible: false) { state in
            let memory = RightSidebarTabVisibilityMemory()
            let tab = UUID()
            state.activateTab(panelId: tab, memory: memory)

            state.setVisible(true)
            #expect(memory.visibility(forPanelId: tab) == true)

            state.isVisible = false
            #expect(memory.visibility(forPanelId: tab) == false)
        }
    }

    @Test func tabsInDifferentWorkspacesKeepSeparateMemories() {
        withState(initiallyVisible: true) { state in
            let firstWorkspace = RightSidebarTabVisibilityMemory()
            let secondWorkspace = RightSidebarTabVisibilityMemory()
            let firstTab = UUID()
            let secondTab = UUID()

            state.activateTab(panelId: firstTab, memory: firstWorkspace)
            state.activateTab(panelId: secondTab, memory: secondWorkspace)
            state.setVisible(false)

            #expect(firstWorkspace.visibility(forPanelId: firstTab) == true)
            #expect(secondWorkspace.visibility(forPanelId: secondTab) == false)
            #expect(firstWorkspace.visibility(forPanelId: secondTab) == nil)
        }
    }

    @Test func closedTabIsForgotten() {
        let memory = RightSidebarTabVisibilityMemory()
        let tab = UUID()
        memory.record(true, forPanelId: tab)

        memory.forget(panelId: tab)

        #expect(memory.visibility(forPanelId: tab) == nil)
    }

    @Test(arguments: [true, false])
    func sessionSnapshotRoundTripsTheTabState(isVisible: Bool) throws {
        var snapshot = Self.panelSnapshot()
        snapshot.rightSidebarVisible = isVisible

        let decoded = try JSONDecoder().decode(
            SessionPanelSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.rightSidebarVisible == isVisible)
    }

    @Test func snapshotWithoutTheFieldDecodesAsUnremembered() throws {
        let legacy = try JSONEncoder().encode(Self.panelSnapshot())
        let object = try #require(try JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        #expect(object["rightSidebarVisible"] == nil)

        let decoded = try JSONDecoder().decode(SessionPanelSnapshot.self, from: legacy)

        #expect(decoded.rightSidebarVisible == nil)
    }

    private static func panelSnapshot() -> SessionPanelSnapshot {
        SessionPanelSnapshot(
            id: UUID(),
            type: .terminal,
            isPinned: false,
            isManuallyUnread: false,
            listeningPorts: []
        )
    }
}
