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
        .library(name: "DocumentsEverywhere", targets: ["DocumentsEverywhere"]),
        .library(name: "SurfaceDeck", targets: ["SurfaceDeck"]),
        .library(name: "ShortcutWorkbench", targets: ["ShortcutWorkbench"]),
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
        .library(name: "SpeechTimeline", targets: ["SpeechTimeline"]),
        .library(name: "FindTheThing", targets: ["FindTheThing"]),
        .library(name: "LabJobs", targets: ["LabJobs"]),
        .library(name: "RenderThatSurvives", targets: ["RenderThatSurvives"]),
        .library(name: "ScreeningRoom", targets: ["ScreeningRoom"]),
        .library(name: "ScreeningRoomPlayback", targets: ["ScreeningRoomPlayback"]),
        .library(name: "AudioWorkshop", targets: ["AudioWorkshop"]),
        .library(name: "TabletopReality", targets: ["TabletopReality"]),
        .library(name: "PeerSession", targets: ["PeerSession"]),
        .library(name: "PeerSessionNetwork", targets: ["PeerSessionNetwork"]),
        .library(name: "LocalConstellation", targets: ["LocalConstellation"]),
        .library(name: "HomeSceneSandbox", targets: ["HomeSceneSandbox"]),
        .library(name: "WalletMoment", targets: ["WalletMoment"]),
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
        // LAB-009 Documents Everywhere: Quick Look previews, the in-app document browser, and the
        // opt-in local-fixture File Provider model. Depends on PortableObjects for `.anlab` decode
        // and for adopting a sample through the same importer/receipt path. Never holds the store.
        .target(
            name: "DocumentsEverywhere",
            dependencies: [
                .product(name: "LabDomain", package: "LabDomain"),
                "PortableObjects",
            ],
            resources: [
                .copy("Resources/harbor-note.anlab"),
                .copy("Resources/tide-card.anlab"),
            ]
        ),
        .testTarget(
            name: "DocumentsEverywhereTests",
            dependencies: [
                "DocumentsEverywhere",
                "PortableObjects",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
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
        // LAB-003 Shortcut Workbench: curated App Shortcuts, typed recipes, and rename-safe entity
        // references over Action Atlas entities and the host's OperationService.
        .target(
            name: "ShortcutWorkbench",
            dependencies: [
                "ActionAtlas",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
        ),
        .testTarget(
            name: "ShortcutWorkbenchTests",
            dependencies: [
                "ShortcutWorkbench",
                "ActionAtlas",
                .product(name: "LabDomain", package: "LabDomain"),
            ]
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
        // LAB-013 Speech Timeline: the timeline of provisional and finalized segments, caption
        // import and export, the save operation, the recording gate over LabSupport's permission
        // stager, and the on-device adapters. Speech and AVFoundation are imported on iOS and
        // macOS only; nothing here holds the store.
        .target(
            name: "SpeechTimeline",
            dependencies: [
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
        .testTarget(
            name: "SpeechTimelineTests",
            dependencies: [
                "SpeechTimeline",
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
        // LAB-006 Find the Thing: an in-app index of opted-in records, lexical search, and an
        // optional semantic retriever that may cite only records the index holds. App entity
        // donation is compiled for iOS and macOS and is not called unless a host asks.
        .target(
            name: "FindTheThing",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "FindTheThingTests",
            dependencies: ["FindTheThing", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // Finite, expensive work that records itself as a LabDomain job (LAB-032, reused by later
        // labs): the recorder over the host's OperationService, launch-time recovery, stop
        // signals, destination checks, atomic publication, and the background runway protocol.
        // Foundation only; the iOS continued-processing runway lives in the iPhone host.
        .target(
            name: "LabJobs",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "LabJobsTests",
            dependencies: ["LabJobs", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-032 Render That Survives: generated frames drawn on the GPU (Core Image on Metal) or
        // the CPU, encoded by AVFoundation into checkpointed segments, joined, checked, and
        // published with one rename. It never opens the store.
        .target(
            name: "RenderThatSurvives",
            dependencies: ["LabJobs", .product(name: "LabDomain", package: "LabDomain")],
            resources: [.copy("Resources/recipes.json")]
        ),
        .testTarget(
            name: "RenderThatSurvivesTests",
            dependencies: ["RenderThatSurvives", "LabJobs", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-031 Native Screening Room: the clips, the playback state, commands, signals, receipts,
        // the resume point, and the link a companion controller uses. Foundation and LabDomain only,
        // so it compiles on every host and its rules are tested without a player.
        .target(
            name: "ScreeningRoom",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "ScreeningRoomTests",
            dependencies: ["ScreeningRoom", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-031: the AVFoundation, AVKit, and MediaPlayer adapters, the shared screening model,
        // the player views, and the original fixture clips. Linked by the Mac, iPhone, and Apple TV
        // hosts; the Watch host does not link it.
        .target(
            name: "ScreeningRoomPlayback",
            dependencies: ["ScreeningRoom", .product(name: "LabDomain", package: "LabDomain")],
            resources: [.copy("Resources/Clips")]
        ),
        .testTarget(
            name: "ScreeningRoomPlaybackTests",
            dependencies: ["ScreeningRoomPlayback", "ScreeningRoom", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-029 Audio Workshop: the realtime kernel in C, where clang checks that every function
        // a render callback calls is non-blocking, and never allocates or locks.
        .target(name: "AudioWorkshopDSP"),
        // LAB-029 Audio Workshop: the graph preset, MIDI mapping, render stats, offline file
        // processing, the preset save through OperationService, and the iOS and macOS adapters:
        // AVAudioEngine output, Core MIDI input, and the AUv3 audio unit the extension serves.
        .target(
            name: "AudioWorkshop",
            dependencies: ["AudioWorkshopDSP", .product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "AudioWorkshopTests",
            dependencies: ["AudioWorkshop", "AudioWorkshopDSP", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-023 Tabletop Reality: the original procedural kit, placement rules, tracking gates,
        // relocalization and mapping policy, and the lab-owned anchor operations, over LabDomain
        // values. No RealityKit or ARKit here: the hosts draw the scene and run the AR adapter.
        .target(
            name: "TabletopReality",
            dependencies: [
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabSupport", package: "LabSupport"),
            ],
            resources: [.copy("Resources/tabletop-kit.json")]
        ),
        .testTarget(
            name: "TabletopRealityTests",
            dependencies: [
                "TabletopReality",
                .product(name: "LabDomain", package: "LabDomain"),
                .product(name: "LabSupport", package: "LabSupport"),
            ]
        ),
        // LAB-019 Local Constellation, the reusable layer: peer identities, explicit pairing with a
        // short code and pinned identity, role and protocol negotiation, the sealed session
        // envelope, reliable commands apart from replaceable samples, clock estimates, sequence
        // gaps, and presence. Transport-independent: an in-process loopback carries the same bytes a
        // network transport does. Foundation, CryptoKit, and LabDomain's StrictJSON only.
        .target(
            name: "PeerSession",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(name: "PeerSessionTests", dependencies: ["PeerSession"]),
        // LAB-019: the local-network transport for PeerSession over the Network framework (Bonjour
        // browse and advertise, TCP on the local network only). Linked only by Companions hosts,
        // never by a CoreLocal host. Compiled out of watchOS, which reaches peers through its phone.
        .target(
            name: "PeerSessionNetwork",
            dependencies: ["PeerSession"]
        ),
        .testTarget(name: "PeerSessionNetworkTests", dependencies: ["PeerSessionNetwork", "PeerSession"]),
        // LAB-019 Local Constellation, the experiment: a conductor, a controller, and a display over
        // PeerSession, the original cue sheet, the single-device simulation over the loopback, and
        // the peer's sensitive request committed through the host's OperationService.
        .target(
            name: "LocalConstellation",
            dependencies: ["PeerSession", .product(name: "LabDomain", package: "LabDomain")],
            resources: [.copy("Resources/cue-sheet.json")]
        ),
        .testTarget(
            name: "LocalConstellationTests",
            dependencies: ["LocalConstellation", "PeerSession", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-037 Home Scene Sandbox: fictional home, light-only scene preview/commit, partial
        // failure, and permission-gated live mode. HomeKit stays out of CoreLocal.
        .target(
            name: "HomeSceneSandbox",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "HomeSceneSandboxTests",
            dependencies: ["HomeSceneSandbox", .product(name: "LabDomain", package: "LabDomain")]
        ),
        // LAB-038 Wallet Moment: unsigned pass preview, barcode validation, expiration, and an
        // operator-supplied signing seam. No PassKit link and no pass-signing key in the client.
        .target(
            name: "WalletMoment",
            dependencies: [.product(name: "LabDomain", package: "LabDomain")]
        ),
        .testTarget(
            name: "WalletMomentTests",
            dependencies: ["WalletMoment", .product(name: "LabDomain", package: "LabDomain")]
        ),
    ]
)
