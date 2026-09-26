import AppKit
import Bonsplit
import CmuxWindowing
import Foundation

/// Tearing a pane tab or sidebar workspace off into its own window, the way
/// Safari handles a tab dragged out of its window: past the window edge the
/// drag grows into a thumbnail of the new window centered on the pointer,
/// and on release the window grows out of that thumbnail from its center.
///
/// Both drag sources ask for the same preview while they are outside every
/// cmux window and report the same release; this is the single action path
/// they share. Merging back into an existing window is not handled here:
/// dropping onto another window's pane or sidebar already routes through
/// the ordinary cross-window moves.
@MainActor
extension AppDelegate {
    /// Reports whether a drag at `screenPoint` is outside every visible main
    /// window, which is where it previews and tears off.
    func shouldTearOffDrag(atScreenPoint screenPoint: NSPoint) -> Bool {
        let frames = mainWindowContexts.values.compactMap { context -> NSRect? in
            guard let window = context.window,
                  window.isVisible,
                  !window.isMiniaturized else { return nil }
            return window.frame
        }
        return WindowTearOffPlacement().shouldTearOff(at: screenPoint, mainWindowFrames: frames)
    }

    // MARK: - Pane tabs

    /// The drag image for a pane tab outside every window: a thumbnail of its
    /// pane, or `nil` while the pointer is over a window.
    func tearOffDragPreview(forBonsplitTab context: TabDragDetachContext) -> TabDragDetachedPreview? {
        let tabId = context.tab.id.uuid
        guard shouldTearOffDrag(atScreenPoint: context.screenPoint) else {
            WindowTearOffPreviewCache.shared.discard()
            return nil
        }
        guard let preview = WindowTearOffPreviewCache.shared.preview(for: tabId, capture: {
            capturePanePreview(tabId: tabId, context: context)
        }) else { return nil }
        return TabDragDetachedPreview(image: preview.image, size: preview.thumbnailSize)
    }

    /// Moves a pane tab into a new window centered on the pointer, growing it
    /// out of the drag thumbnail.
    ///
    /// A tab that is its workspace's only surface carries the whole
    /// workspace, so it tears off through ``tearOffWorkspaces(_:atScreenPoint:draggedWorkspaceId:)``.
    ///
    /// - Returns: `true` when the tab now lives in a new or moved window.
    @discardableResult
    func tearOffBonsplitTab(_ context: TabDragDetachContext) -> Bool {
        let tabId = context.tab.id.uuid
        let screenPoint = context.screenPoint
        let preview = WindowTearOffPreviewCache.shared.take(for: tabId)
        guard shouldTearOffDrag(atScreenPoint: screenPoint),
              let located = locateBonsplitSurface(tabId: tabId),
              let sourceWorkspace = located.tabManager.tabs.first(where: { $0.id == located.workspaceId }) else {
            return false
        }
        guard sourceWorkspace.panels.count > 1 else {
            return tearOffWorkspaces([located.workspaceId], atScreenPoint: screenPoint, preview: preview)
        }

        let frame = tearOffFrame(sourceWindowId: located.windowId, screenPoint: screenPoint)
        let windowId = createMainWindow(initialFrame: frame)
        guard let destinationManager = tabManagerFor(windowId: windowId) else { return false }
        growTornOffWindow(windowId, from: preview, at: screenPoint)
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

    private func capturePanePreview(tabId: UUID, context: TabDragDetachContext) -> WindowTearOffPreview? {
        guard let located = locateBonsplitSurface(tabId: tabId),
              let workspace = located.tabManager.tabs.first(where: { $0.id == located.workspaceId }),
              let window = mainWindow(for: located.windowId) else {
            return nil
        }
        let pane = workspace.bonsplitController.layoutSnapshot().panes.first {
            $0.paneId == context.sourcePaneId.id.uuidString
        }
        let paneRect = pane.map {
            CGRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: $0.frame.height)
        }
        let isOnScreen = located.tabManager.selectedTabId == workspace.id
            && pane?.selectedTabId == tabId.uuidString
        let image = (isOnScreen ? paneRect : nil).flatMap {
            WindowTearOffSnapshot.image(of: window, rectFromTopLeft: $0)
        } ?? WindowTearOffSnapshot.placeholder(
            title: context.tab.title,
            size: paneRect?.size ?? window.frame.size
        )
        return WindowTearOffPreview(key: tabId, image: image)
    }

    // MARK: - Workspaces

