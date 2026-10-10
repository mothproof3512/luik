// swift-tools-version:5.9
import PackageDescription

// Luik — a Guake-style drop-down app for macOS.
//
// SwiftTerm (MIT, Miguel de Icaza) is bundled as source in Vendor/SwiftTerm
// (version 1.11.2), so the build needs no network access, Metal toolchain or
// extra packages. Only the Command Line Tools (or Xcode) are required.

let package = Package(
    name: "Luik",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Vendor/SwiftTerm",
            exclude: ["LICENSE"]
        ),
        .executableTarget(
            name: "Luik",
            dependencies: ["SwiftTerm"],
            path: "Sources/Luik",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
