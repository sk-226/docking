// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Docking",
    platforms: [
        // Docking is a personal pre-1.0 app, so the runtime baseline follows the
        // current Tahoe development target. The explicit string keeps the
        // manifest simple without adding source-level OS branches.
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Docking", targets: ["Docking"]),
        // This tool is internal QA surface for a pre-1.0 app. Naming it with the
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
