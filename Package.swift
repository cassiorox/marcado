// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Marcado",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Marcado",
            path: "Sources/Marcado"
        )
    ],
    swiftLanguageVersions: [.v5]
)
