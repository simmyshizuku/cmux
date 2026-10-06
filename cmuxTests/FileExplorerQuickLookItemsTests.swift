import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite
struct FileExplorerQuickLookItemsTests {
    @Test func selectionOpensOnTheRowTheKeyboardSelectionSitsOn() throws {
        let items = try #require(
            FileExplorerQuickLookItems(
                selectedPaths: ["/repo/a.png", "/repo/b.png", "/repo/c.png"],
                anchorPath: "/repo/b.png",
                isLocal: true
            )
        )

        #expect(items.urls.map(\.path) == ["/repo/a.png", "/repo/b.png", "/repo/c.png"])
        #expect(items.currentIndex == 1)
    }

    @Test func anchorOutsideTheSelectionOpensOnTheFirstFile() throws {
        let items = try #require(
            FileExplorerQuickLookItems(
                selectedPaths: ["/repo/a.png", "/repo/b.png"],
                anchorPath: "/repo/other.png",
                isLocal: true
            )
        )

        #expect(items.currentIndex == 0)
    }

    @Test func emptySelectionHasNothingToShow() {
        #expect(FileExplorerQuickLookItems(selectedPaths: [], anchorPath: nil, isLocal: true) == nil)
    }

    @Test func remoteFilesCannotBeShown() {
        #expect(
            FileExplorerQuickLookItems(
                selectedPaths: ["/home/dev/a.png"],
                anchorPath: "/home/dev/a.png",
                isLocal: false
            ) == nil
        )
    }

    @Test func spaceAloneTogglesQuickLook() throws {
        let space = try #require(Self.keyDown(keyCode: 49, characters: " ", modifiers: []))
        let shiftSpace = try #require(Self.keyDown(keyCode: 49, characters: " ", modifiers: [.shift]))
        let commandSpace = try #require(Self.keyDown(keyCode: 49, characters: " ", modifiers: [.command]))
        let letter = try #require(Self.keyDown(keyCode: 0, characters: "a", modifiers: []))

        #expect(RightSidebarKeyboardNavigation.isPlainSpace(space))
        #expect(!RightSidebarKeyboardNavigation.isPlainSpace(shiftSpace))
        #expect(!RightSidebarKeyboardNavigation.isPlainSpace(commandSpace))
        #expect(!RightSidebarKeyboardNavigation.isPlainSpace(letter))
    }

    private static func keyDown(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
