import AppKit
import CmuxFilePreviewCore
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite(.serialized)
struct FilePreviewGoToLineTests {
    @Test("A location requested before the file loads is revealed once the editor shows it")
    func pendingLocationRevealsAfterEditorShowsLoadedText() async throws {
        let contents = (1...300).map { "line \($0)" }.joined(separator: "\n")
        let url = try temporaryFile(contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }
        let panel = FilePreviewPanel(
            workspaceId: UUID(),
            filePath: url.path,
            startFileWatcher: false,
            modeResolver: { _ in .text }
        )
        defer { panel.close() }
        let location = try #require(FilePreviewTextLocation(line: 240, column: 4))

        let (window, textView) = mountEditor(for: panel)
        defer { window.close() }
        panel.revealTextLocation(location)
        await panel.loadTextContent().value
        await drainMainQueue()

        // Loaded, but the editor still shows the pre-load buffer: nothing moves yet.
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))

        textView.string = panel.textContent
        panel.textEditorDidShowContent(revision: panel.textContentRevision)
        await drainMainQueue()

        let expected = location.utf16Offset(in: panel.textContent)
        #expect(textView.selectedRange() == NSRange(location: expected, length: 0))
        #expect(textView.visibleRect.minY > 0, "Line 240 should be scrolled into view")

        // The request is consumed; a later content refresh does not jump again.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        panel.textEditorDidShowContent(revision: panel.textContentRevision)
        await drainMainQueue()
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("An already-open preview reveals a new location immediately")
    func openPreviewRevealsImmediately() async throws {
        let url = try temporaryFile(contents: "alpha\nbeta\ngamma\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let panel = FilePreviewPanel(
            workspaceId: UUID(),
            filePath: url.path,
            startFileWatcher: false,
            modeResolver: { _ in .text }
        )
        defer { panel.close() }
        await panel.loadTextContent().value
        let (window, textView) = mountEditor(for: panel)
        defer { window.close() }
        textView.string = panel.textContent
        panel.textEditorDidShowContent(revision: panel.textContentRevision)

        panel.revealTextLocation(try #require(FilePreviewTextLocation(line: 3, column: 2)))
        await drainMainQueue()

        #expect(textView.selectedRange() == NSRange(location: 12, length: 0))
    }

    private func mountEditor(for panel: FilePreviewPanel) -> (NSWindow, SavingTextView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        let textView = SavingTextView.makeFilePreviewTextView()
        textView.panel = panel
        scrollView.documentView = textView
        window.contentView?.addSubview(scrollView)
        panel.attachTextView(textView)
        return (window, textView)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func temporaryFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("go-to-line-\(UUID().uuidString).swift")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
