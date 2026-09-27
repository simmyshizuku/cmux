import AppKit
import CmuxFilePreviewCore

/// Find and replace for one File Preview text editor.
///
/// Owns the docked ``FilePreviewFindBarView``, compiles the query with
/// ``TextSearchMatcher``, highlights every match with layout-manager
/// temporary attributes (so syntax colors in the text storage are untouched),
/// and edits through `shouldChangeText` / `didChangeText` so replacements
/// are undoable, mark the file dirty, and re-run syntax highlighting.
@MainActor
final class FilePreviewFindController {
    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?
    let barView = FilePreviewFindBarView(frame: .zero)

    private var query = ""
    private var options = TextSearchOptions()
    private var matcher: TextSearchMatcher?
    private var isInvalidPattern = false
    private var matches: [NSRange] = []
    private var currentIndex: Int?
    private var highlightedLength = 0
    // Written once in init and read in the nonisolated deinit; never mutated after.
    nonisolated(unsafe) private var textChangeObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?

    /// Stops counting after this many matches; very large results show `N+`.
    private static let matchLimit = 20_000
    private static let matchColor = NSColor.systemYellow.withAlphaComponent(0.28)
    private static let currentMatchColor = NSColor.systemOrange.withAlphaComponent(0.55)

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        barView.onQueryChange = { [weak self] query in
            self?.query = query
            self?.recompile(revealFromSelection: true)
        }
        barView.onOptionsChange = { [weak self] options in
            self?.options = options
            self?.recompile(revealFromSelection: true)
        }
        barView.onNext = { [weak self] in self?.findNext() }
        barView.onPrevious = { [weak self] in self?.findPrevious() }
        barView.onReplace = { [weak self] in self?.replaceCurrent() }
        barView.onReplaceAll = { [weak self] in self?.replaceAll() }
        barView.onClose = { [weak self] in self?.hide() }
        barView.onHeightChange = { [weak self] in self?.applyBarHeight() }
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefreshAfterEdit() }
        }
    }

    deinit {
        if let textChangeObserver {
            NotificationCenter.default.removeObserver(textChangeObserver)
        }
    }

    var isVisible: Bool {
        scrollView?.isFindBarVisible == true
    }

    // MARK: - Entry points

    /// Shows the bar and focuses the query field, seeding it from a
    /// single-line selection the way VS Code does.
    ///
    /// - Parameter replace: `true` also opens the replace row; `nil` keeps its current state.
    @discardableResult
    func show(replace: Bool? = nil) -> Bool {
        guard let textView, let scrollView else { return false }
        if let seed = singleLineSelection(in: textView) {
            barView.queryField.stringValue = seed
            query = seed
        }
        if let replace, replace != barView.isReplaceVisible {
            barView.setReplaceVisible(replace)
        }
        if scrollView.findBarView !== barView {
            scrollView.findBarView = barView
        }
        applyBarHeight()
        scrollView.isFindBarVisible = true
        recompile(revealFromSelection: true)
        let field = replace == true ? barView.replaceField : barView.queryField
        if textView.window?.makeFirstResponder(field) == true {
            field.currentEditor()?.selectAll(nil)
        }
        return true
    }

    func hide() {
        guard let textView, let scrollView, scrollView.isFindBarVisible else { return }
        scrollView.isFindBarVisible = false
        clearHighlights()
        if let index = currentIndex, matches.indices.contains(index) {
            textView.setSelectedRange(matches[index])
        }
        textView.window?.makeFirstResponder(textView)
    }

    func findNext() {
        guard isVisible || show() else { return }
        move(by: 1)
    }

    func findPrevious() {
        guard isVisible || show() else { return }
        move(by: -1)
    }

    /// Puts the selected text in the query field without moving focus.
    func useSelectionForFind() {
        guard let textView, let selection = singleLineSelection(in: textView) else { return }
        barView.queryField.stringValue = selection
        query = selection
        if !isVisible {
            show()
        } else {
            recompile(revealFromSelection: true)
        }
    }

    func replaceCurrent() {
        guard let textView, let matcher, let storage = textView.textStorage else { return }
        guard let index = currentIndex, matches.indices.contains(index) else {
            move(by: 1)
            return
        }
        let range = matches[index]
        let text = textView.string
        guard let replacement = matcher.replacement(
            forMatchAt: range,
            in: text,
            template: barView.replaceField.stringValue
        ), textView.shouldChangeText(in: range, replacementString: replacement) else {
            return
        }
        storage.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        let resumeLocation = range.location + (replacement as NSString).length
        recomputeMatches()
        currentIndex = firstMatchIndex(atOrAfter: resumeLocation)
        revealCurrentMatch()
    }

    func replaceAll() {
        guard let textView, let matcher, let storage = textView.textStorage else { return }
        let plan = matcher.replacements(in: textView.string, template: barView.replaceField.stringValue)
        guard !plan.isEmpty,
              textView.shouldChangeText(
                  inRanges: plan.map { NSValue(range: $0.range) },
                  replacementStrings: plan.map(\.replacement)
              ) else {
            return
        }
        storage.beginEditing()
        for edit in plan.reversed() {
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        storage.endEditing()
        textView.didChangeText()
        recomputeMatches()
        currentIndex = nil
        applyHighlights()
    }

    // MARK: - Searching

    private func recompile(revealFromSelection: Bool) {
        do {
            matcher = try TextSearchMatcher(query: query, options: options)
            isInvalidPattern = false
        } catch {
            matcher = nil
            isInvalidPattern = true
        }
        recomputeMatches()
        if revealFromSelection, let textView {
            currentIndex = firstMatchIndex(atOrAfter: textView.selectedRange().location)
            revealCurrentMatch()
        } else {
            applyHighlights()
        }
    }

    private func recomputeMatches() {
        guard let textView, let matcher else {
            matches = []
            currentIndex = nil
            return
        }
        matches = matcher.matches(in: textView.string, limit: Self.matchLimit)
        if let index = currentIndex, !matches.indices.contains(index) {
            currentIndex = nil
        }
    }

    /// Edits in the text re-run the search on the next main-actor turn so a
    /// burst of keystrokes or a replace-all searches once.
    private func scheduleRefreshAfterEdit() {
        guard isVisible, refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshTask = nil
            guard self.isVisible, let textView = self.textView else { return }
            let caret = textView.selectedRange().location
            self.recomputeMatches()
            if self.currentIndex != nil {
                self.currentIndex = self.matches.firstIndex { NSMaxRange($0) >= caret }
            }
            self.applyHighlights()
        }
    }

    private func move(by step: Int) {
        guard let textView, !matches.isEmpty else {
            applyHighlights()
            return
        }
        if let index = currentIndex {
            currentIndex = (index + step + matches.count) % matches.count
        } else {
            let selection = textView.selectedRange()
            if step > 0 {
                currentIndex = firstMatchIndex(atOrAfter: NSMaxRange(selection))
            } else {
                currentIndex = matches.lastIndex { $0.location < selection.location } ?? matches.count - 1
            }
        }
        revealCurrentMatch()
    }

    private func firstMatchIndex(atOrAfter location: Int) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.firstIndex { $0.location >= location } ?? 0
    }

    private func revealCurrentMatch() {
        applyHighlights()
        guard let textView, let index = currentIndex, matches.indices.contains(index) else { return }
        let range = matches[index]
        // Selecting while a find field has focus would paint the inactive
        // selection over the current-match highlight; hide() selects instead.
        if textView.window?.firstResponder === textView {
            textView.setSelectedRange(range)
        }
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    // MARK: - Highlights

    private func applyHighlights() {
        clearHighlights()
        barView.showStatus(
            current: currentIndex,
            total: matches.count,
            isCapped: matches.count >= Self.matchLimit,
            invalidPattern: isInvalidPattern,
            hasQuery: !query.isEmpty
        )
        guard isVisible, let layoutManager = textView?.layoutManager else { return }
        for (index, range) in matches.enumerated() {
            let color = index == currentIndex ? Self.currentMatchColor : Self.matchColor
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
        highlightedLength = (textView?.string as NSString?)?.length ?? 0
    }

    private func clearHighlights() {
        guard let layoutManager = textView?.layoutManager, highlightedLength > 0 else { return }
        let length = min(highlightedLength, (textView?.string as NSString?)?.length ?? 0)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        highlightedLength = 0
    }

    // MARK: - Helpers

    private func applyBarHeight() {
        guard let scrollView else { return }
        barView.frame.size.height = barView.preferredHeight
        if scrollView.findBarView === barView {
            scrollView.findBarViewDidChangeHeight()
        }
    }

    private func singleLineSelection(in textView: NSTextView) -> String? {
        let range = textView.selectedRange()
        guard range.length > 0, range.length <= 1_000 else { return nil }
        let text = (textView.string as NSString).substring(with: range)
        return text.contains(where: \.isNewline) ? nil : text
    }
}
