// swift-tools-version: 6.0
import PackageDescription

// Zero third-party dependencies on purpose. See CLAUDE.md, hard rule 3.
let package = Package(
    name: "Dyogene",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DyogeneCore", targets: ["DyogeneCore"]),
        .executable(name: "dyogene", targets: ["dyogene"]),
        // Not "Dyogene": on a case-insensitive disk it would collide with the `dyogene` CLI binary.
        .executable(name: "DyogeneApp", targets: ["DyogeneApp"]),
    ],
    targets: [
        // Scanning, layout and analysis. No AppKit, no SwiftUI.
        .target(name: "DyogeneCore"),
        // Metadata-only command line tool used by the Claude skill. It never deletes.
        .executableTarget(name: "dyogene", dependencies: ["DyogeneCore"]),
        .executableTarget(name: "DyogeneApp", dependencies: ["DyogeneCore"]),
        .testTarget(name: "DyogeneCoreTests", dependencies: ["DyogeneCore"]),
    ]
)
