// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Docking",
    platforms: [
        // macOS 14 is the product default from the goal file. Keeping the
        // minimum here explicit prevents us from accidentally using newer
        // windowing APIs that would make the personal app fail on Sonoma.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Docking", targets: ["Docking"]),
        // This tool is internal QA surface for a 0.0.0 app. Naming it with the
        // same Docking prefix keeps build logs, QA docs, and app-facing
        // terminology aligned with the actual app name.
        .executable(name: "DockingValidation", targets: ["DockingValidation"])
    ],
    targets: [
        .target(
            name: "DockingCore",
            path: "Sources/DockingCore"
        ),
        .executableTarget(
            name: "Docking",
            dependencies: ["DockingCore"],
            path: "Sources/Docking"
        ),
        .executableTarget(
            name: "DockingValidation",
            dependencies: ["DockingCore"],
            path: "Validation"
        )
    ]
)
