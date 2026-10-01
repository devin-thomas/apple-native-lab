---
id: "LAB-011"
title: "Model Routing Observatory"
state: "implemented"
milestone: "M4"
category: "Intelligence"
depends_on: ["LAB-010"]
source_review: "2026-09-30"
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

- [x] Cloud-off causes zero cloud requests. (`CloudOffTests.cloudOffCausesZeroCloudRequests`)
- [x] Missing entitlement is an explained gate. (`EntitlementGateTests`)
- [x] Exhausted quota never silently switches to a paid provider. (`QuotaExhaustionTests`)
- [x] The declared fallback completes a meaningful version of the interaction. (`FallbackTests`)
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

Implemented split (LAB-011-A):

- `Packages/LabFeatures/Sources/ModelRouting/` holds the domain types `InferenceRoute`, `ConsentGrant`, `UsageReceipt`, `OutgoingFieldPreview`, `PCCEligibility`, the `RouteResolver` / `ModelRoutingFlow`, injectable `CloudTransport`, and the `RoutingProbe` over Foundation Models on iOS and macOS. It depends on LabDomain and LabSupport, never holds the store, and never offers a paid third-party provider.
- `Apps/Shared/ModelRouting/` holds the host backend over `LabLibrary` / `LabDataService`, the session, and the shared views.
  - The Mac reaches it from the sidebar (⌘9) and from this experiment's catalog page.
  - iPhone reaches it from the catalog page only.
- `Fixtures/routing/` holds the original sample prompt, which both hosts bundle as a resource.

## Implementation notes (LAB-011-A)

Observed with Xcode 27.0 (27A266a), the macOS 27.0 SDK's `FoundationModels.swiftinterface`, and this experiment's package tests on research. These are compile and fixture-test facts, not device proof.

- **Private Cloud Compute.** `PrivateCloudComputeLanguageModel` is iOS, macOS, visionOS, and watchOS 27.0 (tvOS unavailable), with `availability` (`.available` / `.unavailable(.deviceNotEligible | .systemNotReady)`), `quotaUsage` (`.belowLimit` / `.limitReached`, `isLimitReached`), and errors `networkFailure`, `quotaLimitReached`, `serviceUnavailable`. The entitlement string used for the gate is `com.apple.developer.private-cloud-compute`. CoreLocal does not carry it; program enrollment and permitted distribution stay closed gates by default.
- **PCC vs on-device.** On-device availability is read from `SystemLanguageModel.default` separately from PCC eligibility. A ready on-device model does not open PCC, and an open PCC availability reading does not imply the account gates are met.
- **Cloud-off.** `RoutingPolicy.localOnly` is the default. The flow never increments cloud send attempts or calls the transport under that policy.
- **Quota.** Exhausted quota closes the PCC route and completes local or manual fallback. `PaidProvider.supportedProviders` is empty; no alternate paid adapter exists.
- **Outgoing fields.** The preview describes the lab’s proposed request envelope, not Apple’s wire format; no live PCC adapter is implemented. `OutgoingFieldPreview` lists exact proposed field names and values before any cloud attempt. Usage receipts and diagnostics keep names and lengths only, never the prompt text.
- **Authorization.** After a separate review and explicit approval, annotating a demo sample with the local summary proposes as the model-tool adapter and commits as the app UI through `LabLibrary.submit` / `OperationService`.
- **Transport.** CoreLocal uses `RefusingCloudTransport`. Even with every gate open and consent granted, nothing leaves the device in this profile.

## Delivery

[Implementation ticket](../tickets/LAB-011-A.md) → [qualification ticket](../tickets/LAB-011-B.md).

**Lab dependencies:** [LAB-010](LAB-010-typed-local-intelligence.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06), [S07](../docs/SOURCE_INDEX.md#s07). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.

[ADR-015](../docs/adr/ADR-015.md) records the refusing transport, session reset, and explicit annotation approval. Unknown PCC gates fail closed. Package probes gate PCC symbols with `compiler(>=6.4)` as well as runtime availability, because app `LAB_SDK_27` conditions do not reach Swift packages. This preserves the source path for the 26-family toolchain; that SDK compile remains unrun.
