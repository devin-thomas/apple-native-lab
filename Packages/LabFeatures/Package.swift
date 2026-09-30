// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabFeatures",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabCatalog", targets: ["LabCatalog"]),
        .library(name: "ActionAtlas", targets: ["ActionAtlas"]),
        .library(name: "TypedIntelligence", targets: ["TypedIntelligence"]),
        .library(name: "AccessSuperpower", targets: ["AccessSuperpower"]),
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
        // LAB-010 Typed Local Intelligence: typed proposals from the on-device model or the
        // non-model sample parser, validated and proposed as the model-tool adapter, committed only
        // after a person approves. FoundationModels is imported on iOS and macOS only.
        .target(
            name: "TypedIntelligence",
            dependencies: [
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
        .testTarget(
            name: "TypedIntelligenceTests",
            dependencies: [
                "TypedIntelligence",
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
        // LAB-035 Access as a Superpower: the task, its chart semantics and Audio Graph descriptor,
        // and the practice data, over LabDomain values. The hosts draw it and commit through the
        // operation service.
        .target(
            name: "AccessSuperpower",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "AccessSuperpowerTests",
            dependencies: ["AccessSuperpower", .product(name: "LabDomain", package: "LabDomain")]
        ),
    ]
)
