import AppKit
import CmuxFilePreviewCore

extension SavingTextView {
    /// Moves the caret to `location`, centers its line, and flashes it.
    ///
    /// Go to Line and `path:line` opens both land here, so the caret, scroll,
    /// and highlight behave the same whichever entrypoint asked.
    func revealFilePreviewLocation(_ location: FilePreviewTextLocation) {
        let text = string as NSString
        let caret = NSRange(location: location.utf16Offset(in: string), length: 0)
        setSelectedRange(caret)

        let lineRange = text.lineRange(for: caret)
        centerFilePreviewLine(lineRange)
        // Horizontal follow-up for long lines when a column is past the fold.
        scrollRangeToVisible(caret)

        let visibleLineRange = Self.rangeTrimmingLineBreak(lineRange, in: text)
        if visibleLineRange.length > 0 {
            showFindIndicator(for: visibleLineRange)
        }
    }

    /// Opens the Go to Line field anchored to the top of the editor.
    ///
    /// - Returns: `false` when the editor is not in a window.
    @discardableResult
    func presentFilePreviewGoToLine() -> Bool {
        guard window != nil else { return false }
        let controller = FilePreviewGoToLineViewController { [weak self] location in
            self?.window?.makeFirstResponder(self)
            self?.revealFilePreviewLocation(location)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
        controller.popover = popover
        // NSTextView is flipped, so minY is the top of what the user sees and
        // `.maxY` opens the popover downward into the editor.
        let visible = visibleRect
        let anchor = NSRect(x: visible.midX, y: visible.minY + 4, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
        return true
    }

    private func centerFilePreviewLine(_ lineRange: NSRange) {
        guard let layoutManager,
              let textContainer,
              let clipView = enclosingScrollView?.contentView else { return }
        layoutManager.ensureLayout(forCharacterRange: lineRange)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.y += textContainerOrigin.y
        let target = NSPoint(x: 0, y: lineRect.midY - clipView.bounds.height / 2)
        let constrained = clipView.constrainBoundsRect(NSRect(origin: target, size: clipView.bounds.size))
        clipView.scroll(to: constrained.origin)
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    private static func rangeTrimmingLineBreak(_ range: NSRange, in text: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let unit = text.character(at: range.location + length - 1)
            guard unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 else { break }
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }
}
