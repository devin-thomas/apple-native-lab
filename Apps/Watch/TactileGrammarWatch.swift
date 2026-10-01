import SwiftUI
import TactileGrammar

/// The Watch surface. It plays the same three cues through one system haptic each, never a
/// custom waveform, and it still shows the words when haptics are muted.
struct TactileGrammarWatchPage: View {
    @State private var model = TactileGrammarModel()

    var body: some View {
        List {
            Section {
                Text(model.summary)
                    .font(.caption)
            }
            ForEach(CueKind.allCases, id: \.self) { kind in
                Button(kind.title) {
                    Task { await model.play(kind) }
                }
                .disabled(model.isBusy)
            }
            Section {
                Picker("Intensity", selection: $model.intensity) {
                    ForEach(IntensityPreference.allCases, id: \.self) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                Button("Stop") {
                    Task { await model.stop() }
                }
            }
        }
        .navigationTitle("Cues")
    }
}
