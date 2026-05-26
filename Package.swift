// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Crema",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CremaKit", targets: ["CremaKit"]),
    ],
    targets: [
        // Reusable engine: Modbus framing, CRC, profile encoding, BLE actor (later).
        // Has no UI dependencies so it can move to iOS/watchOS targets verbatim.
        .target(
            name: "CremaKit"
        ),
        .testTarget(
            name: "CremaKitTests",
            dependencies: ["CremaKit"]
        ),
        // The desktop prototype app — depends on the engine, supplies the UI.
        .executableTarget(
            name: "CremaApp",
            dependencies: ["CremaKit"],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
