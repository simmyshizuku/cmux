import Foundation
import Testing

@testable import CmuxFilePreviewCore

@Suite("File Preview text location")
struct FilePreviewTextLocationTests {
    @Test("Parses line and line:column input", arguments: [
        ("42", 42, nil),
        ("  42  ", 42, nil),
        (":42", 42, nil),
        ("42:7", 42, 7),
        ("42,7", 42, 7),
        (" 3 : 9 ", 3, 9),
    ] as [(String, Int, Int?)])
    func parsesValidInput(_ input: String, _ line: Int, _ column: Int?) throws {
        let location = try #require(FilePreviewTextLocation(parsing: input))
        #expect(location.line == line)
        #expect(location.column == column)
    }

    @Test("Rejects empty, zero, negative, and malformed input", arguments: [
        "", "   ", ":", "0", "-3", "abc", "4a", "42:", "42:0", "42:-1", "1:2:3", "１２",
    ])
    func rejectsInvalidInput(_ input: String) {
        #expect(FilePreviewTextLocation(parsing: input) == nil)
    }

    @Test("Maps a line to its start offset")
    func mapsLineStart() throws {
        let text = "one\ntwo\nthree"
        #expect(try #require(FilePreviewTextLocation(line: 1)).utf16Offset(in: text) == 0)
        #expect(try #require(FilePreviewTextLocation(line: 2)).utf16Offset(in: text) == 4)
        #expect(try #require(FilePreviewTextLocation(line: 3)).utf16Offset(in: text) == 8)
    }

    @Test("Clamps a line past the end to the last line start")
    func clampsLinePastEnd() throws {
        let text = "one\ntwo\nthree"
        let location = try #require(FilePreviewTextLocation(line: 99, column: 3))
        #expect(location.utf16Offset(in: text) == 8)
        #expect(try #require(FilePreviewTextLocation(line: 5)).utf16Offset(in: "") == 0)
    }

    @Test("Places the caret at a column and clamps it to the line end")
    func placesColumn() throws {
        let text = "alpha\nbeta\n"
        #expect(try #require(FilePreviewTextLocation(line: 2, column: 1)).utf16Offset(in: text) == 6)
        #expect(try #require(FilePreviewTextLocation(line: 2, column: 3)).utf16Offset(in: text) == 8)
        // Column past the end stops before the line break, not on the next line.
        #expect(try #require(FilePreviewTextLocation(line: 2, column: 50)).utf16Offset(in: text) == 10)
    }

    @Test("Counts CR, CRLF, and Unicode separators like the gutter index")
    func matchesLineIndexBreaks() throws {
        let text = "a\r\nb\rc\u{2028}d\u{2029}e\nf"
        #expect(FilePreviewTextLocation.lineCount(in: text) == FilePreviewLineIndex(string: text).lineCount)
        let index = FilePreviewLineIndex(string: text)
        for line in 1...index.lineCount {
            let location = try #require(FilePreviewTextLocation(line: line))
            #expect(location.utf16Offset(in: text) == index.offset(forLine: line))
        }
    }

    @Test("Never splits a surrogate pair")
    func keepsSurrogatePairsWhole() throws {
        // "a😀b": the emoji occupies UTF-16 offsets 1 and 2.
        let text = "a😀b"
        let insidePair = try #require(FilePreviewTextLocation(line: 1, column: 3))
        #expect(insidePair.utf16Offset(in: text) == 3)
    }

    @Test("Counts lines in empty and trailing-newline buffers")
    func countsLines() {
        #expect(FilePreviewTextLocation.lineCount(in: "") == 1)
        #expect(FilePreviewTextLocation.lineCount(in: "a\n") == 2)
        #expect(FilePreviewTextLocation.lineCount(in: "a\r\nb") == 2)
    }
}
