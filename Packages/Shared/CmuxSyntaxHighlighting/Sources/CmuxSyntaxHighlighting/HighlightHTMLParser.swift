/// Converts highlight.js HTML output into ``HighlightRun``s over the source.
///
/// highlight.js returns the source wrapped in `<span class="hljs-…">` tags
/// with `&`, `<`, `>`, `"` and `'` escaped. The parser walks that markup
/// once, resolves each span through ``HighlightScopeClassifier`` (the
/// innermost classified span wins), and emits runs in source UTF-16 offsets.
/// Plain-foreground text produces no run.
///
/// Every decoded character is checked against `source`, so markup that does
/// not reproduce the source exactly yields `nil` rather than misplaced color.
public struct HighlightHTMLParser: Sendable {
    private let classifier: HighlightScopeClassifier

    /// Creates a parser.
    ///
    /// - Parameter classifier: Maps span classes to styles. Defaults to the
    ///   built-in table.
    public init(classifier: HighlightScopeClassifier = HighlightScopeClassifier()) {
        self.classifier = classifier
    }

    /// Parses `html` produced by highlight.js for `source`.
    ///
    /// - Parameters:
    ///   - html: The `value` of a `hljs.highlight` result.
    ///   - source: The exact text that was highlighted.
    /// - Returns: Sorted, non-overlapping runs, or `nil` when the markup is
    ///   malformed or does not decode to `source`.
    public func parse(html: String, source: String) -> [HighlightRun]? {
        let markup = Array(html.utf16)
        let expected = Array(source.utf16)
        var styleCache: [StyleCacheKey: TokenStyle?] = [:]
        var styleStack: [TokenStyle?] = []
        var classContainerStack: [Bool] = []
        var runs: [HighlightRun] = []
        var index = 0
        var position = 0
        var segmentStart = 0

        func closeSegment() {
            guard position > segmentStart,
                  let style = styleStack.last ?? nil,
                  style != TokenStyle(role: .foreground) else { return }
            if let last = runs.last, last.end == segmentStart, last.style == style {
                runs[runs.count - 1] = HighlightRun(
                    location: last.location,
                    length: position - last.location,
                    style: style
                )
            } else {
                runs.append(HighlightRun(
                    location: segmentStart,
                    length: position - segmentStart,
                    style: style
                ))
            }
        }

        while index < markup.count {
            let unit = markup[index]
            if unit == Markup.lessThan {
                closeSegment()
                segmentStart = position
                if matches(Markup.spanClose, in: markup, at: index) {
                    guard !styleStack.isEmpty else { return nil }
                    styleStack.removeLast()
                    classContainerStack.removeLast()
                    index += Markup.spanClose.count
                    continue
                }
                guard matches(Markup.spanOpen, in: markup, at: index) else { return nil }
                let classStart = index + Markup.spanOpen.count
                guard let classEnd = markup[classStart...].firstIndex(of: Markup.quote),
                      matches(Markup.tagEnd, in: markup, at: classEnd) else { return nil }
                let classAttribute = String(decoding: markup[classStart..<classEnd], as: UTF16.self)
                let cacheKey = StyleCacheKey(
                    classAttribute: classAttribute,
                    insideClassDeclaration: classContainerStack.last ?? false
                )
                let style: TokenStyle?
                if let cached = styleCache[cacheKey] {
                    style = cached
                } else {
                    style = classifier.style(
                        forClassAttribute: classAttribute,
                        insideClassDeclaration: cacheKey.insideClassDeclaration
                    )
                    styleCache[cacheKey] = style
                }
                styleStack.append(style ?? styleStack.last ?? nil)
                classContainerStack.append(classAttribute == "hljs-class")
                index = classEnd + Markup.tagEnd.count
                continue
            }

            if unit == Markup.ampersand {
                guard let (decoded, consumed) = decodeEntity(in: markup, at: index) else { return nil }
                for decodedUnit in decoded {
                    guard position < expected.count, expected[position] == decodedUnit else { return nil }
                    position += 1
                }
                index += consumed
            } else {
                guard position < expected.count, expected[position] == unit else { return nil }
                position += 1
                index += 1
            }
        }
        closeSegment()
        guard styleStack.isEmpty, position == expected.count else { return nil }
        return runs
    }

    private func matches(_ token: [UInt16], in markup: [UInt16], at index: Int) -> Bool {
        guard index + token.count <= markup.count else { return false }
        for offset in 0..<token.count where markup[index + offset] != token[offset] {
            return false
        }
        return true
    }

    /// Decodes the entity starting at `index` (an `&`).
    ///
    /// - Returns: The decoded UTF-16 units and the number of markup units
    ///   consumed, or `nil` for an unterminated or unknown entity.
    private func decodeEntity(in markup: [UInt16], at index: Int) -> ([UInt16], Int)? {
        let searchEnd = min(markup.count, index + 12)
        guard let semicolon = markup[index..<searchEnd].firstIndex(of: Markup.semicolon) else {
            return nil
        }
        let name = String(decoding: markup[(index + 1)..<semicolon], as: UTF16.self)
        let consumed = semicolon - index + 1
        switch name {
        case "amp": return ([Markup.ampersand], consumed)
        case "lt": return ([Markup.lessThan], consumed)
        case "gt": return ([0x3E], consumed)
        case "quot": return ([Markup.quote], consumed)
        case "apos": return ([0x27], consumed)
        default:
            guard name.hasPrefix("#") else { return nil }
            let digits = name.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return (Array(String(Character(scalar)).utf16), consumed)
        }
    }

    /// A span's classification depends on its class and its direct container.
    private struct StyleCacheKey: Hashable {
        let classAttribute: String
        let insideClassDeclaration: Bool
    }

    /// UTF-16 constants for the markup highlight.js emits.
    private enum Markup {
        static let lessThan: UInt16 = 0x3C
        static let ampersand: UInt16 = 0x26
        static let quote: UInt16 = 0x22
        static let semicolon: UInt16 = 0x3B
        static let spanOpen = Array(#"<span class=""#.utf16)
        static let spanClose = Array("</span>".utf16)
        static let tagEnd = Array(#"">"#.utf16)
    }
}
