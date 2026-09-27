import CmuxFilePreviewCore

extension TextSearchOptions {
    /// ripgrep flags for these options: case, whole word, and literal vs regex.
    ///
    /// Match case off maps to `--ignore-case`, as VS Code's toggle does, rather
    /// than ripgrep's `--smart-case`.
    var ripgrepArguments: [String] {
        var arguments = [matchCase ? "--case-sensitive" : "--ignore-case"]
        if matchWholeWord {
            arguments.append("--word-regexp")
        }
        if !useRegularExpression {
            arguments.append("--fixed-strings")
        }
        return arguments
    }
}
