import AppKit
import Bonsplit
import CmuxWindowing
import Foundation

/// Tearing a pane tab or sidebar workspace off into its own window, the way
/// Safari handles a tab dragged out of its window: past the window edge the
/// drag becomes a thumbnail of the new window, and on release the window
/// grows out of that thumbnail.
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
        return TabDragDetachedPreview(
            image: preview.image,
            frame: preview.thumbnailFrame(at: context.screenPoint)
        )
    }

    /// Moves a pane tab into a new window placed so the pointer lands on the
    /// tab, growing it out of the drag thumbnail.
    ///
    /// A tab that is its workspace's only surface carries the whole
    /// workspace, so it tears off through ``tearOffWorkspaces(_:atScreenPoint:pointerOffsetInWindow:)``.
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
        // In the new window the tab is the first tab of a pane that fills
        // the workspace area, which sits where the source's does.
        let container = sourceWorkspace.bonsplitController.layoutSnapshot().containerFrame
        let pointerOffsetInWindow = CGSize(
            width: CGFloat(container.x) + context.pointerOffsetInPane.width,
            height: CGFloat(container.y) + context.pointerOffsetInPane.height
        )
        guard sourceWorkspace.panels.count > 1 else {
            return tearOffWorkspaces(
                [located.workspaceId],
                atScreenPoint: screenPoint,
                pointerOffsetInWindow: pointerOffsetInWindow,
                preview: preview
            )
        }

        let frame = tearOffFrame(
            sourceWindowId: located.windowId,
            screenPoint: screenPoint,
            pointerOffsetInWindow: pointerOffsetInWindow
        )
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
            "newWin=\(windowId.uuidString.prefix(5)) offset=\(Int(pointerOffsetInWindow.width)),\(Int(pointerOffsetInWindow.height))"
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
        return WindowTearOffPreview(key: tabId, image: image, pointerInImage: context.pointerOffsetInPane)
    }

    // MARK: - Workspaces

    /// The drag image for a sidebar workspace outside every window: a
    /// thumbnail of its window, or `nil` while the pointer is over a window.
    ///
    /// - Parameters:
    ///   - workspaceId: The dragged workspace.
    ///   - screenPoint: The pointer in screen coordinates.
    ///   - pointerOffsetInWindow: Where the pointer lands in the new window,
    ///     from its top-left.
    func tearOffDragPreview(
        forWorkspace workspaceId: UUID,
        atScreenPoint screenPoint: NSPoint,
        pointerOffsetInWindow: CGSize
    ) -> (image: NSImage, frame: NSRect)? {
        guard shouldTearOffDrag(atScreenPoint: screenPoint) else {
            WindowTearOffPreviewCache.shared.discard()
            return nil
        }
        guard let preview = WindowTearOffPreviewCache.shared.preview(for: workspaceId, capture: {
            captureWorkspacePreview(workspaceId: workspaceId, pointerOffsetInWindow: pointerOffsetInWindow)
        }) else { return nil }
        return (preview.image, preview.thumbnailFrame(at: screenPoint))
    }

    private func captureWorkspacePreview(workspaceId: UUID, pointerOffsetInWindow: CGSize) -> WindowTearOffPreview? {
        guard let manager = tabManagerFor(tabId: workspaceId),
              let workspace = manager.tabs.first(where: { $0.id == workspaceId }),
              let windowId = windowId(for: manager),
              let window = mainWindow(for: windowId) else {
            return nil
        }
        let image = (manager.selectedTabId == workspaceId ? WindowTearOffSnapshot.image(of: window) : nil)
            ?? WindowTearOffSnapshot.placeholder(title: workspace.title, size: window.frame.size)
        return WindowTearOffPreview(key: workspaceId, image: image, pointerInImage: pointerOffsetInWindow)
    }

    /// Moves workspaces into a new window placed at `screenPoint`, keeping
    /// their sidebar order. When they are every workspace of their window,
    /// that window moves to the point instead, since tearing off everything
    /// would leave an empty window behind.
    ///
    /// - Parameters:
    ///   - workspaceIds: Workspaces from one window; the last one that moves
    ///     is selected. The first one is the dragged workspace whose preview
    ///     the window grows out of.
    ///   - screenPoint: The release point in screen coordinates.
    ///   - pointerOffsetInWindow: Where the pointer lands in the new window,
    ///     from its top-left.
    /// - Returns: `true` when at least one workspace now lives at the point.
    @discardableResult
    func tearOffWorkspaces(
        _ workspaceIds: [UUID],
        atScreenPoint screenPoint: NSPoint,
        pointerOffsetInWindow: CGSize,
        draggedWorkspaceId: UUID? = nil
    ) -> Bool {
        let preview = (draggedWorkspaceId ?? workspaceIds.first)
            .flatMap { WindowTearOffPreviewCache.shared.take(for: $0) }
        return tearOffWorkspaces(
            workspaceIds,
            atScreenPoint: screenPoint,
            pointerOffsetInWindow: pointerOffsetInWindow,
            preview: preview
        )
    }

    private func tearOffWorkspaces(
        _ workspaceIds: [UUID],
        atScreenPoint screenPoint: NSPoint,
        pointerOffsetInWindow: CGSize,
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
        let frame = tearOffFrame(
            sourceWindowId: sourceWindowId,
            screenPoint: screenPoint,
            pointerOffsetInWindow: pointerOffsetInWindow
        )

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

    /// Frame for a torn-off window: the source window's size, on the display
    /// under the release point, with the pointer at `pointerOffsetInWindow`.
    private func tearOffFrame(
        sourceWindowId: UUID,
        screenPoint: NSPoint,
        pointerOffsetInWindow: CGSize
    ) -> NSRect {
        let sourceSize = mainWindow(for: sourceWindowId)?.frame.size
            ?? NSSize(width: 1_000, height: 700)
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) }
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame
            ?? NSRect(origin: .zero, size: sourceSize)
        return WindowTearOffPlacement(pointerOffsetFromTopLeft: pointerOffsetInWindow).frame(
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

/// A full-size tear-off preview and where the pointer sits in it.
struct WindowTearOffPreview {
    /// The dragged tab or workspace.
    let key: UUID
    let image: NSImage
    /// The pointer's offset from the image's top-left, in image points.
    let pointerInImage: CGSize

    /// The thumbnail's screen frame with the pointer at `screenPoint`.
    func thumbnailFrame(at screenPoint: NSPoint) -> NSRect {
        WindowTearOffPlacement().thumbnailFrame(
            imageSize: image.size,
            pointerInImage: pointerInImage,
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
