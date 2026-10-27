// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "finito",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "finito", targets: ["Finito"])
    ],
    targets: [
        .executableTarget(
            name: "Finito",
            path: "Sources/Finito"
        )
    ]
)
