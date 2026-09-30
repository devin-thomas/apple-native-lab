# Access as a Superpower: the manual passes

This is the script for the passes a person runs on [Access as a Superpower](../../experiments/LAB-035-access-as-a-superpower.md) (LAB-035): VoiceOver, Audio Graph, Voice Control, and Full Keyboard Access, on the Mac and on a physical iPhone. It covers flows S1 to S7 in the [accessibility review](../ACCESSIBILITY_REVIEW.md#manual-passes). Each step says what to do, what you should hear or see, and what to write down.

**None of these passes has been run.** Every S1 to S7 cell in the review stays `not-run` until a person does the pass on the named device. The automated checks read the same structure through the accessibility API, and they're listed in the [walkthrough](LAB-035-access-as-a-superpower.md#how-we-checked-it). They never fill in a manual row.

## Before you start

- **The build.** On the Mac, run `script/build_and_run.sh` from the revision you're testing. On iPhone, the integrator installs the build with `script/install_phone.sh` and tells you the provisioning profile's expiry date. On either device, the Readiness screen shows the build's source revision. Write it on your sheet.
- **The Mac passes change the whole Mac.** VoiceOver, Voice Control, and Full Keyboard Access act on every app, so run them when nothing else is using the Mac. Turn each one off again when its pass ends.
- **Audio Graph plays tones.** Use headphones.
- **Start from the same state.** Open the experiment. If its status isn't "Task: Nothing Archived", choose Reset Practice first. Practice data changes only the lab's demo samples, never anything of your own.
- **Use your own words for what you hear.** Write down what VoiceOver actually said, as closely as you can, not what this script expects. If you aren't sure what you heard, repeat the step. If you still aren't sure, mark that check `not-run` and say why.

### The record sheet

Copy this once per pass and device.

| Field | Write |
|---|---|
| Pass | VoiceOver, Voice Control, or Full Keyboard Access |
| Device | Mac or iPhone, with its model name, such as "iPhone 16 Pro". No serial number. |
| OS | The version and build, such as "iOS 27.0 (24A5430a)" |
| App | The revision the integrator gave you, or the one on the Mac build |
| Settings | Anything you changed from the default, such as speaking rate or verbosity |
| Date and time | When you started |
| Each step | The flow ID (S1 to S7), `passed`, `failed`, `blocked`, or `not-run`, and what you heard or saw |

- **passed**: what the step says you should hear or see happened.
- **failed**: it didn't. Write what happened instead.
- **blocked**: you couldn't get to the step. Write what stopped you.
- **not-run**: you skipped it or couldn't tell.

## Pass 1: VoiceOver on the Mac

Turn VoiceOver on with ⌘F5. In this script, VO means Control-Option.

1. **S1, open the experiment.** Press ⌘5. Or move to the sidebar and choose Access as a Superpower with VO-Space.
   - The list reads "Archived samples, 0 samples".
   - Moving through the list, you hear the question "Which demo collection has the most archived samples?" as a heading, then "Restore one sample from that collection.", then "Task: Nothing Archived", then "12 demo samples: 12 not archived."
2. **S2, set up practice.** Move to the detail column's Practice data section and press VO-Space on Set Up Practice.
   - You hear "Archived 6 practice samples. Each has its own receipt."
   - The status reads "Task: To Do".
3. **S4, finish with VoiceOver.** Move to the chart, "Archived samples by collection", and interact with it (VO-Shift-Down). Move through the bars with VO-Right.
   - The bars read "Pigment swatches, 2 of 4 samples archived", then "Mineral specimens, 3 of 4 samples archived, the most", then "Paper stock, 1 of 4 samples archived". A bar has no role of its own, as a Swift Charts bar doesn't. Write down whatever VoiceOver says for its type.
   - On Mineral specimens, open the actions menu with VO-Command-Space. It lists Restore Banded agate slice, Restore Obsidian flake, and Restore Quartz point, in that order.
   - Choose Restore Quartz point. You hear one announcement: "Restored item “Quartz point”. Undo is available. Task done: Mineral specimens had the most archived samples (3)." Write down all of it, or say where it stopped.
   - The receipt opens in the inspector. Press ⌥⌘L if it isn't there, then find the Undo button and press it with VO-Space. The status reads "Task: To Do" again.
4. **The rotor.** Stop interacting with the chart (VO-Shift-Up), move into the list of archived samples, and open the rotor with VO-U. Move with Left and Right Arrow until you reach "Archived Samples".
   - Its entries read a title, then a collection, such as "Quartz point, Mineral specimens".
   - Choosing one moves to that sample. Record whether it does.
5. **S6, finish by ear.** Move to the chart again. VoiceOver should say that the chart has an Audio Graph and how to open it. If it doesn't, look in the actions menu (VO-Command-Space), then in VoiceOver Help (VO-H). Write down the exact command that worked, and whether it was offered on the chart or on each bar.
   - Describe the chart. It reads the title "Archived samples by collection", the summary starting "Mineral specimens has the most archived samples: 3 of 4.", a Collection axis, and an Archived samples axis from 0 to 4.
   - Play it. There are three tones, in the order Pigment swatches, Mineral specimens, Paper stock. The second tone, Mineral specimens, is the highest. Write down which one you heard as highest before you check.
   - Leave the Audio Graph, then use that bar's Restore Obsidian flake action. You hear the same kind of announcement, ending "Task done". Undo it from the inspector.
6. **S7, finish without the chart.** Skip the chart. Read the summary, then the list.
   - The summary gives every count: "…By collection: Pigment swatches 2 of 4, Mineral specimens 3 of 4, Paper stock 1 of 4."
   - Each heading reads like its bar, such as "Mineral specimens, 3 of 4 samples archived, the most".
   - Each sample reads title, collection, "Archived", then its note, such as "Quartz point, Mineral specimens, Archived, Clear and six-sided, about the length of a thumb."
   - On Tracing vellum, open the actions menu and choose Restore Tracing vellum. This is a miss, so you hear "…Task not done: Paper stock had 1 archived sample, and Mineral specimens had the most (3)."
   - Then select Quartz point in the list and press Return. The task is done.
7. **S2 again, reset.** Press Reset Practice. You hear "Restored 4 practice samples. Each has its own receipt." or the number still archived, and the status reads "Task: Nothing Archived".
8. **S3, by sight.** With VoiceOver off, set up practice again, find the longest bar, click a sample in that collection in the list, and click Restore Sample. "Task: Done" and the result sentence are shown, and the receipt opens in the inspector. Reset Practice.

Turn VoiceOver off with ⌘F5.

## Pass 2: VoiceOver on iPhone

Turn VoiceOver on in Settings › Accessibility › VoiceOver, or with the Accessibility Shortcut. Swipe right to move to the next item, double-tap to activate, swipe up or down for actions, and turn two fingers on the screen to change the rotor.

1. **S1, open the experiment.** In the Catalog tab, move to "Access as a Superpower, State: Implemented, LAB-035, M1, Accessibility" and double-tap. On its page, find "Open Access as a Superpower" and double-tap.
   - The page reads the question as a heading, then "Restore one sample from that collection.", then "Task: Nothing Archived", then "12 demo samples: 12 not archived."
2. **S2, set up practice.** Swipe to Set Up Practice, in the Practice data section, and double-tap.
   - You hear "Archived 6 practice samples. Each has its own receipt." The status reads "Task: To Do".
3. **S4, finish with VoiceOver.** Swipe to the chart and through its bars.
   - The bars read "Pigment swatches, 2 of 4 samples archived", "Mineral specimens, 3 of 4 samples archived, the most", and "Paper stock, 1 of 4 samples archived".
   - On Mineral specimens, swipe up or down. The actions are Restore Banded agate slice, Restore Obsidian flake, and Restore Quartz point, in that order. Record the order you hear.
   - On Restore Quartz point, double-tap. You hear "Restored item “Quartz point”. Undo is available. Task done: Mineral specimens had the most archived samples (3)."
   - Swipe to the Result section and double-tap its receipt. The receipt reads its status, summary, undo offer, then details. Double-tap the Undo button at the bottom. Go back; the status reads "Task: To Do".
4. **The rotor.** Turn the rotor to "Archived Samples", then swipe down. Each entry reads a title and a collection, and focus moves to that sample. Record whether it does.
5. **S6, finish by ear.** Move to the chart and turn the rotor to "Audio Graph". Swipe down through its options. Write down each one's exact name.
   - Describe Chart reads the title, the summary, and both axes.
   - Play Audio Graph plays three tones. The second, Mineral specimens, is the highest. Write down which one you heard as highest before you check.
   - Chart Details, if offered, lists each value. Record what it shows.
   - Then use Mineral specimens' Restore Obsidian flake action. Undo it from the receipt.
6. **S7, finish without the chart.** Swipe past the chart to the lists.
   - Each collection heading reads like its bar.
   - Each sample reads title, collection, "Archived", then its note, and is followed by its own button, such as "Restore Quartz point, button".
   - Double-tap Restore Tracing vellum. It's a miss: "…Task not done: Paper stock had 1 archived sample, and Mineral specimens had the most (3)."
   - Double-tap Restore Quartz point. The task is done.
7. **S2 again, reset.** Double-tap Reset Practice. The status reads "Task: Nothing Archived".
8. **S3, by sight.** With VoiceOver off, set up practice again, find the longest bar, and tap Restore beside one of its samples. "Task: Done" and the result sentence are shown. Reset Practice.

## Pass 3: Voice Control

Turn Voice Control on in System Settings › Accessibility › Voice Control on the Mac, or Settings › Accessibility › Voice Control on iPhone. On the Mac you say "Click"; on iPhone you say "Tap".

1. **S1.** Say "Show names". Every control on the experiment's page has a name. Record any that doesn't. On iPhone, say "Tap Open Access as a Superpower". On the Mac, say "Click Access as a Superpower" in the sidebar.
2. **S2.** Say "Click Set Up Practice" on the Mac or "Tap Set Up Practice" on iPhone. The status reads "Task: To Do".
3. **S3 and S7, the visible way.**
   - iPhone: say "Tap Restore Quartz point". The task is done. Then say "Tap Restore". Because every sample has a Restore button, Voice Control should show numbers to choose from. Record what it does.
   - Mac: say "Show numbers", then the number on the Quartz point row to select it, then "Click Restore Sample". The button also answers to "Restore Quartz point" and "Restore". The task is done.
4. **The receipt.** iPhone: open the receipt and say "Tap Undo". Mac: say "Click Undo". Record whether the shorter name works on the Undo button.
5. **Reset.** Say "Tap Reset Practice" or "Click Reset Practice".

The chart's Restore actions are for VoiceOver. Voice Control reaches the same restore through the list and its buttons, so S4 and S6 are `not-run` for Voice Control unless you find a spoken path to them. If you do, write it down.

## Pass 4: Full Keyboard Access

### Mac

First, with Full Keyboard Access off, check the keyboard path that needs no keyboard navigation (S5):

1. Set up practice with the pointer. Press ⌘5, then Tab once. The list of archived samples has focus.
2. Press the Down Arrow until Quartz point is selected, then Return. "Task: Done" and the result sentence are shown.
3. Press ⌥⌘L. The receipt is shown in the inspector. Press ⌥⌘Z. The undo runs, and the status reads "Task: To Do".

Then turn on Full Keyboard Access in System Settings › Accessibility › Keyboard, and repeat:

4. Tab and Shift-Tab reach the list, the selected sample's Restore Sample button, Set Up Practice, Reset Practice, and the inspector's Undo. Space presses the focused button. Record anything you can't reach, and the order you reach them in.
5. Return in the list still restores the selected sample.
6. Record whether you'd want a Lab menu command for Restore Sample. This is finding 2 in the accessibility review.

### iPhone

This needs a hardware keyboard paired with the iPhone. Without one, the pass is `blocked`.

1. Turn on Settings › Accessibility › Keyboards › Full Keyboard Access.
2. Tab moves between items, and Space activates. Open the experiment, set up practice, move to Restore Quartz point, and press Space. The task is done.
3. Open the receipt and activate Undo. Then Reset Practice.

## Display settings

These passes need no assistive technology, just a setting. They're quick, and they check the first acceptance criterion, that no information is carried by color alone.

- **Grayscale.** Turn on Color Filters › Grayscale (Settings › Accessibility › Display & Text Size on iPhone; System Settings › Accessibility › Display on the Mac). Set up practice. You can still tell archived squares, which are filled with a solid edge, from active ones, which are dashed outlines. The counts, the star, and the word "Most" still give the answer.
- **Differentiate Without Color, Increase Contrast, Reduce Transparency, Reduce Motion.** Turn each on and repeat S3. Record anything that stops working or becomes hard to read.
- **Largest text (iPhone).** At the largest accessibility size, each bar puts its count under its name, the Open button is on screen without scrolling, and every Restore button can be reached.

## Recording the result

When a pass is done, give the sheet to the integrator. The integrator:

1. Updates that pass's row for S1 to S7 in the [accessibility review](../ACCESSIBILITY_REVIEW.md#manual-passes), with the result, the path `physical`, the device class, and the OS.
2. Writes a physical evidence record for the pass, under `evidence/LAB-035/`, with `DeviceRunEvidence` in `Packages/LabDemo`. Its facts file lives outside the repository and looks like this:

   ```json
   {
     "name": "access-superpower-iphone-voiceover",
     "subject": "LAB-035",
     "check": "VoiceOver pass over Access as a Superpower (S1 to S7) on a physical iPhone, run by a person",
     "observedAt": "<when the pass ended, ISO 8601 UTC>",
     "platform": "iOS",
     "deviceClass": "<model identifier and name>",
     "osVersion": "<version and build>",
     "profileExpiry": "<the installed build's profile expiry, iPhone only>",
     "buildInfoPlist": "<path to the Info.plist of the build that was installed>",
     "inputs": ["seed:app-bundle@sha256:<hash of the bundled seed>"],
     "steps": ["<each step from this script that was run>"],
     "result": "<passed, failed, blocked, or not-run: the worst step result>",
     "observed": "<what was heard and seen, from the sheet>",
     "limitations": ["<steps not run, and why>"],
     "overrideReason": "<why this record may leave the device: what it holds and what it doesn't>"
   }
   ```

   Run `LAB_DEVICE_RUN_FACTS=<facts> LAB_DEMO_EVIDENCE_DIR=<folder> swift test --package-path Packages/LabDemo --filter DeviceRunEvidence`, check the export's review, and copy the record into `evidence/LAB-035/`.
3. Opens a finding in the review for each failed step, with the file, the control, what failed, and the matrix item.

A pass with a failed step is still recorded, with its failure. A `blocked` or `not-run` step is never written up as passed, and nothing goes into a record that the person didn't hear or see.
