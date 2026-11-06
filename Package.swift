// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Penlight",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Penlight", path: "Sources/Penlight")
    ]
)
