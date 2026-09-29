# Capability matrix

All rows are currently **specified, not device-tested**. Host descriptions are target plans; each API gets an actual availability probe during implementation. See the experiment for fallback and boundaries.
| ID / experience | Wave | Planned hosts | Main capability |
|---|---|---|---|
| [LAB-001 — Action Atlas](../experiments/LAB-001-action-atlas.md) | M1 | iPhone, iPad, Mac; Watch adapter later | AppIntents, AppEntity, entity queries |
| [LAB-002 — Context Cards](../experiments/LAB-002-context-cards.md) | M2 | iPhone and iPad; Mac support probed separately | App Schemas, NSUserActivity, SwiftUI snippets |
| [LAB-003 — Shortcut Workbench](../experiments/LAB-003-shortcut-workbench.md) | M2 | iPhone, iPad, Mac | AppIntents, Shortcuts, 27-generation Storage actions |
| [LAB-004 — Surface Deck](../experiments/LAB-004-surface-deck.md) | M1 | iPhone, iPad, Mac; supported Watch surfaces | WidgetKit, Control widgets, AppIntents |
| [LAB-005 — Live Session Beacon](../experiments/LAB-005-live-session-beacon.md) | M2 | iPhone; system-mediated companion presentations probed | ActivityKit, WidgetKit |
| [LAB-006 — Find the Thing](../experiments/LAB-006-find-the-thing.md) | M2 | iPhone, iPad, Mac | Core Spotlight, AppEntity indexing, optional model retrieval |
| [LAB-007 — Share Ingress Station](../experiments/LAB-007-share-ingress-station.md) | M1 | iPhone, iPad; separate Mac Share extension | Share extensions, NSItemProvider, App Groups |
| [LAB-008 — Portable Objects](../experiments/LAB-008-portable-objects.md) | M1 | iPhone, iPad, Mac | Transferable, UTType, document import/export |
| [LAB-009 — Documents Everywhere](../experiments/LAB-009-documents-everywhere.md) | M4 | Mac and iPhone/iPad extensions separately | Quick Look, File Provider, document coordination |
| [LAB-010 — Typed Local Intelligence](../experiments/LAB-010-typed-local-intelligence.md) | M1 | Apple-Intelligence-capable iPhone/iPad/Mac | Foundation Models, guided generation, Tool |
| [LAB-011 — Model Routing Observatory](../experiments/LAB-011-model-routing-observatory.md) | M4 | iPhone, iPad, Mac; optional watchOS 27 PCC path | Foundation Models LanguageModel, PCC, optional provider adapter |
| [LAB-012 — Point, Inspect, Propose](../experiments/LAB-012-point-inspect-propose.md) | M3 | Supported iPhone; iPad/Mac camera-import fallback | Vision, Foundation Models image input, Visual Intelligence integration |
| [LAB-013 — Speech Timeline](../experiments/LAB-013-speech-timeline.md) | M2 | iPhone, iPad, Mac subject to language/device support | SpeechAnalyzer, SpeechTranscriber, AssetInventory |
| [LAB-014 — Language Bridge](../experiments/LAB-014-language-bridge.md) | M3 | iPhone, iPad, Mac after runtime check | Translation, Speech output where supported |
| [LAB-015 — Local Model Bench](../experiments/LAB-015-local-model-bench.md) | M3 | Apple-silicon Mac; optional capable iPhone/iPad | Core ML, optional MLX/provider bridge, Foundation Models evaluation |
| [LAB-016 — Pick Up Here](../experiments/LAB-016-pick-up-here.md) | M2 | iPhone, iPad, Mac | NSUserActivity, Handoff, universal-link routing |
| [LAB-017 — Durable Sync Ledger](../experiments/LAB-017-durable-sync-ledger.md) | M3 | iPhone, iPad, Mac; companion state distribution separately | CloudKit, CKSyncEngine, local transactional store |
| [LAB-018 — Together Mode](../experiments/LAB-018-together-mode.md) | M3 | Supported iPhone, iPad, Mac; tvOS participation independently proved | GroupActivities, GroupSessionMessenger, AVPlayer coordination |
| [LAB-019 — Local Constellation](../experiments/LAB-019-local-constellation.md) | M2 | Mac, iPhone, iPad, Apple TV on a local network; Watch relayed | Network framework, Bonjour, authenticated transport |
| [LAB-020 — Aware Link](../experiments/LAB-020-aware-link.md) | M4 | Supported devices only; iPhone/iPad proof before any broader promise | WiFiAware, DeviceDiscoveryUI, Network |
| [LAB-021 — Wrist Relay](../experiments/LAB-021-wrist-relay.md) | M2 | Paired iPhone and Watch; Mac/TV receive through a separate link | WatchConnectivity, watchOS SwiftUI, system haptics |
| [LAB-022 — Proximity Instrument](../experiments/LAB-022-proximity-instrument.md) | M4 | Participating UWB-capable devices; per-role distance/direction check | NearbyInteraction |
| [LAB-023 — Tabletop Reality](../experiments/LAB-023-tabletop-reality.md) | M3 | ARKit-supported iPhone/iPad; non-AR Mac viewer | ARKit, RealityKit |
| [LAB-024 — Room Ledger](../experiments/LAB-024-room-ledger.md) | M3 | LiDAR-capable iPhone/iPad capture; Mac review | RoomPlan, RealityKit |
| [LAB-025 — Object Forge](../experiments/LAB-025-object-forge.md) | M3 | Supported iPhone capture and supported Mac/device reconstruction | RealityKit Object Capture, PhotogrammetrySession |
| [LAB-026 — Camera Instrument Panel](../experiments/LAB-026-camera-instrument-panel.md) | M3 | iPhone/iPad; Mac uses selected frames or available camera | AVFoundation, Vision, Core Image |
| [LAB-027 — Sound in Space](../experiments/LAB-027-sound-in-space.md) | M3 | iPhone, iPad, Mac; output-device capabilities checked | PHASE, AVAudioEngine, optional headphone motion |
| [LAB-028 — Recognize Our Audio](../experiments/LAB-028-recognize-our-audio.md) | M2 | Supported iPhone/iPad/Mac; microphone input separately gated | ShazamKit SHCustomCatalog, AVAudioEngine |
| [LAB-029 — Audio Workshop](../experiments/LAB-029-audio-workshop.md) | M3 | Mac and iPhone/iPad; AUv3 target isolated | AVAudioEngine, Audio Units, Core MIDI |
| [LAB-030 — Tactile Grammar](../experiments/LAB-030-tactile-grammar.md) | M2 | Capable iPhone, supported controllers, Watch system haptics separately | Core Haptics, GameController, Watch haptic APIs |
| [LAB-031 — Native Screening Room](../experiments/LAB-031-native-screening-room.md) | M2 | iPhone, iPad, Mac, Apple TV | AVPlayer, AVKit, Now Playing, PiP/AirPlay where supported |
| [LAB-032 — Render That Survives](../experiments/LAB-032-render-that-survives.md) | M2 | iPhone/iPad user-started background work; Mac foreground worker | AVFoundation export, BackgroundTasks, optional GPU path |
| [LAB-033 — Capture With Consent](../experiments/LAB-033-capture-with-consent.md) | M3 | Mac capture host; optional iPhone Continuity Camera | ScreenCaptureKit, AVFoundation, system content picker |
| [LAB-034 — Television Stage](../experiments/LAB-034-television-stage.md) | M3 | Apple TV 4K second generation or later for the camera sample; paired camera device | tvOS AVKit Continuity Camera, Network transport |
| [LAB-035 — Access as a Superpower](../experiments/LAB-035-access-as-a-superpower.md) | M1 | iPhone, iPad, Mac; Watch/TV adapt primary tasks | SwiftUI accessibility, AXChartDescriptor, custom actions |
| [LAB-036 — Workout Session Mirror](../experiments/LAB-036-workout-session-mirror.md) | M4 | Watch and paired iPhone; health-capable target | HealthKit workout sessions and mirroring |
| [LAB-037 — Home Scene Sandbox](../experiments/LAB-037-home-scene-sandbox.md) | M4 | iPhone/iPad; supported Mac client separately | HomeKit, Matter optional controller investigation |
| [LAB-038 — Wallet Moment](../experiments/LAB-038-wallet-moment.md) | M4 | iPhone; Watch Wallet display is system-managed | Wallet passes, PassKit |
| [LAB-039 — Tiny Doorway](../experiments/LAB-039-tiny-doorway.md) | M4 | iPhone with optional App Clip; universal-link fallback elsewhere | App Clips, associated domains, universal links |
| [LAB-040 — Commerce Without Tricks](../experiments/LAB-040-commerce-without-tricks.md) | M4 | StoreKit-supported iPhone/iPad/Mac/TV targets independently | StoreKit 2, StoreKit configuration tests |
| [LAB-041 — Trust Desk](../experiments/LAB-041-trust-desk.md) | M2 | iPhone, iPad, Mac; passkey service is optional | Keychain, LocalAuthentication, AuthenticationServices |
| [LAB-042 — Desktop Native Power](../experiments/LAB-042-desktop-native-power.md) | M2 | Mac only | SwiftUI scenes, AppKit, Services, optional scripting |
| [LAB-043 — Respectful Attention](../experiments/LAB-043-respectful-attention.md) | M3 | iPhone primary; supported Mac/Watch behavior separate | UserNotifications, Focus filters, AlarmKit |
| [LAB-044 — Play Together Native](../experiments/LAB-044-play-together-native.md) | M4 | Supported iPhone/iPad/Mac/TV; device qualification required | GameKit, GameController |
| [LAB-045 — Ink Has Structure](../experiments/LAB-045-ink-has-structure.md) | M4 | iPad/Pencil optional; touch on iPhone and pointer on Mac | PencilKit, native document APIs |
| [LAB-046 — Pocket Render Museum](../experiments/LAB-046-pocket-render-museum.md) | M3 | Metal-capable iPhone/iPad/Mac/TV with feature probes | Metal, RealityKit interoperability where justified |
| [LAB-047 — Accessory Without a Factory](../experiments/LAB-047-accessory-without-a-factory.md) | M4 | iPhone host; optional paired Watch; user-supplied compatible peripheral | AccessorySetupKit, CoreBluetooth, optional Core MIDI |
| [LAB-048 — Commercial Frontier Desk](../experiments/LAB-048-commercial-frontier-desk.md) | M4 | iPhone primary; three isolated optional targets | PushToTalk, CarPlay, FamilyControls/DeviceActivity |