    /// The drag image for a sidebar workspace outside every window: a
    /// thumbnail of its window and its on-screen size, or `nil` while the
    /// pointer is over a window.
    func tearOffDragPreview(
        forWorkspace workspaceId: UUID,
        atScreenPoint screenPoint: NSPoint
    ) -> (image: NSImage, size: NSSize)? {
        guard shouldTearOffDrag(atScreenPoint: screenPoint) else {
            WindowTearOffPreviewCache.shared.discard()
            return nil
        }
        guard let preview = WindowTearOffPreviewCache.shared.preview(for: workspaceId, capture: {
            captureWorkspacePreview(workspaceId: workspaceId)
        }) else { return nil }
        return (preview.image, preview.thumbnailSize)
    }

    /// Captures a dragged sidebar row: the window itself when the row's
    /// workspace is the one on screen, otherwise a titled card. A group
    /// header drag (its anchor's id, or an empty group's own id) is titled
    /// with the group name.
    private func captureWorkspacePreview(workspaceId: UUID) -> WindowTearOffPreview? {
        let group = workspaceGroupIdForHeaderDrag(workspaceId).flatMap { groupId in
            tabManagerFor(workspaceGroupId: groupId)?.workspaceGroups.first { $0.id == groupId }
        }
        guard let manager = tabManagerFor(tabId: workspaceId)
                ?? group.flatMap({ tabManagerFor(workspaceGroupId: $0.id) }),
              let windowId = windowId(for: manager),
              let window = mainWindow(for: windowId) else {
            return nil
        }
        let title = group?.name
            ?? manager.tabs.first(where: { $0.id == workspaceId })?.title
            ?? ""
        let image = (manager.selectedTabId == workspaceId ? WindowTearOffSnapshot.image(of: window) : nil)
            ?? WindowTearOffSnapshot.placeholder(title: title, size: window.frame.size)
        return WindowTearOffPreview(key: workspaceId, image: image)
    }

    /// Moves a whole workspace group into a new window centered on
    /// `screenPoint`, growing it out of the drag thumbnail. When the group is
    /// everything its window holds, that window moves instead.
    ///
    /// - Parameters:
    ///   - groupId: The group to tear off.
    ///   - screenPoint: The release point in screen coordinates.
    ///   - draggedId: The dragged header's identity, which keys its preview.
    /// - Returns: `true` when the group now lives at the point.
    @discardableResult
    func tearOffWorkspaceGroup(_ groupId: UUID, atScreenPoint screenPoint: NSPoint, draggedId: UUID) -> Bool {
        let preview = WindowTearOffPreviewCache.shared.take(for: draggedId)
        guard shouldTearOffDrag(atScreenPoint: screenPoint),
              let sourceManager = tabManagerFor(workspaceGroupId: groupId),
              let sourceWindowId = windowId(for: sourceManager) else {
            return false
        }
        let frame = tearOffFrame(sourceWindowId: sourceWindowId, screenPoint: screenPoint)
        let memberCount = sourceManager.tabs.filter { $0.groupId == groupId }.count
        if memberCount > 0, memberCount == sourceManager.tabs.count {
            guard let window = mainWindow(for: sourceWindowId) else { return false }
            window.setFrame(frame, display: true)
            growTornOffWindow(sourceWindowId, from: preview, at: screenPoint)
            _ = focusMainWindow(windowId: sourceWindowId)
            return true
        }

        let windowId = createMainWindow(initialFrame: frame)
        guard let destinationManager = tabManagerFor(windowId: windowId) else { return false }
        growTornOffWindow(windowId, from: preview, at: screenPoint)
        let bootstrapWorkspaceId = destinationManager.tabs.first?.id
        guard moveWorkspaceGroupToWindow(groupId: groupId, windowId: windowId, focus: true) else {
            _ = closeMainWindow(windowId: windowId, recordHistory: false)
            return false
        }
        closeBootstrapWorkspace(bootstrapWorkspaceId, in: destinationManager)
#if DEBUG
        cmuxDebugLog(
            "tearOff.group group=\(groupId.uuidString.prefix(5)) members=\(memberCount) " +
            "sourceWin=\(sourceWindowId.uuidString.prefix(5)) newWin=\(windowId.uuidString.prefix(5))"
        )
#endif
        return true
    }

