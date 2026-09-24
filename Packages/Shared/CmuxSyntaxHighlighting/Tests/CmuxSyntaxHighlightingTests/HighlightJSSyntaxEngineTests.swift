@testable import CmuxSyntaxHighlighting
import Foundation
import Testing

#if canImport(AppKit)
import AppKit
#endif

@Suite("highlight.js syntax engine")
struct HighlightJSSyntaxEngineTests {
    private let swiftSource = """
    class VideoResizePlugin: NSObject {
        func handle(_ call: String) -> Int {
            let size = track.naturalSize.applying(transform)
            resizeVideo(inputPath: call)
            return abs(size)
        }
    }
    """

    @Test("Policy rejection returns nil without coloring")
    func policyRejectionReturnsNil() async {
        let engine = HighlightJSSyntaxEngine()
        let highlighted = await engine.highlight(text: #"{"a":1}"#, language: nil, theme: .light)
        #expect(highlighted == nil)
    }

    @Test("Languages highlight.js does not know return nil")
    func unknownLanguageReturnsNil() async {
        let engine = HighlightJSSyntaxEngine()
        let highlighted = await engine.highlight(text: "x", language: "not-a-language", theme: .dark)
        #expect(highlighted == nil)
    }

    @Test(
        "Swift types, declarations, calls, and members are colored in both themes",
        arguments: [TokenTheme.dark, TokenTheme.light]
    )
    func swiftScopesUsePalette(theme: TokenTheme) async throws {
        let engine = HighlightJSSyntaxEngine()
        let highlighted = try #require(
            await engine.highlight(text: swiftSource, language: "swift", theme: theme)
        )
        let palette = theme.palette
        #expect(highlighted.value.string == swiftSource)

        #expect(hex(highlighted, "String") == palette.type.hexKey)
        #expect(hex(highlighted, "Int") == palette.type.hexKey)
        #expect(hex(highlighted, "VideoResizePlugin") == palette.type.hexKey)
        #expect(hex(highlighted, "NSObject") == palette.type.hexKey)
        #expect(hex(highlighted, "abs") == palette.type.hexKey)
        #expect(hex(highlighted, "handle") == palette.function.hexKey)
        #expect(hex(highlighted, "resizeVideo") == palette.function.hexKey)
        #expect(hex(highlighted, "applying") == palette.function.hexKey)
        #expect(hex(highlighted, "naturalSize") == palette.property.hexKey)
        #expect(hex(highlighted, "func") == palette.keyword.hexKey)
        #expect(hex(highlighted, "track") == palette.foreground.hexKey)
    }

    @Test("Dart classes, types, calls, and members use the palette")
    func dartScopesUsePalette() async throws {
        let source = """
        class HomePage extends StatelessWidget {
          final String title;
          @override
          Widget build(BuildContext context) {
            return Scaffold(body: Text(title, style: Theme.of(context).textTheme.bodyLarge));
          }
        }
        """
        let palette = TokenTheme.dark.palette
        let highlighted = try #require(
            await HighlightJSSyntaxEngine().highlight(text: source, language: "dart", theme: .dark)
        )
        for typeName in ["HomePage", "StatelessWidget", "String", "Widget", "BuildContext", "Scaffold", "Text", "Theme"] {
            #expect(hex(highlighted, typeName) == palette.type.hexKey, "\(typeName)")
        }
        #expect(hex(highlighted, "build") == palette.function.hexKey)
        #expect(hex(highlighted, "of(") == palette.function.hexKey)
        #expect(hex(highlighted, "textTheme") == palette.property.hexKey)
        #expect(hex(highlighted, "class") == palette.keyword.hexKey)
        #expect(hex(highlighted, "@override") == palette.attribute.hexKey)
    }

    @Test("Kotlin types, declarations, calls, and members use the palette")
    func kotlinScopesUsePalette() async throws {
        let source = """
        class Foo(private val list: List<String>) : Bar() {
            fun computeFrames(count: Int): Long {
                val result = helper.compute(count, 30L)
                return result.frames.size.toLong()
            }
        }
        """
        let palette = TokenTheme.dark.palette
        let highlighted = try #require(
            await HighlightJSSyntaxEngine().highlight(text: source, language: "kotlin", theme: .dark)
        )
        for typeName in ["Foo", "List", "String", "Bar", "Int", "Long"] {
            #expect(hex(highlighted, typeName) == palette.type.hexKey, "\(typeName)")
        }
        #expect(hex(highlighted, "computeFrames") == palette.function.hexKey)
        #expect(hex(highlighted, "compute(") == palette.function.hexKey)
        #expect(hex(highlighted, "toLong") == palette.function.hexKey)
        #expect(hex(highlighted, "frames") == palette.property.hexKey)
        #expect(hex(highlighted, "fun") == palette.keyword.hexKey)
    }

    @Test("JSON tokens use the cmux palette")
    func jsonTokensUsePalette() async throws {
        let engine = HighlightJSSyntaxEngine()
        let source = """
        {
          "name": "cmux",
          "count": 3,
          "enabled": true
        }
        """
        let highlighted = try #require(
            await engine.highlight(text: source, language: "json", theme: .dark)
        )
        #expect(hex(highlighted, "true") == "0091FF")
        #expect(hex(highlighted, "\"cmux\"") == "E0B86A")
        #expect(hex(highlighted, "3") == "5ED0C8")
    }

#if canImport(AppKit)
    @Test("Markdown emphasis carries font traits")
    func markdownCarriesFontTraits() async throws {
        let engine = HighlightJSSyntaxEngine()
        let source = "**bold** _it_"
        let highlighted = try #require(
            await engine.highlight(text: source, language: "markdown", theme: .light)
        )
        let boldFont = try #require(
            highlighted.value.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        let italicLocation = (source as NSString).range(of: "_it_").location
        let italicFont = try #require(
            highlighted.value.attribute(.font, at: italicLocation, effectiveRange: nil) as? NSFont
        )
        #expect(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
    }
#endif

    /// Hex color at the first occurrence of `token`.
    private func hex(_ highlighted: HighlightedText, _ token: String) -> String? {
        let location = (highlighted.value.string as NSString).range(of: token).location
        guard location != NSNotFound,
              let color = highlighted.value.attribute(.foregroundColor, at: location, effectiveRange: nil),
              let packed = HighlightColorPacking().packedRGBKey(from: color) else { return nil }
        return HighlightColorPacking().hexKey(fromPacked: packed)
    }
}
