---
id: "LAB-019-A"
title: "Implement Local Constellation"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "CORE-013", "LAB-001-B"]
---

# LAB-019-A — Implement Local Constellation

## Goal

Use a Mac as conductor, a phone as controller, and a television as a stateful display without an internet server.

## Authority and scope

Read the [governing specification](../experiments/LAB-019-local-constellation.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** local-constellation module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Pair explicitly using a short code plus pinned peer identity
3. Negotiate role and protocol version
4. Separate reliable commands from replaceable samples
5. Measure clock error, sequence gaps, and reconnection
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] A stale command is ignored or explicitly reconciled. (Fixture and Mac-host runs; see the completion record.)
- [x] An unpaired peer sees no session data. (Fixture runs.)
- [x] A disconnected client visibly becomes stale. (Fixture runs and the Mac host's views.)
- [x] Fallback is usable: Single-device conductor/client simulation with identical wire messages.. (Mac host; loopback TCP for the comparison.)
- [x] Sensitive operations share the domain authorization/receipt path. (Fixture runs and the Mac host's store.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Local network availability and permissions are required. No arbitrary remote shell, unattended wake, or hard real-time claim.

**Research:** [S61](../docs/SOURCE_INDEX.md#s61).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-019's spec now claims `implemented`, for its declared fallback: the single-device conductor and client simulation ran in package tests, in the sandboxed Mac host over its own store, and in its real views operated through the accessibility press action. The network adapter ran only over this Mac's loopback interface in a test process. Nothing here ran between two devices or on a physical device.

**Acceptance.**

- [x] A stale command is ignored or explicitly reconciled. A command based on an older revision is refused as `stale`, nothing changes, and the sender gets the current snapshot (`aStaleCommandIsRefusedWithTheCurrentStateAndNothingChanges`, `aStaleCueCommandIsRefusedAndTheControllerIsReconciled`). Commands from before a conductor restart are refused for their epoch, commands older than the lifetime by the clock estimate are refused as expired, and a command that waited too long for a link is never sent. Fixture path, manual clocks.
- [x] An unpaired peer sees no session data. A resume from a device the conductor never paired gets one plaintext refusal and no sealed frame (`anUnpairedPeerThatTriesToResumeGetsOnlyARefusal`, `anUnpairedPeerSeesNoSessionData`, and the simulation's Unpaired Device Tries to Join in `SimulationTests`). A wrong code pins nothing on either side, and a device in the middle cannot make both sides show one code (`HandshakeTests`).
- [x] A disconnected client visibly becomes stale. With its link silently down, both the conductor's roster and the client's own board show Stale after 2 seconds and Disconnected after 8 (`aSilentClientBecomesStaleThenDisconnectedOnBothSides`, manual clocks); in the Mac host's views, the controller's board read "Nothing heard from the conductor…" and the conductor's roster row read Stale (`ConstellationAccessibilityTests`, real time).
- [x] Fallback is usable: single-device conductor/client simulation with identical wire messages. The loopback carries the same `FrameCodec` bytes as the network transport; one scripted session over each matched envelope for envelope (`theNetworkCarriesTheSameEnvelopesAsTheLoopback`, loopback TCP on the Mac). The simulation paired, commanded, sampled, held and allowed a start, and went stale in the Mac host (`ConstellationHostTests`, `ConstellationAccessibilityTests`).
- [x] Sensitive operations share the domain authorization/receipt path. A peer's start or pause is held for the conductor's person; Allow commits `setSession` through the host's `OperationService` as the authorized-peer adapter with a grant for that operation alone, and its receipt is listed with every other receipt (`aPeersStartWaitsForTheConductorAndCommitsAsAnAuthorizedPeerWithAGrant`, `anAllowedPeerRequestCommitsAsTheAuthorizedPeerWithAReceiptInTheHostsList`). Without an allowed request the same commit fails closed (`aDeclinedOrUnallowedRequestCommitsNothing`); a resend returns the same receipt (`aResentAllowedRequestReturnsItsReceiptAndCommitsOnce`).

**Decisions.** [ADR-015](../docs/adr/ADR-015.md): the reusable `PeerSession` layer; pairing by a commitment and a six-digit code derived from the transcript (CryptoKit has no password-authenticated key exchange); pinned Curve25519 identities; every frame sealed with ChaCha20-Poly1305 in the session layer, so the loopback carries network bytes; and the network adapter, local network declarations, and Mac network entitlements only in Companions builds. The show's running flag reuses LabDomain's demo-namespace `LabSession` and `setSession`; LabDomain is unchanged.

**Changed.**

- `Packages/LabFeatures`: `PeerSession`, `PeerSessionNetwork`, and `LocalConstellation` (new targets and products) with `PeerSessionTests` (37), `PeerSessionNetworkTests` (4), and `LocalConstellationTests` (12); `LabCatalogTests` now count 7 implemented and 41 specified. The catalog JSON was regenerated.
- `Fixtures/LAB-019/` (new): eight hostile wire messages and their README. The cue sheet is the module's resource.
- `Apps/Shared/Constellation/` (new): `ConstellationModel`, `LibraryShowBackend`, the page and launch, and, in Companions builds only, `LiveConstellation` and the live controls. `Apps/Mac/Window/ConstellationColumns.swift` and `Apps/TV/Constellation/` (new).
- Hooks in shared host files, one each:
  - `LabDataService`: the `peerApproved` commit authority, the authorized-peer actor, and its one grantable operation.
  - `MainWindowState`: `.localConstellation`. `MainWindow`: its columns. `SidebarView`: its row. `LabCommands`: View › Local Constellation (⌘9).
  - `ExperimentDetailView`: `ConstellationLaunch`. The TV's `ExperimentDetailScreen`: the Open button and "Runs here" for LAB-019.
- `Tests/LabMacTests/ConstellationHostTests.swift` (4) and `ConstellationAccessibilityTests.swift` (1); `Tests/LabTVTests/ConstellationTVTests.swift` (2).
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `PeerSession` and `LocalConstellation`; LabTV links those and `PeerSessionNetwork` and declares `NSLocalNetworkUsageDescription` and `NSBonjourServices`; new Companions targets `LabMacCompanions` and `LabPhoneCompanions` with schemes `LabMac-Companions` and `LabPhone-Companions`, their Info.plists and the Mac variant's entitlements under `Apps/Companions/`.
- `Config/ProductPolicy.txt` (Companions link and entitlement lines for the variants and the TV) and `Config/Profiles/Companions.xcconfig` (comment).
- Docs: ADR-015 and `ADR.md`; `docs/DATA_CONTRACTS.md` (the session's frames, handshake, envelope, admission, clocks, presence, and joiner rules); `docs/VERIFICATION_BOUNDARIES.md` (installed SDK ledger); `docs/BUILD_AND_DISTRIBUTION.md` and the scheme rows in `docs/BUILD_STATUS.md`; the experiment spec's state, split, and notes.

**Implementation steps.**

1. **Probe.** The Network and CryptoKit interfaces of the 27.0 SDKs, recorded in the ledger and the spec's notes.
2. **Pair explicitly.** `HostHandshake` and `JoinerHandshake`: pairing only while a person opened it (two minutes, three attempts), the code typed on the joiner, Allow on the host only after the joiner says it matched, then both pin.
3. **Negotiate.** Protocol name, version range, and role in `hello`; refusals say which versions the other side speaks.
4. **Separate channels.** Reliable commands, results, and snapshots; replaceable samples and clock probes, latest-only, with stale ones dropped.
5. **Measure.** Clock offset and uncertainty, reliable gaps (which force a snapshot before admission), lost and stale samples, reconnections, and presence, shown in every host's roster and panels.
6. **Tests.** The domain operation (the allowed start through `OperationService`), cancellation (`cancellingTheCodePromptRefusesThePairingAndPinsNothing`; a joiner's refusal cancels the host's waiting Allow in `aWrongCodePinsNothingOnEitherSide`), invalid input (hostile fixtures, smuggled fields, duplicate keys, tampered frames), and the unavailable path (CoreLocal hosts carry no adapter and say so; a denied local network shows as the adapter's status).

**Evidence:** the LAB-019-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). `script/test.sh` passed every step except the tvOS one, whose simulator research's maintenance deleted mid-run; that step and the release manifest then passed when rerun through `labr`.

**Not run:**

- Any physical device, and any two devices on a real network: no Bonjour browse, no local network prompt, no denial, no Wi-Fi loss or delay. Clock and delay figures from the loopback are not network measurements.
- The optional two-simulator loopback demonstration (a Companions Mac host with a tvOS or iOS simulator): research was heavily loaded, and the code entry needs a person or a UI harness on both sides.
- The Companions host variants were built, not launched. The iPhone screen was built, not driven. On Apple TV the simulation ran in the hosted `ConstellationTVTests` in the tvOS simulator, but the new screen was not driven with the remote.
- VoiceOver, Voice Control, Full Keyboard Access, large text on iPhone, and the Apple TV remote on the new screen.
- A 26-SDK compile; CI does not build the Companions variants (as it does not build `LabPhone-Surfaces`).

**Known limitations.**

- Pins live in memory: relaunching a host means pairing again. A keychain-backed `PeerTrustStore` is future work.
- On a single device the simulation's controller, display, and conductor share one person, who reads the code from one panel and types it in another.
- The Apple TV's simulation stores the show in memory for the launch; the TV has no lab store.
- The receipt for the show uses LabDomain's session phrase, "Started the demo session."

**Next dependency-ready ticket:** LAB-019-B (qualification): it depends on this ticket and on CORE-007, CORE-009, and CORE-010, all done. Its live path needs two devices on one network.
