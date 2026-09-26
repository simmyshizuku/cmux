import Foundation

/// A one-based line, and optional one-based column, inside a File Preview
/// text buffer.
///
/// Locations come from two places: the Go to Line field, where the user
/// types `42` or `42:7`, and terminal `path:line[:column]` links. Lines are
/// counted with the same breaks as ``FilePreviewLineIndex`` (LF, CR, CRLF,
/// U+2028, U+2029) so the caret lands on the line the gutter numbers.
public struct FilePreviewTextLocation: Equatable, Sendable {
    /// The one-based line number.
    public let line: Int
    /// The one-based column in UTF-16 units, or `nil` for the line start.
    public let column: Int?

    /// Creates a location, rejecting non-positive components.
    ///
    /// - Parameters:
    ///   - line: One-based line number; must be at least 1.
    ///   - column: One-based column; `nil` or at least 1.
    public init?(line: Int, column: Int? = nil) {
        guard line >= 1 else { return nil }
        if let column, column < 1 { return nil }
        self.line = line
        self.column = column
    }

    /// Parses Go to Line input such as `42`, `42:7`, or `:42`.
    ///
    /// Surrounding whitespace and one leading colon are ignored. Line and
    /// column may be separated by `:` or `,`.
    ///
    /// - Parameter input: The text the user typed.
    public init?(parsing input: String) {
        var text = Substring(input.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == ":" {
            text = text.dropFirst()
        }
        let components = text.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: false
        ).flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
        guard (1...2).contains(components.count),
              let line = Self.positiveInteger(components[0]) else { return nil }
        guard components.count == 2 else {
            self.init(line: line)
            return
        }
        guard let column = Self.positiveInteger(components[1]) else { return nil }
        self.init(line: line, column: column)
    }

    /// Returns the UTF-16 caret offset for this location in `text`.
    ///
    /// A line past the end clamps to the start of the last line. A column
    /// past the end of its line clamps to the line end, before the break,
    /// and never splits a surrogate pair.
    ///
    /// - Parameter text: The buffer the location points into.
    /// - Returns: A UTF-16 offset in `0...text.utf16.count`.
    public func utf16Offset(in text: String) -> Int {
        let units = text.utf16
        var index = units.startIndex
        var position = 0
        var currentLine = 1
        var lineStart = 0

        while currentLine < line, index != units.endIndex {
            let unit = units[index]
            units.formIndex(after: &index)
            position += 1
            switch unit {
            case 0x0D:
                if index != units.endIndex, units[index] == 0x0A {
                    units.formIndex(after: &index)
                    position += 1
                }
                currentLine += 1
                lineStart = position
            case 0x0A, 0x2028, 0x2029:
                currentLine += 1
                lineStart = position
            default:
                break
            }
        }

        guard currentLine == line, let column, column > 1 else {
            return lineStart
        }

        var offset = lineStart
        var remaining = column - 1
        while remaining > 0, index != units.endIndex {
            let unit = units[index]
            if Self.isLineBreak(unit) { break }
            units.formIndex(after: &index)
            offset += 1
            remaining -= 1
        }
        if index != units.endIndex, UTF16.isTrailSurrogate(units[index]) {
            offset += 1
        }
        return offset
    }

    /// Counts logical lines in `text` the way ``FilePreviewLineIndex`` does.
    ///
    /// - Parameter text: The buffer to count.
    /// - Returns: At least 1; an empty buffer has one line.
    public static func lineCount(in text: String) -> Int {
        var count = 1
        var pendingCarriageReturn = false
        for unit in text.utf16 {
            if pendingCarriageReturn {
                pendingCarriageReturn = false
                if unit == 0x0A { continue }
            }
            switch unit {
            case 0x0D:
                count += 1
                pendingCarriageReturn = true
            case 0x0A, 0x2028, 0x2029:
                count += 1
            default:
                break
            }
        }
        return count
    }

    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
    }

    private static func positiveInteger(_ text: Substring) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(\.isASCII),
              let value = Int(trimmed),
              value >= 1 else { return nil }
        return value
    }
}
