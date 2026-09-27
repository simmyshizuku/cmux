import AppKit
import CmuxFilePreviewCore
import CmuxFoundation

/// The `Aa` (match case), `ab` (whole word), and `.*` (regular expression)
/// toggles, sized to sit inside a search field like VS Code's find widget.
@MainActor
final class TextSearchOptionToggles: NSStackView {
    /// Called after the user flips a toggle, with the new options.
    var onChange: ((TextSearchOptions) -> Void)?

    private let matchCaseButton: FindBarButton
    private let wholeWordButton: FindBarButton
    private let regexButton: FindBarButton

    /// The options the toggles show. Setting it does not call ``onChange``.
    var options: TextSearchOptions {
        get {
            TextSearchOptions(
                matchCase: matchCaseButton.state == .on,
                matchWholeWord: wholeWordButton.state == .on,
                useRegularExpression: regexButton.state == .on
            )
        }
        set {
            matchCaseButton.state = newValue.matchCase ? .on : .off
            wholeWordButton.state = newValue.matchWholeWord ? .on : .off
            regexButton.state = newValue.useRegularExpression ? .on : .off
        }
    }

    /// Creates the toggles.
    ///
    /// - Parameter shortcutHints: Appends the ⌥⌘C / ⌥⌘W / ⌥⌘R hints to the
    ///   tooltips, for hosts that handle those keys.
    init(shortcutHints: Bool) {
        let labels = Self.labels(shortcutHints: shortcutHints)
        matchCaseButton = FindBarButton(toggleTitle: Self.glyph("Aa"), accessibilityLabel: labels.matchCase, target: nil, action: nil)
        wholeWordButton = FindBarButton(toggleTitle: Self.glyph("ab", underlined: true), accessibilityLabel: labels.wholeWord, target: nil, action: nil)
        regexButton = FindBarButton(toggleTitle: Self.glyph(".*"), accessibilityLabel: labels.regex, target: nil, action: nil)
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 1
        translatesAutoresizingMaskIntoConstraints = false
        for button in [matchCaseButton, wholeWordButton, regexButton] {
            button.target = self
            button.action = #selector(toggleDidChange(_:))
            addArrangedSubview(button)
        }
        matchCaseButton.setAccessibilityIdentifier("TextSearchMatchCaseToggle")
        wholeWordButton.setAccessibilityIdentifier("TextSearchWholeWordToggle")
        regexButton.setAccessibilityIdentifier("TextSearchRegexToggle")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Flips one toggle from a keyboard shortcut and reports the change.
    func toggle(_ keyPath: WritableKeyPath<TextSearchOptions, Bool>) {
        var next = options
        next[keyPath: keyPath].toggle()
        options = next
        onChange?(next)
    }

    @objc private func toggleDidChange(_ sender: NSButton) {
        onChange?(options)
    }

    private static func glyph(_ text: String, underlined: Bool = false) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: GlobalFontMagnification.systemFont(ofSize: 11, weight: .semibold),
        ]
        if underlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func labels(shortcutHints: Bool) -> (matchCase: String, wholeWord: String, regex: String) {
        let matchCase = String(localized: "textSearch.matchCase", defaultValue: "Match Case")
        let wholeWord = String(localized: "textSearch.matchWholeWord", defaultValue: "Match Whole Word")
        let regex = String(localized: "textSearch.useRegularExpression", defaultValue: "Use Regular Expression")
        guard shortcutHints else { return (matchCase, wholeWord, regex) }
        return ("\(matchCase) (⌥⌘C)", "\(wholeWord) (⌥⌘W)", "\(regex) (⌥⌘R)")
    }
}
