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
        .library(name: "ShareIngress", targets: ["ShareIngress"]),
        .library(name: "PortableObjects", targets: ["PortableObjects"]),
        .library(name: "SurfaceDeck", targets: ["SurfaceDeck"]),
    ],
    dependencies: [
        .package(path: "../LabSupport"),
        .package(path: "../LabDomain"),
        .package(path: "../LabStaging"),
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
        // LAB-007 Share Ingress Station: stages shared and pasted content into a staging inbox and
        // lists it for review. Used by the share extension and by both hosts' import fallbacks.
        .target(
            name: "ShareIngress",
            dependencies: [
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabStaging", package: "LabStaging"),
            ]
        ),
        .testTarget(
            name: "ShareIngressTests",
            dependencies: [
                "ShareIngress",
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabStaging", package: "LabStaging"),
            ]
        ),
        // LAB-008 Portable Objects: the `.anlab` document, its Transferable representations, and
        // imports that stage (LabStaging), validate, and commit through OperationService.
        .target(
            name: "PortableObjects",
            dependencies: [
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabStaging", package: "LabStaging"),
            ],
            resources: [.copy("Resources/sample-object.anlab")]
        ),
        .testTarget(
            name: "PortableObjectsTests",
            dependencies: ["PortableObjects", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-004 Surface Deck: the demo session's actions and App Intents over the host's
        // OperationService, the immutable snapshot the app writes for surfaces, and the widget
        // views. SwiftUI and AppIntents only: the widget extension adds WidgetKit, and nothing here
        // opens the store or runs a model.
        .target(
            name: "SurfaceDeck",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "SurfaceDeckTests",
            dependencies: ["SurfaceDeck", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // CORE-012: the first six-lab journey across every M1 module over one OperationService.
        // Tests only; no product or host links it.
        .testTarget(
            name: "FirstJourneyTests",
            dependencies: [
                "ActionAtlas", "SurfaceDeck", "ShareIngress", "PortableObjects", "TypedIntelligence", "AccessSuperpower",
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabStaging", package: "LabStaging"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
    ]
)
