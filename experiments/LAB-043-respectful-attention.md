---
id: "LAB-043"
title: "Respectful Attention"
state: "implemented"
milestone: "M3"
category: "System surfaces"
depends_on: ["LAB-004"]
source_review: "2026-09-29"
---

# LAB-043 — Respectful Attention

## The moment

Compare an ordinary reminder, an app Focus filter, and a user-authorized alarm without spamming the system.

## Scope and native leverage

**Hosts:** iPhone primary; supported Mac/Watch behavior separate.

**Primary APIs:** UserNotifications, Focus filters, AlarmKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AttentionRequest, FocusScope, AlarmState. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Preview when and why attention is requested
2. Schedule app-owned notifications or alarm only by consent
3. Filter only lab content for a selected Focus
4. Provide one cancel-all-lab-alerts action

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

Checked items are fixture/model proof from LAB-043-B. Live system delivery and manual accessibility remain unverified.

- [x] Denied permissions do not trigger repeated prompts.
- [x] Timezone changes retain intended date semantics.
- [x] Cancel removes only lab-owned schedules.
- [x] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No entitlement bypass, automatic global Focus switching, or general control of Clock alarms.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app agenda and timers visible while foregrounded.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/respectful-attention/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-043-A):

- `Packages/LabDomain`: `LabAttention`, `AttentionDraft`, `CivilMoment`, `AttentionConsent`, and `DomainOperation.scheduleAttention` / `cancelLabAlerts` / `restoreLabAlerts`. A draft exists only after explicit consent. The civil time keeps its own time zone identifier, so a device zone change does not move the intended wall time. Cancel names only lab-owned alerts. Reset Demo removes demo attention rows and never touches user collections.
- `Packages/LabStore`: schema version 4 adds an `attentions` table whose rows can only be in the demo namespace.
- `Packages/LabFeatures/Sources/RespectfulAttention/`: the sample offers and previews; the in-app agenda and Focus scope; `PromptGate` (one prompt, sticky denial); `AttentionActions` shared by the page and the intents; `ScheduleLabAlertIntent`, `CancelLabAlertsIntent`, and `LabFocusFilterIntent` (`SetFocusFilterIntent`). It depends on LabDomain only. AlarmKit and UserNotifications stay out of this package.
- `Apps/Shared/RespectfulAttention/`: the host model, the library backend, and the agenda page. `LiveAttentionSystem` (AlarmKit + UserNotifications) compiles only in a SystemSurfaces iPhone build; CoreLocal and Mac keep `UnavailableAttentionSystem` and the in-app agenda.

## Implementation notes (LAB-043-A)

Observed with Xcode 27.0 and the 27.0 SDKs on research. These are compile and package/hosted-test facts, not device proof.

- AlarmKit is iOS 26.0+, unavailable on Mac Catalyst and absent from the macOS SDK. `AlarmManager.requestAuthorization()`, `authorizationState`, `schedule(id:configuration:)`, `cancel(id:)`, `AlarmConfiguration.alarm(schedule:attributes:)`, `Alarm.Schedule.fixed(Date)`, and `AlarmPresentation.Alert` (title-only from iOS 26.1; stopButton deprecated) match the installed `AlarmKit.swiftinterface`. Scheduling uses the lab alert's own UUID; cancel names only those IDs.
- `SetFocusFilterIntent`, `FocusFilterAppContext(notificationFilterPredicate:)`, and `suggestedFocusFilters(for:)` are in the iOS, macOS, watchOS, and tvOS AppIntents interfaces. The lab filter's predicate keeps only `lab-alert.` notification identifiers; a foreign identifier in the parameter is dropped before the predicate is built.
- `NSAlarmKitUsageDescription` is declared only on `LabPhoneSurfaces`. CoreLocal never links AlarmKit or UserNotifications. AlarmKit's `AlarmAttributes` conforms to ActivityKit's `ActivityAttributes`, so SystemSurfaces also links ActivityKit for that conformance alone; no Live Activity starts.
- Denied permission: `PromptGate` allows at most one system prompt and stores a denial so Allow Lab Alerts does not ask again. The agenda timers still run while the page is open.
- Cancel Lab Alerts removes only stored lab attentions and, on SystemSurfaces, only lab-owned notification and AlarmKit IDs. Other pending identifiers stay.

## Qualification boundaries (LAB-043-B)

The [walkthrough](../docs/walkthroughs/LAB-043-respectful-attention.md) and [evidence](../evidence/LAB-043/) qualify the agenda and recording-adapter fixtures, with CoreLocal simulator behavior labeled separately. State remains `implemented`. No physical iPhone, live AlarmKit delivery, notification delivery, or Focus filter in Settings was qualified.

Source review found that Reset Demo removes domain attention rows without canceling system schedules; cancel before reset on a live route. Live scheduling discards adapter errors, and the page cannot confirm a schedule (`systemScheduled` is always false). The intents mutate the domain agenda but do not call the live system adapter. Refresh does not upgrade a persisted denial after Settings grants permission. These are existing implementation limits, not proven live outcomes. Original sample dates are fixed on October 1, 2026; they are not rolling future alarms. Accessibility review remains source-only with manual gates not-run.

## Delivery

[Implementation ticket](../tickets/LAB-043-A.md) → [qualification ticket](../tickets/LAB-043-B.md).

**Lab dependencies:** [LAB-004](LAB-004-surface-deck.md).

**Primary-source references:** [S33](../docs/SOURCE_INDEX.md#s33), [S01](../docs/SOURCE_INDEX.md#s01). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
