---
id: "LAB-007"
title: "Share Ingress Station"
state: "specified"
milestone: "M1"
category: "Sharing"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-007 — Share Ingress Station

## The moment

Share a page, image, or video into a staging inbox without losing the source context.

## Scope and native leverage

**Hosts:** iPhone, iPad; separate Mac Share extension.

**Primary APIs:** Share extensions, NSItemProvider, App Groups. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** ImportEnvelope, StagedAttachment. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Accept URL/text/image/movie attachments
2. Copy bounded data while extension access is valid
3. Write a durable inbox entry and finish promptly
4. Let the host app validate and process the staged item

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Cloud-backed attachments can be cancelled safely.
- [ ] Multiple attachments preserve order and provenance.
- [ ] Malformed and oversized payloads never block future imports.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Share extensions have constrained lifetime/memory. They do not scrape the host app or run a large media pipeline.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Host-app file picker and paste action; extension not required for core build.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/share-ingress-station/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-007-A.md) → [qualification ticket](../tickets/LAB-007-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S13](../docs/SOURCE_INDEX.md#s13), [S11](../docs/SOURCE_INDEX.md#s11). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
