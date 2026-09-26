import AppKit
import CmuxWindowing
import Foundation

/// Tearing a pane tab or sidebar workspace off into its own window, the way a
/// browser tab dragged out of its window becomes a new window.
///
/// Both drag sources report a release that no destination accepted; this is
/// the single action path they share. Merging back into an existing window
/// is not handled here: dropping onto another window's pane or sidebar
/// already routes through the ordinary cross-window moves.
@MainActor
extension AppDelegate {
    /// Reports whether a drag released at `screenPoint` should tear off,
    /// meaning the point is outside every visible main window.
    func shouldTearOffDrag(atScreenPoint screenPoint: NSPoint) -> Bool {
        let frames = mainWindowContexts.values.compactMap { context -> NSRect? in
            guard let window = context.window,
                  window.isVisible,
                  !window.isMiniaturized else { return nil }
            return window.frame
        }
        return WindowTearOffPlacement().shouldTearOff(at: screenPoint, mainWindowFrames: frames)
    }

    /// Moves a pane tab into a new window placed at `screenPoint`.
    ///
    /// A tab that is its workspace's only surface carries the whole
    /// workspace, so it tears off through ``tearOffWorkspaces(_:atScreenPoint:)``.
    ///
    /// - Returns: `true` when the tab now lives in a new or moved window.
    @discardableResult
    func tearOffBonsplitTab(tabId: UUID, atScreenPoint screenPoint: NSPoint) -> Bool {
        guard shouldTearOffDrag(atScreenPoint: screenPoint),
              let located = locateBonsplitSurface(tabId: tabId),
              let sourceWorkspace = located.tabManager.tabs.first(where: { $0.id == located.workspaceId }) else {
            return false
        }
        guard sourceWorkspace.panels.count > 1 else {
            return tearOffWorkspaces([located.workspaceId], atScreenPoint: screenPoint)
        }

        let frame = tearOffFrame(sourceWindowId: located.windowId, screenPoint: screenPoint)
        let windowId = createMainWindow(initialFrame: frame)
        guard let destinationManager = tabManagerFor(windowId: windowId) else { return false }
        let bootstrapWorkspaceId = destinationManager.tabs.first?.id
        guard moveBonsplitTabToNewWorkspace(
            tabId: tabId,
            destinationManager: destinationManager,
            focus: true,
            focusWindow: true
        ) != nil else {
            _ = closeMainWindow(windowId: windowId, recordHistory: false)
            return false
        }
        closeBootstrapWorkspace(bootstrapWorkspaceId, in: destinationManager)
#if DEBUG
        cmuxDebugLog(
            "tearOff.tab tab=\(tabId.uuidString.prefix(5)) sourceWin=\(located.windowId.uuidString.prefix(5)) " +
            "newWin=\(windowId.uuidString.prefix(5))"
        )
#endif
        return true
    }

    /// Moves workspaces into a new window placed at `screenPoint`, keeping
    /// their sidebar order. When they are every workspace of their window,
    /// that window moves to the point instead, since tearing off everything
    /// would leave an empty window behind.
    ///
    /// - Parameter workspaceIds: Workspaces from one window; the last one
    ///   that moves is selected.
    /// - Returns: `true` when at least one workspace now lives at the point.
    @discardableResult
    func tearOffWorkspaces(_ workspaceIds: [UUID], atScreenPoint screenPoint: NSPoint) -> Bool {
        guard shouldTearOffDrag(atScreenPoint: screenPoint),
              let firstId = workspaceIds.first,
              let sourceManager = tabManagerFor(tabId: firstId),
              let sourceWindowId = windowId(for: sourceManager) else {
            return false
        }
        let requested = Set(workspaceIds)
        let orderedIds = sourceManager.tabs.map(\.id).filter { requested.contains($0) }
        guard !orderedIds.isEmpty else { return false }
        let frame = tearOffFrame(sourceWindowId: sourceWindowId, screenPoint: screenPoint)

        if orderedIds.count == sourceManager.tabs.count {
            guard let window = mainWindow(for: sourceWindowId) else { return false }
            window.setFrame(frame, display: true)
            _ = focusMainWindow(windowId: sourceWindowId)
            return true
        }

        guard let newWindowId = moveWorkspaceToNewWindow(
            workspaceId: orderedIds[0],
            focus: false,
            initialFrame: frame
        ) else {
            return false
        }
        var movedIds = [orderedIds[0]]
        for workspaceId in orderedIds.dropFirst()
        where moveWorkspaceToWindow(workspaceId: workspaceId, windowId: newWindowId, focus: false) {
            movedIds.append(workspaceId)
        }
        if let focusId = movedIds.last {
            // Already attached, so this only selects it and focuses the window.
            _ = moveWorkspaceToWindow(workspaceId: focusId, windowId: newWindowId, focus: true)
        }
#if DEBUG
        cmuxDebugLog(
            "tearOff.workspaces count=\(movedIds.count) sourceWin=\(sourceWindowId.uuidString.prefix(5)) " +
            "newWin=\(newWindowId.uuidString.prefix(5))"
        )
#endif
        return true
    }

    /// Frame for a torn-off window: the source window's size, on the display
    /// under the release point.
    private func tearOffFrame(sourceWindowId: UUID, screenPoint: NSPoint) -> NSRect {
        let sourceSize = mainWindow(for: sourceWindowId)?.frame.size
            ?? NSSize(width: 1_000, height: 700)
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) }
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame
            ?? NSRect(origin: .zero, size: sourceSize)
        return WindowTearOffPlacement().frame(
            forWindowSize: sourceSize,
            releasedAt: screenPoint,
            visibleFrame: visibleFrame
        )
    }

    /// Removes the empty workspace a new window starts with once real
    /// content has arrived.
    private func closeBootstrapWorkspace(_ bootstrapWorkspaceId: UUID?, in manager: TabManager) {
        guard let bootstrapWorkspaceId,
              manager.tabs.count > 1,
              let bootstrap = manager.tabs.first(where: { $0.id == bootstrapWorkspaceId }) else {
            return
        }
        manager.closeWorkspace(bootstrap, recordHistory: false)
    }
}