    /// Moves workspaces into a new window centered on `screenPoint`, keeping
    /// their sidebar order. When they are every workspace of their window,
    /// that window moves to the point instead, since tearing off everything
    /// would leave an empty window behind.
    ///
    /// - Parameters:
    ///   - workspaceIds: Workspaces from one window; the last one that moves
    ///     is selected.
    ///   - screenPoint: The release point in screen coordinates.
    ///   - draggedWorkspaceId: The workspace whose drag preview the window
    ///     grows out of, if not the first.
    /// - Returns: `true` when at least one workspace now lives at the point.
    @discardableResult
    func tearOffWorkspaces(
        _ workspaceIds: [UUID],
        atScreenPoint screenPoint: NSPoint,
        draggedWorkspaceId: UUID? = nil
    ) -> Bool {
        let preview = (draggedWorkspaceId ?? workspaceIds.first)
            .flatMap { WindowTearOffPreviewCache.shared.take(for: $0) }
        return tearOffWorkspaces(workspaceIds, atScreenPoint: screenPoint, preview: preview)
    }

    private func tearOffWorkspaces(
        _ workspaceIds: [UUID],
        atScreenPoint screenPoint: NSPoint,
        preview: WindowTearOffPreview?
    ) -> Bool {
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
            growTornOffWindow(sourceWindowId, from: preview, at: screenPoint)
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
        growTornOffWindow(newWindowId, from: preview, at: screenPoint)
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

    // MARK: - Shared

    /// Frame for a torn-off window: the source window's size, centered on the
    /// release point and kept on the display under it.
    private func tearOffFrame(sourceWindowId: UUID, screenPoint: NSPoint) -> NSRect {
        let sourceSize = mainWindow(for: sourceWindowId)?.frame.size
            ?? NSSize(width: 1_000, height: 700)
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) }
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame
            ?? NSRect(origin: .zero, size: sourceSize)
        let centered = CGSize(width: sourceSize.width / 2, height: sourceSize.height / 2)
        return WindowTearOffPlacement(pointerOffsetFromTopLeft: centered).frame(
            forWindowSize: sourceSize,
            releasedAt: screenPoint,
            visibleFrame: visibleFrame
        )
    }

    /// Hides a torn-off window and grows its preview from the drag thumbnail
    /// into the window's frame, then reveals the window. Without a preview
    /// the window simply appears.
    private func growTornOffWindow(_ windowId: UUID, from preview: WindowTearOffPreview?, at screenPoint: NSPoint) {
        guard let preview, let window = mainWindow(for: windowId) else { return }
        WindowTearOffGrowAnimation.run(
            image: preview.image,
            from: preview.thumbnailFrame(at: screenPoint),
            into: window
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

/// A full-size tear-off preview. Its thumbnail, like the window that grows
/// out of it, is centered on the pointer.
struct WindowTearOffPreview {
    /// The dragged tab or workspace.
    let key: UUID
    let image: NSImage

    /// The thumbnail's on-screen size.
    var thumbnailSize: NSSize {
        thumbnailFrame(at: .zero).size
    }

    /// The thumbnail's screen frame, centered on `screenPoint`.
    func thumbnailFrame(at screenPoint: NSPoint) -> NSRect {
        WindowTearOffPlacement().thumbnailFrame(
            imageSize: image.size,
            pointerInImage: CGSize(width: image.size.width / 2, height: image.size.height / 2),
            at: screenPoint
        )
    }
}

/// Holds the preview for the drag currently outside every window, so a
/// drag captures once however many times the pointer moves. Moving back
/// over a window discards it, so a later drag never reuses a stale image.
@MainActor
final class WindowTearOffPreviewCache {
    static let shared = WindowTearOffPreviewCache()

    private var current: WindowTearOffPreview?

    /// Returns the cached preview for `key`, capturing it first if needed.
    func preview(for key: UUID, capture: () -> WindowTearOffPreview?) -> WindowTearOffPreview? {
        if let current, current.key == key { return current }
        current = capture()
        return current
    }

    /// Removes and returns the preview for `key`, if it is the cached one.
    func take(for key: UUID) -> WindowTearOffPreview? {
        guard let current, current.key == key else { return nil }
        self.current = nil
        return current
    }

    func discard() {
        current = nil
    }
}

/// The Safari-style release: a borderless copy of the preview grows from the
/// drag thumbnail to the window's frame, then the real window takes over.
@MainActor
enum WindowTearOffGrowAnimation {
    static func run(image: NSImage, from startFrame: NSRect, into window: NSWindow) {
        guard !startFrame.isEmpty else { return }
        window.alphaValue = 0

        let overlay = NSWindow(contentRect: startFrame, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = true
        overlay.ignoresMouseEvents = true
        overlay.level = .floating
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        overlay.contentView = imageView
        overlay.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().setFrame(window.frame, display: true)
        } completionHandler: {
            window.alphaValue = 1
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                overlay.animator().alphaValue = 0
            } completionHandler: {
                overlay.orderOut(nil)
            }
        }
    }
}
