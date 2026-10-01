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
        .library(name: "CommerceWithoutTricks", targets: ["CommerceWithoutTricks"]),
        // CORE-012: the journey's fixed values only. A product so that Xcode gives the journey's
        // tests a scheme, as every module's scheme holds its own tests. No host links it.
        .library(name: "FirstJourney", targets: ["FirstJourney"]),
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
        // LAB-040 Commerce Without Tricks: local product fixtures products and a local
        // transaction-state simulator. Entitlement grants commit through OperationService. StoreKit
        // is not linked, so no button can create a real charge.
        .target(
            name: "CommerceWithoutTricks",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "CommerceWithoutTricksTests",
            dependencies: ["CommerceWithoutTricks", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // CORE-012: the first six-lab journey across every M1 module over one OperationService.
        // `FirstJourney` holds only the journey's fixed values; no host links it.
        .target(
            name: "FirstJourney",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "FirstJourneyTests",
            dependencies: [
                "FirstJourney", "ActionAtlas", "SurfaceDeck", "ShareIngress", "PortableObjects", "TypedIntelligence", "AccessSuperpower",
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabStaging", package: "LabStaging"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
    ]
)
