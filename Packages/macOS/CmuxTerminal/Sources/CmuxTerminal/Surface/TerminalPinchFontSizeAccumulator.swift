public import CoreGraphics

/// Converts trackpad pinch magnification deltas into whole-point terminal
/// font-size steps, the same unit Cmd+= and Cmd+- apply.
///
/// AppKit reports a pinch as many small `magnification` deltas. The
/// accumulator carries the remainder between events so a slow pinch still
/// steps, and a pinch that reverses direction gives back what it took.
public struct TerminalPinchFontSizeAccumulator: Sendable {
    /// Pinch magnification that equals one font-size point.
    public static let magnificationPerPoint: CGFloat = 0.08

    private var pending: CGFloat = 0

    /// Creates an accumulator with no carried pinch.
    public init() {}

    /// Drops any carried pinch, for the start or end of a gesture.
    public mutating func reset() {
        pending = 0
    }

    /// Adds one pinch delta.
    ///
    /// - Parameter magnification: The event's `magnification` delta.
    /// - Returns: Whole points to grow (positive) or shrink (negative) now.
    public mutating func consume(_ magnification: CGFloat) -> Int {
        guard magnification.isFinite else { return 0 }
        pending += magnification
        let steps = Int(pending / Self.magnificationPerPoint)
        pending -= CGFloat(steps) * Self.magnificationPerPoint
        return steps
    }

    /// The Ghostty binding action for a signed step count, or `nil` for zero.
    public static func bindingAction(forSteps steps: Int) -> String? {
        guard steps != 0 else { return nil }
        let verb = steps > 0 ? "increase_font_size" : "decrease_font_size"
        return "\(verb):\(abs(steps))"
    }
}
