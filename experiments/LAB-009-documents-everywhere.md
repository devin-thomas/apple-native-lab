---
id: "LAB-009"
title: "Documents Everywhere"
state: "specified"
milestone: "M4"
category: "Sharing"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-009 — Documents Everywhere

## The moment

Preview a custom document in the system and browse an opt-in sample provider.

## Scope and native leverage

**Hosts:** Mac and iPhone/iPad extensions separately.

**Primary APIs:** Quick Look, File Provider, document coordination. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** ProviderItem, DocumentRevision. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Ship Quick Look support first
2. Add a separate local-fixture provider target
3. Enumerate and open tiny safe sample documents
4. Test conflicts and eviction before remote storage

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Quick Look works without provider activation.
- [ ] External edits preserve document revision rules.
- [ ] Provider disconnect never deletes the authoritative source.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

File Provider is a serious storage extension, not needed for ordinary sharing. No production cloud service in v1.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Document browser with previews; provider remains disabled until qualified.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/documents-everywhere/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-009-A.md) → [qualification ticket](../tickets/LAB-009-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S14](../docs/SOURCE_INDEX.md#s14), [S22](../docs/SOURCE_INDEX.md#s22). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
