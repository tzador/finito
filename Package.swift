// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "confetti",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "confetti", targets: ["Confetti"])
    ],
    targets: [
        .executableTarget(
            name: "Confetti",
            path: "Sources/Confetti"
        )
    ]
)
