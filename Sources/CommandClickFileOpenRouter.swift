import AppKit
import CmuxFilePreviewCore
import CmuxSettings
import Foundation

enum CommandClickFileOpenRouter {
    nonisolated static func shouldRouteInCmux(
        path: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let store = FileRouteSettingsStore(defaults: defaults)
        return store.shouldRouteMarkdown(path: path)
            || store.shouldRouteSupportedFile(path: path)
    }

    /// Whether a `path:line` link should open in File Preview at that line
    /// rather than in the external editor.
    ///
    /// Markdown and HTML routes open viewers that have no line to jump to, so
    /// those locations keep going to the editor.
    nonisolated static func shouldRouteLocationInFilePreview(
        path: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let store = FileRouteSettingsStore(defaults: defaults)
        guard !store.shouldRouteMarkdown(path: path) else { return false }
        let pathExtension = (path as NSString).pathExtension.lowercased()
        guard pathExtension != "html", pathExtension != "htm" else { return false }
        return store.shouldRouteSupportedFile(path: path)
    }

    @MainActor
    static func openInCmux(
        workspace: Workspace,
        sourcePanelId: UUID,
        filePath: String,
        location: FilePreviewTextLocation? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let store = FileRouteSettingsStore(defaults: defaults)
        if store.shouldRouteMarkdown(path: filePath),
           workspace.openOrFocusMarkdownSplit(from: sourcePanelId, filePath: filePath) != nil {
            return true
        }

        guard store.shouldRouteSupportedFile(path: filePath) else {
            return false
        }

        if TerminalHTMLFileBrowserAction(defaults: defaults).open(
            fileURL: URL(fileURLWithPath: filePath),
            sourcePanelId: sourcePanelId,
            container: workspace
        ) {
            return true
        }

        guard let preview = workspace.openOrFocusFilePreviewSplit(from: sourcePanelId, filePath: filePath) else {
            return false
        }
        if let location {
            preview.revealTextLocation(location)
        }
        return true
    }

    /// Resolve the working directory for a terminal surface, preferring the
    /// per-panel directory, then the panel's requested working directory,
    /// then the workspace-level directory.
    @MainActor
    static func resolveWorkingDirectory(
        workspace: Workspace,
        surfaceId: UUID
    ) -> String? {
        if let dir = workspace.panelDirectories[surfaceId]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !dir.isEmpty {
            return dir
        }
        if let dir = workspace.terminalPanel(for: surfaceId)?
            .requestedWorkingDirectory?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !dir.isEmpty {
            return dir
        }
        let dir = workspace.currentDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return dir.isEmpty ? nil : dir
    }

    /// Schedule a file open in cmux, deferred to the next runloop tick.
    ///
    /// Ghostty's `Surface.openUrl` holds an internal `os_unfair_lock` when it
    /// dispatches into Swift; opening a new panel synchronously re-enters
    /// Ghostty and deadlocks (#3370). This helper defers the split creation
    /// via `DispatchQueue.main.async` and re-validates the workspace and path
    /// at dispatch time (TOCTOU). When routing fails, `fallback` is called so
    /// the caller can open the file externally.
    @MainActor
    static func deferredOpenFileInCmux(
        workspace: Workspace,
        preferredWorkspaceId: UUID,
        surfaceId: UUID,
        filePath: String,
        location: FilePreviewTextLocation? = nil,
        defaults: UserDefaults = .standard,
        fallback: (@MainActor @Sendable () -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            let resolvedWorkspace = AppDelegate.shared?.workspaceContainingPanel(
                panelId: surfaceId,
                preferredWorkspaceId: preferredWorkspaceId
            )?.workspace ?? workspace
            guard !resolvedWorkspace.isRemoteTerminalSurface(surfaceId) else {
                fallback?()
                return
            }
            guard shouldRouteInCmux(path: filePath, defaults: defaults) else {
                fallback?()
                return
            }
            if openInCmux(
                workspace: resolvedWorkspace,
                sourcePanelId: surfaceId,
                filePath: filePath,
                location: location,
                defaults: defaults
            ) {
                return
            }
            fallback?()
        }
    }
}
