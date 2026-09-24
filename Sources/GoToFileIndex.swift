import Foundation

struct GoToFileEntry: Equatable, Sendable {
    let relativePath: String

    var name: String { (relativePath as NSString).lastPathComponent }

    var searchKeywords: [String] {
        var words = ""
        var previousWasLowercaseOrNumber = false
        for character in name {
            if character.isUppercase && previousWasLowercaseOrNumber {
                words.append(" ")
            }
            words.append(character)
            previousWasLowercaseOrNumber = character.isLowercase || character.isNumber
        }
        return words == name ? [relativePath] : [relativePath, words]
    }

    func absolutePath(in rootPath: String) -> String {
        (rootPath as NSString).appendingPathComponent(relativePath)
    }
}

/// Lists files for the palette with ripgrep so repository ignore rules apply.
actor GoToFileIndex {
    private let executable: FileSearchRipgrepExecutable
    private let maximumFiles: Int

    init(executable: FileSearchRipgrepExecutable, maximumFiles: Int = 100_000) {
        self.executable = executable
        self.maximumFiles = maximumFiles
    }

    func files(in rootPath: String) async throws -> [GoToFileEntry] {
        let executable = executable
        let maximumFiles = maximumFiles
        let scan = Task.detached(priority: .userInitiated) {
            try Self.scan(rootPath: rootPath, executable: executable, maximumFiles: maximumFiles)
        }
        return try await withTaskCancellationHandler {
            try await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

    private nonisolated static func scan(
        rootPath: String,
        executable: FileSearchRipgrepExecutable,
        maximumFiles: Int
    ) throws -> [GoToFileEntry] {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable.url
        process.currentDirectoryURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        process.arguments = executable.prefixArguments + ["--files", "--hidden", "--no-require-git", "--glob", "!.git/**", "--null"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        output.fileHandleForWriting.closeFile()

        var entries: [GoToFileEntry] = []
        entries.reserveCapacity(min(maximumFiles, 4096))
        var pending = Data()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            output.fileHandleForReading.closeFile()
        }

        while !Task.isCancelled && entries.count < maximumFiles {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            var start = pending.startIndex
            while let terminator = pending[start...].firstIndex(of: 0) {
                let pathData = pending[start..<terminator]
                if let path = String(data: pathData, encoding: .utf8), !path.isEmpty {
                    entries.append(GoToFileEntry(relativePath: path))
                }
                start = pending.index(after: terminator)
                if entries.count >= maximumFiles { break }
            }
            pending.removeSubrange(..<start)
        }
        try Task.checkCancellation()
        if entries.count < maximumFiles {
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
                throw GoToFileIndexError.ripgrepFailed(process.terminationStatus)
            }
        }
        return entries.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }
}

private enum GoToFileIndexError: Error {
    case ripgrepFailed(Int32)
}
