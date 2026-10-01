---
id: "LAB-019"
title: "Local Constellation"
state: "implemented"
milestone: "M2"
category: "Continuity"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-019 — Local Constellation

## The moment

Use a Mac as conductor, a phone as controller, and a television as a stateful display without an internet server.

## Scope and native leverage

**Hosts:** Mac, iPhone, iPad, Apple TV on a local network; Watch relayed.

**Primary APIs:** Network framework, Bonjour, authenticated transport. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** SessionEnvelope, PeerIdentity, ClockEstimate. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Pair explicitly using a short code plus pinned peer identity
2. Negotiate role and protocol version
3. Separate reliable commands from replaceable samples
4. Measure clock error, sequence gaps, and reconnection

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A stale command is ignored or explicitly reconciled.
- [ ] An unpaired peer sees no session data.
- [ ] A disconnected client visibly becomes stale.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Local network availability and permissions are required. No arbitrary remote shell, unattended wake, or hard real-time claim.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Single-device conductor/client simulation with identical wire messages.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/local-constellation/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-019-A):

- `Packages/LabFeatures/Sources/PeerSession/`: the reusable layer later experiments build on ([ADR-015](../docs/adr/ADR-015.md)). Identities and pins (`PeerIdentity`, `LocalIdentity`, `PeerTrustStore`), the frame format and `FrameReader`, the handshake (`HostHandshake`, `JoinerHandshake`, `PairingCode`), `SecureChannel`, the generic `SessionEnvelope` over a `SessionVocabulary`, `Conductor` and `Client` with their published states, `ClockEstimator`, `SequenceTracker`, presence, the `PeerConnection` and `PeerNetwork` transport protocols, and the in-process `LoopbackConnection`, `LoopbackHub`, and `LoopbackNetwork`. Foundation, CryptoKit, and LabDomain's `StrictJSON` only.
- `Packages/LabFeatures/Sources/PeerSessionNetwork/`: the local-network transport over the Network framework (`LANNetwork`, `LANListener`, `LANBrowser`, `LANConnection`), compiled out of watchOS. Linked only by Companions hosts.
- `Packages/LabFeatures/Sources/LocalConstellation/`: the show. The bundled six-cue sheet, `Constellation` (the vocabulary: `ShowCommand`, `Pointer`, `ShowSnapshot`), `ShowRules`, `ShowHost` (the conductor side, and the path from an allowed peer request to the operation service), `ShowSessionBackend` and `ServiceShowBackend`, `PeerApproval`, `ConstellationSimulation` (the fallback), `LiveConductor` and `LiveJoiner`, and the shared SwiftUI views.
- `Packages/LabDomain` is unchanged: the show's running flag is a demo-namespace `LabSession` (`LocalConstellation.showSessionID`), changed only by `setSession`.
- Hosts: `Apps/Shared/Constellation/` (the library backend, the model, the page, and, in Companions builds, the live controls), `Apps/Mac/Window/ConstellationColumns.swift`, and `Apps/TV/Constellation/`. The Mac has a sidebar destination and View › Local Constellation (⌃⌘5); iPhone and iPad open it from the catalog page; the Apple TV opens it from the experiment's record.
- Profiles: CoreLocal hosts carry the simulation only. `LabMacCompanions` and `LabPhoneCompanions` (schemes `LabMac-Companions` and `LabPhone-Companions`) and the Apple TV host add `PeerSessionNetwork`, `NSLocalNetworkUsageDescription`, and `NSBonjourServices` (`_nativelab-lc._tcp`); the Mac variant adds the sandbox's network client and server entitlements.

## Implementation notes (LAB-019-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs, on the development Mac. These are compile, test-process, and loopback facts, not network or device proof.

- **The installed SDK.** `NWListener`, `NWBrowser` (`.bonjour(type:domain:)`), `NWConnection`, `NWParameters.acceptLocalOnly`, `includePeerToPeer`, `prohibitedInterfaceTypes`, `requiredInterfaceType`, and `NWPath.UnsatisfiedReason.localNetworkDenied` are all declared in the macOS, iOS, tvOS, and watchOS 27.0 SDKs, the classes `Sendable`. The adapter is compiled out of watchOS anyway: the Watch reaches peers through its phone. CryptoKit's `Curve25519.Signing`, `Curve25519.KeyAgreement`, `HKDF`, and `ChaChaPoly` are below the 26.0 floor. CryptoKit has no password-authenticated key exchange, which is why the code is derived from a committed transcript rather than used as a key ([ADR-015](../docs/adr/ADR-015.md)).
- **The permission.** The lab cannot read local network permission in advance (CORE-004). Host and Join each first ask `PermissionStager` for a `FeatureAction` on `.localNetwork`; on iOS and tvOS that returns "the system asks on use", and on a Mac build without the network entitlements it falls back with the missing entitlement named. Nothing is advertised or browsed before the person's action. A denial shows as the adapter's status: Bonjour's `kDNSServiceErr_PolicyDenied` (-65570) or a path whose unsatisfied reason is `localNetworkDenied`.
- **Local only.** The adapter excludes cellular and peer-to-peer Wi-Fi, a listener accepts local connections only, and a joiner can connect only to an endpoint its own browser found. No message can name a host to connect to.
- **Identical wire messages.** The loopback encodes and splits frames with the same `FrameCodec` and `FrameReader` as the network transport. A test runs one scripted session over each, with fixed keys, clocks, and message IDs: every envelope's plaintext, sequence, channel, and sealed size match.
- **Sensitive changes.** Moving between cues changes only the live show. Starting or pausing changes the stored session, so a peer can only ask: the conductor holds the request, and the person there allows or declines it. Allowing commits `setSession` through the host's `OperationService` as the authorized-peer adapter, with a 30-second grant for that operation alone, under a request ID derived from the peer and its command, so a resend returns the same receipt. The host's own Start and Pause commit as the app UI.
- **Not yet shown:** a real network. Loopback round trips are microseconds, so the clock estimates and delays measured here are not network measurements, and no latency is claimed.

## Delivery

[Implementation ticket](../tickets/LAB-019-A.md) → [qualification ticket](../tickets/LAB-019-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S61](../docs/SOURCE_INDEX.md#s61). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
