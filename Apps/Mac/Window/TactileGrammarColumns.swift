import SwiftUI
import TactileGrammar

/// The Mac window for Tactile Grammar. The list plays a cue; the detail shows the pulse, stop,
/// and intensity. Both use the window’s model, which calls the same engine as the App Intent.
struct TactileGrammarListColumn: View {
    @Bindable var model: TactileGrammarModel

    var body: some View {
        List {
            Section {
                Text("Three cues. Each one has words and a pulse, whether or not this Mac has an actuator.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(CueKind.allCases, id: \.self) { kind in
                    Button {
                        Task { await model.play(kind) }
                    } label: {
                        Label(kind.title, systemImage: symbol(kind))
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        .navigationTitle(TactileGrammarExperiment.title)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    private func symbol(_ kind: CueKind) -> String {
        switch kind {
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .timing: "metronome"
        }
    }
}

struct TactileGrammarDetailColumn: View {
    @Bindable var model: TactileGrammarModel

    var body: some View {
        TactileGrammarPage(model: model)
    }
}
