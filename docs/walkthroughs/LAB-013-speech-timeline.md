# Speech Timeline: a walkthrough

Speech Timeline ([LAB-013](../../experiments/LAB-013-speech-timeline.md)) turns speech into a transcript you can scrub. Each line of text keeps the moment of the audio it came from, so the text and the sound move together. While the recognizer is still listening, its guess shows in italics after the finished lines and is replaced as it improves; it is never saved or exported. When you fix a word, the line keeps its time and remembers what the recognizer said.

## What's real and what's simulated

Read this first, because it decides what the rest of the page can claim.

**Transcription has run for real only on a Mac, on speech the Mac's own voice spoke. The iPhone simulator ran the fallback. No physical iPhone or iPad took part, and no microphone was opened.**

- **On a real Mac, the on-device transcriber.** Apple's on-device speech recognizer transcribed a short clip on the development Mac (Apple M5 Max, macOS 27.0), both in a test process and inside the Mac app. The clip is the experiment's four-line script, spoken by the Mac's built-in voice at test time. It is not a person speaking, and the recognizer's accuracy on real voices and rooms is not claimed. A test drove the app's session, not a person in the window.
- **On iPhone, only in the simulator, and only the fallback.** In the iOS 27.0 simulator the transcriber reports itself unavailable, so the app says so and the caption fallback completes the task. No physical iPhone or iPad has run Speech Timeline.
- **Recording is closed in this build, on purpose.** Record needs two things the project owner has not decided to add: a sentence explaining microphone use (`NSMicrophoneUsageDescription`) and, on the Mac, the audio-input entitlement. Until then Record says why it is closed and never asks for the microphone. So recording, and what happens when headphones are unplugged mid-recording, have only been simulated: the tests feed the app the events a recording would send.
- **So the experiment is `implemented`, not `device-verified`.** The Mac run supports the on-device file path on that Mac only.
- **The replays are simulations of the logic, not of the system.** They run the same timeline, export, and save code with a scripted recognizer and scripted recording events, inside tests on the Mac. They prove what the code does with what the recognizer sends. They don't prove what a real recognizer or microphone sends.

## Try it yourself

On a Mac, run `script/build_and_run.sh`, then choose Speech Timeline in the sidebar. On iPhone, open the Catalog tab, choose Speech Timeline, and press Open Speech Timeline. You don't need an account or a network connection.

1. **Read the language line.** It says whether this device can transcribe the chosen language: the model is installed, it can be downloaded, the language isn't supported here, or the transcriber isn't available at all. An unsupported language is named, not hidden.
2. **Speak and Transcribe the Sample.** The device's own voice speaks the four-line script into a clip, and the on-device transcriber reads it. Watch the italic guess grow, then turn into finished lines. Each line says "On-device transcription".


3. **Correct a line.** Choose Correct… on a line (or its Correct action). Type the fix and save. The line's time doesn't change, and it now says "Corrected from" with the recognizer's words. Revert to Recognized Text puts it back.


4. **Scrub.** Drag the playhead or choose a line; the line playing is shown in bold and named above the list. Play from Here plays the clip from that line.
5. **Save and export.** Create a collection of your own, then Save to Collection: one item with the text, and every line's time and original words kept with it, as a change with a receipt. Export Captions… writes a WebVTT file; Export Timeline… writes the times, both texts, and the audio's SHA-256, never its file name.
6. **When the transcriber isn't there, use the fallback.** Import Sample Captions (or your own WebVTT file), or Annotate by Hand. Every line is labeled as an imported caption or a hand annotation, never as recognition, and corrections, scrubbing, saving, and exporting work the same way.


7. **Record (closed in this build).** Record says why it is closed and points to the fallback. When recording is opened, a change of audio device pauses the recording instead of ending it silently: the finished lines stay, the unfinished guess is removed and counted, the reason is shown and spoken, and Resume Recording continues the same timeline.


8. **Reset Speech Timeline.** It removes the sample clip, any copy of audio you imported, and the timeline on screen. Transcripts you saved are yours and stay, and so does everything else in your collections. The lab's Reset Demo doesn't touch them either.

## How we checked it

| Check | What ran | Result and limit |
|---|---|---|
| Domain qualification | `SpeechTimelineTests`, 62 tests; live probe opted out | Passed: clean-state replay twice; route-change/resume simulations; 300 generated recognizer streams; corrections and exports; denial, cancellation, stale/duplicate requests, and reset boundaries |
| Mac app | 17 targeted hosted tests on macOS 27.0 | Passed: the real on-device transcriber read the synthesized clip into 4 segments; corrections kept every time; both exports and an app-UI save; scripted route changes and the fallback; accessibility-tree presses. No microphone or manual assistive-technology pass |
| iPhone simulator | 8 targeted app test runs, 3 tests each, iOS 27.0 | Passed: 24 executions, including the real synthesizer, stated unavailable recognition route, caption fallback and saved transcript surviving reset; no reported app crash |
| Launch negative control | Real Focus context with the old predicate | Expected failure: the context-construction regression crashes the app. With `SELF IN`, the same context builds and evaluates correctly. This was launch metadata, not speech teardown |
| Live recording | Real permission stager inside the Mac app | Blocked on the owner's purpose-string and entitlement decision; zero captures started |

The records, including the deliberate failing control, are in [`evidence/LAB-013/`](../../evidence/LAB-013/). Each one names the source revision, the toolchain, the hash of every input, where it ran, and what it doesn't cover. [BUILD_STATUS](../BUILD_STATUS.md) lists every run with its command.

## Replay it

The script and captions are in [`Fixtures/speech/`](../../Fixtures/speech/README.md). They are original text; no audio is committed.

```sh
swift test --package-path Packages/LabFeatures --filter SpeechTimelineTests
```

That runs the replay of the whole interaction from a clean store, twice, with the route-change, provisional-text, correction, and boundary tests. To transcribe for real on a Mac with the English (US) model installed, add `LAB_LIVE_SPEECH=1` and follow the comment on `LiveSpeechEvidenceTests`. To run the interaction inside the Mac app and keep its records, follow the comment on `SpeechTimelineHostEvidenceTests` in `Tests/LabMacTests/SpeechTimelineHostEvidenceTests.swift`. The targeted phone repeat is `script/qualify_speech_timeline_phone.sh`, run on the build host through `labr`; it creates and deletes only its own simulator. It checks actual test counts as well as the command exit status.

## Not checked yet

- Speech Timeline on a physical iPhone or iPad, including whether their transcriber is available.
- Recording from a microphone, on any device, and a real change of audio device, a call, or another interruption during one. Recording waits on the owner's decision.
- A model download, on any device.
- Real voices, rooms, and microphones, and languages other than English (US). Accuracy is not claimed.
- Importing audio a person chose through the open panel or Files; the tests copied a file in directly.
- VoiceOver, Voice Control, and Full Keyboard Access, by a person, on any device.
- A build with an older (26) SDK.
