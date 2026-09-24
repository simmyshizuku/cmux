import Foundation
import JavaScriptCore

/// Runs the bundled highlight.js in a private JavaScriptCore context.
///
/// Not thread-safe: a `JSContext` must not be entered concurrently. The
/// owning ``HighlightJSSyntaxEngine`` actor serializes every call.
final class HighlightJSRuntime {
    private let context: JSContext
    private let hljs: JSValue

    /// Loads highlight.js from `scriptURL`.
    ///
    /// - Parameter scriptURL: Location of `highlight.min.js`. Defaults to the
    ///   copy bundled with this package.
    /// - Returns: `nil` when the script is missing or fails to evaluate.
    init?(scriptURL: URL? = Bundle.module.url(forResource: "highlight.min", withExtension: "js")) {
        guard let scriptURL,
              let script = try? String(contentsOf: scriptURL, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.evaluateScript(script)
        guard context.exception == nil,
              let hljs = context.objectForKeyedSubscript("hljs"),
              hljs.isObject else { return nil }
        self.context = context
        self.hljs = hljs
    }

    /// Returns highlight.js HTML for `code`, or `nil` when `language` is not
    /// registered or highlighting throws.
    func highlightHTML(_ code: String, language: String) -> String? {
        context.exception = nil
        guard let grammar = hljs.invokeMethod("getLanguage", withArguments: [language]),
              grammar.isObject else { return nil }
        let options: [String: Any] = ["language": language, "ignoreIllegals": true]
        guard let result = hljs.invokeMethod("highlight", withArguments: [code, options]),
              context.exception == nil,
              let value = result.objectForKeyedSubscript("value"),
              value.isString else { return nil }
        return value.toString()
    }
}
