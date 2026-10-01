import LabCatalog
import LabDomain
import SwiftUI
import TactileGrammar

/// The three cues, the intensity preference, stop, and the visual pulse. iPhone pushes this from
/// the catalog page. The Mac uses the same controls in its columns.
struct TactileGrammarPage: View {
    @Bindable var model: TactileGrammarModel
    @State private var isConfirmingReset = false

    var body: some View {
        List {
            Section {
                Text(model.summary)
                    .font(.body)
                if let visual = model.visual {
                    CuePulseRow(visual: visual, routeTitle: model.routeTitle, spoken: model.spoken)
                }
            } header: {
                Text("Result")
            } footer: {
                Text("A fixture or an adapter path. It is not a measurement of a physical actuator.")
            }
            Section {
                ForEach(CueKind.allCases, id: \.self) { kind in
                    Button {
                        Task { await model.play(kind) }
                    } label: {
                        Label(kind.title, systemImage: symbol(kind))
                    }
                    .disabled(model.isBusy)
                    .accessibilityHint("Plays the \(kind.title.lowercased()) cue. The words and the pulse show even if haptics do not.")
                }
            } header: {
                Text("Cues")
            }
            Section {
                Picker("Intensity", selection: $model.intensity) {
                    ForEach(IntensityPreference.allCases, id: \.self) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Muted keeps the visual pulse and the spoken words, and starts no haptic or tone.")
                Button("Stop", systemImage: "stop.fill") {
                    Task { await model.stop() }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Stops the cue that is playing.")
            }
            Section {
                Text(model.capabilitySentence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("This device")
            }
            Section {
                Button("Reset Demo", role: .destructive) { isConfirmingReset = true }
                    .accessibilityHint("Clears cue receipts and the intensity preference. Lab collections are not changed.")
            }
        }
        .navigationTitle(TactileGrammarExperiment.title)
        .confirmationDialog(
            "Reset the cue demo?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Demo", role: .destructive) {
                Task { await model.resetDemo() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears this experiment’s cue receipts and sets intensity back to standard. Lab data stays.")
        }
        .task { await model.refreshCapabilities() }
    }

    private func symbol(_ kind: CueKind) -> String {
        switch kind {
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .timing: "metronome"
        }
    }
}

struct CuePulseRow: View {
    let visual: VisualPulse
    let routeTitle: String
    let spoken: String
    @State private var pulseIndex = 0
    @State private var isLit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(visual.word, systemImage: visual.symbol)
                .font(.title2)
                .opacity(isLit ? 1 : 0.45)
                .accessibilityLabel("\(visual.word). \(visual.pulseCount) pulses.")
            Text(spoken)
            if !routeTitle.isEmpty {
                Text(routeTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: visual) {
            pulseIndex = 0
            for step in 0..<visual.pulseCount {
                guard !Task.isCancelled else { return }
                isLit = true
                pulseIndex = step + 1
                try? await Task.sleep(for: .milliseconds(max(40, visual.intervalMilliseconds / 2)))
                guard !Task.isCancelled else { return }
                isLit = false
                if step < visual.pulseCount - 1 {
                    try? await Task.sleep(for: .milliseconds(visual.intervalMilliseconds))
                }
            }
            isLit = true
        }
    }
}

/// Shown only on LAB-030’s catalog page.
struct TactileGrammarLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == TactileGrammarExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .tactileGrammar
            } label: {
                Label("Open \(TactileGrammarExperiment.title)", systemImage: TactileGrammarExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                TactileGrammarPage(model: TactileGrammarModel())
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(TactileGrammarExperiment.title)", systemImage: TactileGrammarExperiment.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            #endif
        }
    }
}
