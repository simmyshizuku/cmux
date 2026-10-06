import CmuxFoundation
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite
struct FileExplorerChangeScopeTests {
    private let scope = FileExplorerChangeScope(rootPath: "/repo", resolvedRootPath: "/repo")

    @Test func changedFileRefreshesItsLoadedParentFolder() {
        let directories = scope.directoriesToRefresh(
            for: RecursivePathChange(paths: ["/repo/src/new.swift"]),
            loadedDirectories: ["/repo", "/repo/src"]
        )

        #expect(directories == ["/repo/src"])
    }

    @Test func changedFolderRefreshesItselfAndItsParent() {
        let directories = scope.directoriesToRefresh(
            for: RecursivePathChange(paths: ["/repo/src/"]),
            loadedDirectories: ["/repo", "/repo/src"]
        )

        #expect(directories == ["/repo", "/repo/src"])
    }

    @Test func changeUnderFoldersThatAreNotLoadedRefreshesNothing() {
        let directories = scope.directoriesToRefresh(
            for: RecursivePathChange(paths: ["/repo/build/out/a.o", "/repo/.git/index.lock"]),
            loadedDirectories: ["/repo", "/repo/src"]
        )

        #expect(directories.isEmpty)
    }

    @Test func droppedHistoryRefreshesEveryLoadedFolder() {
        let loaded: Set<String> = ["/repo", "/repo/src"]

        let directories = scope.directoriesToRefresh(
            for: RecursivePathChange(paths: [], requiresFullRescan: true),
            loadedDirectories: loaded
        )

        #expect(directories == loaded)
    }

    @Test func pathOutsideTheRootRefreshesEveryLoadedFolder() {
        let loaded: Set<String> = ["/repo", "/repo/src"]

        let directories = scope.directoriesToRefresh(
            for: RecursivePathChange(paths: ["/elsewhere/file.txt"]),
            loadedDirectories: loaded
        )

        #expect(directories == loaded)
    }

    @Test func siblingFolderSharingTheRootPrefixIsOutsideTheRoot() {
        #expect(scope.treePath(forChangedPath: "/repo-old/file.txt") == nil)
    }

    @Test func physicalPathsAreReRootedOntoTheTreeSpelling() {
        let symlinked = FileExplorerChangeScope(
            rootPath: "/tmp/project",
            resolvedRootPath: "/private/tmp/project"
        )

        #expect(symlinked.treePath(forChangedPath: "/private/tmp/project") == "/tmp/project")
        #expect(symlinked.treePath(forChangedPath: "/private/tmp/project/src/a.swift") == "/tmp/project/src/a.swift")
        #expect(
            symlinked.directoriesToRefresh(
                for: RecursivePathChange(paths: ["/private/tmp/project/src/a.swift"]),
                loadedDirectories: ["/tmp/project", "/tmp/project/src"]
            ) == ["/tmp/project/src"]
        )
    }

    @Test func filesystemRootIsHandled() {
        let filesystemRoot = FileExplorerChangeScope(rootPath: "/", resolvedRootPath: "/")

        #expect(filesystemRoot.treePath(forChangedPath: "/etc/hosts") == "/etc/hosts")
        #expect(filesystemRoot.treePath(forChangedPath: "/") == "/")
    }

    @Test func rootReachedThroughASymlinkResolvesToItsPhysicalPath() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-change-scope-\(UUID().uuidString)", isDirectory: true)
        let target = base.appendingPathComponent("target", isDirectory: true)
        let link = base.appendingPathComponent("link", isDirectory: false)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        let symlinked = FileExplorerChangeScope(rootPath: link.path)

        #expect(symlinked.resolvedRootPath.hasSuffix("/target"))
        #expect(
            symlinked.treePath(forChangedPath: symlinked.resolvedRootPath + "/a.txt") == link.path + "/a.txt"
        )
    }
}
