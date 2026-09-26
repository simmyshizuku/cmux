public import CoreGraphics

/// Pure placement rules for tearing a tab or workspace off into its own window.
///
/// A drag released where no cmux destination accepted it becomes a tear-off
/// only when the release point is outside every main window. A release over a
/// window's chrome that simply had no drop target stays a no-op, so a missed
/// drop never spawns a window on top of the one the user was aiming at.
public struct WindowTearOffPlacement: Sendable {
    /// Where the release point lands inside the new window, measured from its
    /// top-left corner. This keeps the grabbed item under the pointer, near
    /// the tab bar and sidebar rows it came from.
    public var pointerOffsetFromTopLeft: CGSize

    /// Creates placement rules.
    ///
    /// - Parameter pointerOffsetFromTopLeft: Offset of the release point from
    ///   the new window's top-left corner.
    public init(pointerOffsetFromTopLeft: CGSize = CGSize(width: 120, height: 40)) {
        self.pointerOffsetFromTopLeft = pointerOffsetFromTopLeft
    }

    /// Reports whether a release point should tear off into a new window.
    ///
    /// - Parameters:
    ///   - point: The release point in screen coordinates.
    ///   - mainWindowFrames: Frames of every visible main window.
    /// - Returns: `true` when no main window contains the point.
    public func shouldTearOff(at point: CGPoint, mainWindowFrames: [CGRect]) -> Bool {
        !mainWindowFrames.contains { $0.contains(point) }
    }

    /// Returns the frame for a torn-off window released at `point`.
    ///
    /// The window keeps `size`, is positioned so the pointer sits at
    /// ``pointerOffsetFromTopLeft``, and is then pulled fully inside
    /// `visibleFrame` (shrinking only when it is larger than the display).
    ///
    /// - Parameters:
    ///   - size: The window size, usually the source window's.
    ///   - point: The release point in screen coordinates (origin bottom-left).
    ///   - visibleFrame: The visible frame of the display under the point.
    public func frame(forWindowSize size: CGSize, releasedAt point: CGPoint, visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let proposedX = point.x - pointerOffsetFromTopLeft.width
        let proposedY = point.y + pointerOffsetFromTopLeft.height - height
        let x = min(max(proposedX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
