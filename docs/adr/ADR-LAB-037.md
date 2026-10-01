# ADR-LAB-037 — Fictional home scenes before a live HomeKit adapter

Status: accepted 2026-09-30 (LAB-037-A).

## Decision

CoreLocal implements Home Scene Sandbox with original fictional accessories only. No HomeKit framework, entitlement, purpose string, real home, or network writes enter the default build. The permission source is a deterministic test stand-in; authorized live reads in that stand-in do not permit live commits. A separately scoped opt-in adapter must authorize the external operation before real writes and report irreversible partial results.

For the fictional source, evaluate light outcomes without mutation, admit the run through the host's OperationService, then publish the reversible in-memory lamp state. Denial, cancellation before admission, stale previews, and conflict receipts leave lamp state unchanged. Do not treat this ordering as a transaction protocol for real accessories.

The stable Home Scene Sandbox collection and run item are created as user records through ordinary domain operations. ADR-012 reserves demo entities for the global seed; this ticket does not change that seed. The experiment's explicit Reset Demo updates only its owned run note and restores its ephemeral lamp state. It neither deletes other records nor removes receipts. Lamp state resets when a new session is constructed; the last run note remains durable.

## Consequences

The fictional interaction can prove selection, exclusions, partial outcomes, receipts, and fallback usability. It cannot prove HomeKit access or live accessory behavior. A repeat request in the same session reauthorizes and replays the original operation without writing lamps again. Across sessions, OperationService still refuses incompatible reuse of a recorded request ID; no external writes are attempted. The receipt records the fictional run, not a real HomeKit effect or a guarantee of atomic external execution.

## Validation

`HomeSceneOperationTests` covers disconnected and reachable lights, exclusions, permission revocation, denied/cancelled commits, stale preview, duplicate replay, incomplete outcomes, invalid selection, fallback access, and reset. See the actual results in [LAB-037-A](../../tickets/LAB-037-A.md).
