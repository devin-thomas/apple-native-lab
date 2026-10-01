---
id: "LAB-043-A"
title: "Implement Respectful Attention"
status: "done"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-004-B"]
---

# LAB-043-A — Implement Respectful Attention

## Goal

Compare an ordinary reminder, an app Focus filter, and a user-authorized alarm without spamming the system.

## Authority and scope

Read the [governing specification](../experiments/LAB-043-respectful-attention.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** respectful-attention module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Preview when and why attention is requested
3. Schedule app-owned notifications or alarm only by consent
4. Filter only lab content for a selected Focus
5. Provide one cancel-all-lab-alerts action
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Denied permissions do not trigger repeated prompts. (`PromptGate` allows one prompt; a denial or a dismissed prompt leaves `mayPrompt` false: `RespectfulAttentionTests.aDeniedGateDoesNotPromptAgain`, `aDismissedPromptIsNotRepeated`. Hosted: `RespectfulAttentionHostTests.cancelRemovesOnlyLabAlertsAndADeniedGateDoesNotPrompt` restores a denied gate from defaults and Allow does not change it.)
- [x] Timezone changes retain intended date semantics. (`CivilMoment` stores a zone identifier; `instant(deviceZone:)` and `label(deviceZone:)` ignore the device zone: `AttentionTests.theStoredZoneDoesNotFollowTheDeviceZone`. Agenda timers keep `America/Chicago` in the label when the device zone is Tokyo: `RespectfulAttentionTests.theAgendaShowsTimersWithoutPermission`.)
- [x] Cancel removes only lab-owned schedules. (Domain cancel names only stored attentions: `AttentionTests.cancelRemovesOnlyTheNamedAlerts`. Mixed pending lists keep foreign and Clock identifiers: `RespectfulAttentionTests.cancelKeepsAlertsTheLabDoesNotOwn`, `aRecordingSystemDropsOnlyLabAlarms`. Focus filter predicate drops foreign IDs: `aFocusScopeShowsOnlyItsLabAlerts`.)
- [x] Fallback is usable: In-app agenda and timers visible while foregrounded.. (CoreLocal and Mac use `UnavailableAttentionSystem`; the agenda needs no permission: `theAgendaShowsTimersWithoutPermission`, hosted schedule/cancel on Mac. AlarmKit stays off in CoreLocal; the page says so.)
- [x] Sensitive operations share the domain authorization/receipt path. (Schedule and cancel go through `AttentionActions` → `LabLibrary.submit` → `OperationService`; model tools may propose but not commit; Reset Demo removes only demo attentions: `AttentionTests`, `RespectfulAttentionTests.schedulingAndCancellingShareTheReceiptPath`, hosted `thePageAndTheIntentScheduleOneAlertWithReceiptsInOneList`.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No entitlement bypass, automatic global Focus switching, or general control of Clock alarms.

**Research:** [S33](../docs/SOURCE_INDEX.md#s33), [S01](../docs/SOURCE_INDEX.md#s01).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-043's spec now claims `implemented`. The agenda, consented schedule/cancel, and sticky permission gate ran in package tests and on the Mac CoreLocal host. AlarmKit and UserNotifications compile only into `LabPhoneSurfaces` and were not exercised on a device or in the simulator UI. Nothing here is device-verified.

**Changed:**

- `Packages/LabDomain`: `Attention.swift` (new); `scheduleAttention` / `cancelLabAlerts` / `restoreLabAlerts`; store and planner support; Reset Demo removes attentions. Tests: `AttentionTests` (9).
- `Packages/LabStore`: schema version 4 `attentions` table (demo namespace only). Tests: `AttentionStoreTests` (4). Migration expectations updated to version 4.
- `Packages/LabFeatures`: `RespectfulAttention` product (new): offers, agenda, Focus scope, prompt gate, actions, intents (`ScheduleLabAlertIntent`, `CancelLabAlertsIntent`, `LabFocusFilterIntent`). Tests: `RespectfulAttentionTests` (12). Catalog regenerated; 7 implemented / 41 specified.
- `Apps/Shared/RespectfulAttention/` (new): host model, library backend, agenda page, `LiveAttentionSystem` (SystemSurfaces iOS only).
- Shared host hooks (one case each): `LabMacApp` / `LabPhoneApp` (`AttentionHost.connect`); `MainWindowState` / `MainWindow` / `SidebarView` / `LabCommands` (⌘9); `ExperimentDetailView`; `ActionAtlasHost` intents package; `LabDataService` / `LabLibrary` attention reads; `ReceiptRecord` titles; Action Atlas / DemoRunner / LibraryMessages error strings; TypedIntelligence and store test fakes.
- `project.yml` and regenerated project: LabMac, LabPhone, LabPhoneSurfaces link `RespectfulAttention`; `NSAlarmKitUsageDescription` on LabPhoneSurfaces only.
- `Config/ProductPolicy.txt`: SystemSurfaces may link AlarmKit and UserNotifications; AlarmKit purpose string.
- Docs: experiment implementation notes; SOURCE_INDEX S33; VERIFICATION_BOUNDARIES ledger; SHORTCUTS_AND_INTENTS; BUILD_STATUS rows.

**Implementation steps:**

1. **Probe.** iOS 27.0 `AlarmKit.swiftinterface`: authorization, schedule, cancel, fixed schedule, Alert APIs as above. `SetFocusFilterIntent` / `FocusFilterAppContext` on iOS, macOS, watchOS, tvOS. AlarmKit absent from macOS SDK.
2. **Preview.** Sample offers show when and why; building a preview schedules nothing.
3. **Consent.** `AttentionDraft` requires `.explicit`; withheld consent refuses. UI and intents confirm before schedule/cancel.
4. **Focus.** `LabFocusFilterIntent` filters lab notification IDs only; selecting the sample Focus in-app does not change the system Focus.
5. **Cancel all.** One destructive cancel of named lab attentions; system cancel drops only lab IDs.
6. **Tests.** Domain, store, feature, and Mac hosted coverage for denial, zone, cancel scope, unavailable fallback, authorization/receipt, cancellation, and invalid input.

**Not run:**

- Physical iPhone (AlarmKit authorization, live notification/alarm delivery, Focus filter in Settings).
- SystemSurfaces simulator UI for live AlarmKit/UserNotifications.
- VoiceOver / Voice Control / Full Keyboard Access passes.
- A 26-SDK compile.
- Watch or TV surfaces for this experiment.

**Evidence:** LAB-043-A rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). No `evidence/LAB-043/` fixture files yet; qualification (LAB-043-B) owns device/simulator surface proof.

**Next dependency-ready ticket:** LAB-043-B (qualify Respectful Attention), or another M3 implementation whose depends_on are done.
