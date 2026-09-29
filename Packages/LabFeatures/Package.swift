// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabFeatures",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabCatalog", targets: ["LabCatalog"]),
        .library(name: "ActionAtlas", targets: ["ActionAtlas"]),
    ],
    dependencies: [
        .package(path: "../LabSupport"),
        .package(path: "../LabDomain"),
    ],
    targets: [
        .target(
            name: "LabCatalog",
            dependencies: [.product(name: "LabSupport", package: "LabSupport")],
            resources: [.copy("Resources/experiments.json")]
        ),
        .testTarget(name: "LabCatalogTests", dependencies: ["LabCatalog"]),
        // LAB-001 Action Atlas: App Intents, entities, and entity queries over OperationService.
        // Xcode extracts their metadata into the host app that links this product.
        .target(
            name: "ActionAtlas",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "ActionAtlasTests",
            dependencies: ["ActionAtlas", .product(name: "LabDomain", package: "LabDomain")]
        ),
    ]
)
