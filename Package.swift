// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodexTokenCost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexTokenCostApp", targets: ["CodexTokenCostApp"]),
        .executable(name: "CodexTokenCostHelper", targets: ["CodexTokenCostHelper"])
    ],
    targets: [
        .target(
            name: "CCryptoBridge",
            path: "Sources/CCryptoBridge"
        ),
        .target(
            name: "CodexTokenCostCore",
            dependencies: ["CCryptoBridge"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CodexTokenCostApp",
            dependencies: ["CodexTokenCostCore"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CodexTokenCostHelper",
            dependencies: ["CodexTokenCostCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CodexTokenCostCoreTests",
            dependencies: ["CodexTokenCostCore", "CCryptoBridge"]
        ),
        .testTarget(
            name: "CodexTokenCostAppTests",
            dependencies: ["CodexTokenCostApp"]
        )
    ]
)
