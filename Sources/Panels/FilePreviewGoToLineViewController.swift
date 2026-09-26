import AppKit
import CmuxFilePreviewCore

/// The Go to Line field shown in a popover over a File Preview text editor.
///
/// Return parses the field as `line` or `line:column` and hands the location
/// back; invalid input beeps and keeps the field open. Escape closes it.
final class FilePreviewGoToLineViewController: NSViewController, NSTextFieldDelegate {
    weak var popover: NSPopover?
    private let onSubmit: (FilePreviewTextLocation) -> Void
    private let field = NSTextField()

    init(onSubmit: @escaping (FilePreviewTextLocation) -> Void) {
        self.onSubmit = onSubmit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        field.placeholderString = String(
            localized: "filePreview.goToLine.placeholder",
            defaultValue: "Line number, or line:column"
        )
        field.setAccessibilityLabel(String(localized: "shortcut.filePreviewGoToLine.label", defaultValue: "Go to Line"))
        field.delegate = self
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            field.widthAnchor.constraint(equalToConstant: 240),
        ])
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard let location = FilePreviewTextLocation(parsing: field.stringValue) else {
                NSSound.beep()
                return true
            }
            popover?.close()
            onSubmit(location)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            popover?.close()
            return true
        default:
            return false
        }
    }
}
