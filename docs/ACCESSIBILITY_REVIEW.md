# Accessibility review

Accessibility is a release gate (R-08 in the [specification](../SPEC.md)). This checklist is that gate: the rules shared views follow, the automated checks, and the manual assistive-technology passes that a person runs on a device. It started at [CORE-010](../tickets/CORE-010.md) and covers the host's core flows. Every qualification ticket adds its experiment's flows to the same matrix.

**An automated result is never a manual pass.** Automated checks read labels, press controls through the accessibility API, and run audits. None of them hears VoiceOver, speaks to Voice Control, or moves through the app the way a person with Full Keyboard Access does. A manual row stays `not-run` until a person performs that pass on the named device, and an automated row never fills it in.

## Shared accessible components

The components live in `Apps/Shared/Components/`. It's one folder compiled into the Mac and iPhone hosts, with no separate target or package. Feature views use them rather than restyling their own.

| Component | Use it for | What it guarantees |
|---|---|---|
| `StatusDescriptor`, `StatusTone` | Any status: lifecycle state, readiness, receipt status | A status is a word and a symbol; the tone only picks a color. It's spoken as "Kind: word", for example "State: Blocked". |
| `StatusBadge`, `StatusLabel` | Showing a status as a capsule or inline | One accessibility element with the spoken label. The word keeps primary text contrast, and Increase Contrast deepens the fill and draws a solid outline. |
| `LabAnnouncement` | A change that lands somewhere other than where the person is, such as a receipt after a confirmation closes | Announces the receipt's summary and says whether it can be undone. A refused change or failure interrupts. The same words are always visible somewhere. Call `LabAnnouncement.outcome(of:in:)?.post()` after an action. When a result adds to a receipt, such as a task's result, or covers several receipts, use `LabAnnouncement(text:priority:)` with words that are also on screen. |
| `CountSummary`, `CountSummaryText` | Any display of counts, such as a board, legend, or chart | One sentence, such as "9 capabilities: 1 available, 6 unavailable, 2 waiting for an action.", shown as text so everyone gets it. |

The Mac main window's keyboard order is in `Apps/Mac/Window/WindowKeyboard.swift`. Existing shared views now use these components: `StateBadge`, `ReadinessBadge`, `ReceiptStatusLabel`, the Readiness rows and summary, the receipt's undo, and the sample archive button.

## Rules for every view

