import CmuxFoundation

/// The single action path behind the Global Font Magnification shortcuts and
/// their command palette entries.
extension KeyboardShortcutSettings.Action {
    static let globalFontMagnificationActions: [Self] = [
        .increaseGlobalFontMagnification,
        .decreaseGlobalFontMagnification,
        .resetGlobalFontMagnification,
    ]

    /// Command palette id for a global magnification action.
    var globalFontMagnificationCommandId: String { "palette.\(rawValue)" }

    /// Applies this action to the app-wide font magnification.
    ///
    /// - Returns: `false` when this is not a global magnification action.
    @discardableResult
    func performGlobalFontMagnification() -> Bool {
        switch self {
        case .increaseGlobalFontMagnification:
            GlobalFontMagnification.stepPercent(by: 1)
        case .decreaseGlobalFontMagnification:
            GlobalFontMagnification.stepPercent(by: -1)
        case .resetGlobalFontMagnification:
            GlobalFontMagnification.resetToDefault()
        default:
            return false
        }
        return true
    }
}
