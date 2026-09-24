@testable import CmuxSyntaxHighlighting
import Foundation
import Testing

/// Swift type names must take the palette's type color in both appearances.
/// Highlightr's CSS parser dropped `.hljs-type` from the `xcode-dark` theme,
/// so dark File Preview rendered `String`, `Int`, and friends as plain text.
@Suite("Swift type colors")
struct SwiftTypeColorRegressionTests {
    private let source = """
    func handle(_ call: String) -> Int {
        let url = URL(fileURLWithPath: call)
        return abs(Int(url.path.count))
    }
    """

    @Test("Swift types use the palette type color", arguments: [TokenTheme.dark, TokenTheme.light])
    func swiftTypesUsePaletteTypeColor(theme: TokenTheme) async throws {
        let engine: any SyntaxHighlightingEngine = HighlightrSyntaxEngine()
        let highlighted = try #require(
            await engine.highlight(text: source, language: "swift", theme: theme)
        )
        for typeName in ["String", "Int", "URL"] {
            #expect(hex(highlighted, typeName) == theme.palette.type.hexKey, "\(typeName) in \(theme)")
        }
    }

    /// Hex color at the first occurrence of `token`.
    private func hex(_ highlighted: HighlightedText, _ token: String) -> String? {
        let location = (highlighted.value.string as NSString).range(of: token).location
        guard location != NSNotFound,
              let color = highlighted.value.attribute(.foregroundColor, at: location, effectiveRange: nil),
              let packed = HighlightColorPacking().packedRGBKey(from: color) else { return nil }
        return HighlightColorPacking().hexKey(fromPacked: packed)
    }
}
