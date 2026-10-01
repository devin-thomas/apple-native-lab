import LabCatalog
import LabDomain
import RespectfulAttention
import SwiftUI

/// The in-app agenda: previews of when and why, timers while this page is open, and one cancel.
struct AttentionPage: View {
    @State private var model = AttentionModel.shared
    @Environment(LabLibrary.self) private var library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Compare a reminder, a Focus filter, and an alarm. Nothing is scheduled until you add it.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.permissionNote)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("attention-permission")
                if model.gate.mayPrompt {
                    Button("Allow Lab Alerts") { Task { await model.allowSystemAlerts() } }
                        .disabled(model.isWorking)
                        .accessibilityHint("Asks once for alarms and reminders. A denial is not asked again.")
                }
                ForEach(model.offers) { offer in
                    offerRow(offer)
                }
                agenda
                Button("Cancel Lab Alerts", role: .destructive) { Task { await model.cancelAll() } }
                    .disabled(model.isWorking || model.stored.isEmpty)
                    .accessibilityHint("Removes Native Lab's alerts. Other alerts stay.")
                if let lastMessage = model.lastMessage {
                    Text(lastMessage)
                        .font(.callout)
                        .accessibilityIdentifier("attention-result")
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .navigationTitle(RespectfulAttention.title)
        .task {
            model.connect(library)
            await model.refresh()
        }
        .onChange(of: model.filtersToSampleFocus) { Task { await model.refresh() } }
    }

    private func offerRow(_ offer: AttentionOffer) -> some View {
        let preview = model.preview(offer)
        return VStack(alignment: .leading, spacing: 8) {
            Label(preview.channel.title, systemImage: symbol(preview.channel))
                .font(.headline)
            Text(preview.why)
            Text(preview.when)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(alarmNote(offer))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Add to Agenda") { Task { await model.schedule(offer) } }
                .disabled(model.isWorking)
                .accessibilityHint("Schedules this lab alert after you press it. Opening the page does not.")
        }
        .accessibilityElement(children: .contain)
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agenda")
                .font(.headline)
            Toggle("Lab Sample Focus", isOn: $model.filtersToSampleFocus)
                .accessibilityHint("Shows only the sample lab alerts. It does not change a system Focus.")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let rows = LabAgenda.timers(
                    model.stored,
                    scope: model.filtersToSampleFocus ? RespectfulAttention.sampleFocus : nil,
                    at: context.date,
                    deviceZone: .current
                )
                if rows.isEmpty {
                    Text("Nothing is on the agenda yet. Add a sample above. Timers run while this page is open.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(row.why)
                                    Text(row.when).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.remainingLabel)
                                    .accessibilityLabel("\(row.why), \(row.remainingLabel)")
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("attention-agenda")
    }

    private func alarmNote(_ offer: AttentionOffer) -> String {
        switch model.alarmState(for: offer, systemScheduled: false) {
        case .notAnAlarm: "Shown on the agenda. No system alarm."
        case .unavailable: "AlarmKit is off in this build. The agenda timer is the fallback."
        case .needsConsent: "An alarm needs Allow Lab Alerts. The agenda works without it."
        case .denied: "The alarm stays in the app. The system will not be asked again."
        case .inAppOnly: "Allowed. This build records it on the agenda."
        case .scheduled: "Scheduled as a lab alarm."
        }
    }

    private func symbol(_ channel: AttentionChannel) -> String {
        switch channel {
        case .reminder: "checklist"
        case .focusFilter: "moon"
        case .alarm: "alarm"
        }
    }
}

/// The experiment's entry on its catalog page.
struct RespectfulAttentionLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == RespectfulAttention.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .respectfulAttention
            } label: {
                Label("Open \(RespectfulAttention.title)", systemImage: RespectfulAttention.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌥⌘6)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                AttentionPage()
            } label: {
                Label("Open \(RespectfulAttention.title)", systemImage: RespectfulAttention.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the agenda.")
            #endif
        }
    }
}
