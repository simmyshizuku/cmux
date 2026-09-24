/// Light or dark token appearance for File Preview.
///
/// Surface (panel) colors stay on Ghostty `PanelAppearance`. Token colors
/// come from ``palette``.
public enum TokenTheme: Sendable, Equatable {
    /// Light cmux token palette.
    case light
    /// Dark cmux token palette.
    case dark

    /// Product colors for highlighted tokens.
    public var palette: TokenPalette {
        switch self {
        case .light:
            return .cmuxLight
        case .dark:
            return .cmuxDark
        }
    }
}
