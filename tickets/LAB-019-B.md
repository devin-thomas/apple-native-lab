---
id: "LAB-019-B"
title: "Qualify and document Local Constellation"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-019-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-019-B — Qualify and document Local Constellation

## Goal

Prove Local Constellation on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-019-local-constellation.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** local-constellation tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: A stale command is ignored or explicitly reconciled; An unpaired peer sees no session data; A disconnected client visibly becomes stale
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] A stale command is ignored or explicitly reconciled.
- [ ] An unpaired peer sees no session data.
- [ ] A disconnected client visibly becomes stale.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Mac, iPhone, iPad, Apple TV on a local network; Watch relayed.

**Unavailable path:** Single-device conductor/client simulation with identical wire messages.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-019 stays `implemented`.** The fallback, the single-device simulation, is qualified in the Mac app and in the Apple TV app in the tvOS Simulator. The session also ran between two processes on one Mac, a macOS test process conducting and the Apple TV app in the tvOS Simulator displaying, over TCP on the loopback interface only. Nothing ran between two devices, on a network, or on a physical device. Three records in `evidence/LAB-019/` at 725bf49: one fixture, two simulator.

**The run that would promote it.** The eight steps under "Try the live path" in the [walkthrough](../docs/walkthroughs/LAB-019-local-constellation.md#try-the-live-path): a Companions Mac, iPhone, and Apple TV on one Wi-Fi network, paired with the code, the show moved from the iPhone, an allowed start with its Authorized peer receipt, Wi-Fi off and on, local network access denied on the Apple TV, and the roster's clock and gap figures. Record each with `DeviceRunEvidence`.

**Acceptance.**

- [x] A stale command is ignored or explicitly reconciled. Fixture: a Next from an older revision is refused as `stale` with the current snapshot, in the package replay, the qualification suites, the Mac host (`ConstellationHostEvidenceTests`, "Based on revision 2, but the state is at 3"), and the Apple TV app. Contract: a command queued offline is judged on its own revision after a reconnect, eight queued commands make one effect and seven `stale` answers, and a held start overtaken by the conductor's own Start is answered "already running" with one receipt.
- [x] An unpaired peer sees no session data. A stranger that knows the conductor's identity gets two handshake frames and no sealed frame (package, Mac host, Apple TV app, and across processes over loopback TCP). Also: a denied or mistyped pairing, a device paired for another role, a forgotten device, and a paired peer claiming another sender or the conductor's role (dropped, counted, link kept); a replayed sealed frame closes the link; a display never receives another peer's commands or results.
- [x] A disconnected client visibly becomes stale. Fixture: with its link silently down, the display's board reads "Nothing heard from the conductor" and the roster reads Stale after 2 s, both Disconnected after 8 s, and the roster keeps it (Mac host views through the accessibility API, three renderings; package replay with manual clocks; Apple TV app). Across processes, a link closed without a goodbye showed Disconnected on the conductor.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations: 3 records, each with Xcode 27.0 (27A266a), its SDK, the cue sheet's SHA-256 `a2b9428f…`, its path, and what it does not cover.
- [x] The walkthrough never claims a simulation is the live integration: it opens with "Nothing here has run between two devices", labels every picture, and lists the live steps as not run.
- [x] Only approved original/public-safe material: the cue sheet and fixtures are original; the 5 pictures show only the app's own views (3 Mac renderings by the test bundle, 2 tvOS Simulator screenshots), scaled down, with no device or account identifiers.

**Cases.** Denial: Deny at the conductor, a wrong code, a display's command (`not-allowed`), a declined start, a commit without a grant (LAB-019-A). Cancellation: Cancel on the device withdraws the conductor's prompt (also with the remote), a held request expires after 30 s and a late Allow commits nothing. Stale and duplicate: the above, Allow pressed twice commits once, a resent command and a held command's lost answer are answered from the record across a reconnect. Reset: Reset Demo pauses the show and leaves a collection and an item of the person's own unchanged (package and Mac host); Start Over keeps the stored show.

**Findings.**

- **Known issue, not fixed:** `Conductor.forget` keeps the forgotten peer's held commands, so Allow still commits one as the authorized peer. Held with `withKnownIssue` in `PeerSessionContractQualification` and `ConstellationQualification`. The fix belongs in `PeerSession` (withdraw and refuse that peer's pending commands on Forget).
- **Contract limits, recorded in DATA_CONTRACTS and the spec:** key checking stops at the vocabulary's own objects; the conductor's age check starts with a link's first clock round trip; a command queued before any snapshot names revision 0.
- **Fixed:** the Apple TV screen had no background and overlapped the detail page under it (7ebd32a, 22a6b4e: tvOS has no system background color, so it draws black).
- Accessibility findings 1 to 7 in the [review](../docs/ACCESSIBILITY_REVIEW.md#local-constellation-review-lab-019-b): duplicate button labels, middle dots read aloud, no announcement after Allow, no Mac menu commands, the stale overlay drawn over the cue title, the TV background (closed), and the TV's first focus on Join.

**Changed:** `PeerSessionTests/ContractQualificationTests.swift` (14), `LocalConstellationTests/QualificationTests.swift` (10), `PeerSessionNetworkTests/TwoEndpointConductorTests.swift` (1, run only with `LAB_019_DEMO_DIR`); `Tests/LabMacTests/ConstellationHostEvidenceTests.swift`, `Tests/LabTVTests/ConstellationTVEvidenceTests.swift`, `ConstellationTwoEndpointTests.swift` (run only with its folder), `Tests/LabTVUITests/ConstellationRemoteUITests.swift`; `Apps/TV/Constellation/ConstellationScreen.swift` (the background); `Packages/LabFeatures/Package.swift` (`PeerSessionNetworkTests` also depends on `LocalConstellation`, for the demonstration; no project change); `evidence/LAB-019/` (3), the walkthrough with 5 pictures, the accessibility review (check row, flows C1–C5, findings), DATA_CONTRACTS, and the spec's qualification notes. No showcase fixture: the replay script format has no session messages, and `ConstellationInteractionReplay` replays the whole interaction from clean stores; the stored side is one `setSession`, the shape the Surface Deck showcase already replays. The capability descriptor is unchanged; it already names the fallback.

**Commands and results:** see the LAB-019-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Platforms:** Mac passed on the fixture path (hosted tests). Apple TV passed in the tvOS Simulator only, including the remote. iPhone and iPad: built by `script/test.sh`, the page not driven. Watch: the relay is not built.

**Not run:** any physical device; two devices on a network; Bonjour, the local network prompt and its denial; Wi-Fi loss; the Companions builds launched; typing the code with the Apple TV keyboard; the iPhone page; VoiceOver, Voice Control, Full Keyboard Access, and large text by a person; a 26-SDK compile.

**Next dependency-ready tickets:** with LAB-019-B done, LAB-018-A (Together Mode), LAB-020-A (Aware Link), LAB-021-A (Wrist Relay), LAB-034-A (Television Stage), LAB-044-A (Play Together Native), and LAB-047-A (Accessory Without a Factory) have every dependency done. The Forget fix in `PeerSession` should land before any of them relies on held requests. LAB-019's own promotion waits on the live run above.

