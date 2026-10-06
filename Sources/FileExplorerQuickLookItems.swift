import Foundation

/// What Quick Look shows for a file tree selection: the selected files in row
/// order, opened on the one the keyboard selection sits on.
struct FileExplorerQuickLookItems: Equatable {
    let urls: [URL]
    let currentIndex: Int

    /// - Parameters:
    ///   - selectedPaths: Paths of the selected rows, top to bottom.
    ///   - anchorPath: The row the keyboard selection sits on.
    ///   - isLocal: Whether the paths are files on this Mac. Quick Look cannot
    ///     read a file that only exists on a remote host.
    /// - Returns: `nil` when there is nothing Quick Look can show.
    init?(selectedPaths: [String], anchorPath: String?, isLocal: Bool) {
        guard isLocal, !selectedPaths.isEmpty else { return nil }
        urls = selectedPaths.map { URL(fileURLWithPath: $0) }
        currentIndex = anchorPath.flatMap { selectedPaths.firstIndex(of: $0) } ?? 0
    }
}
