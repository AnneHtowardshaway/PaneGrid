// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaneGrid",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaneGridCore", targets: ["PaneGridCore"]),
        .executable(name: "PaneGrid", targets: ["PaneGrid"]),
        .executable(name: "PaneGridFixture", targets: ["PaneGridFixture"])
    ],
    targets: [
        .target(name: "PaneGridCore"),
        .executableTarget(name: "PaneGrid", dependencies: ["PaneGridCore"]),
        .executableTarget(name: "PaneGridFixture"),
        .testTarget(name: "PaneGridCoreTests", dependencies: ["PaneGridCore"])
    ],
    swiftLanguageModes: [.v5]
)
