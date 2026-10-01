---
id: "LAB-012"
title: "Point, Inspect, Propose"
state: "implemented"
milestone: "M3"
category: "Intelligence"
depends_on: ["LAB-007", "LAB-010"]
source_review: "2026-09-29"
---

# LAB-012 — Point, Inspect, Propose

## The moment

Inspect an object or screenshot and turn observations into a reviewable lab record.

## Scope and native leverage

**Hosts:** Supported iPhone; iPad/Mac camera-import fallback.

**Primary APIs:** Vision, Foundation Models image input, Visual Intelligence integration. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** Observation, ImageEvidence, CaptureConsent. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Begin with a user-selected image
2. Run deterministic OCR/barcode where suitable
3. Offer a model-generated interpretation with image provenance
4. Add optional supported system visual-search participation

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [x] Barcode payloads cannot execute actions.
- [x] Photos containing private text remain local by default.
- [x] Uncertain recognition stays an editable suggestion.
- [x] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

System Visual Intelligence participation is not the same as arbitrary visual-agent control. Camera observation is not identity recognition.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Image picker plus OCR and manual fields.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Implemented split (LAB-012-A):

- `Packages/LabFeatures/Sources/PointInspect/` holds the record, the Vision and model adapters, the review gate, and `PointInspectFlow`. Views stay in the hosts.
- `Apps/Shared/PointInspect/` is the image picker, the fields, and the catalog entry. Mac and iPhone link the product. Watch and Apple TV do not.

Shared operations stay in LabDomain. The Inspections collection is a user collection created when a person applies a record.

## Implementation notes (LAB-012-A)

A chosen PNG, JPEG, or GIF stays on the device. Its SHA-256 is the provenance stored in the item note. Vision's `RecognizeTextRequest` and `DetectBarcodesRequest` read the bytes on iOS and macOS. A barcode payload is text in that note. The on-device model describes the image only where `Attachment` can take a `CGImage` (iOS 27 and macOS 27, compiled out of a 26-family build). If Vision or the model cannot run, the fields still complete the record. System visual search, when the system offers it, contributes labels only. The model-tool adapter proposes. Apply commits through the app UI. Reset Demo does not remove Inspections, because those items are not in the demo namespace.

## Delivery

[Implementation ticket](../tickets/LAB-012-A.md) → [qualification ticket](../tickets/LAB-012-B.md).

**Lab dependencies:** [LAB-007](LAB-007-share-ingress-station.md), [LAB-010](LAB-010-typed-local-intelligence.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06), [S55](../docs/SOURCE_INDEX.md#s55), [S62](../docs/SOURCE_INDEX.md#s62). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.

## Qualification notes (LAB-012-B)

The [walkthrough](../docs/walkthroughs/LAB-012-point-inspect-propose.md) and [evidence](../evidence/LAB-012/) distinguish scripted recognition, generated Vision adapter inputs, and the hosted manual replay. Barcode/local/uncertainty checks are fixture proof; the manual path ran through the Mac and iPhone simulator host sessions on fresh SQLite stores. No physical iPhone/iPad, camera, live image-model description, or system visual-search invocation was qualified. Assistive-technology passes remain not-run. The state stays `implemented`.

One approval can be retried without another item. Separate Apply actions create separate items even for identical bytes. Reset Demo preserves applied inspections in the user namespace. Applying recognized text writes it into the local note; a separately chosen downstream export may carry that note. This is not automatic redaction or a claim about the system visual-search service's own privacy behavior.
