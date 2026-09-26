import CoreGraphics
import Testing

@testable import CmuxWindowing

@Suite("Window tear-off placement")
struct WindowTearOffPlacementTests {
    private let placement = WindowTearOffPlacement(pointerOffsetFromTopLeft: CGSize(width: 100, height: 40))
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1_512, height: 944)

    @Test("A release outside every main window tears off")
    func releaseOutsideWindowsTearsOff() {
        let frames = [CGRect(x: 0, y: 0, width: 800, height: 600)]

        #expect(placement.shouldTearOff(at: CGPoint(x: 1_000, y: 300), mainWindowFrames: frames))
        #expect(placement.shouldTearOff(at: CGPoint(x: 10, y: 10), mainWindowFrames: []))
    }

    @Test("A release over any main window does not tear off")
    func releaseOverWindowStaysPut() {
        let frames = [
            CGRect(x: 0, y: 0, width: 800, height: 600),
            CGRect(x: 900, y: 100, width: 500, height: 500),
        ]

        #expect(!placement.shouldTearOff(at: CGPoint(x: 400, y: 300), mainWindowFrames: frames))
        #expect(!placement.shouldTearOff(at: CGPoint(x: 1_000, y: 300), mainWindowFrames: frames))
    }

    @Test("The new window keeps its size and puts the pointer at the offset")
    func frameKeepsPointerAtOffset() {
        let frame = placement.frame(
            forWindowSize: CGSize(width: 600, height: 400),
            releasedAt: CGPoint(x: 500, y: 700),
            visibleFrame: visibleFrame
        )

        #expect(frame == CGRect(x: 400, y: 340, width: 600, height: 400))
        #expect(frame.maxY - 700 == 40)
    }

    @Test("A release near a display edge is pulled fully on screen")
    func frameIsClampedToVisibleFrame() {
        let nearTopLeft = placement.frame(
            forWindowSize: CGSize(width: 600, height: 400),
            releasedAt: CGPoint(x: 20, y: 940),
            visibleFrame: visibleFrame
        )
        let nearBottomRight = placement.frame(
            forWindowSize: CGSize(width: 600, height: 400),
            releasedAt: CGPoint(x: 1_500, y: 5),
            visibleFrame: visibleFrame
        )

        #expect(nearTopLeft == CGRect(x: 0, y: 544, width: 600, height: 400))
        #expect(nearBottomRight == CGRect(x: 912, y: 0, width: 600, height: 400))
    }

    @Test("A window larger than the display shrinks to fit it")
    func oversizedWindowShrinks() {
        let frame = placement.frame(
            forWindowSize: CGSize(width: 2_000, height: 1_200),
            releasedAt: CGPoint(x: 700, y: 500),
            visibleFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055)
        )

        #expect(frame == CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055))
    }
}
