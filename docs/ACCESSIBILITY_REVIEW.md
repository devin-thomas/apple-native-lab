# Accessibility review

Accessibility is a release gate (R-08 in the [specification](../SPEC.md)). This checklist is that gate: the rules shared views follow, the automated checks, and the manual assistive-technology passes that a person runs on a device. It started at [CORE-010](../tickets/CORE-010.md) and covers the host's core flows. Every qualification ticket adds its experiment's flows to the same matrix.

**An automated result is never a manual pass.** Automated checks read labels, press controls through the accessibility API, and run audits. None of them hears VoiceOver, speaks to Voice Control, or moves through the app the way a person with Full Keyboard Access does. A manual row stays `not-run` until a person performs that pass on the named device, and an automated row never fills it in.

## Shared accessible components

The components live in `Apps/Shared/Components/`. It's one folder compiled into the Mac and iPhone hosts, with no separate target or package. Feature views use them rather than restyling their own.

| Component | Use it for | What it guarantees |
|---|---|---|
| `StatusDescriptor`, `StatusTone` | Any status: lifecycle state, readiness, receipt status | A status is a word and a symbol; the tone only picks a color. It's spoken as "Kind: word", for example "State: Blocked". |
| `StatusBadge`, `StatusLabel` | Showing a status as a capsule or inline | One accessibility element with the spoken label. The word keeps primary text contrast, and Increase Contrast deepens the fill and draws a solid outline. |
| `LabAnnouncement` | A change that lands somewhere other than where the person is, such as a receipt after a confirmation closes | Announces the receipt's summary and says whether it can be undone. A refused change or failure interrupts. The same words are always visible somewhere. Call `LabAnnouncement.outcome(of:in:)?.post()` after an action. |
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
| Action Atlas on iPhone (LAB-001) | A UI-test harness in a throwaway copy, iOS Simulator, at the default and largest accessibility text sizes | The Action Atlas journey works by accessibility label, from the Actions tab to a receipt's pinned Undo. Xcode's accessibility audit results are recorded per screen, and whether each form's action is on screen at the largest size | A physical iPhone, VoiceOver, Voice Control |

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
