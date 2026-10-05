// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlashcardReviewer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlashcardReviewer", targets: ["FlashcardReviewer"])
    ],
    targets: [
        .executableTarget(
            name: "FlashcardReviewer",
            path: "Sources/FlashcardEvaluatorApp",
            resources: [
                .copy("Resources/MathJax"),
                .copy("Resources/flashcard-reviewer-logo.png")
            ]
        ),
        .testTarget(
            name: "FlashcardReviewerTests",
            dependencies: ["FlashcardReviewer"],
            path: "Tests/FlashcardReviewerTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
