# CmuxSyntaxHighlighting

Leaf package for token-coloring source text. File Preview (and later other native code views) consume it. Editor chrome — gutters, current-line, indent guides — stays in the app target.

## Pipeline

1. `HighlightJSRuntime` runs the bundled highlight.js 11.11.1 (`Resources/highlight.min.js`, BSD-3-Clause) in JavaScriptCore and returns its HTML.
2. `HighlightHTMLParser` walks that markup once and maps each `hljs-*` scope through `HighlightScopeClassifier` to a `TokenRole`, producing UTF-16 `HighlightRun`s. Output that does not decode back to the source is rejected.
3. `IdentifierUsageScanner` colors what highlight.js leaves plain in code languages: call sites (`name(`) as `.function`, member accesses (`.name`) as `.property`.
4. `HighlightAttributedStringBuilder` paints the runs with the cmux product palette (`TokenPalette.cmuxDark` / `.cmuxLight`).

Scopes map straight to roles, with no CSS theme in between, so types, function and class names, and built-ins keep their color in both appearances.

## Test instantiation

```swift
let catalog = LanguageCatalog()
let language = catalog.language(forExtension: "swift")

let policy = HighlightPolicy()
guard policy.shouldHighlight(content: source, language: language) else { return }

let engine = HighlightJSSyntaxEngine(policy: policy)
let highlighted = await engine.highlight(text: source, language: language, theme: .dark)
```

No filesystem, `UserDefaults`, or app launch is required. `swift test` in this directory is the package gate.
