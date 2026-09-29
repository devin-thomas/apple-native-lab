---
id: "LAB-032"
title: "Render That Survives"
state: "specified"
milestone: "M2"
category: "Media"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-032 — Render That Survives

## The moment

Start a render, leave the screen, return, and see a truthful recoverable job instead of a vanished spinner.

## Scope and native leverage

**Hosts:** iPhone/iPad user-started background work; Mac foreground worker.

**Primary APIs:** AVFoundation export, BackgroundTasks, optional GPU path. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** RenderRequest, JobCheckpoint, ExportArtifact. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Validate file access and destination capacity
2. Create a durable foreground job
3. Use continued processing only when qualified
4. Checkpoint, cancel, and atomically publish output

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Cancellation never replaces a good output with a partial file.
- [ ] Task expiration produces a resumable or clearly failed job.
- [ ] GPU-unavailable uses a supported lower-cost path.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Background APIs do not promise completion, launch at arbitrary times, or infinite agent execution.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Keep the job foreground; Mac worker only while explicitly running.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/render-that-survives/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-032-A.md) → [qualification ticket](../tickets/LAB-032-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S28](../docs/SOURCE_INDEX.md#s28), [S41](../docs/SOURCE_INDEX.md#s41). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
