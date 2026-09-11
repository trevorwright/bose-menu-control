// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoseMenuControl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BoseMenuControl", targets: ["BoseMenuControl"])
    ],
    targets: [
        .executableTarget(name: "BoseMenuControl")
    ]
)
