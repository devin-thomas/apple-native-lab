---
id: "LAB-014"
title: "Language Bridge"
state: "specified"
milestone: "M3"
category: "Intelligence"
depends_on: ["LAB-013"]
source_review: "2026-09-29"
---

# LAB-014 — Language Bridge

## The moment

Read a translated caption beside its original and immediately inspect uncertainty or an unavailable language.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac after runtime check.

**Primary APIs:** Translation, Speech output where supported. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** TranslationPair, LanguageAvailability. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Keep original text immutable
2. Download needed assets with consent
3. Translate bounded segments
4. Provide user-invoked spoken playback where supported

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unsupported pairs remain readable in original form.
- [ ] Names and notation survive as protected tokens.
- [ ] No translation is relabeled as the original quotation.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Language support and system live translation are distinct; the lab translates its own content.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Bilingual fixtures and editable side-by-side text.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/language-bridge/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-014-A.md) → [qualification ticket](../tickets/LAB-014-B.md).

**Lab dependencies:** [LAB-013](LAB-013-speech-timeline.md).

**Primary-source references:** [S48](../docs/SOURCE_INDEX.md#s48). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
