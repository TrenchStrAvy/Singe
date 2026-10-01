// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Singe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Singe",
            path: "Sources/Singe",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreServices"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
