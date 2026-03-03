// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortWatch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PortWatch",
            path: "Sources/PortWatch"
        )
    ]
)
