---
id: "LAB-011"
title: "Model Routing Observatory"
state: "specified"
milestone: "M4"
category: "Intelligence"
depends_on: ["LAB-010"]
source_review: "2026-09-29"
---

# LAB-011 — Model Routing Observatory

## The moment

See where a request would run, what may leave the device, and why a larger model is or is not available.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; optional watchOS 27 PCC path.

**Primary APIs:** Foundation Models LanguageModel, PCC, optional provider adapter. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** InferenceRoute, ConsentGrant, UsageReceipt. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Keep local-only as the default policy
2. Model PCC eligibility separately from model availability
3. Show exact outgoing fields before a cloud request
4. Record route and usage without raw prompt telemetry

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Cloud-off causes zero cloud requests.
- [ ] Missing entitlement is an explained gate.
- [ ] Exhausted quota never silently switches to a paid provider.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

PCC requires qualifying program enrollment, account entitlement, eligible distribution and user availability; not a free API for every source build.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local generation or manual workflow; no mandatory third-party key.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/model-routing-observatory/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-011-A.md) → [qualification ticket](../tickets/LAB-011-B.md).

**Lab dependencies:** [LAB-010](LAB-010-typed-local-intelligence.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06), [S07](../docs/SOURCE_INDEX.md#s07). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
