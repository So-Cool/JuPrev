// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JuPrev",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotebookKit", targets: ["NotebookKit"]),
        .executable(name: "juprev", targets: ["juprev"]),
    ],
    targets: [
        .target(
            name: "NotebookKit",
            resources: [
                // Built by `npm run build` in renderer/; committed so Swift builds don't need Node.
                .copy("Resources/render.js"),
                .copy("Resources/style.css"),
            ]
        ),
        .executableTarget(name: "juprev", dependencies: ["NotebookKit"]),
        // Fixtures and snapshots are read from the source tree (via #filePath), so recording
        // new snapshots writes straight back into the repo.
        .testTarget(
            name: "NotebookKitTests",
            dependencies: ["NotebookKit"],
            exclude: ["Fixtures", "__Snapshots__"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
