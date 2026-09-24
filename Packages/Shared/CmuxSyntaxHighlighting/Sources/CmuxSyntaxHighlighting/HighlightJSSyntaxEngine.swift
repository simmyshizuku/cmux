import Foundation

/// Highlighting engine: bundled highlight.js in JavaScriptCore, with scopes
/// mapped straight onto ``TokenPalette`` roles.
///
/// highlight.js tokenizes; ``HighlightHTMLParser`` turns its markup into
/// runs; ``IdentifierUsageScanner`` adds call sites and member accesses; and
/// the palette paints the result. No CSS theme sits in between, so every
/// scope highlight.js reports (types, function and class names, built-ins)
/// keeps its color in both light and dark appearances.
///
/// One JavaScriptCore context is created lazily and reused. Callers must
/// still honor ``HighlightPolicy``; this actor applies it again so a missed
/// gate cannot push a multi-megabyte buffer through JavaScriptCore.
public actor HighlightJSSyntaxEngine: SyntaxHighlightingEngine {
    private var runtime: HighlightJSRuntime?
    private let policy: HighlightPolicy
    private let parser = HighlightHTMLParser()
    private let usageScanner = IdentifierUsageScanner()
    private var latestRequestID = 0

    /// Creates an engine that applies `policy` before invoking highlight.js.
    ///
    /// - Parameter policy: Size ceilings. Defaults to ``HighlightPolicy``'s
    ///   standard limits.
    public init(policy: HighlightPolicy = HighlightPolicy()) {
        self.policy = policy
    }

    /// Highlights `text` as `language`, painted with `theme`'s palette.
    public func highlight(
        text: String,
        language: String?,
        theme: TokenTheme
    ) async -> HighlightedText? {
        guard !Task.isCancelled else { return nil }
        latestRequestID &+= 1
        let requestID = latestRequestID
        // Yield before touching the policy or JavaScriptCore. Actor reentrancy
        // lets a newer edit publish its request ID here, dropping stale queued
        // requests instead of tokenizing every intermediate document.
        await Task.yield()
        guard !Task.isCancelled, requestID == latestRequestID else { return nil }
        guard let language, policy.shouldHighlight(content: text, language: language) else {
            return nil
        }

        // Creating the runtime evaluates highlight.js. Skip that work if this
        // request was canceled or superseded during the policy scan.
        guard !Task.isCancelled, requestID == latestRequestID else { return nil }
        let runtime: HighlightJSRuntime
        if let existing = self.runtime {
            runtime = existing
        } else {
            guard let created = HighlightJSRuntime() else { return nil }
            self.runtime = created
            runtime = created
        }

        guard let html = runtime.highlightHTML(text, language: language) else { return nil }
        guard !Task.isCancelled, requestID == latestRequestID,
              let tokenRuns = parser.parse(html: html, source: text) else { return nil }
        let runs = usageScanner.addingUsageRuns(to: tokenRuns, source: text, language: language)
        let builder = HighlightAttributedStringBuilder(palette: theme.palette)
        return HighlightedText(builder.build(source: text, runs: runs))
    }
}
