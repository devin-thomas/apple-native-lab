# LAB-019 hostile wire messages

Original, synthetic session envelopes for Local Constellation (LAB-019). Each one is the plaintext
JSON a peer could put inside a sealed frame, and each must be refused by
`SessionEnvelope<Constellation>(json:)` before any rule sees it. The peer IDs, session IDs, and
message IDs are made up; nothing here came from a real device or network.

| File | What it tries |
|---|---|
| `smuggled-grant.json` | A top-level `grant` field beside a valid command |
| `command-line-action.json` | A command whose action is `run` with a command-line argument |
| `path-in-command.json` | A valid action with an extra `path` field |
| `cue-out-of-range.json` | A snapshot at cue 40 of a six-cue sheet |
| `palette-color-value.json` | A snapshot whose palette is a color value instead of a named palette |
| `pointer-out-of-range.json` | A pointer sample outside the unit square |
| `unknown-kind.json` | A message kind the protocol does not define |
| `duplicate-key.json` | A payload with `issuedAt` twice, which a plain decoder would merge |

The show's own fixture, the six-cue sheet, is bundled with the module at
`Packages/LabFeatures/Sources/LocalConstellation/Resources/cue-sheet.json`.
