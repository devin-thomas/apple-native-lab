# Speech Timeline fixtures (LAB-013)

Original, synthetic text written for this project and distributed under its MIT License. Nothing here came from a person, a recording, or an import. Both hosts bundle the script and the sample captions as resources (`project.yml`), and `SpeechFixture` in `Packages/LabFeatures/Sources/SpeechTimeline` names them.

| File | SHA-256 | What it is for |
|---|---|---|
| `speech-sample-script.txt` | `c03523b47c45768c621061b257719e1b97e2a311a44dfc00f6ff69265e52cdf0` | Four short sentences in English (United States), one per line. The app speaks them into the sample clip. |
| `speech-sample-captions.vtt` | `1615650c15788f53d1d009d6f8a83ad354a4d3b5b0ba3874d8402ebe5e19ee4b` | WebVTT captions for the script, timed by hand at a steady pace: the fallback's import. Cue 3 wraps its text in a `<v Narrator>` voice tag, which the reader removes, so a caption never becomes a speaker claim. |
| `speech-captions-overlapping.vtt` | `f6233e796c341d04310a7400e28ac29df6cace8f0ff1902e13752c8f6fb860b6` | Two cues whose times overlap. The whole file is refused. |
| `speech-captions-malformed.vtt` | `8dfc449148580259a7fc217d9b6ecfc77b9fa22c0244c7a59db7f344cd5737f7` | A cue that ends before it starts, then a timestamp that is not WebVTT. The whole file is refused. |

## No committed audio

There is no audio file here, on purpose. The sample clip is spoken from `speech-sample-script.txt` by the device's own speech synthesizer (`AVSpeechSynthesizer.write`) into the experiment's folder in the app's container, the first time a person asks for it, and the app labels it as synthesized. The system voices are licensed for use on the device, not for redistributing their output, so no synthesized recording is committed. Reset Demo deletes the clip with the rest of the experiment's folder.

No fixture was recorded from a microphone. The caption times are approximate: the synthesized clip's own times depend on the voice a device has, so the captions and the clip are not expected to line up exactly.

`FixtureAndRouteTests.theFixturesAreTheFilesTheREADMENames` pins every hash above and fails if any other file appears in this folder. Change a fixture only together with this table and the evidence that cites it.
