---
id: "CORE-002"
title: "Implement the typed operation and receipt spine"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001"]
---

# CORE-002 — Implement the typed operation and receipt spine

## Goal

Make all system entry points share one deterministic, authorization-checked application service.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Packages/LabDomain and unit tests.

## Implementation steps

1. Define distinct stable identifier and revision types
2. Implement create/find/update/archive operations with explicit validation
3. Atomically persist idempotency and operation results through a store protocol
4. Return meaningful conflict/error receipts and bounded undo operations

## Acceptance criteria

- [x] The same request ID and payload cannot mutate twice.
- [x] A reused request ID with a different payload is refused.
- [x] A stale revision returns an inspectable conflict.
- [x] No caller bypasses the authorization policy by selecting a different adapter. (Proven at the service and store boundary. Each host must still give an adapter its true kind when wiring it; that is checked when adapters exist.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:** `Packages/LabDomain` (new package: library `LabDomain`, tests `LabDomainTests`), this ticket, and `docs/BUILD_STATUS.md` evidence rows. No app target, project, config, or script changes; the package is not yet wired into the hosts.

**What exists:** typed IDs (`EntityID<Entity>` as `ItemID`/`CollectionID`, `RequestID`, `OperationID`) and `Revision`; `LabCollection` and `LabItem`; eight typed operations (create, update, archive, and restore for collections and items) with validated payload values; `ActorScope` with five adapter kinds and fixed permission ceilings; one `OperationService` actor for every read, proposal, and commit; the `OperationStore` protocol, whose only write takes a service-issued `AuthorizedCommit`; and `InMemoryOperationStore`.

**Acceptance evidence** (all in `swift test --package-path Packages/LabDomain`, 49 tests):

- Same request, one mutation: `theSameRequestTwiceMutatesOnceAndReturnsTheOriginalReceipt`, `aReplayAfterLaterChangesReturnsTheOriginalReceiptWithoutTouchingState`, `concurrentDuplicatesMutateOnce` (48 concurrent submissions of two requests), `aFailedCommitRecordsNothingAndTheSameRequestCanBeRetried`.
- Reused ID refused: `aReusedRequestIDWithADifferentPayloadIsRefused`, `aReusedRequestIDFromAnotherAdapterIsRefused`.
- Inspectable conflict: `aStaleRevisionReturnsAnInspectableConflictAndOverwritesNothing` (expected 1, current 2, no changes, no undo, replayable), `aWriterInAnotherProcessBetweenReadAndCommitCausesAConflict`, `concurrentWritersFromTheSameBaseProduceOneCommitAndConflicts`, `aPersonCanRebaseAConflictUnderANewRequestID`.
- No bypass: `aDenyingPolicyExemptsNoAdapter` (all five adapter kinds), `thePolicyRunsForEveryRequestIncludingReadsProposalsAndReplays`, `aPermissivePolicyCannotWidenAnAdapterCeiling`, `aModelToolCannotCommitEvenWhenGrantedEverything`. A throwaway package outside the repository confirmed that code outside LabDomain cannot create or decode an `AuthorizedCommit`, create a receipt, or decode an `OperationRequest`; all four attempts fail to compile.

**Defect found and fixed during validation:** a repeated run of the concurrency tests failed 17 of 25 times. When two attempts of the same creation interleaved, the second could see the first's new entity and report `alreadyExists` instead of replaying. The service now re-checks the request ID before surfacing a validation error. With the fix, 100 of 100 targeted runs and 50 of 50 full-suite runs passed; with it removed, the test failed 17 of 20 runs.

**Not run:** `script/test.sh` does not yet include LabDomain (the script is outside this ticket's ownership). No host or adapter uses the package yet, so UI and intent equivalence is proven only at the service level (`appUIAndAppIntentProduceEquivalentStateAndReceipts`). No persistent store; that is CORE-003. Authorization grants have no expiry yet; short-lived grants are CORE-006.

**Specification notes:** LAB-001's `Collection` is `LabCollection`, because a public `Collection` type would shadow the standard library protocol in every importing module. The operation type is `DomainOperation` (Foundation already has `Operation`) and the actor is `ActorScope` (Swift already has `Actor`). DATA_CONTRACTS' `RevisionID` is `Revision`: an ordered per-entity counter starting at 1, matching its JSON example. The expected revision lives inside each operation on an existing entity and is required there, rather than being an optional request field. A conflict is a recorded receipt plus `DomainOperation.rebased(onto:)` rather than a separate conflict-proposal type. `SessionID` and `DeviceID` are deferred to the transport labs.

**Next dependency-ready ticket:** CORE-003 (a persistent `OperationStore`). CORE-006 follows CORE-003, and CORE-007 also needs CORE-004.
