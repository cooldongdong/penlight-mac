// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HawkPresenter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "HawkPresenter", path: "Sources/HawkPresenter")
    ]
)
