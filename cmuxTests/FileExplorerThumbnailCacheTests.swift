import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

private actor ThumbnailGenerationRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private enum ThumbnailFixture {
    static func image() -> CGImage? {
        CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}

@MainActor
@Suite
struct FileExplorerThumbnailCacheTests {
    /// A real file whose modification date the cache reads, plus a cache whose
    /// generator only counts how often it is asked to render.
    @MainActor
    private struct Fixture {
        let directory: URL
        let path: String
        let recorder: ThumbnailGenerationRecorder
        let cache: FileExplorerThumbnailCache

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("cmux-thumbnail-cache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("photo.png")
            try Data([0x01]).write(to: file)
            path = file.path
            let recorder = ThumbnailGenerationRecorder()
            self.recorder = recorder
            cache = FileExplorerThumbnailCache(generate: { _, _, _ in
                await recorder.record()
                return ThumbnailFixture.image()
            })
        }

        func setModificationDate(_ date: Date) throws {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func unchangedFileIsRenderedOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let first = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)
        let second = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)

        #expect(first != nil)
        #expect(first === second)
        let renderCount = await fixture.recorder.count
        #expect(renderCount == 1)
        #expect(fixture.cache.cachedThumbnail(forPath: fixture.path) === first)
    }

    @Test func changedFileIsRenderedAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.setModificationDate(Date(timeIntervalSince1970: 1_000_000))
        let before = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)

        try fixture.setModificationDate(Date(timeIntervalSince1970: 2_000_000))
        let after = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)

        #expect(after != nil)
        #expect(before !== after)
        let renderCount = await fixture.recorder.count
        #expect(renderCount == 2)
    }

    @Test func largerSizeIsRenderedAgainAndSmallerReusesTheCache() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        _ = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 1)
        _ = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)
        let renderCountAfterLarger = await fixture.recorder.count
        #expect(renderCountAfterLarger == 2)

        _ = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 1)
        let renderCountAfterSmaller = await fixture.recorder.count
        #expect(renderCountAfterSmaller == 2)
    }

    @Test func simultaneousRequestsShareOneRender() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        async let first = fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)
        async let second = fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)
        let images = await [first, second]

        #expect(images[0] != nil)
        #expect(images[0] === images[1])
        let renderCount = await fixture.recorder.count
        #expect(renderCount == 1)
    }

    @Test func deletedFileLosesItsThumbnail() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        _ = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)

        try FileManager.default.removeItem(atPath: fixture.path)
        let afterDelete = await fixture.cache.thumbnail(forPath: fixture.path, pointSize: 16, scale: 2)

        #expect(afterDelete == nil)
        #expect(fixture.cache.cachedThumbnail(forPath: fixture.path) == nil)
        let renderCount = await fixture.recorder.count
        #expect(renderCount == 1)
    }

    @Test(arguments: ["photo.png", "Photo.JPG", "scan.heic", "anim.gif", "logo.svg", "shot.webp", "icon.tiff"])
    func imageFilesGetThumbnails(fileName: String) {
        #expect(FileExplorerThumbnailCache.isThumbnailable(fileName: fileName))
    }

    @Test(arguments: ["main.swift", "README.md", "report.pdf", "clip.mov", "Makefile", ".gitignore", "archive.png.zip"])
    func otherFilesKeepTheirIcon(fileName: String) {
        #expect(!FileExplorerThumbnailCache.isThumbnailable(fileName: fileName))
    }
}
