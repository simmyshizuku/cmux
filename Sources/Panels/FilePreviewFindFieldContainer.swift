import AppKit

/// Rounded well behind a find-bar text field; outlines in the accent color
/// while its field is editing, and in red for an invalid pattern.
@MainActor
final class FilePreviewFindFieldContainer: NSView {
    var isInvalid = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var isEditing: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        shape.fill()
        let stroke: NSColor? = isInvalid
            ? .systemRed
            : (isEditing ? .controlAccentColor : nil)
        if let stroke {
            stroke.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
    }
}
