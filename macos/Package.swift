// swift-tools-version: 5.9
// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.
import PackageDescription

let package = Package(
    name: "BookLand",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BookLand", targets: ["BookLandApp"])
    ],
    targets: [
        .executableTarget(
            name: "BookLandApp",
            path: "Sources/BookLandApp"
        )
    ]
)
