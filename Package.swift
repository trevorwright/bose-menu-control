// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoseMenuControl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BoseMenuControl", targets: ["BoseMenuControl"])
    ],
    targets: [
        .executableTarget(
            name: "BoseMenuControl",
            linkerSettings: [
                // Embed Info.plist in the executable so Bluetooth permission works for `swift run` too.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "BoseMenuControlTests", dependencies: ["BoseMenuControl"]),
    ]
)
