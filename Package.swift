// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Singe",
    platforms: [.macOS(.v13)],
    products: [
        // The whole app. Replaced on every update.
        .library(name: "SingeCore", type: .dynamic, targets: ["SingeCore"]),
        // The launcher inside Singe.app. Kept unchanged so Accessibility stays granted.
        .executable(name: "Singe", targets: ["SingeLauncher"]),
    ],
    targets: [
        .target(
            name: "SingeCore",
            path: "Sources/SingeCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreServices"),
            ]
        ),
        .executableTarget(
            name: "SingeLauncher",
            path: "Sources/SingeLauncher"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
