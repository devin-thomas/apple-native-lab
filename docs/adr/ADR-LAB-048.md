# ADR-LAB-048 — Lifecycle simulations before managed system hosts

Status: accepted 2026-10-01 (LAB-048-A).

## Decision

Commercial Frontier Desk ships three independent in-app lifecycle simulations. Each transition
writes only one experiment-owned local item through the host's OperationService. No baseline
host links PushToTalk, CarPlay, FamilyControls, ManagedSettings or DeviceActivity. Three separate,
unlinked package targets contain compile-only SDK seams. They are not optional signed apps.

The CarPlay example uses the audio category and an original two-row list preview. The compiled
CPListTemplate is not attached to a CarPlay scene. Screen Time demonstrates individual consent,
a sample restriction and revocation without installing any system restriction. Revoke and Reset
clear the saved simulated restriction and authorization together. PTT has join/leave only: no
push handler, background mode, recording or transport exists.

## Rationale and consequences

Managed approval and distribution provisioning are external prerequisites, not booleans a demo
can turn on. The ticket's three optional executable hosts and actual CarPlay simulator scene
remain blocked on separate host configuration and approval work; the delivered fallback is
usable without them. The experiment may reach `implemented` for its fallback only. This narrows
the live portion of the implementation steps; it does not establish device verification.

The desk's local records are isolated by fixed IDs and collection membership. Reset updates only
the selected probe; it never deletes a collection or another record. Reset Demo therefore does
not remove these user-created lifecycle records; Reset probe is their explicit reset path.
State is read from the authorization-checked service, including after reopening the desk. Request
replay is bounded to 256 successful actions per desk instance and reauthorized each time.

Before attaching the compile-only authorization seam to a live Screen Time host, implement and
verify clearing every owned ManagedSettings store and stopping owned DeviceActivity monitoring
before revocation. Never shield the lab or Settings. A live system operation must use its own
explicit consent and authorization boundary and distinguish system failure from a local receipt.
The current compile-only targets are not an authorized live operation path.

## Validation

See [LAB-048-A](../../tickets/LAB-048-A.md) for commands and observed results. No entitlement,
Info.plist permission, account, network route or minimum platform requirement is added.