1. **State is never color alone.** Build every status with `StatusDescriptor`. Statuses of one kind never share a word or a symbol.
2. **Every essential action has a labeled control and a path without a gesture.** On the Mac, it also has a menu command with a shortcut, so it works without keyboard navigation reaching the button. On iPhone, a swipe action always has a context menu and a button on the detail page.
3. **Long labels have short Voice Control names.** Use `accessibilityInputLabels` when the spoken label is longer than the visible title. For example, "Undo: Restore Item “Amber swatch”" also answers to "Undo".
4. **Results are announced where they land elsewhere.** After an action, post its `LabAnnouncement`. A haptic or sound never stands alone: it plays beside an announcement and visible text. The hosts have no haptics or sounds today.
5. **Reading order follows meaning.** A receipt reads its status and summary, then its undo offer, then its request details. Combined rows read with commas in reading order, never the visual middle dots.
6. **Large text keeps the primary action on screen.** On iPhone, a page's primary action is pinned in a `PinnedActionBar`, and that includes a receipt's Undo.
7. **Motion is optional.** Animations are skipped under Reduce Motion, and no function depends on one.
8. **Transparency and contrast adapt.** Use system materials (`.bar`), which turn opaque under Reduce Transparency. Build status colors from `StatusTone` so they respond to Increase Contrast.
9. **Data displays have a sentence.** Give every set of counts, chart, or grid a `CountSummary`. Give a chart structured data too, and audio graph semantics where the SDK supports them ([S29](SOURCE_INDEX.md#s29), [S30](SOURCE_INDEX.md#s30)).

## Recording a result

Every row records a result (`passed`, `failed`, `blocked`, or `not-run`). It also records the path:

- `physical`: hands-on use on a device.
- `simulator`: a layout or journey check in the iOS Simulator.
- `hosted test`: the Mac hosted test bundle inside the built app.
- `accessibility API`: scripted inspection of the running app.
- `audit`: Xcode's accessibility audit.
- `static review`: reading the code.

Name the device class, OS, and assistive technology, and never a serial number or account. A finding stays open on its ticket until it's fixed, with the file, control, failure, and matrix item.

## Automated checks

These support the manual passes and never replace them. The last run is in the CORE-010 rows of [BUILD_STATUS](BUILD_STATUS.md).

| Check | How it runs | What it proves | What it does not prove |
|---|---|---|---|
| Status vocabulary | `AccessibilityVocabularyTests` in `script/test.sh` (Mac hosted tests) | Each lifecycle state, readiness value, gate state, and receipt status has its own word and symbol. Spoken labels name the kind. | How a screen reader pronounces them |
| Key controls through the accessibility API | `HostedAccessibilityTreeTests` in `script/test.sh` | Renders the real shared views in the running app and reads their accessibility tree. Checks labels, hints, values, and the receipt's reading order. Presses Archive, Restore, Undo, and a Readiness row through the accessibility press action. It repeats this with environment overrides that stand in for Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, and the largest text size. | The system settings themselves, VoiceOver speech, or focus movement |
| Announcements and summaries | `AnnouncementAndSummaryTests` in `script/test.sh` | The words announced for a commit, an undo, a reset, a refused change, and a failure. The Readiness summary sentence. | That speech happens: both hosts post announcements (iPhone through UIKit, Mac through AppKit), but only a person listening can confirm VoiceOver speaks them |
| Keyboard commands and Tab order | `KeyboardAccessTests` in `script/test.sh` | Every essential Mac command is in the running app's menus with its shortcut, and no two ⌘ shortcuts collide. Tab visits the window's stops in reading order and cannot loop on one. | Key presses in a real window (next row) |
| Running Mac app | The accessibility API and System Events key presses against `script/build_and_run.sh` | Tab order from the search field, and Escape from the inspector and from Reset Demo. The shortcuts do what their menus say, and the labels and groups are in the live tree. | VoiceOver speech; Full Keyboard Access |
| iPhone journey and audit | A UI-test harness in a throwaway copy, iOS Simulator, at the default and largest accessibility text sizes and with Increase Contrast | The core flows work by accessibility label, the primary actions (including Undo) can be tapped without scrolling, and Xcode's accessibility audit results are recorded per screen | A physical iPhone, VoiceOver, Voice Control |
| Mac accessibility audit | Not run | | It needs a Mac UI-test run, and turning on UI automation on this Mac asks for authentication |
| Action Atlas screens through the accessibility API (LAB-001) | `ActionAtlasAccessibilityTests` in `script/test.sh` | Each action row is one element that reads its Shortcuts title, then what it does. In all 8 forms, every text field, picker, and switch is named by its visible label, and the form has exactly one button, named for what it does, disabled until its input is complete. Find Items runs through its button under every display override, and each result is one element led by the item's title. Create Collection, typed into its named field and pressed through its button, commits as the app UI, shows its result in words, and leaves a receipt row that reads "Status: Committed". An open finding is held as a known issue, so the test fails when it is fixed. | VoiceOver speech, Voice Control, Full Keyboard Access, or the system settings |
| Access as a Superpower through the accessibility API (LAB-035) | `AccessSuperpowerAccessibilityTests` in `script/test.sh` | The chart is one group with one `AXChartDescriptor`: its title, summary, categorical collection axis, numeric archived-samples axis, and one series. Each bar reads its collection, then its count, and has a Restore action for each archived sample, in title order. Each collection heading reads like its bar, and each sample row reads title, collection, "Archived", then its note, with a Restore action. The list has an Archived Samples rotor. A bar's action, Return in the list, the selected sample's button, and the page's Restore buttons each restore through the operation service as the app UI, leave a receipt, and say whether the task is done. Without the descriptor, the summary and the list finish the task under every display override. ⌘5 and the catalog page's Open button reach the experiment. | VoiceOver speech, Audio Graph playback, Voice Control, Full Keyboard Access, or the system settings |
| Access as a Superpower in the running Mac app (LAB-035) | The accessibility API and System Events against a Debug build under a separate bundle prefix | Each way of finishing the task, from ⌘5 to the receipt and its undo, and the catalog page's Open button. The chart group's `AXAudiograph` attribute holds the chart's title, summary, axes, and values | VoiceOver speech, Audio Graph playback, Full Keyboard Access |
| Access as a Superpower qualification (LAB-035-B) | `AccessSuperpowerQualificationHostTests` and `AccessSuperpowerHostEvidenceTests` in `script/test.sh`; an accessibility-API client against the running Mac app from another process, with no key presses; the iOS Simulator harness again | The whole task through the accessibility tree alone. Five ways to finish, each on a fresh store, end in the same receipt, announcement, and state. Archived and active squares differ without color. Cancellation, a stale chart, a second press, and Reset Practice beside imported data. From another process, the bars' words and actions, the rotor, the `AXAudiograph` data, and the Restore Sample button's Voice Control names | VoiceOver speech, Audio Graph playback, Voice Control recognition, Full Keyboard Access, the Mac audit |
| Access as a Superpower on iPhone (LAB-035) | A UI-test harness in a throwaway copy, iOS Simulator, at the default settings and at the largest accessibility text size with Increase Contrast | The journey by accessibility label, from the catalog page's Open button through practice data, a Restore button, the result, the receipt, and its pinned Undo. Each bar's label and value. Xcode's accessibility audit results per screen | A physical iPhone, VoiceOver, Voice Control, the custom actions and rotor on iOS |
| Action Atlas on iPhone (LAB-001) | A UI-test harness in a throwaway copy, iOS Simulator, at the default and largest accessibility text sizes | The Action Atlas journey works by accessibility label, from the Actions tab to a receipt's pinned Undo. Xcode's accessibility audit results are recorded per screen, and whether each form's action is on screen at the largest size | A physical iPhone, VoiceOver, Voice Control |
| Share Ingress through the accessibility API (LAB-007) | `ShareIngressAccessibilityTests` in `script/test.sh` | Paste and Choose Files… are named buttons. With the file entitlement, Choose Files… is enabled and says what it does; without it, it stays in place, disabled, with a hint that names the way round. Each waiting import is one element that reads its content, kind, and origin with commas, and a file says it can't be added yet. An intake's result is one element: the summary, then each refusal by position. The review screen reads its origin, keeps Add disabled until the person has a collection, and Add, pressed through the accessibility press action, commits as the app UI and hands over its receipt. | VoiceOver speech, Voice Control, Full Keyboard Access, or the system settings |
| Share Ingress on iPhone and in the running Mac app (LAB-007) | A UI-test harness in a throwaway copy on an iPhone 17 Pro simulator (iOS 27.0), and the accessibility API against a Debug Mac build under a separate bundle prefix | iPhone: Paste, the review screen, New Collection…, Add, and the receipt by accessibility label; Choose Files… through the document picker; a Photos share into the extension. Xcode's accessibility audit results at the default text size. Mac: View › Share Inbox, Choose Files…, and the open panel, by accessibility element | A physical iPhone, VoiceOver, Voice Control, large text |

## Manual passes

Each pass covers the core flows below on the named device. All of them are `not-run` until a person performs them. The Mac passes use the development Mac on macOS 27. The iPhone passes use a physical iPhone on iOS 27. iPad isn't possible, and Watch and TV wait for their devices.

**Core flows**

| ID | Flow | Done when |
|---|---|---|
| F1 | Browse the catalog | Every state reads as its word; lists name themselves with a count |
| F2 | Open an experiment | Its page reads title, state, payoff, then the primary action |
| F3 | Open the Lab Collection | Samples read title, Archived if archived, note, revision |
| F4 | Archive and restore a sample | The action, its result, and the receipt's undo offer are reachable and heard |
| F5 | Reset Demo: cancel, then confirm | Cancel changes nothing; confirm leaves a receipt that is heard or focused |
| F6 | Inspect a receipt and undo it | Status, summary, undo offer, then details; a used undo says what it did |

**Pass matrix**

| Pass | Device | F1 | F2 | F3 | F4 | F5 | F6 |
|---|---|---|---|---|---|---|---|
| VoiceOver | Mac | not-run | not-run | not-run | not-run | not-run | not-run |
| VoiceOver | iPhone | not-run | not-run | not-run | not-run | not-run | not-run |
| Voice Control | Mac | not-run | not-run | not-run | not-run | not-run | not-run |
| Voice Control | iPhone | not-run | not-run | not-run | not-run | not-run | not-run |
| Full Keyboard Access | Mac | not-run | not-run | not-run | not-run | not-run | not-run |
| Full Keyboard Access (hardware keyboard) | iPhone | not-run | not-run | not-run | not-run | not-run | not-run |
| Largest accessibility text size | iPhone | not-run | not-run | not-run | not-run | not-run | not-run |
| Increase Contrast | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run |
| Reduce Motion | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run |
| Reduce Transparency | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run |
| Differentiate Without Color, grayscale | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run |

**What to check in each pass**

- **VoiceOver (Mac).**
  - The sidebar reads each row as its name and count, such as "Blocked, 0 experiments" and "Lab Collection, 12 samples".
  - The results list names its scope and count, and a row reads "Action Atlas, State: Specified, LAB-001, M1, System surfaces".
  - In F4 and F6, press the button and listen for the announcement. Also confirm that the button's new title ("Restore Sample") and the receipt (⌥⌘L) carry the result. Record what is spoken.
  - In F5, the alert reads its message and Cancel is reachable.
- **VoiceOver (iPhone).**
  - The tab bar, the state legend, and the state filter read their state words.
  - After Archive, Undo, and Reset Demo, VoiceOver announces the receipt's summary and "Undo is available." when there is one.
  - A receipt reads status, summary, undo offer, then details, and the pinned Undo button is reachable.
- **Voice Control.** Say "Show names". Every control has a name that can be spoken. "Tap Archive", "Tap Undo", and "Tap Reset Demo" work, and so do "Tap Cancel" and "Tap Reset Demo" in the alert.
- **Full Keyboard Access (Mac).** With keyboard navigation on:
  - Tab from the search field lands on the results.
  - Tab and Shift-Tab reach the detail column's buttons and links, and the inspector's Undo.
  - Escape in the inspector returns to the results, and Escape cancels Reset Demo.
  - Record whether the forward Tab order skips the detail controls (see Known gaps).
- **Largest text size (iPhone).** At accessibility extra extra extra large:
  - No state word or row metadata truncates mid-word.
  - Each screen's primary action, including a receipt's Undo, is on screen without scrolling.
- **Increase Contrast, Reduce Transparency, grayscale.**
  - Every badge stays readable with its word.
  - Status still reads without color.
  - The pinned bar is opaque.
- **Reduce Motion.** Opening a Readiness row's gates, the inspector, and navigation all work, with motion removed or reduced.

Record each pass in [EVIDENCE_TEMPLATE](EVIDENCE_TEMPLATE.md) form, and list the ticket, the source revision, and each flow's result.

**Experiment flows**

Each qualification ticket adds its experiment's flows here. They use the same passes and devices as the core flows, and all of them are `not-run` until a person performs them.

| ID | Experiment | Flow | Done when |
|---|---|---|---|
| A1 | [LAB-001](../experiments/LAB-001-action-atlas.md) Action Atlas | Open Action Atlas (Mac: sidebar or ⌘4; iPhone: Actions tab) and browse the actions | Each action reads its Shortcuts title, then what it does |
| A2 | LAB-001 | Create a collection, then an item in it | Each field reads its label, the button reads what it does, the result reads each field in words, and the receipt row reads its status |
| A3 | LAB-001 | Find items | The count is read, and each item reads title, collection, status, and note, separated by commas |
| A4 | LAB-001 | Archive an item, open its receipt, and undo | The result and the receipt are heard or focused, and Undo is reachable and says what it did |
| A5 | LAB-001 | Update an item that changed after it was picked | The "Not applied" sentence is read, and the receipt says nothing changed |

| Pass | Device | A1 | A2 | A3 | A4 | A5 |
|---|---|---|---|---|---|---|
| VoiceOver | Mac | not-run | not-run | not-run | not-run | not-run |
| VoiceOver | iPhone | not-run | not-run | not-run | not-run | not-run |
| Voice Control | Mac | not-run | not-run | not-run | not-run | not-run |
| Voice Control | iPhone | not-run | not-run | not-run | not-run | not-run |
| Full Keyboard Access | Mac | not-run | not-run | not-run | not-run | not-run |
| Full Keyboard Access (hardware keyboard) | iPhone | not-run | not-run | not-run | not-run | not-run |
| Largest accessibility text size | iPhone | not-run | not-run | not-run | not-run | not-run |
| Increase Contrast | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |
| Reduce Motion | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |
| Reduce Transparency | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |
| Differentiate Without Color, grayscale | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |

What to check in the Action Atlas flows, beyond the core list:

- **VoiceOver.** After each change in a form, listen for an announcement of the receipt; today none is posted (see the findings below). On the Mac the receipt also opens in the inspector, so confirm where focus goes.
- **Voice Control.** "Tap Create Collection", "Tap Archive Item", and "Tap Undo" work, and every form field can be named by its label.
- **Full Keyboard Access (Mac).** Return runs the form's action. Tab reaches each field and the button, then the receipt row.
- **Largest text size (iPhone).** Each form's action button can be reached, and whether it is on screen without scrolling is recorded (see the findings below).

| ID | Experiment | Flow | Done when |
|---|---|---|---|
| S1 | [LAB-035](../experiments/LAB-035-access-as-a-superpower.md) Access as a Superpower | Open the experiment (Mac: sidebar, ⌘5, or the Open button on its catalog page; iPhone: the Open button on its catalog page) | The page reads the question, then "Task: …", then the counts |
| S2 | LAB-035 | Set Up Practice, then Reset Practice | Each reads its result; Reset restores only the practice samples |
| S3 | LAB-035 | Finish by sight: find the longest bar, then restore one of its samples from the list | "Task done" is shown and heard, with the receipt |
| S4 | LAB-035 | Finish with VoiceOver: read the bars, then use a Restore action on the bar with the most | Each bar reads its collection, then "3 of 4 samples archived, the most"; the actions read in title order; the announcement names the receipt, its undo, and the task result |
| S5 | LAB-035 | Finish by keyboard (Mac: ⌘5, Tab to the list, arrow keys, Return; iPhone: Full Keyboard Access to a Restore button) | The list is reached without keyboard navigation, Return restores, and ⌥⌘L and ⌥⌘Z reach the receipt and its undo |
| S6 | LAB-035 | Finish by ear: describe the chart and play its Audio Graph, then use that bar's Restore action | The description reads the title, summary, and both axes; the highest tone is Mineral specimens |
| S7 | LAB-035 | Finish without the chart: the summary and the list only | The summary gives every count, each heading reads like its bar, and each sample has its own Restore |

| Pass | Device | S1 | S2 | S3 | S4 | S5 | S6 | S7 |
|---|---|---|---|---|---|---|---|---|
| VoiceOver | Mac | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| VoiceOver | iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Voice Control | Mac | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Voice Control | iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Full Keyboard Access | Mac | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Full Keyboard Access (hardware keyboard) | iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Largest accessibility text size | iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Increase Contrast | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Reduce Motion | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Reduce Transparency | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |
| Differentiate Without Color, grayscale | Mac, iPhone | not-run | not-run | not-run | not-run | not-run | not-run | not-run |

The step-by-step script for these flows, with a record sheet, is [Access as a Superpower: the manual passes](walkthroughs/LAB-035-manual-passes.md).

What to check in the Access as a Superpower flows, beyond the core list:

- **VoiceOver and Audio Graph.** Record the exact command that opens the chart's Audio Graph on each device, whether it is offered on the chart or on each bar, and what "Describe" reads. Play it and record whether the highest tone is Mineral specimens. On the Mac a bar has no role of its own, as a Swift Charts bar does not; confirm VoiceOver reads its value and offers its actions. Confirm the whole combined announcement is spoken, for example "Restored item “Quartz point”. Undo is available. Task done: Mineral specimens had the most archived samples (3)." The Archived Samples rotor moves between samples.
- **Voice Control.** "Tap Restore Quartz point", "Tap Set Up Practice", and "Tap Open Access as a Superpower" work. "Tap Restore" shows numbers, because every sample has one.
- **Full Keyboard Access (Mac).** Return in the list restores the selected sample, and Tab or Shift-Tab reaches the selected sample's Restore Sample button and the practice buttons. Record whether a Lab-menu command is still wanted (finding 2 below).
- **Largest text size (iPhone).** Each bar puts its count under its name, the Open button is on screen without scrolling, and every Restore button can be reached.
- **Grayscale and Differentiate Without Color.** Filled squares against dashed outlines, the counts, and the word "Most" carry the answer without color.

| ID | Experiment | Flow | Done when |
|---|---|---|---|
| I1 | [LAB-007](../experiments/LAB-007-share-ingress-station.md) Share Ingress Station | Open the inbox (Mac: sidebar or ⌘6; iPhone: Import tab) and read it | The intake buttons, the limits, each waiting import (content, kind, origin), and the share sheet status are read |
| I2 | LAB-007 | Paste a note, open it, create a collection, and Add | The intake's summary is heard, the review reads content then origin, Add says what it does, and the receipt is heard or focused |
| I3 | LAB-007 | Choose Files… and pick two files | The picker is reachable, and each file reads as File picker with its position and "Can't be added in this version" |
| I4 | LAB-007 | Share an image from another app to Native Lab (iPhone, SystemSurfaces build) | The extension's summary and each item's line are read, and Done is reachable |
| I5 | LAB-007 | Paste content that is refused, then remove a waiting import | Each refusal is read by position, never by content; Remove asks first, and its result is heard |

| Pass | Device | I1 | I2 | I3 | I4 | I5 |
|---|---|---|---|---|---|---|
| VoiceOver | Mac | not-run | not-run | not-run | not applicable | not-run |
| VoiceOver | iPhone | not-run | not-run | not-run | not-run | not-run |
| Voice Control | Mac | not-run | not-run | not-run | not applicable | not-run |
| Voice Control | iPhone | not-run | not-run | not-run | not-run | not-run |
| Full Keyboard Access | Mac | not-run | not-run | not-run | not applicable | not-run |
| Full Keyboard Access (hardware keyboard) | iPhone | not-run | not-run | not-run | not-run | not-run |
| Largest accessibility text size | iPhone | not-run | not-run | not-run | not-run | not-run |
| Increase Contrast | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |
| Reduce Motion | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |
| Reduce Transparency | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |
| Differentiate Without Color, grayscale | Mac, iPhone | not-run | not-run | not-run | not-run | not-run |

The Mac has no share extension, so I4 is not applicable there.

What to check in the Share Ingress flows, beyond the core list:

- **VoiceOver.** After Paste, listen for the intake's summary; after Add, for the receipt's announcement. A refusal must name its position ("Item 2: …") and never read the refused content. On the Mac, confirm where focus goes when the receipt opens in the inspector.
- **Voice Control.** "Tap Paste", "Tap Choose Files", "Tap Add to Collection", and "Tap Remove from Inbox" work. In the share extension, "Tap Done" works.
- **Full Keyboard Access (Mac).** ⌘V pastes into the inbox. Record how Choose Files…, Add to Collection, and Remove from Inbox are reached from the keyboard (finding 1 below).
- **Largest text size (iPhone).** Record whether Add to Collection is on screen without scrolling (finding 2 below), and whether any row's origin line truncates.

## Known gaps

- **Mac announcements are posted but not yet heard.** Since the integration of CORE-010, `LabAnnouncement.post()` uses AppKit's `announcementRequested` notification on the Mac (the product policy allows AppKit for that). No person has yet confirmed that VoiceOver speaks them; that stays a manual row.
- **Only forward Tab is routed on the Mac.** Tab runs sidebar, search, results, the inspector's receipt list, then back to the sidebar. Shift-Tab is left to the system. It reaches every stop, but not in the exact reverse order.
- **The forward Tab order may skip controls under keyboard navigation.** With keyboard navigation on, forward Tab from the search field goes to the results and passes over the detail column's and inspector's controls. Shift-Tab still reaches them. Archive, Restore, and Undo also have menu commands (⌃⌘A, ⌥⌘Z). The Full Keyboard Access pass decides whether the forward order should include the detail column.
- **Return in the search field doesn't move to the results.** Tab does.
- **Read the Specification has no menu command.** It's a link to the public repository, reachable with keyboard navigation and VoiceOver.

## Open audit findings

Xcode's accessibility audit ran on the iPhone 17e simulator (iOS 27.0) at the default text size, and again at accessibility extra extra extra large with Increase Contrast. It covered seven screens: catalog, experiment page, collection, sample, receipt, Reset Demo alert, and Readiness. These findings are triaged, not fixed. Each stays open until the manual pass or its owner closes it.

| Finding | Where | Triage |
|---|---|---|
| Contrast flagged on status badges ("Unavailable", "Specified") at the default text size | Readiness, catalog | Measured from the screenshot, the badge word is black on the tinted fill at 17.4:1. The tinted symbol against the fill is about 3.0:1, and the audit appears to be measuring that. The symbol is supplementary: the word carries the meaning. Visual design to decide whether the symbol and outline should be stronger in standard contrast. |
| "Contrast nearly passed" or failed on secondary caption text (revision numbers, identifiers, row metadata, notes) at the default text size | Collection, receipt, sample, experiment page | The system secondary label color at caption sizes. It passes with Increase Contrast. Visual design to review secondary text at caption sizes. |
| Contrast failed or text clipped on content under the tab bar, the navigation bar, or the pinned action bar | Catalog, collection, receipt, Readiness | That content had scrolled beneath a translucent bar when the audit ran. It reads normally once scrolled into view. Confirm in the Increase Contrast and Reduce Transparency passes. |
| Dynamic Type partially unsupported on Read the Specification, Archive Sample, and Undo | Pinned action bar | By design, the pinned bar grows to accessibility size 2 and then holds, like a toolbar, and the Large Content Viewer shows the label at full size. At the largest size these are the only app controls flagged. The default-size run also flags some form row labels and the Readiness summary sentence, but the largest-size run doesn't flag them. Confirm the Large Content Viewer in the large-text pass. |
| Dynamic Type or text flagged in the Reset Demo alert | Alert | The system alert. The app supplies only its title, message, and button titles. |

## Action Atlas review (LAB-001-B)

The Action Atlas screens were reviewed against the rules above with automated checks and by reading the code. No manual pass was run: every row in the [experiment flows](#manual-passes) matrix is `not-run`.

**Automated results**

| Check | Path | Result |
|---|---|---|
| `ActionAtlasAccessibilityTests` (Mac hosted tests, in `script/test.sh`) | hosted test, macOS 27.0 | passed: action rows, named controls in all 8 forms, Find Items under every display override, and Create Collection end to end. One known issue, finding 1. |
| iPhone journey by accessibility label | simulator, iPhone 17, iOS 27.0, a UI-test harness in a throwaway copy that is not committed | passed: the Actions tab, then Create Lab Collection, Create Lab Item, Find Lab Items, Archive Lab Item, the receipt, and its pinned Undo, each reached and pressed by its label |
| Xcode's accessibility audit on each of those screens | same harness, default text size and the largest accessibility size | issues recorded as findings 5 and 6 |
| Form actions at the largest accessibility text size | same harness | failed for rule 6: finding 3 |

**Findings.** These stay open until fixed or closed by the manual pass. Each names the rule it concerns.

| # | Rule | Finding | Where | Found by | Triage |
|---|---|---|---|---|---|
| 1 | 5 | A found item's row reads the middle dot between its collection and "Demo sample", for example "Amber swatch, Pigment swatches · Demo sample, Warm yellow-brown…". The same joined text names items in the forms' item pickers. | `AtlasItemChoice.detail` and `label` in `Apps/Shared/ActionAtlas/AtlasRun.swift` | accessibility API (`foundItemRowsReadWithCommasNotMiddleDots`, a known issue) | Join the spoken parts with commas. The test fails once this is fixed, so the review is updated with it. |
| 2 | 4 | The forms post no announcement after a change. On the Mac, the receipt also opens in the inspector, away from the form. | `Apps/Shared/ActionAtlas/AtlasActionForms.swift` | static review | Post `LabAnnouncement.outcome(of:in:)` after each change that leaves a receipt, as the collection browser and the receipt's Undo do. |
| 3 | 6 | At the largest accessibility text size on iPhone, no form's action button is on screen without scrolling. Create Collection, Find Items, Archive Item, and Export Item were checked; each can be reached by scrolling. | `AtlasRunButton` in `AtlasActionForms.swift` | simulator harness | Pin the form's action in a `PinnedActionBar` on iPhone, as a receipt pins Undo. |
| 4 | 2 | On the Mac, each form's action is the window's default button, so Return runs it, but it has no menu command. | Mac forms | static review | The Full Keyboard Access pass decides whether Return is enough. |
| 5 | 3 | On iPhone, the Find Items text field has no label, so VoiceOver and Voice Control get only its placeholder, "Any text". On the Mac the same field is titled "Text". | `FindItemsForm` in `AtlasActionForms.swift` | simulator harness | Give the field an explicit label. |
| 6 | 8, 9 | At the default text size, the final harness run's audit reported 75 issues across 6 screens. Contrast "nearly passed" (31) or failed (10) on secondary text: row summaries, section headers, receipt times and summaries, and entity lines. Dynamic Type was partially supported (28) or unsupported (2, on unnamed elements in the Archive form) on form row labels and the pinned Undo. Text was clipped (4), including the Find form's "Any collection" picker value. At the largest size, the action list and the Create Lab Collection form had 1 issue each: contrast on an unnamed element. | iPhone screens | simulator audit | Secondary text and content under bars: the same triage as the core audit findings above. The pinned Undo holds at accessibility size 2 by design. Confirm the clipping and the unsupported elements in the large-text pass. |

## Access as a Superpower review (LAB-035-A)

[LAB-035](../experiments/LAB-035-access-as-a-superpower.md) asks for one task, "Which demo collection has the most archived samples? Restore one sample from that collection.", finished four ways: by sight, with VoiceOver, by keyboard, and by ear through the chart's Audio Graph. Every way ends in the same `restoreItem` through the operation service, with the same receipt. The review below was made with automated checks and by reading the code. No manual pass was run: every row in the [experiment flows](#manual-passes) matrix for S1 to S7 is `not-run`.

**Automated results**

| Check | Path | Result |
|---|---|---|
| `AccessSuperpowerAccessibilityTests` (Mac hosted tests, in `script/test.sh`) | hosted test, macOS 27.0 | passed: 10 tests, 15 cases. They cover the chart's descriptor, series, and axes; the bars' labels, values, and Restore actions in title order; the list's headings, rows, row actions, and Archived Samples rotor; Return in the list; the selected sample's button; the page without the descriptor under all 6 display overrides; ⌘5; and the catalog page's Open button. |
| `AccessSuperpowerTests` (package, in `script/test.sh`) | fixture | passed: 25 tests. The chart's text and audio readings match `Fixtures/access/archive-chart.json` exactly, and the descriptor holds the same series and axes. |
| Running Mac app, each way to finish | accessibility API and System Events, macOS 27.0, a Debug build under a separate bundle prefix | passed. Pointer: a real click on the Quartz point row, then on Restore Sample. VoiceOver structure: the Mineral specimens bar's "Restore Quartz point" action, performed through the accessibility API. Keyboard: ⌘2, ⌘5, one Tab to the list, five Down arrows, Return, ⌥⌘L, ⌥⌘Z. Audio Graph: read the chart group's `AXAudiograph` attribute, take the highest value (Mineral specimens), then that bar's action. Each way showed "Task: Done" and its receipt in the inspector, and each undo returned it to "Task: To Do". |
| iPhone journey by accessibility label | simulator, iPhone 17, iOS 27.0, created for this ticket; a UI-test harness in a throwaway copy that is not committed | passed at the default settings and at accessibility extra extra extra large with Increase Contrast. The journey went from the catalog page's Open button through Set Up Practice, the three bars' labels and values, Restore Quartz point, "Task done", the receipt, and its pinned Undo, then back to "Task: To Do" and Reset Practice. At both sizes the Open button and the receipt's Undo were hittable without scrolling. |
| Xcode's accessibility audit on the experiment page, the task page, and the receipt | same harness | issues recorded as findings 3 and 4 |

**Findings.** These stay open until fixed or closed by the manual pass. Each names the rule it concerns.

| # | Rule | Finding | Where | Found by | Triage |
|---|---|---|---|---|---|
| 1 | 5 | On the Mac, a selectable `Text` keeps reporting its first value to assistive technology after its text changes: the outer static text keeps the old words and a child element has the new ones. In the receipt inspector, after a second receipt, the summary's outer element still read "Restored item “Quartz point”." under the heading Archive Item. On an experiment's catalog page, after another experiment was selected, the Fallback section still read the previous experiment's fallback. | `ReceiptDetailView` summary in `Apps/Shared/Receipts/ReceiptViews.swift`; `DetailSection` in `Apps/Shared/Catalog/ExperimentDetailView.swift` | accessibility API, running Mac app | For the host views' owner: drop `.textSelection(.enabled)` where the text changes, or give the view a new identity for each receipt or experiment. The Access as a Superpower summary is not selectable for this reason. The Mac VoiceOver pass records what is spoken. |
| 2 | 2 | The restore has no menu command of its own. On the Mac its keyboard path is Return in the list. The list is the window's results stop, so the path needs no keyboard navigation. The selected sample's Restore Sample button, the context menu, and the bars' actions restore too. | `AccessSuperpowerListColumn` in `Apps/Mac/Window/AccessSuperpowerColumns.swift` | static review | This is the same question as Action Atlas finding 4. A Lab-menu command would be one more case in `LabCommands`; it was held back to keep the shared hook to one case. The Full Keyboard Access pass decides. |
| 3 | 8, 9 | At the default text size the audit reported 13 issues on the experiment page, 15 on the task page, and 16 on the receipt. Contrast "nearly passed" or failed on secondary text: section headers, the chart key, and sample notes. Dynamic Type was flagged "partially supported" on the chart's collection names, counts, "Most", and key, and 1 unnamed text was clipped. In the first run, the bordered Restore buttons' tinted titles and the bordered Open button failed contrast, so both are now prominent. In the second run the Restore buttons were not flagged, and the Open button's contrast "nearly passed". | iPhone task page | simulator audit | Secondary text follows the triage of the core audit findings above. The chart's text uses text styles and grows. At the largest size the audit flags none of it, as with Action Atlas finding 6. The large-text pass confirms. |
| 4 | 6 | At the largest accessibility size with Increase Contrast, the audit reported 2 issues on the experiment page, 1 on the task page, and 2 on the receipt. Contrast failed on text that had scrolled under a translucent bar ("12 demo samples: …" under the tab bar). The capped pinned buttons were flagged as partially supporting Dynamic Type. The Open button is on screen and hittable, but its lower part sits under the pinned Read the Specification bar. | Experiment page, task page, receipt | simulator audit and screenshots | Content under bars and the capped pinned bar follow the core triage. For visual design and the host views' owner: decide whether an implemented experiment's page pins its Open button instead of Read the Specification. |

## Typed Local Intelligence review (LAB-010-B)

The [LAB-010](../experiments/LAB-010-typed-local-intelligence.md) screens were reviewed against the rules above with automated checks and by reading `Apps/Shared/Intelligence/`. No manual pass was run, and no iPhone screen was checked. The experiment has no rows in the [manual passes](#manual-passes) matrix yet. Its flows are: pick a note; draft with each of the three sources; review and edit; apply; open the receipt; Reset Demo.

What the code already does for these rules:

- Every draft's source is a `StatusDescriptor` badge, and the model's availability is one too (rule 1).
- Each issue's icon is hidden from assistive technology. Its label starts "Must fix:" or "Check:", so the meaning never rests on red or orange (rule 1).
- Each draft button has a hint, and the two non-model buttons say "Not a model".
- Apply posts the receipt's `LabAnnouncement` (rule 4).

**Automated results**

| Check | Path | Result |
|---|---|---|
| `TypedIntelligenceViewTests` (Mac hosted tests, in `script/test.sh`) | hosted test, macOS 27.0 | passed. With Apple Intelligence faked off, the view reads the gate sentence, the model button is disabled, and the parser's draft is applied through accessibility presses alone. |
| `TypedIntelligenceHostEvidenceTests` (Mac hosted tests) | hosted test, macOS 27.0, fake devices | passed: 64 checks across the 4 ways the model can be unavailable. In each, both non-model buttons carry the hint "Not a model", the draft's badge reads "Sample parser (not a model)", and the change is applied through accessibility presses. |
| The model path through accessibility presses | accessibility API, a throwaway hosted harness that is not committed, macOS 27.0, live model | passed for both notes: "Draft with the On-Device Model", pressed through the accessibility press action, reached an enabled "Apply Change" |
| iPhone screens, Xcode's accessibility audit | not run | The iPhone screens were not driven |

**Findings.** These stay open until fixed or closed by the manual pass. Each names the rule it concerns.

| # | Rule | Finding | Where | Found by | Triage |
|---|---|---|---|---|---|
| 1 | 4 | A finished draft posts no announcement, and neither does a failed one. The proposal appears below the draft buttons, and a failure shows as a problem row above the proposal. A VoiceOver user who pressed a draft button hears nothing. In the simulator a model draft took up to 29 seconds. | `IntelligenceWorkbench.draft(with:)` and `TypedIntelligenceView` in `Apps/Shared/Intelligence/` | static review | For the experiment's owner: when a draft reaches review, post an announcement naming its source and sample. When a draft fails, post its message. |
| 2 | 2 | The Mac has no menu command for Typed Local Intelligence. ⌘1 to ⌘8 now go to other destinations, and LAB-010-A added none, to avoid clashing with parallel branches. The draft buttons and Apply have no menu command either, and Apply is not the default button. All of them are reachable from the sidebar or the catalog page's Open button, then with keyboard navigation or VoiceOver. | `LabCommands` in `Apps/Mac/`; `TypedIntelligenceView` | static review | This is the same question as Action Atlas finding 4. The Full Keyboard Access pass decides. For the host views' owner: consider a View-menu command, and making Apply the default action while a proposal can be applied. |
| 3 | 6 | On iPhone, Apply Change is the last control of a long form, after the proposal, the checks, the evidence, and the diff. It is not pinned, so at large text sizes it will be off screen until the person scrolls. | `ProposalSections` in `TypedIntelligenceView.swift` | static review; not measured | Pin Apply in a `PinnedActionBar` on iPhone, as a receipt pins Undo. The large-text pass measures it. |
| 4 | 5 | The Change rows are selectable text, and they change as the person edits the proposal. Access as a Superpower finding 1 saw selectable text on the Mac keep reporting its old value after a change. | `DiffRow` in `TypedIntelligenceView.swift` | static review; not observed here | Confirm in the Mac VoiceOver pass. If it reproduces, apply the same fix as that finding. |

## Access as a Superpower review (LAB-035-B)

LAB-035-B qualified the experiment with automated checks and by reading the code. No manual pass was run: every S1 to S7 row in the [experiment flows](#manual-passes) matrix is still `not-run`. The script a person follows for them is [Access as a Superpower: the manual passes](walkthroughs/LAB-035-manual-passes.md).

**Automated results**

| Check | Path | Result |
|---|---|---|
| `AccessSuperpowerQualificationHostTests` (Mac hosted tests, in `script/test.sh`) | hosted test, macOS 27.0 | passed: 7 tests, 8 cases. Opening the experiment changes nothing. The whole task finishes through the accessibility tree alone. An archived square and an active one differ in grayscale, with their fill hidden, at standard and increased contrast. Cancelling Set Up Practice keeps what committed. A restore from a stale chart is a conflict, then succeeds. A second press commits once. Reset Practice leaves imported and personal data alone. |
| `AccessSuperpowerHostEvidenceTests` (Mac hosted tests) | hosted test, macOS 27.0 | passed: the visible button, a bar's action, the keyboard in the list, the Audio Graph's highest value, and the page without its descriptor each end in the same restore, receipt, announcement, and state. All 60 comparisons matched (`evidence/LAB-035/access-superpower-host-four-ways.json`). |
| Running Mac app from another process | accessibility API, macOS 27.0, a Debug build under a separate bundle prefix, VoiceOver off | passed. The bars' value descriptions and Restore actions in title order, one Archived Samples rotor, and the chart group's `AXAudiograph` data: title, summary, both axes, and the values 2, 3, and 1. The bar's action, the highest Audio Graph value, a list row's action (a miss), and the Restore Sample button each gave the expected result. The Restore Sample button's `AXUserInputLabels` are Restore Sample, the sample's name, and Restore (`evidence/LAB-035/access-superpower-mac-running-app.json`). No key was pressed, so the keyboard path here is covered only by the hosted tests. |
| iPhone journey by accessibility label | simulator, iPhone 17, iOS 27.0, created for this ticket; a UI-test harness in a throwaway copy that is not committed | passed at the largest accessibility text size with Increase Contrast and at the default settings, from a fresh install each time: the catalog row, Open, Set Up Practice, the bars and the summary, Restore Quartz point, the result, the receipt and its pinned Undo, and Reset Practice. The Open button and the Undo were hittable without scrolling at both settings (`evidence/LAB-035/access-superpower-iphone-simulator-journey.json`). |
| Xcode's accessibility audit on the experiment page, the task page, and the receipt | same harness | Default settings: 12, 20, and 16 issues. Largest size with Increase Contrast: 2, 1, and 2. Triage below. |
| Mac accessibility audit | not run | It needs a Mac UI-test run, and turning on UI automation on this Mac asks for authentication. |

**The LAB-035-A findings, rechecked**

| # | Status after LAB-035-B |
|---|---|
| 1 | Open. The Access as a Superpower summary is still not selectable; the host views keep their selectable text. |
| 2 | Open for the Full Keyboard Access pass. Return in the list, the Restore Sample button, the context menu, and the bars' actions still restore. |
| 3 | Rechecked at the default size. The chart key now uses primary text and is no longer flagged for contrast. It is flagged only as partially supporting Dynamic Type, as are the chart's names, counts, "Most", and its section title. Contrast "nearly passed" on the "Archived samples by collection" header, and "nearly passed" or failed on 5 elements the audit couldn't name. The same page has 5 "Text clipped" issues on unnamed elements. At the top of the page, list rows and a Restore button sit beneath the translucent tab bar, which is the likely source of both. On the experiment page, the Open button's contrast still "nearly passed". Same triage as before. |
| 4 | Still open. At the largest size the Open button is hittable, but its lower part sits under the pinned Read the Specification bar, and its title breaks "Super-power" across two lines. The audit flagged contrast on the experiment's payoff sentence and Dynamic Type on the capped Read the Specification button. On the task page it flagged one unnamed element's contrast, and on the receipt the capped Undo's Dynamic Type and one clipped unnamed text. |

**Findings.** These stay open until fixed or closed by the manual pass. Each names the rule it concerns.

| # | Rule | Finding | Where | Found by | Triage |
|---|---|---|---|---|---|
| 1 | 9 | Each Audio Graph data point carries a label that repeats its value. Read from the running Mac app, the points' descriptions are "2 of 4 archived, Pigment swatches, 2 archived samples", and so on: the point's label, its category, then the axis's reading of its value. | `ChartSemantics` points in `Packages/LabFeatures/Sources/AccessSuperpower/`, and `Fixtures/access/archive-chart.json` | accessibility API, running Mac app | For the Access as a Superpower module (LAB-035): the Audio Graph pass records what VoiceOver says for a point. If it repeats the count, drop the point label or make it add only what the value doesn't, such as "of 4". The fixture and its tests change with it. |
| 2 | 1 | On the Mac, the task's status badge has no role: it reads as `AXUnknown` with its label, such as "Task: To Do", like the chart's bars. | `StatusBadge` in `Apps/Shared/Components/` | accessibility API, running Mac app | For the shared components: the Mac VoiceOver pass records what is spoken for it. If VoiceOver says nothing about what kind of element it is, consider giving the badge a static-text role there. |

## Share Ingress review (LAB-007-B)

[LAB-007](../experiments/LAB-007-share-ingress-station.md) stages what is pasted, chosen, or shared into an inbox, where each import waits until the person reviews it, chooses a collection, and presses Add. The review below was made with automated checks, two driven runs, and by reading the code. No manual pass was run: every row in the [experiment flows](#manual-passes) matrix for I1 to I5 is `not-run`.

**Automated results**

| Check | Path | Result |
|---|---|---|
| `ShareIngressAccessibilityTests` (Mac hosted tests, in `script/test.sh`) | hosted test, macOS 27.0 | passed: 4 tests, 5 cases, covering the intake controls with and without the file picker, the rows, an intake's result, and the review screen from New Collection… to Add |
| iPhone journey by accessibility label | simulator, iPhone 17 Pro, iOS 27.0, created for this ticket and deleted afterwards; a UI-test harness in a throwaway copy that is not committed | passed: Import tab, Paste, the pasted row, its review screen, New Collection…, Add to Collection, the receipt; Choose Files… through the document picker; a Photos share into the extension and Done; the shared movie's review screen |
| Xcode's accessibility audit, default text size | same harness | issues recorded as finding 3 |
| Mac Share Inbox by accessibility element | a Debug build at 074eaaa under a separate bundle prefix, driven by process ID | passed: View › Share Inbox, Choose Files…, the open panel, the imports' rows, and a movie's review screen were reached and read |

**Findings.** These stay open until fixed or closed by the manual pass. Each names the rule it concerns.

| # | Rule | Finding | Where | Found by | Triage |
|---|---|---|---|---|---|
| 1 | 2 | On the Mac, Choose Files…, Add to Collection, and Remove from Inbox have no menu command or shortcut. Paste has Edit › Paste (⌘V). | `LabCommands` in `Apps/Mac/LabCommands.swift`; `ShareInboxListColumn` and `InboxEntryDetail` | static review | For the host views' owner: a command for Choose Files… (a File-menu item) and for Add and Remove on the selected import, or the Full Keyboard Access pass decides that the buttons are enough. |
| 2 | 6 | On iPhone, Add to Collection sits in the review form rather than in a pinned bar. At the default size it was on screen without scrolling; at the largest size it will scroll. | `InboxEntryDetail` in `Apps/Shared/ShareInbox/ShareInboxViews.swift` | static review and the simulator harness | Pin Add in a `PinnedActionBar` on iPhone, as a receipt pins Undo. |
| 3 | 6, 8 | At the default text size the audit reported 13 issues on the Import tab, 13 on a text import's review screen, and 10 on a file import's review screen. Dynamic Type was flagged "partially unsupported" on section footers, the share sheet status, and form rows. Contrast "nearly passed" on section headers and footers, and failed on the review screen's footer ("Adding creates one item…"). The Choose Files… label was flagged as clipped, though it read whole in the screenshot. | iPhone Import tab and review screens | simulator audit | Secondary text follows the core audit triage above. Confirm the clipping and the footers in the large-text and Increase Contrast passes. |
