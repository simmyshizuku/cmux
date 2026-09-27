import AppKit
import CmuxFilePreviewCore
import CmuxFoundation

final class FileExplorerSearchField: SidebarSearchField {
    var fileExplorerPanelPlacement: FileExplorerPanelPlacement = .rightSidebar
    var onCancel: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onCommit: (() -> Void)?
    var onFocus: (() -> Void)?
    /// Called for ⌥⌘C / ⌥⌘W / ⌥⌘R while editing, to flip a search option.
    var onToggleOption: ((WritableKeyPath<TextSearchOptions, Bool>) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocus?()
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if handleOpenSelectionShortcut(event) { return }
        if let delta = searchFieldMoveDelta(for: event) {
            onMoveSelection?(delta)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleOpenSelectionShortcut(event) || handleOptionToggle(event) || super.performKeyEquivalent(with: event)
    }

    private func handleOptionToggle(_ event: NSEvent) -> Bool {
        guard let onToggleOption,
              event.type == .keyDown,
              let editor = currentEditor(),
              window?.firstResponder === editor,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option] else {
            return false
        }
        switch KeyboardLayout.normalizedCharacters(for: event) {
        case "c": onToggleOption(\.matchCase)
        case "w": onToggleOption(\.matchWholeWord)
        case "r": onToggleOption(\.useRegularExpression)
        default: return false
        }
        return true
    }

    private func searchFieldMoveDelta(for event: NSEvent) -> Int? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommandOrOption = !flags.intersection([.command, .option]).isEmpty
        if flags.contains(.control), !hasCommandOrOption {
            switch event.keyCode {
            case 45: return 1
            case 35: return -1
            default: return nil
            }
        }
        guard flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.keyCode {
        case 125: return 1
        case 126: return -1
        default: return nil
        }
    }
}
