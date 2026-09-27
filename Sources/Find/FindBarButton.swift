import AppKit

/// Borderless find-bar button: hover and pressed fills, and an accent
/// outline while a toggle (`Aa`, `ab`, `.*`) is on, like VS Code's find widget.
@MainActor
final class FindBarButton: NSButton {
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var hoverTrackingArea: NSTrackingArea?
    private var toggleGlyph: NSAttributedString?

    /// A momentary button showing an SF Symbol.
    convenience init(symbolName: String, accessibilityLabel: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        imagePosition = .imageOnly
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        configure(accessibilityLabel: accessibilityLabel, target: target, action: action)
    }

    /// An on/off toggle showing a short text glyph such as `Aa`.
    convenience init(toggleTitle: NSAttributedString, accessibilityLabel: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        setButtonType(.pushOnPushOff)
        toggleGlyph = toggleTitle
        imagePosition = .noImage
        configure(accessibilityLabel: accessibilityLabel, target: target, action: action)
    }

    private func configure(accessibilityLabel: String, target: AnyObject?, action: Selector?) {
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        contentTintColor = .secondaryLabelColor
        toolTip = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            heightAnchor.constraint(equalToConstant: 20),
        ])
        updateAppearance()
    }

    override var state: NSControl.StateValue {
        didSet { updateAppearance() }
    }

    private var isToggleOn: Bool { toggleGlyph != nil && state == .on }

    private func updateAppearance() {
        let color: NSColor = isToggleOn || isHovered ? .labelColor : .secondaryLabelColor
        contentTintColor = color
        if let toggleGlyph {
            let title = NSMutableAttributedString(attributedString: toggleGlyph)
            title.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: title.length))
            attributedTitle = title
            attributedAlternateTitle = title
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        if isToggleOn {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            shape.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        } else if pressed || isHovered {
            NSColor.labelColor.withAlphaComponent(pressed ? 0.2 : 0.1).setFill()
            shape.fill()
        }
        super.draw(dirtyRect)
    }

    override func drawFocusRingMask() {}
}
