import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Icon-sized thumbnails for image files in the file tree.
///
/// A row shows whatever is cached at once, then ``thumbnail(forPath:pointSize:scale:)``
/// checks the file's modification date off the main thread and regenerates only
/// when the file changed, so redrawing a row never blocks on disk or flickers.
@MainActor
final class FileExplorerThumbnailCache {
    typealias ModificationDateReader = @Sendable (String) -> Date?
    typealias Generator = @Sendable (URL, CGFloat, CGFloat) async -> CGImage?

    private final class Entry {
        let image: NSImage
        let modificationDate: Date
        let pixelSize: CGFloat

        init(image: NSImage, modificationDate: Date, pixelSize: CGFloat) {
            self.image = image
            self.modificationDate = modificationDate
            self.pixelSize = pixelSize
        }
    }

    private let entries = NSCache<NSString, Entry>()
    private var loads: [String: Task<NSImage?, Never>] = [:]
    private let modificationDate: ModificationDateReader
    private let generate: Generator

    /// - Parameters:
    ///   - countLimit: How many thumbnails to keep.
    ///   - modificationDate: Reads a file's modification date; `nil` when the file is gone.
    ///   - generate: Renders a thumbnail for a file URL at a point size and scale.
    init(
        countLimit: Int = 512,
        modificationDate: ModificationDateReader? = nil,
        generate: Generator? = nil
    ) {
        entries.countLimit = countLimit
        self.modificationDate = modificationDate ?? { path in
            FileExplorerThumbnailCache.fileModificationDate(atPath: path)
        }
        self.generate = generate ?? { url, pointSize, scale in
            await FileExplorerThumbnailCache.quickLookThumbnail(url: url, pointSize: pointSize, scale: scale)
        }
    }

    /// Whether a file with this name is an image that gets a thumbnail in place of its icon.
    nonisolated static func isThumbnailable(fileName: String) -> Bool {
        let pathExtension = (fileName as NSString).pathExtension
        guard !pathExtension.isEmpty else { return false }
        return UTType(filenameExtension: pathExtension)?.conforms(to: .image) == true
    }

    /// The last thumbnail generated for `path`, without checking whether the file changed since.
    func cachedThumbnail(forPath path: String) -> NSImage? {
        entries.object(forKey: path as NSString)?.image
    }

    /// The current thumbnail for `path`, generating it when none is cached, the
    /// file changed, or a larger size is needed. `nil` when the file is gone or
    /// cannot be rendered.
    func thumbnail(forPath path: String, pointSize: CGFloat, scale: CGFloat) async -> NSImage? {
        if let load = loads[path] {
            return await load.value
        }
        let load = Task { @MainActor [weak self] () -> NSImage? in
            await self?.loadThumbnail(forPath: path, pointSize: pointSize, scale: scale)
        }
        loads[path] = load
        return await load.value
    }

    private func loadThumbnail(forPath path: String, pointSize: CGFloat, scale: CGFloat) async -> NSImage? {
        defer { loads[path] = nil }
        let key = path as NSString
        let readModificationDate = modificationDate
        let currentDate = await Task.detached(priority: .utility) {
            readModificationDate(path)
        }.value
        guard let currentDate else {
            entries.removeObject(forKey: key)
            return nil
        }

        let pixelSize = pointSize * scale
        if let entry = entries.object(forKey: key),
           entry.modificationDate == currentDate,
           entry.pixelSize >= pixelSize {
            return entry.image
        }

        guard let rendered = await generate(URL(fileURLWithPath: path), pointSize, scale) else {
            return nil
        }
        let image = NSImage(
            cgImage: rendered,
            size: NSSize(width: CGFloat(rendered.width) / scale, height: CGFloat(rendered.height) / scale)
        )
        entries.setObject(
            Entry(image: image, modificationDate: currentDate, pixelSize: pixelSize),
            forKey: key
        )
        return image
    }

    private nonisolated static func fileModificationDate(atPath path: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    private nonisolated static func quickLookThumbnail(
        url: URL,
        pointSize: CGFloat,
        scale: CGFloat
    ) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pointSize, height: pointSize),
            scale: scale,
            representationTypes: .thumbnail
        )
        // QuickLookThumbnailing reports through a completion handler; bridge it at this one seam.
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }
    }
}
