import CmuxFoundation
import Foundation

/// Maps filesystem change paths onto the directories a file tree has loaded.
///
/// FSEvents reports physical paths (`/private/tmp/project/a.txt`) while the tree
/// may spell its root through a symlink (`/tmp/project`), so changed paths are
/// re-rooted onto the tree's spelling before they are matched.
struct FileExplorerChangeScope: Equatable, Sendable {
    /// The root as the tree spells it.
    let rootPath: String
    /// The root with symlinks resolved.
    let resolvedRootPath: String

    init(rootPath: String, resolvedRootPath: String) {
        self.rootPath = rootPath
        self.resolvedRootPath = resolvedRootPath
    }

    init(rootPath: String) {
        self.init(rootPath: rootPath, resolvedRootPath: Self.resolvedPath(rootPath) ?? rootPath)
    }

    /// The loaded directories whose listing `change` may have altered: each
    /// changed path itself and its parent. When history was dropped, or a path
    /// cannot be placed under the root, every loaded directory is returned.
    func directoriesToRefresh(
        for change: RecursivePathChange,
        loadedDirectories: Set<String>
    ) -> Set<String> {
        guard !change.requiresFullRescan else { return loadedDirectories }
        var directories: Set<String> = []
        for changedPath in change.paths {
            guard let treePath = treePath(forChangedPath: changedPath) else { return loadedDirectories }
            let parentPath = (treePath as NSString).deletingLastPathComponent
            for candidate in [treePath, parentPath] where loadedDirectories.contains(candidate) {
                directories.insert(candidate)
            }
        }
        return directories
    }

    /// `changedPath` re-rooted onto the tree's spelling, or `nil` when it lies outside the root.
    func treePath(forChangedPath changedPath: String) -> String? {
        let path = Self.withoutTrailingSlashes(changedPath)
        let treeBase = rootPath == "/" ? "" : rootPath
        for prefix in [resolvedRootPath, rootPath] {
            if path == prefix { return rootPath }
            let base = prefix == "/" ? "" : prefix
            if path.hasPrefix(base + "/") {
                return treeBase + String(path.dropFirst(base.count))
            }
        }
        return nil
    }

    private static func withoutTrailingSlashes(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    // `URL.resolvingSymlinksInPath()` strips `/private`, which is exactly the
    // spelling FSEvents reports, so resolve through realpath(3) instead.
    private static func resolvedPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
