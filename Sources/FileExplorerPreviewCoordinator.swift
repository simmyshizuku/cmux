import AppKit
import Bonsplit
import CmuxFilePreviewCore

/// Both sidebar entrypoints capture the displayed provider before suspending.
@MainActor
struct FileExplorerPreviewCoordinator {
    let store: FileExplorerStore

    /// - Parameter location: Line (and column) to reveal once the preview is open,
    ///   as from a Find in Directory result.
    func open(
        path: String,
        location: FilePreviewTextLocation? = nil,
        workspace: Workspace,
        pane: PaneID,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard store.workspaceRootIdentity == workspace.id, let provider = store.provider,
              provider.isAvailable else { return }
        let context = store.resourceContextID
        if provider is LocalFileExplorerProvider {
            guard !workspace.usesRemoteDirectoryProvenance else { return }
            let panels = workspace.openFileSurfaces(inPane: pane, filePaths: [path], focus: true,
                                                   reuseExisting: true, duplicateWhenFocused: true)
            if let location, let preview = panels.first as? FilePreviewPanel {
                preview.revealTextLocation(location)
            }
            return
        }
        guard let remoteProvider = provider as? any RemoteFileExplorerProvider else { return }
        let providerIdentity = remoteProvider.remoteIdentity
        Task { [weak workspace, store] in
            guard let workspace else { return }
            do {
                guard isCurrent(), store.resourceContextID == context else { return }
                if let cloud = provider as? CloudVMFileExplorerProvider {
                    guard let target = cloud.target else { throw FileExplorerError.providerUnavailable }
                    try target.validate(vmID: cloud.vmID)
                    if try await Self.refreshExistingRemotePreview(
                        path: path, location: location, providerIdentity: providerIdentity, workspace: workspace, pane: pane,
                        store: store, context: context, isCurrent: isCurrent,
                        validate: { try target.validate(vmID: cloud.vmID) }, provider: cloud
                    ) { return }
                    let lease = try await store.cloudPreviewCache.materialize(path: path, provider: cloud)
                    guard isCurrent(), store.resourceContextID == context else { return }
                    try target.validate(vmID: cloud.vmID)
                    // Markdown also uses the read-only file preview: its links must
                    // never resolve relative remote paths through the Mac browser.
                    if let panel = workspace.openFilePreviewSurfaces(inPane: pane, filePaths: [lease.url.path],
                        focus: true, reuseExisting: false).first {
                        panel.cloudPreviewLease = lease
                        Self.installRemotePreviewRefresh(
                            on: panel, workspace: workspace,
                            isCurrent: isCurrent, provider: cloud, vmID: cloud.vmID, target: target
                        )
                        workspace.handKeyboardFocusFromRightSidebarAfterFileOpen(to: panel)
                        if let location { panel.revealTextLocation(location) }
                    }
                } else if let remote = provider as? any RemoteFileExplorerProvider {
                    if try await Self.refreshExistingRemotePreview(
                        path: path, location: location, providerIdentity: providerIdentity, workspace: workspace, pane: pane,
                        store: store, context: context, isCurrent: isCurrent,
                        validate: {}, provider: remote
                    ) { return }
                    let lease = try await store.cloudPreviewCache.materialize(path: path, provider: remote)
                    guard isCurrent(), store.resourceContextID == context else { return }
                    if let panel = workspace.openFilePreviewSurfaces(inPane: pane, filePaths: [lease.url.path],
                        focus: true, reuseExisting: false).first {
                        panel.cloudPreviewLease = lease
                        Self.installRemotePreviewRefresh(
                            on: panel, workspace: workspace,
                            isCurrent: isCurrent, provider: remote, vmID: nil, target: nil
                        )
                        workspace.handKeyboardFocusFromRightSidebarAfterFileOpen(to: panel)
                        if let location { panel.revealTextLocation(location) }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(), store.resourceContextID == context else { return }
                Self.present(error, window: AppDelegate.shared?.mainWindowContainingWorkspace(workspace.id))
            }
        }
    }

    private static func refreshExistingRemotePreview(
        path: String,
        location: FilePreviewTextLocation?,
        providerIdentity: String,
        workspace: Workspace,
        pane: PaneID,
        store: FileExplorerStore,
        context: UUID,
        isCurrent: @escaping @MainActor () -> Bool,
        validate: @escaping @MainActor () throws -> Void,
        provider: any RemoteFileExplorerProvider
    ) async throws -> Bool {
        guard let existing = workspace.panels.values
            .compactMap({ $0 as? FilePreviewPanel })
            .first(where: {
                !$0.isClosed &&
                    $0.cloudPreviewRemotePath == path &&
                    $0.cloudPreviewProviderIdentity == providerIdentity &&
                    FileManager.default.fileExists(atPath: $0.filePath)
            }) else { return false }
        guard let lease = existing.cloudPreviewLease else { return false }
        guard !existing.isClosed else { return true }
        try validate()
        try await lease.refresh(using: provider)
        guard isCurrent(), store.resourceContextID == context, !existing.isClosed,
              workspace.panels[existing.id] != nil else { return true }
        try validate()
        _ = existing.reloadFromDisk()
        _ = workspace.openOrFocusFilePreviewSurface(inPane: pane, filePath: existing.filePath, focus: true)
        workspace.handKeyboardFocusFromRightSidebarAfterFileOpen(to: existing)
        if let location { existing.revealTextLocation(location) }
        return true
    }

    private static func installRemotePreviewRefresh(
        on panel: FilePreviewPanel,
        workspace: Workspace,
        isCurrent: @escaping @MainActor () -> Bool,
        provider: any RemoteFileExplorerProvider,
        vmID: String?,
        target: CloudFileExplorerTarget?
    ) {
        panel.remotePreviewRefresh = { [weak panel, weak workspace] in
            Task { @MainActor [weak panel, weak workspace] in
                guard let panel, let workspace, let lease = panel.cloudPreviewLease,
                      !panel.isClosed, isCurrent() else { return }
                do {
                    if let target, let vmID { try target.validate(vmID: vmID) }
                    try await lease.refresh(using: provider)
                    guard isCurrent(),
                          !panel.isClosed, workspace.panels[panel.id] != nil else { return }
                    if let target, let vmID { try target.validate(vmID: vmID) }
                    _ = panel.reloadFromDisk()
                } catch is CancellationError {
                    return
                } catch {
                    Self.present(error, window: AppDelegate.shared?.mainWindowContainingWorkspace(workspace.id))
                }
            }
        }
    }

    private static func present(_ error: Error, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "fileExplorer.preview.failedTitle", defaultValue: "Unable to open remote file")
        alert.informativeText = (error as? FileExplorerError)?.localizedDescription
            ?? String(localized: "fileExplorer.preview.genericFailure", defaultValue: "The remote file could not be downloaded. Reconnect and try again.")
        alert.addButton(withTitle: String(localized: "fileExplorer.preview.ok", defaultValue: "OK"))
        _ = alert.runCmuxModal(presentingWindow: window)
    }
}
