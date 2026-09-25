import Foundation
import Testing
@testable import CmuxFoundation

@Suite struct GlobalFontMagnificationStepTests {
    private func makeMagnification() -> (GlobalFontMagnification, UserDefaults, NotificationCenter) {
        let suiteName = "GlobalFontMagnificationStepTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let center = NotificationCenter()
        return (GlobalFontMagnification(userDefaults: defaults, notificationCenter: center), defaults, center)
    }

    @Test func stepsUpAndDownByOneIncrement() {
        let (magnification, _, _) = makeMagnification()
        #expect(magnification.stepPercent(by: 1) == 110)
        #expect(magnification.stepPercent(by: 1) == 120)
        #expect(magnification.stepPercent(by: -3) == 90)
        #expect(magnification.storedPercent == 90)
    }

    @Test func clampsAtRangeEdgesWithoutPostingNoOpChanges() {
        let (magnification, _, center) = makeMagnification()
        magnification.setPercent(GlobalFontMagnification.maximumPercent)
        let posts = PostCounter()
        let token = center.addObserver(
            forName: GlobalFontMagnification.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in posts.value += 1 }
        defer { center.removeObserver(token) }

        #expect(magnification.stepPercent(by: 1) == GlobalFontMagnification.maximumPercent)
        #expect(posts.value == 0)

        magnification.setPercent(GlobalFontMagnification.minimumPercent)
        posts.value = 0
        #expect(magnification.stepPercent(by: -1) == GlobalFontMagnification.minimumPercent)
        #expect(posts.value == 0)
        #expect(magnification.stepPercent(by: 1) == GlobalFontMagnification.minimumPercent + GlobalFontMagnification.stepPercent)
        #expect(posts.value == 1)
    }
}

/// Notifications post synchronously on the test's thread; the box only exists
/// to satisfy the observer block's Sendable requirement.
private final class PostCounter: @unchecked Sendable {
    var value = 0
}
