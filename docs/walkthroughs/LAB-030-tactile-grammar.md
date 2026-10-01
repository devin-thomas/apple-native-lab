# Tactile Grammar

This qualification covers deterministic fixture plays, a muted Mac adapter call, and a muted iPhone simulator adapter call. It does not measure a physical actuator. LAB-030 remains `implemented`, not `device-verified`.

On Mac, open Tactile Grammar from the sidebar or View › Tactile Grammar (⌥⌘5). On iPhone, open LAB-030 in the catalog and choose Open Tactile Grammar. Choose Muted before playing if you want only the words and visual feedback. Success, Warning, and Timing each produce their own words; the first has two pulses and the others three. “Spoken words” here means text supplied for accessible presentation, not synthesized narration or a verified VoiceOver announcement.

Try each cue, choose Stop, then Reset Demo and confirm. Reset clears this engine's cue receipts and returns the window's intensity preference to Standard. The engine does not hold the collection store, so it cannot delete imported items. Cancel in the reset dialog should leave state alone; that dialog interaction has not been driven in this qualification.

With Standard or Quiet, the router prefers Core Haptics, then a controller that reports haptics, then Watch system feedback, otherwise the visual fallback. Quiet audio is optional. The API capability read is not proof of output. Watch uses success/retry/start system haptics, never the custom cue event list. Apple TV has no Tactile Grammar page.

The fixture replay creates a fresh engine for Standard and Muted, plays all three cues, retries each request, and resets its log. The boundary tests hold a haptic until each cue's exact minimum gap (400/600/800 ms) and hold the sixth haptic within the 10-second fatigue window. At 10 seconds the oldest play leaves that window. These are injected-clock and stand-in actuator results, not measured hardware timings. Denied actors, invalid IDs, changed payloads under an old request ID, cancellation by Stop, and reset isolation run in the same package suite. There is no entity revision on a cue; generation changes invalidate an in-flight play instead.

The publication material is the lab's original pattern and generated-tone source plus test code. No screenshots, recordings, user files, accounts, or audio exports were collected. Input hashes and exact runs are in [evidence](../../evidence/LAB-030/) and [the ticket](../../tickets/LAB-030-B.md).

The remaining live qualification needs the owner: compare all three cues on a capable iPhone, separately on a supported controller, and separately on Watch, record hardware capability and actual output, then repeat muted, Stop, and fatigue cases. Manual VoiceOver, Voice Control, keyboard access, large text, and reduced-motion checks remain not-run.

Source review found limits to revisit before release: the pulse does not inspect Reduce Motion; identical consecutive visual values do not restart `.task(id: visual)`; result text is not posted as an accessibility announcement; the Mac has no individual cue menu commands; the Watch page has no reset control or pulse row; Watch Stop cannot interrupt a system haptic; Reset Demo invalidates pending receipts but does not call the actuator stop methods; and the controller adapter turns every event into a transient, including Warning's continuous event. Concurrent in-flight request admission and limiter reservations have not been qualified. A returned receipt cannot prove a person felt, heard, or saw the cue.

The API directions come from Apple's [Core Haptics](https://developer.apple.com/documentation/corehaptics) and [Game Controller](https://developer.apple.com/documentation/gamecontroller) references; installed SDK declarations and compilations are recorded in [the verification ledger](../VERIFICATION_BOUNDARIES.md). Documentation is not device evidence.
