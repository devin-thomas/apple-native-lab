# Commercial Frontier Desk

Open LAB-048 from the catalog, then Open Commercial Frontier Desk. All three probes are
simulations. Join and leave the sample PTT channel. Connect the CarPlay audio list preview,
then disconnect. Authorize yourself in the Screen Time simulation, restrict the sample, then
Revoke and clear restrictions. The saved status and receipt confirm each local transition.
Reset probe resets only that section. A new desk reads the same saved local state.

No audio, APNs, CarPlay scene, system prompt, shield or monitoring session runs. The separate
SDK probe targets are compile-only and not linked by any host. See the
[decision](../../docs/adr/ADR-LAB-048.md) and [verification ledger](../../docs/VERIFICATION_BOUNDARIES.md).

Live self-escape requirement: clear all owned ManagedSettings stores and stop owned DeviceActivity
monitoring before revoking individual authorization. Never shield the app or Settings. Settings
provides an independent authorization-revocation path: see Apple’s
[Screen Time individual authorization walkthrough](https://developer.apple.com/videos/play/wwdc2022/110336/). This live cleanup is not implemented or
verified here because no system restrictions are installed.

Manual VoiceOver, Voice Control, keyboard traversal, large text and focus review remain not-run.
The fallback uses native Form, Button, NavigationLink and textual state; no color-only status,
automatic permission request, or custom motion is used. No screenshot or recording was captured.
