// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreePunto",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PuntoCore", targets: ["PuntoCore"]),
        .executable(name: "FreePunto", targets: ["FreePunto"])
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
        .testTarget(
            name: "PuntoCoreTests",
            dependencies: ["PuntoCore"]
        )
    ]
)
