---
id: "CORE-010"
title: "Establish accessible components and native review gates"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-005", "CORE-007"]
---

# CORE-010 — Establish accessible components and native review gates

## Goal

Make accessibility a shared component property, not late per-demo remediation.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Native shared components, accessibility fixtures, manual review checklist.

## Implementation steps

1. Audit labels, reading order, keyboard/focus, and meaningful state announcements
2. Test large text, contrast, reduced motion/transparency
3. Provide text alternatives for sound/haptics and semantic data summaries
4. Document manual assistive-technology checks in release evidence

## Acceptance criteria

- [x] The core import/review/commit flow is usable without visual-only cues. (Met on iPhone; the Mac announcement gap was closed at integration, see below. Nothing can be imported yet: the share inbox is LAB-007. The flows this build has are browse, open an experiment, the Lab Collection, archive and restore, Reset Demo, and a receipt and its undo. Each status is a word and a symbol, spoken with its kind, and the six lifecycle states, five readiness values, and receipt statuses never share a word or symbol. A receipt reads status and summary, then its undo, then its details. On iPhone every result is announced. On the Mac, only the announcement is missing: `LabAnnouncement` needs AppKit, which the product policy doesn't allow the Mac host to link yet. Mac results reach VoiceOver through the changed control title and the receipt inspector. Evidence: hosted tests and the accessibility API in the running Mac app, plus an iPhone simulator journey by accessibility label. No VoiceOver speech was heard.)
- [x] A keyboard user can navigate and cancel all essential Mac operations. (In the running app, Tab from the search field goes to the results, then the receipt list, the sidebar, and back to search. The receipt list no longer traps Tab. Escape leaves the inspector for the results, and it cancels Reset Demo with no receipt. Archive and restore a sample, and undo the shown receipt, now have menu commands (⌃⌘A, ⌥⌘Z), because their buttons aren't reachable by Tab without keyboard navigation. Every essential command was read from the running app's menus with its shortcut and pressed. Path: accessibility API and System Events on the development Mac. Full Keyboard Access: not run.)
- [x] Reduced Motion does not remove functionality. (Static review: the hosts' one animation, opening a Readiness row, is skipped under Reduce Motion, and no function waits on it. Hosted tests render the sample page, the receipt, and a Readiness row with Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, and the largest text size overridden. Archive, Restore, Undo, and opening the gates all work through the accessibility press action in each case. These are environment overrides inside the test process. The Mac's own settings weren't changed, and the manual passes with the system settings are not run.)
- [x] Automated audit results are not represented as a full manual accessibility pass. ([ACCESSIBILITY_REVIEW](../docs/ACCESSIBILITY_REVIEW.md) lists each automated check with what it proves and what it doesn't. The VoiceOver, Voice Control, Full Keyboard Access, and settings passes for each core flow are all `not-run`. The iPhone audit findings are recorded as triaged findings, not as a pass.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**State claimed: implemented.** Criteria 2 to 4 are met, and criterion 1 is met except for announcements on the Mac. That item needs one reviewed line in `Config/ProductPolicy.txt` to let the Mac host link AppKit, as the iPhone host already links UIKit, plus a three-line `post()` branch. No manual assistive-technology pass has been run.

**Component location:** `Apps/Shared/Components/`. It's one folder compiled into both hosts through the synchronized `Apps/Shared` source folder, so it needs no new target or package.

- `StatusDescriptor(kind:title:symbol:tone:)` and `StatusTone`. A status is a word and a symbol, spoken as "Kind: word"; the tone only picks a color.
- `StatusBadge(status:)` and `StatusLabel(status:)`. Each is one accessibility element. The word is in the primary text color, and the badge draws a solid outline under Increase Contrast.
- `LabAnnouncement(receipt:)`, `LabAnnouncement(failure:)`, and `LabAnnouncement.outcome(of:in:)`, then `.post()`. This is the text alternative for every change that lands elsewhere, and for any future haptic or sound.
- `CountSummary(total:singular:plural:parts:)` with `.sentence`, and `CountSummaryText`. Every data display gets one sentence.

`StateBadge`, `ReadinessBadge`, and `ReceiptStatusLabel` keep their names and signatures, now built on these components.

**Changed:**

- New `Apps/Shared/Components/`: `StatusBadge.swift`, `LabAnnouncement.swift`, and `CountSummary.swift`.
- `Apps/Shared/`:
  - `Catalog/StateBadge.swift` and `Readiness/CapabilityRow.swift` build their badges on the status component and add `status`/`tone`.
  - `Catalog/ExperimentRow.swift` speaks in reading order with commas.
  - `Collection/DemoItemViews.swift` and `Collection/ResetDemoConfirmation.swift` announce their results. Archive also accepts the Voice Control names "Archive" and "Restore".
  - `Receipts/ReceiptViews.swift`: the status label is built on the component. A new `UndoButton` announces its result and also answers to "Undo". A used undo says what it did ("Undone: Restored item …"). On iPhone, Undo is pinned above the tab bar.
  - `Readiness/CapabilityBoard.swift` and `Readiness/ReadinessView.swift` add the probe summary sentence.
- `Apps/Mac/`:
  - New `Window/WindowKeyboard.swift` holds the window's Tab order and the lookups for the selected sample and the shown receipt.
  - `Window/MainWindow.swift` routes forward Tab and handles Escape from the inspector.
  - `Window/ReceiptInspector.swift` is one named group, and its receipt list is labeled with a count.
  - `Window/CatalogColumns.swift` and `Window/CollectionColumns.swift` label the results list with its scope and count.
  - `Window/SidebarView.swift` reads the Lab Collection row as "Lab Collection, 12 samples".
  - `LabCommands.swift` adds Archive Sample or Restore Sample (⌃⌘A) and Undo <operation> (⌥⌘Z) to the Lab menu.
- New `Tests/LabMacTests/`:
  - `AccessibilityTree.swift` renders a shared view off screen in the running app, and reads and presses it through the accessibility API.
  - The test suites: `HostedAccessibilityTreeTests`, `AccessibilityVocabularyTests`, `AnnouncementAndSummaryTests`, and `KeyboardAccessTests`.
- New `docs/ACCESSIBILITY_REVIEW.md`, and a link to it in `docs/TEST_STRATEGY.md`.

`project.yml`, `Config/`, `script/`, the packages, and the Info.plists are unchanged.

**CORE-005 limitations resolved:**

- The Mac Tab order from the search field now goes to the results.
- At the largest accessibility text size, a receipt's Undo is on screen without scrolling on iPhone 17e (simulator).

**Evidence:** the CORE-010 rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). Screenshots and the scripted Mac transcript were kept outside the repository.

**Not run:**

- VoiceOver, Voice Control, and Full Keyboard Access on any device.
- Reduce Motion, Reduce Transparency, and Increase Contrast as Mac system settings. System settings were not changed on this Mac.
- The Mac accessibility audit: a Mac UI-test run needs UI automation, which asks for authentication on this Mac.
- Any physical iPhone.
- iPad, Watch, and TV.

**Known limitations:** listed in [ACCESSIBILITY_REVIEW](../docs/ACCESSIBILITY_REVIEW.md#known-gaps):

- No announcements on the Mac yet.
- Only forward Tab is routed.
- With keyboard navigation on, forward Tab may skip the detail controls.
- Return in the search field doesn't move to the results.

The iPhone audit's open findings are in the same document.

**Accessibility fixtures:** none were needed for these flows. The tests use the bundled demo seed in a temporary store. Chart fixtures whose text and audio can be checked exactly arrive with LAB-035-A.

**Next dependency-ready tickets:**

- CORE-009, whose dependencies are all done.
- The LAB-nnn-A tickets that need only CORE-003 to CORE-008, such as LAB-001-A.
- LAB-035-A (Access as a Superpower) waits on LAB-001-B.

Each qualification ticket signs against this checklist.

**Integration (2026-09-29):** the integrator allowed AppKit for the Mac CoreLocal host in `Config/ProductPolicy.txt` and added the macOS branch of `LabAnnouncement.post()` (`NSAccessibility.post(element:notification: .announcementRequested, userInfo:)` with the same text and priority). Criterion 1 is now met by construction on both hosts. The manual VoiceOver, Voice Control, and Full Keyboard Access passes in `docs/ACCESSIBILITY_REVIEW.md` remain `not-run`; automated results are not a manual pass.
