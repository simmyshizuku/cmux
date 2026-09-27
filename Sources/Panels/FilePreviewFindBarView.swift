import AppKit
import CmuxFilePreviewCore
import CmuxFoundation

/// The File Preview editor's find-and-replace bar, docked above the text as
/// the scroll view's `findBarView`.
///
/// Row one: replace chevron, query field with the `Aa` / `ab` / `.*`
/// toggles, match count, previous, next, close. Row two, shown by the
/// chevron: replace field, Replace, Replace All. The bar only reports user
/// intent; ``FilePreviewFindController`` owns searching and editing.
@MainActor
final class FilePreviewFindBarView: NSView, NSTextFieldDelegate {
    var onQueryChange: ((String) -> Void)?
    var onOptionsChange: ((TextSearchOptions) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?
    var onHeightChange: (() -> Void)?

    let queryField = NSTextField()
    let replaceField = NSTextField()
    let optionToggles = TextSearchOptionToggles(shortcutHints: true)
    private let queryContainer = FilePreviewFindFieldContainer()
    private let replaceContainer = FilePreviewFindFieldContainer()
    private let countLabel = NSTextField(labelWithString: "")
    private lazy var replaceChevron = FindBarButton(
        symbolName: "chevron.right",
        accessibilityLabel: String(localized: "fileEditor.find.toggleReplace", defaultValue: "Toggle Replace"),
        target: self,
        action: #selector(toggleReplaceRow)
    )
    private lazy var previousButton = FindBarButton(
        symbolName: "arrow.up",
        accessibilityLabel: String(localized: "search.previousMatch.help", defaultValue: "Previous match (Shift+Return)"),
        target: self,
        action: #selector(previousPressed)
    )
    private lazy var nextButton = FindBarButton(
        symbolName: "arrow.down",
        accessibilityLabel: String(localized: "search.nextMatch.help", defaultValue: "Next match (Return)"),
        target: self,
        action: #selector(nextPressed)
    )
    private lazy var closeButton = FindBarButton(
        symbolName: "xmark",
        accessibilityLabel: String(localized: "search.close.help", defaultValue: "Close (Esc)"),
        target: self,
        action: #selector(closePressed)
    )
    private lazy var replaceButton = Self.textButton(
        title: String(localized: "fileEditor.find.replace", defaultValue: "Replace"),
        target: self,
        action: #selector(replacePressed)
    )
    private lazy var replaceAllButton = Self.textButton(
        title: String(localized: "fileEditor.find.replaceAll", defaultValue: "Replace All"),
        target: self,
        action: #selector(replaceAllPressed)
    )
    private var replaceRowViews: [NSView] = []

    static let rowHeight: CGFloat = 30
    private static let fieldWidth: CGFloat = 300

    /// Whether the replace row is showing.
    private(set) var isReplaceVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureFields()
        layoutBar()
        setReplaceVisible(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    // Transparent so the editor's theme background shows through; only the
    // bottom separator is drawn.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    /// Height the bar needs for its visible rows.
    var preferredHeight: CGFloat {
        (isReplaceVisible ? 2 * Self.rowHeight : Self.rowHeight) + 6
    }

    func setReplaceVisible(_ visible: Bool) {
        isReplaceVisible = visible
        for view in replaceRowViews {
            view.isHidden = !visible
        }
        replaceChevron.image = NSImage(
            systemSymbolName: visible ? "chevron.down" : "chevron.right",
            accessibilityDescription: replaceChevron.accessibilityLabel()
        )
        queryField.nextKeyView = visible ? replaceField : queryField
        replaceField.nextKeyView = queryField
        onHeightChange?()
    }

    /// Shows a match count, "No results", or an invalid-pattern warning.
    func showStatus(current: Int?, total: Int, isCapped: Bool, invalidPattern: Bool, hasQuery: Bool) {
        let noResultsColor = NSColor.systemRed
        queryContainer.isInvalid = invalidPattern
        if invalidPattern {
            countLabel.stringValue = String(localized: "fileEditor.find.invalidRegex", defaultValue: "Invalid regex")
            countLabel.textColor = noResultsColor
        } else if !hasQuery {
            countLabel.stringValue = ""
        } else if total == 0 {
            countLabel.stringValue = String(localized: "fileEditor.find.noResults", defaultValue: "No results")
            countLabel.textColor = noResultsColor
        } else {
            let totalText = isCapped ? "\(total)+" : "\(total)"
            countLabel.stringValue = current.map { "\($0 + 1)/\(totalText)" } ?? "-/\(totalText)"
            countLabel.textColor = .secondaryLabelColor
        }
        let canNavigate = !invalidPattern && total > 0
        previousButton.isEnabled = canNavigate
        nextButton.isEnabled = canNavigate
        replaceButton.isEnabled = canNavigate
        replaceAllButton.isEnabled = canNavigate
    }

    /// Handles ⌥⌘C / ⌥⌘W / ⌥⌘R (options) and ⌥⌘Return (Replace All).
    func handleFindKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option] else {
            return false
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            guard isReplaceVisible else { return false }
            onReplaceAll?()
            return true
        }
        switch KeyboardLayout.normalizedCharacters(for: event) {
        case "c": optionToggles.toggle(\.matchCase)
        case "w": optionToggles.toggle(\.matchWholeWord)
        case "r": optionToggles.toggle(\.useRegularExpression)
        default: return false
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) else {
            return super.performKeyEquivalent(with: event)
        }
        return handleFindKeyEquivalent(event) || super.performKeyEquivalent(with: event)
    }

