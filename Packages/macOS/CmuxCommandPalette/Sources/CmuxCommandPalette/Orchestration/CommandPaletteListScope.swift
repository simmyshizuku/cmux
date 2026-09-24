import Foundation

/// Which list the palette is showing.
public enum CommandPaletteListScope: String, Sendable {
    /// The command list (query prefixed with `>`).
    case commands
    /// The workspace/surface switcher list.
    case switcher
    /// Files below the selected local workspace directory.
    case files
}
