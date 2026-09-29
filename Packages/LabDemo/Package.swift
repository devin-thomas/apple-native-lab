// swift-tools-version: 6.2
import PackageDescription

// Replayable demonstrations and evidence export (CORE-009).
//
// The runner drives LabDomain's OperationService against a fresh LabStore store, and it reports
// with LabSupport's evidence vocabulary. LabSupport must not depend on LabDomain, and neither
// store nor domain should carry evidence tooling, so the code that needs all three lives here.
// It uses only system frameworks and adds no third-party code.
let package = Package(
    name: "LabDemo",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabDemo", targets: ["LabDemo"]),
    ],
    dependencies: [
        .package(path: "../LabDomain"),
        .package(path: "../LabStore"),
        .package(path: "../LabSupport"),
    ],
    targets: [
        .target(
            name: "LabDemo",
            dependencies: [
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabStore", package: "LabStore"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
        .testTarget(
            name: "LabDemoTests",
            dependencies: [
                "LabDemo",
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabStore", package: "LabStore"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
    ]
)
