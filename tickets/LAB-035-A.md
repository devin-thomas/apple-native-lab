---
id: "LAB-035-A"
title: "Implement Access as a Superpower"
status: "done"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-035-A — Implement Access as a Superpower

## Goal

Complete the same meaningful task visually, by VoiceOver, with keyboard control, and through a sonified chart.

## Authority and scope

Read the [governing specification](../experiments/LAB-035-access-as-a-superpower.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** access-as-a-superpower module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Create a data-backed chart with a text summary
3. Expose labels, grouping, actions, and rotor structure as appropriate
4. Add Audio Graphs for supported chart surfaces
5. Test Dynamic Type, contrast, reduce motion and transparency
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] No information is encoded by color alone. (Each bar is one square per sample, filled when archived and dashed when not, with its count in digits and the word "Most" beside a star; the task status is a word and a symbol. Checked by reading the code, by the hosted tests under the Differentiate Without Color override, and in simulator screenshots with Increase Contrast. The grayscale pass by a person is `not-run`.)
- [ ] Keyboard and VoiceOver can finish the full task. (Keyboard: passed. In the running Mac app, real key presses sent through System Events went ⌘5, Tab to the list, arrow keys, and Return, which restored the sample and finished the task; ⌥⌘L and ⌥⌘Z reached the receipt and undid it. VoiceOver: only the structure it uses is proven. The bars' labels, values, and Restore actions were read and performed through the Accessibility API, in the hosted tests and in the running app. Left unchecked until a person finishes the task with VoiceOver on, which is `not-run`.)
- [x] An unsupported sonification API retains a table and summary. (`withoutTheAudioGraphTheSummaryAndListFinishTheTask` renders the page with no chart descriptor under all 6 display overrides: the summary, every heading, and a Restore button for each archived sample remain, and the task finishes.)
- [x] Fallback is usable: Semantic list/table and standard platform controls. (The list of archived samples by collection, with standard buttons, finished the task in the hosted tests, in the running Mac app with the pointer and with the keyboard, and in the iOS simulator at the default and the largest accessibility text size.)
- [x] Sensitive operations share the domain authorization/receipt path. (Every path calls `AccessTaskSession.restore(_:in:)`, which commits `restoreItem` through `LabLibrary.submit` and `LabDataService` to `OperationService` as the app UI. Set Up Practice archives, a destructive kind, each under its own grant from that path. Each leaves a receipt in the inspector with its undo.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Accessibility is a release gate across all labs, not only this showcase; optional Assistive Access is a separate probe.

**Research:** [S29](../docs/SOURCE_INDEX.md#s29), [S30](../docs/SOURCE_INDEX.md#s30).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**State claimed: implemented.** The four paths ran on the Mac and in the iOS simulator. Nothing is device-verified, and no person has used VoiceOver, Voice Control, or Full Keyboard Access on it. The branch is `ticket/LAB-035-A`; integration is pending.

**The task.** "Which demo collection has the most archived samples? Restore one sample from that collection." A first run archives nothing, so Set Up Practice archives 6 demo samples, one receipt each: 3 mineral specimens, 2 pigment swatches, and 1 paper stock sample. The answer is Mineral specimens, the middle bar. Every path ends in the same `restoreItem` through the operation service, with a receipt that offers an undo. A restore from another collection still commits, and the result says the task is not done. Reset Practice restores only the practice samples still archived.

**The four paths and the fallback:**

- **By sight.** The chart's longest bar, then Restore on one of its samples: the list's Restore button on iPhone, or on the Mac a selected row and Restore Sample.
- **With VoiceOver.** Each bar reads its collection, then "3 of 4 samples archived, the most", and has a Restore action for each of its archived samples. Each list row has a Restore action as well, and the list has an Archived Samples rotor. The result is announced once, as the receipt's sentence followed by the task's result.
- **By keyboard (Mac).** ⌘5, then Tab to the list, which is the window's results stop and needs no keyboard navigation. The arrow keys select a sample and Return restores it. ⌥⌘L shows the receipt and ⌥⌘Z undoes it.
- **By ear.** The chart group carries an `AXChartDescriptor`. In the running Mac app it appears as the group's `AXAudiograph` attribute: title, summary, a categorical collection axis, and a numeric archived-samples axis from 0 to 4, with values 2, 3, and 1. The highest value leads to that bar's Restore actions.
- **Fallback.** The summary sentence ("Mineral specimens has the most archived samples: 3 of 4. By collection: …") and the list of archived samples by collection carry the same numbers, with standard buttons. They are always shown, whether or not the descriptor is attached.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `AccessSuperpower` product and target, depending on LabDomain only, and `AccessSuperpowerTests`.
- `Packages/LabFeatures/Sources/AccessSuperpower/` (new):
  - `AccessibleTask`: the restore operation, the judgment, `TaskStatus`, `TaskOutcome`, and `AccessTaskError`.
  - `ArchiveTally`: the demo namespace only.
  - `ChartSemantics` and its `AXChartDescriptor` (make and update).
  - `PracticeSet` and `PracticeRun`: cancellable between commits.
  - `InteractionAlternative`: the four paths as text for each host.
- `Packages/LabFeatures/Tests/AccessSuperpowerTests/` (new): 25 tests in 4 suites.
- `Fixtures/access/archive-chart.json` and `README.md` (new): the practice set and the exact textual and audible reading of the chart. They were built only from `Fixtures/demo/seed.json`.
- `Apps/Shared/AccessSuperpower/` (new):
  - `AccessTaskSession`: the one restore path, practice data, and the combined announcement.
  - `ArchiveChart`: the bars, the custom actions, the descriptor, and the `SonificationRoute` environment value.
  - `AccessTaskViews`: the header, summary, headings, rows, buttons, result, practice controls, and the four ways.
  - `AccessSuperpowerPage`: the iPhone page and `AccessSuperpowerLaunch`, the catalog page's Open button.
- `Apps/Mac/Window/AccessSuperpowerColumns.swift` (new): the Mac list and detail columns.
- The shared hooks. Each has one case except where noted:
  - `SidebarDestination.accessSuperpower` and its title and storage key, plus one `access` session in `MainWindowState`.
  - One case in each of `MainWindow`'s three switches (content, detail, search prompt), and `.environment(window)`, so the catalog page's Open button can reach its window. A focused value is `nil` in a view.
  - One sidebar row.
  - One command, View › Access as a Superpower (⌘5).
  - One line in `ExperimentDetailView`, which shows the Open button only on LAB-035's page.
  - There is no iPhone tab.
- `Apps/Shared/Components/LabAnnouncement.swift` (additive): `init(text:priority:)` for a sentence that adds to a receipt or covers several receipts.
- `project.yml` and the regenerated project: LabMac and LabPhone link the `AccessSuperpower` product. Nothing else changed, and regeneration is byte-identical.
- `Config/ProductPolicy.txt`: CoreLocal may link Accessibility on macOS and iOS, for `AXChartDescriptor`. No entitlement was added, and no other framework (Swift Charts is not used).
- `experiments/LAB-035-access-as-a-superpower.md`: `state: implemented`, the module split, and the implementation notes. The catalog JSON was regenerated. `ExperimentCatalogTests` and `ExperimentRegistryTests` now expect two implemented experiments.
- `Tests/LabMacTests/AccessSuperpowerAccessibilityTests.swift` (new): 10 tests, 15 cases.
- [ACCESSIBILITY_REVIEW](../docs/ACCESSIBILITY_REVIEW.md): the automated rows, flows S1 to S7 with every manual pass `not-run`, and the LAB-035-A review and findings. [BUILD_STATUS](../docs/BUILD_STATUS.md): the LAB-035-A rows.

**Implementation steps:**

1. **API gates.** The installed SDK was read, and an off-screen probe was run, not committed. The results are in the spec's implementation notes and in BUILD_STATUS.
2. **Chart with a summary.** Stated above.
3. **Labels, grouping, actions, rotor.** Stated above.
4. **Audio Graphs.** Stated above.
5. **Dynamic Type, contrast, Reduce Motion, Reduce Transparency.** Checked by the hosted tests under the environment overrides and in the iOS simulator at the largest size with Increase Contrast. The chart has no animation.
6. **Deterministic tests.** `TaskOperationTests` covers the operation through `OperationService` with `GrantAuthorizationPolicy`, invalid input, stale state, a duplicate request, user data left out, and cancellation between practice commits. The unavailable path is the hosted test without the descriptor.

**Evidence:** the LAB-035-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). The live-run logs and simulator screenshots were kept outside the repository.

**Not run:** VoiceOver speech and Audio Graph playback by a person, Voice Control, and Full Keyboard Access on either device. Also not run: a physical iPhone, iPad layouts, the Mac accessibility audit (UI automation asks for authentication on this Mac), and a 26-SDK compile.
