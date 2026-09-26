import AppKit
import CmuxCommandPalette
import CmuxFoundation
import Foundation

extension ContentView {
    static func commandPaletteViewCommandContributions() -> [CommandPaletteCommandContribution] {
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        return [
            CommandPaletteCommandContribution(
                commandId: "palette.triggerFlash",
                title: constant(String(localized: "command.triggerFlash.title", defaultValue: "Flash Focused Panel")),
                subtitle: constant(String(localized: "command.triggerFlash.subtitle", defaultValue: "View")),
                keywords: ["flash", "highlight", "focus", "panel"]
            ),
            CommandPaletteCommandContribution(
                commandId: "palette.swapWithSession",
                title: constant(CmuxPaneSwapStrings().swapWithSession),
                subtitle: constant(CmuxPaneSwapStrings().terminalPane),
                keywords: ["swap", "pane", "session", "terminal", "exchange"],
                when: { context in
                    context.bool(CommandPaletteContextKeys.panelIsTerminal)
                        && context.bool(CommandPaletteContextKeys.panelHasPane)
                }
            ),
            CommandPaletteCommandContribution(
                commandId: "palette.openTaskManager",
                title: constant(String(localized: "taskManager.title", defaultValue: "Task Manager")),
                subtitle: constant(String(localized: "command.closeWindow.subtitle", defaultValue: "Window")),
                keywords: ["task", "manager", "process", "cpu", "memory", "kill"]
            ),
            CommandPaletteCommandContribution(
                commandId: "palette.sleepyMode",
                title: constant(String(localized: "command.sleepyMode.title", defaultValue: "Sleepy Mode")),
                subtitle: constant(String(localized: "command.sleepyMode.subtitle", defaultValue: "View")),
                keywords: ["sleepy", "screensaver", "caffeinate", "keep awake", "do not sleep", "lock", "pets", "night"]
            ),
        ] + globalFontMagnificationCommandContributions()
    }

    private static func globalFontMagnificationCommandContributions() -> [CommandPaletteCommandContribution] {
        let subtitle = String(localized: "command.globalFontMagnification.subtitle", defaultValue: "View")
        let baseKeywords = ["zoom", "ui", "interface", "magnification", "magnify", "font", "scale", "text size", "display"]
        return KeyboardShortcutSettings.Action.globalFontMagnificationActions.map { action in
            let extraKeywords: [String]
            switch action {
            case .increaseGlobalFontMagnification: extraKeywords = ["in", "bigger", "larger", "increase"]
            case .decreaseGlobalFontMagnification: extraKeywords = ["out", "smaller", "decrease"]
            default: extraKeywords = ["reset", "actual size", "default", "100%"]
            }
            let title = action.label
            return CommandPaletteCommandContribution(
                commandId: action.globalFontMagnificationCommandId,
                title: { _ in title },
                subtitle: { _ in subtitle },
                keywords: baseKeywords + extraKeywords
            )
        }
    }

    static func appendViewZoomCommandContributions(
        to contributions: inout [CommandPaletteCommandContribution],
        panelSubtitle: @escaping (CommandPaletteContextSnapshot) -> String
    ) {
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        func browserOrTextPreview(_ context: CommandPaletteContextSnapshot) -> Bool {
            context.bool(CommandPaletteContextKeys.panelIsBrowser)
                || context.bool(CommandPaletteContextKeys.panelIsFilePreviewTextEditor)
        }

        contributions.append(
            CommandPaletteCommandContribution(
                commandId: "palette.browserZoomIn",
                title: constant(String(localized: "command.browserZoomIn.title", defaultValue: "Zoom In")),
                subtitle: panelSubtitle,
                keywords: ["browser", "file", "text", "preview", "zoom", "font", "in"],
                when: browserOrTextPreview
            )
        )
        contributions.append(
            CommandPaletteCommandContribution(
                commandId: "palette.browserZoomOut",
                title: constant(String(localized: "command.browserZoomOut.title", defaultValue: "Zoom Out")),
                subtitle: panelSubtitle,
                keywords: ["browser", "file", "text", "preview", "zoom", "font", "out"],
                when: browserOrTextPreview
            )
        )
        contributions.append(
            CommandPaletteCommandContribution(
                commandId: "palette.browserZoomReset",
                title: constant(String(localized: "command.browserZoomReset.title", defaultValue: "Actual Size")),
                subtitle: panelSubtitle,
                keywords: ["browser", "file", "text", "preview", "zoom", "font", "reset", "actual size"],
                when: browserOrTextPreview
            )
        )
    }

    static let commandPaletteFilePreviewGoToLineCommandId = "palette.filePreviewGoToLine"

    static func appendFilePreviewGoToLineCommandContribution(
        to contributions: inout [CommandPaletteCommandContribution],
        panelSubtitle: @escaping (CommandPaletteContextSnapshot) -> String
    ) {
        let title = KeyboardShortcutSettings.Action.filePreviewGoToLine.label
        contributions.append(
            CommandPaletteCommandContribution(
                commandId: commandPaletteFilePreviewGoToLineCommandId,
                title: { _ in title },
                subtitle: panelSubtitle,
                keywords: ["go to line", "goto", "jump", "line", "column", "file", "preview", "editor"],
                when: { $0.bool(CommandPaletteContextKeys.panelIsFilePreviewTextEditor) }
            )
        )
    }

    func registerViewCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        registry.register(commandId: "palette.triggerFlash") {
            tabManager.triggerFocusFlash()
        }
        registry.register(commandId: "palette.swapWithSession") {
            if !PaneSwapSelectionController().beginFocused(in: tabManager) {
                NSSound.beep()
            }
        }
        registry.register(commandId: "palette.openTaskManager") {
            TaskManagerWindowController.shared.show()
        }
        registry.register(commandId: "palette.sleepyMode") {
            SleepyModeController.shared.activate()
        }
        registry.register(commandId: Self.commandPaletteFilePreviewGoToLineCommandId) {
            guard let preview = tabManager.focusedTextFilePreviewPanel else {
                NSSound.beep()
                return
            }
            // Let the palette dismiss and hand focus back before anchoring the popover.
            DispatchQueue.main.async {
                if !preview.presentGoToLine() {
                    NSSound.beep()
                }
            }
        }
        for action in KeyboardShortcutSettings.Action.globalFontMagnificationActions {
            registry.register(commandId: action.globalFontMagnificationCommandId) {
                _ = action.performGlobalFontMagnification()
            }
        }
    }
}
