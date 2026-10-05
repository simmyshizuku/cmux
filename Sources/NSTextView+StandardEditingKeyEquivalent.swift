import AppKit

extension NSTextView {
    /// Performs ⌘A / ⌘C / ⌘X / ⌘V on this field editor directly.
    ///
    /// Native text fields hosted in cmux's SwiftUI panes (the sidebar search
    /// fields, the File Preview find bar) can lose these to a hosting view that
    /// claims the key equivalent without performing it, so their owners route
    /// them here first.
    ///
    /// - Returns: `true` when the event was one of those commands and was performed.
    @MainActor
    func cmuxPerformStandardEditingKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else {
            return false
        }
        switch KeyboardLayout.normalizedCharacters(for: event) {
        case "a": selectAll(nil)
        case "c": copy(nil)
        case "x": cut(nil)
        case "v": paste(nil)
        default: return false
        }
        return true
    }
}
