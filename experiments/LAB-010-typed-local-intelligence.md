---
id: "LAB-010"
title: "Typed Local Intelligence"
state: "implemented"
milestone: "M1"
category: "Intelligence"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-010 — Typed Local Intelligence

## The moment

Turn an ambiguous note into a typed proposal, then let a deterministic operation perform the approved change.

## Scope and native leverage

**Hosts:** Apple-Intelligence-capable iPhone/iPad/Mac.

**Primary APIs:** Foundation Models, guided generation, Tool. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** ExtractionProposal, ValidationIssue, EvidenceSpan. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Probe model readiness and language support
2. Generate a constrained draft from a bundled text fixture
3. Validate lengths, values, and cross-field rules
4. Preview the diff before commit

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Model-unavailable paths remain usable.
- [ ] Malicious imported instructions cannot authorize tools.
- [ ] Generated-but-invalid values never reach persistence.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Structured generation constrains form, not factual truth. No hidden network fallback or billing.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Deterministic sample parser and manual editor clearly labeled as non-model paths.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/typed-local-intelligence/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-010-A):

- `Packages/LabFeatures/Sources/TypedIntelligence/` holds everything except the views:
  - the domain types `ExtractionProposal`, `ValidationIssue`, and `EvidenceSpan`, with `ProposalValidator`;
  - two extractors: `OnDeviceModelExtractor` over Foundation Models, and the non-model `SampleParser`;
  - the read-only `SampleLookup` tool, the review and approval gate, and `TypedIntelligenceFlow`.

  It depends on LabDomain and LabSupport, never holds the store, and imports FoundationModels on iOS and macOS only.
- `Apps/Shared/Intelligence/` holds the host backend over `LabLibrary` and `LabDataService`, the workbench model, and the views.
  - The Mac reaches it from the sidebar and from this experiment's catalog page.
  - iPhone reaches it from the catalog page only. It has no tab.
- `Fixtures/intelligence/` holds the two original notes, which both hosts bundle as resources.

## Implementation notes (LAB-010-A)

Observed with Xcode 27.0 (27A266a), the macOS 27.0 and iOS 27.0 SDKs, and this experiment's tests on the development Mac (Apple M5 Max, macOS 27.0). These are compile, test, and simulator facts, not device proof.

- **Guided generation.** Output is typed with `@Generable` and `@Guide`. At run time, `GenerationSchema(type:description:properties:)` narrows the sample title to the offered titles with `.anyOf(_:)`, and the model answers through `respond(to:schema:includeSchemaInPrompt:options:)`.
  - A free-text title did not work. In a probe the model wrote "Cobalt swatch (Pigment swatches)", which matches no sample. The narrowed schema gives only real titles.
  - It does not give the right one. On the ambiguous note, the macOS process chose the verdigris both times, while the iOS simulator chose the cobalt both times.
  - So the validator adds one deterministic cross-check: every sample the note names outright that the draft left out is shown to the reviewer.
- **Partial JSON.** `GeneratedContent(json:)` accepts cut-off JSON, because the type also represents streamed snapshots, and its fields can decode. The extractor therefore also requires `isComplete`.
- **27-generation error types.** The 27 SDK deprecates `LanguageModelSession.GenerationError` in favor of `LanguageModelError`, `SystemLanguageModel.Error`, `GeneratedContent.ParsingError`, and `LanguageModelSession.Error`, all available from 27.0.
  - The extractor maps both families by type and case, never by description. The 27-only names are behind `#if compiler(>=6.4)` and `if #available(iOS 27.0, macOS 27.0, *)`.
  - `SystemLanguageModel.variant` (27.0) is read the same way, for evidence only.
- **Private Cloud Compute.** The 27 SDK ships `PrivateCloudComputeLanguageModel` (macOS, iOS, visionOS, and watchOS 27.0), with network, quota, and service errors. This experiment never references it, and a test fails if any of its sources does. There is no cloud or network route.
- **The proposer.** Both extractors, and a person's own edits, are proposed as the model-tool adapter: reads, the `findSamples` tool, and `OperationService.propose`.
  - Model tool is the only ADR-011 adapter whose ceiling is read and propose. The sample parser handles the same untrusted note, so it gets the same ceiling. The interface labels each source separately.
  - A commit needs an `ApprovedChange`, which only the review's `approve()` makes. It commits as the app UI under a new request ID.
- **The tool.** `findSamples` is the session's only tool. It takes one word of at most 40 characters and returns at most five of the offered samples. It searches with `ItemFilter` through the service as the model tool. On this Mac the model called it three times for the ambiguous note and never for the injected one.
- **Availability.** It is read twice, and neither read is inferred from the device name.
  - The CORE-004 probe decides whether the model is offered, and the view shows the failing gate in the probe's own words.
  - The extractor reads `SystemLanguageModel.default.availability` and `supportsLocale(_:)` again for every request.
- **Time limit and cancellation.** A draft stops at a time limit (30 seconds) or when cancelled, and returns at once even if the work ignores cancellation. The late result is discarded.
- **The iOS 27.0 simulator.** On this Mac it reports the model available and runs it, so the unavailable path cannot be shown live there. The hosted Mac view test shows it with a fake device.

## Delivery

[Implementation ticket](../tickets/LAB-010-A.md) → [qualification ticket](../tickets/LAB-010-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
