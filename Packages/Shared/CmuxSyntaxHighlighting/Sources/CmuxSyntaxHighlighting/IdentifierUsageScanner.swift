/// Colors type references, call sites, and member accesses that highlight.js
/// leaves plain.
///
/// highlight.js marks declarations (`func resizeVideo(`) but not uses:
/// `resizeVideo(` at a call site and `.preferredTransform` are plain text,
/// and grammars such as Dart and Kotlin tag almost no type names. IDEs color
/// those from compiler information. This scanner approximates it lexically
/// over the uncolored gaps between existing runs:
///
/// - a PascalCase identifier with at least one lowercase letter
///   (`Widget`, `BuildContext`) is a ``TokenRole/type``, including
///   constructor calls, in ``pascalCaseTypeLanguages``;
/// - an identifier directly followed by `(` is a ``TokenRole/function``;
/// - an identifier directly after a single `.` is a ``TokenRole/property``
///   (`a...b` and `a..<b` ranges are not member accesses).
///
/// It only runs for C-family and scripting languages where both rules hold,
/// never for prose or data formats such as Markdown or JSON.
public struct IdentifierUsageScanner: Sendable {
    /// highlight.js language ids the scanner applies to.
    public static let supportedLanguages: Set<String> = [
        "swift", "objectivec", "c", "cpp", "csharp", "java", "kotlin",
        "go", "rust", "typescript", "javascript", "python", "ruby", "dart"
    ]

    /// Languages whose convention reserves PascalCase for types. C#, Go, C,
    /// and C++ are excluded: their functions and methods are often PascalCase.
    public static let pascalCaseTypeLanguages: Set<String> = [
        "swift", "objectivec", "java", "kotlin", "dart", "typescript",
        "javascript", "python", "rust", "ruby"
    ]

    /// Creates a scanner.
    public init() {}

    /// Returns `runs` with call-site and member-access runs added in the gaps.
    ///
    /// - Parameters:
    ///   - runs: Sorted, non-overlapping runs from ``HighlightHTMLParser``.
    ///   - source: The highlighted text.
    ///   - language: highlight.js language id of `source`.
    /// - Returns: Sorted, non-overlapping runs. Unchanged when `language` is
    ///   not in ``supportedLanguages``.
    public func addingUsageRuns(
        to runs: [HighlightRun],
        source: String,
        language: String
    ) -> [HighlightRun] {
        guard Self.supportedLanguages.contains(language) else { return runs }
        let text = Array(source.utf16)
        let colorsPascalCaseTypes = Self.pascalCaseTypeLanguages.contains(language)
        var result: [HighlightRun] = []
        result.reserveCapacity(runs.count * 2)
        var gapStart = 0
        for run in runs {
            appendUsages(
                in: gapStart..<run.location,
                of: text,
                colorsPascalCaseTypes: colorsPascalCaseTypes,
                to: &result
            )
            result.append(run)
            gapStart = run.end
        }
        appendUsages(
            in: gapStart..<text.count,
            of: text,
            colorsPascalCaseTypes: colorsPascalCaseTypes,
            to: &result
        )
        return result
    }

    private func appendUsages(
        in gap: Range<Int>,
        of text: [UInt16],
        colorsPascalCaseTypes: Bool,
        to result: inout [HighlightRun]
    ) {
        var index = gap.lowerBound
        // Skip the tail of an identifier that started inside the previous run.
        while index < gap.upperBound, index > 0, isIdentifierPart(text[index - 1]),
              isIdentifierPart(text[index]) {
            index += 1
        }
        while index < gap.upperBound {
            guard isIdentifierStart(text[index]) else {
                index += 1
                continue
            }
            let start = index
            while index < gap.upperBound, isIdentifierPart(text[index]) {
                index += 1
            }
            let role: TokenRole
            if colorsPascalCaseTypes, isPascalCaseTypeName(text[start..<index]) {
                role = .type
            } else if index < text.count, text[index] == Punctuation.openParen {
                role = .function
            } else if start > 0, text[start - 1] == Punctuation.dot,
                      start < 2 || text[start - 2] != Punctuation.dot {
                role = .property
            } else {
                continue
            }
            result.append(HighlightRun(
                location: start,
                length: index - start,
                style: TokenStyle(role: role)
            ))
        }
    }

    /// `Widget` and `HTTPClient` qualify; `URL`, `RED`, and `MAX_SIZE` do not.
    private func isPascalCaseTypeName(_ identifier: ArraySlice<UInt16>) -> Bool {
        guard let first = identifier.first, isUppercase(first) else { return false }
        return identifier.contains(where: isLowercase)
    }

    private func isUppercase(_ unit: UInt16) -> Bool { unit >= 0x41 && unit <= 0x5A }

    private func isLowercase(_ unit: UInt16) -> Bool { unit >= 0x61 && unit <= 0x7A }

    private func isIdentifierStart(_ unit: UInt16) -> Bool {
        isUppercase(unit) || isLowercase(unit) || unit == 0x5F || unit == 0x24
    }

    private func isIdentifierPart(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || (unit >= 0x30 && unit <= 0x39)
    }

    /// UTF-16 constants for the characters the rules look at.
    private enum Punctuation {
        static let openParen: UInt16 = 0x28
        static let dot: UInt16 = 0x2E
    }
}
