// swift-tools-version: 6.0

import PackageDescription

/// Leaf syntax-highlighting engine used by File Preview (and later other
/// native code views). Bundled highlight.js runs in JavaScriptCore; chrome
/// stays in the app.
let package = Package(
    name: "CmuxSyntaxHighlighting",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSyntaxHighlighting",
            targets: ["CmuxSyntaxHighlighting"]
        ),
    ],
    targets: [
        .target(
            name: "CmuxSyntaxHighlighting",
            resources: [
                // highlight.js 11.11.1 (BSD-3-Clause), all grammars.
                .copy("Resources/highlight.min.js"),
                .copy("Resources/highlight.js-LICENSE"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "CmuxSyntaxHighlightingTests",
            dependencies: ["CmuxSyntaxHighlighting"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
    ]
)