    // MARK: - Field delegate

    func controlTextDidBeginEditing(_ notification: Notification) {
        queryContainer.needsDisplay = true
        replaceContainer.needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        queryContainer.needsDisplay = true
        replaceContainer.needsDisplay = true
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === queryField else { return }
        onQueryChange?(queryField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            guard !textView.hasMarkedText() else { return false }
            let isShift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if control === replaceField {
                onReplace?()
            } else if isShift {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Actions

    @objc private func toggleReplaceRow() {
        setReplaceVisible(!isReplaceVisible)
        window?.makeFirstResponder(isReplaceVisible ? replaceField : queryField)
    }

    @objc private func previousPressed() { onPrevious?() }
    @objc private func nextPressed() { onNext?() }
    @objc private func closePressed() { onClose?() }
    @objc private func replacePressed() { onReplace?() }
    @objc private func replaceAllPressed() { onReplaceAll?() }

    // MARK: - Layout

    private func configureFields() {
        for field in [queryField, replaceField] {
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.cell?.lineBreakMode = .byClipping
            field.font = GlobalFontMagnification.systemFont(ofSize: 12)
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        queryField.placeholderString = String(localized: "fileEditor.find.placeholder", defaultValue: "Find")
        queryField.setAccessibilityIdentifier("FilePreviewFindQueryField")
        replaceField.placeholderString = String(localized: "fileEditor.find.replacePlaceholder", defaultValue: "Replace")
        replaceField.setAccessibilityIdentifier("FilePreviewFindReplaceField")
        countLabel.font = GlobalFontMagnification.monospacedDigitSystemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byClipping
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        optionToggles.onChange = { [weak self] options in
            self?.onOptionsChange?(options)
        }
    }

    private func layoutBar() {
        queryContainer.addSubview(queryField)
        queryContainer.addSubview(optionToggles)
        replaceContainer.addSubview(replaceField)
        for view: NSView in [
            replaceChevron, queryContainer, countLabel, previousButton, nextButton, closeButton,
            replaceContainer, replaceButton, replaceAllButton,
        ] {
            addSubview(view)
        }
        replaceRowViews = [replaceContainer, replaceButton, replaceAllButton]

        let firstRowCenter = 3 + Self.rowHeight / 2
        NSLayoutConstraint.activate([
            replaceChevron.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            replaceChevron.centerYAnchor.constraint(equalTo: topAnchor, constant: firstRowCenter),

            queryContainer.leadingAnchor.constraint(equalTo: replaceChevron.trailingAnchor, constant: 4),
            queryContainer.centerYAnchor.constraint(equalTo: replaceChevron.centerYAnchor),
            queryContainer.widthAnchor.constraint(equalToConstant: Self.fieldWidth),
            queryContainer.heightAnchor.constraint(equalToConstant: 24),

            queryField.leadingAnchor.constraint(equalTo: queryContainer.leadingAnchor, constant: 6),
            queryField.centerYAnchor.constraint(equalTo: queryContainer.centerYAnchor),
            queryField.trailingAnchor.constraint(equalTo: optionToggles.leadingAnchor, constant: -4),
            optionToggles.trailingAnchor.constraint(equalTo: queryContainer.trailingAnchor, constant: -2),
            optionToggles.centerYAnchor.constraint(equalTo: queryContainer.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: queryContainer.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: replaceChevron.centerYAnchor),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            previousButton.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 4),
            previousButton.centerYAnchor.constraint(equalTo: replaceChevron.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: replaceChevron.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 2),
            closeButton.centerYAnchor.constraint(equalTo: replaceChevron.centerYAnchor),
            closeButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),

            replaceContainer.leadingAnchor.constraint(equalTo: queryContainer.leadingAnchor),
            replaceContainer.topAnchor.constraint(equalTo: queryContainer.bottomAnchor, constant: 6),
            replaceContainer.widthAnchor.constraint(equalTo: queryContainer.widthAnchor),
            replaceContainer.heightAnchor.constraint(equalTo: queryContainer.heightAnchor),

            replaceField.leadingAnchor.constraint(equalTo: replaceContainer.leadingAnchor, constant: 6),
            replaceField.trailingAnchor.constraint(equalTo: replaceContainer.trailingAnchor, constant: -6),
            replaceField.centerYAnchor.constraint(equalTo: replaceContainer.centerYAnchor),

            replaceButton.leadingAnchor.constraint(equalTo: replaceContainer.trailingAnchor, constant: 8),
            replaceButton.centerYAnchor.constraint(equalTo: replaceContainer.centerYAnchor),
            replaceAllButton.leadingAnchor.constraint(equalTo: replaceButton.trailingAnchor, constant: 4),
            replaceAllButton.centerYAnchor.constraint(equalTo: replaceContainer.centerYAnchor),
        ])
    }

    private static func textButton(title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .push
        button.controlSize = .small
        button.font = GlobalFontMagnification.systemFont(ofSize: 11)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
