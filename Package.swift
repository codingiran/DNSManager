// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DNSManager",
    platforms: [
        .macOS(.v10_15),
        .macCatalyst(.v13),
        .iOS(.v13),
        .tvOS(.v13),
        .visionOS(.v1),
        .watchOS(.v6),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DNSManager",
            targets: ["DNSManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/codingiran/ScriptRunner.git", .upToNextMajor(from: "0.0.2")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DNSManager",
            dependencies: [
                .product(
                    name: "ScriptRunner",
                    package: "ScriptRunner",
                    condition: .when(platforms: [.macOS])),
            ],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]),
        .testTarget(
            name: "DNSManagerTests",
            dependencies: ["DNSManager"]),
    ])
