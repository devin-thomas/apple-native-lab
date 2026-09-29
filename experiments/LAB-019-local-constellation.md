---
id: "LAB-019"
title: "Local Constellation"
state: "specified"
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

## Delivery

[Implementation ticket](../tickets/LAB-019-A.md) → [qualification ticket](../tickets/LAB-019-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S61](../docs/SOURCE_INDEX.md#s61). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
