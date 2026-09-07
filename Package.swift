// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreePunto",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PuntoCore", targets: ["PuntoCore"]),
        .executable(name: "FreePunto", targets: ["FreePunto"]),
        .executable(name: "punto-transform", targets: ["PuntoCLI"]),
        .executable(name: "PuntoCoreTestsRunner", targets: ["PuntoCoreTestsRunner"])
    ],
    targets: [
        .target(
            name: "PuntoCore"
        ),
        .executableTarget(
            name: "FreePunto",
            dependencies: ["PuntoCore"],
            path: "Sources/PuntoApp"
        ),
        .executableTarget(
            name: "PuntoCLI",
            dependencies: ["PuntoCore"],
            path: "Sources/PuntoCLI"
        ),
        .executableTarget(
            name: "PuntoCoreTestsRunner",
            dependencies: ["PuntoCore"],
            path: "Sources/PuntoCoreTestsRunner"
        ),
        .testTarget(
            name: "PuntoCoreTests",
            dependencies: ["PuntoCore"]
        )
    ]
)
