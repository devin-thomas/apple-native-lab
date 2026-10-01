// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LabFeatures",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "LabCatalog", targets: ["LabCatalog"]),
        .library(name: "ActionAtlas", targets: ["ActionAtlas"]),
        .library(name: "ContextCards", targets: ["ContextCards"]),
        .library(name: "TypedIntelligence", targets: ["TypedIntelligence"]),
        .library(name: "AccessSuperpower", targets: ["AccessSuperpower"]),
        .library(name: "ShareIngress", targets: ["ShareIngress"]),
        .library(name: "PortableObjects", targets: ["PortableObjects"]),
        .library(name: "PickUpHere", targets: ["PickUpHere"]),
        .library(name: "SurfaceDeck", targets: ["SurfaceDeck"]),
        // CORE-012: the journey's fixed values only. A product so that Xcode gives the journey's
        // tests a scheme, as every module's scheme holds its own tests. No host links it.
        .library(name: "FirstJourney", targets: ["FirstJourney"]),
        .library(name: "DesktopNativePower", targets: ["DesktopNativePower"]),
        .library(name: "TrustDesk", targets: ["TrustDesk"]),
        .library(name: "LocalModelBench", targets: ["LocalModelBench"]),
        .library(name: "DurableSyncLedger", targets: ["DurableSyncLedger"]),
        .library(name: "TactileGrammar", targets: ["TactileGrammar"]),
        .library(name: "RespectfulAttention", targets: ["RespectfulAttention"]),
        .library(name: "PointInspect", targets: ["PointInspect"]),
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
        // LAB-002 Context Cards: the visible sample, the schema gate, and the set-aside decision
        // over Action Atlas's operation path. SwiftUI draws the snippet; the host draws the card.
        .target(
            name: "ContextCards",
            dependencies: [
                "ActionAtlas",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
        ),
        .testTarget(
            name: "ContextCardsTests",
            dependencies: [
                "ContextCards",
                "ActionAtlas",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
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
        // LAB-016 Pick Up Here: a continuation hint (identifiers and a section position) and the
        // explicit link or document a person copies when Handoff is not the transfer. Resolving
        // and importing go through OperationService. NSUserActivity is Foundation, on every host.
        .target(
            name: "PickUpHere",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "PickUpHereTests",
            dependencies: ["PickUpHere", .product(name: "LabDomain", package: "LabDomain")]
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
        // LAB-042 Desktop Native Power: command palette, documents that outlive their windows,
        // a Services-style text import, and one allowlisted command. Mac-only scenes stay in the host.
        .target(
            name: "DesktopNativePower",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")],
            resources: [.copy("Resources/sample-desk-note.txt")]
        ),
        .testTarget(
            name: "DesktopNativePowerTests",
            dependencies: [
                "DesktopNativePower",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
        ),
        // LAB-041 Trust Desk: local authorization, a scoped keychain record, and a labeled
        // passkey simulation. The sealed-record open commits through OperationService.
        .target(
            name: "TrustDesk",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "TrustDeskTests",
            dependencies: ["TrustDesk", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-015 Local Model Bench: a fixed corpus, a license and memory gate before any load,
        // and a fixture executor that is not inference. No Core ML or Foundation Models import.
        .target(
            name: "LocalModelBench",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "LocalModelBenchTests",
            dependencies: [
                "LocalModelBench",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
        ),
        // LAB-017 Durable Sync Ledger: a local write-ahead log, an optional private/shared profile,
        // and manual document exchange. CloudKit is not imported; CoreLocal does not link it.
        .target(
            name: "DurableSyncLedger",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "DurableSyncLedgerTests",
            dependencies: ["DurableSyncLedger", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-030 Tactile Grammar: three cues, their visual and spoken equivalents, and the
        // authorization-checked play operation. Core Haptics, GameController, and WatchKit are
        // imported only on the platforms that ship them, so a host that does not link this product
        // never links those frameworks.
        .target(
            name: "TactileGrammar",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "TactileGrammarTests",
            dependencies: ["TactileGrammar", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-043 Respectful Attention: the agenda, Focus filter, and consented lab alerts over
        // LabDomain. AlarmKit and UserNotifications stay out of this package so CoreLocal never
        // links them.
        .target(
            name: "RespectfulAttention",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "RespectfulAttentionTests",
            dependencies: ["RespectfulAttention", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-012 Point, Inspect, Propose: a chosen image becomes a reviewable item. Vision OCR
        // and barcodes, an on-device description where the system can attach an image, and manual
        // fields. The model-tool adapter proposes; the app UI commits.
        .target(
            name: "PointInspect",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "PointInspectTests",
            dependencies: [
                "PointInspect",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
        ),
    ]
)
