// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Crema",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CremaKit", targets: ["CremaKit"]),
    ],
    targets: [
        // The reusable engine — protocol, transport, registry. No UI deps so it
        // moves verbatim to any future watchOS / visionOS app. The actual app
        // shells live in the xcodegen-generated Crema.xcodeproj (iOS + macOS
        // app targets), both consuming this library and the shared Sources/CremaApp
        // SwiftUI views.
        .target(
            name: "CremaKit"
        ),
        .testTarget(
            name: "CremaKitTests",
            dependencies: ["CremaKit"]
        ),
    ]
)
