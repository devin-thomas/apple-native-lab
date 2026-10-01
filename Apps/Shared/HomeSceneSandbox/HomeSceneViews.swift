import HomeSceneSandbox
import LabCatalog
import SwiftUI

/// The sandbox form shared by Mac columns and the iPhone page.
struct HomeSceneForm: View {
    @Bindable var session: HomeSceneSession
    var onReceipt: (ReceiptRecord) -> Void = { _ in }
    @Environment(LabLibrary.self) private var library

    var body: some View {
        List {
            routeSection
            homeSection
            selectionSection
                .disabled(session.isRunning)
            previewSection
            commitSection
        }
        .navigationTitle(HomeSceneExperiment.title)
        .task { await session.refresh() }
    }

    private var routeSection: some View {
        Section {
            Text(session.simulationLabel)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Route") {
                Text(session.route == .live ? "Live" : "Fictional")
            }
            Text(session.platformGate)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Request live home access") {
                Task { await session.requestLiveAccess() }
            }
            .disabled(session.isRunning)
            Button("Use fictional home") {
                Task { await session.useSimulatedHome() }
            }
            .disabled(session.isRunning || session.route == .simulated)
        } header: {
            Text("Home access")
        } footer: {
            Text("Locks, doors, alarms, and heating stay excluded. Live HomeKit needs a separate opt-in build.")
        }
    }

    private var homeSection: some View {
        Section {
            if let home = session.home {
                LabeledContent("Home") { Text(home.name) }
                ForEach(home.accessories, id: \.id) { accessory in
                    Text(accessory.statusLine)
                        .font(.callout)
                        .foregroundStyle(accessory.isExcludedByDefault ? .secondary : .primary)
                }
            } else {
                Text("No home loaded yet.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Accessories")
        }
    }

    private var selectionSection: some View {
        Section {
            Toggle("Living room lamp on", isOn: Binding(
                get: { session.livingOn },
                set: { session.setLiving(on: $0) }
            ))
            Slider(
                value: Binding(
                    get: { Double(session.livingBrightness) },
                    set: { session.setLivingBrightness($0) }
                ),
                in: 0...100,
                step: 1
            ) {
                Text("Living room brightness")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("100")
            }
            .accessibilityValue("\(session.livingBrightness) percent")

            Toggle("Include hallway lamp", isOn: Binding(
                get: { session.includeHallway },
                set: { session.setIncludeHallway($0) }
            ))
            .accessibilityHint("The hallway lamp starts disconnected in the fictional home.")
            if session.includeHallway {
                Toggle("Hallway lamp on", isOn: Binding(
                    get: { session.hallwayOn },
                    set: { session.setHallway(on: $0) }
                ))
                Slider(
                    value: Binding(
                        get: { Double(session.hallwayBrightness) },
                        set: { session.setHallwayBrightness($0) }
                    ),
                    in: 0...100,
                    step: 1
                ) {
                    Text("Hallway brightness")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
                .accessibilityValue("\(session.hallwayBrightness) percent")
            }
        } header: {
            Text("Selected light changes")
        }
    }

    private var previewSection: some View {
        Section {
            if let proposal = session.proposal {
                Text(proposal.summary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(proposal.selected, id: \.accessory.id) { action in
                    Text(action.diffLine)
                        .font(.callout)
                }
                ForEach(proposal.excluded, id: \.accessory.id) { excluded in
                    Text("Excluded: \(excluded.accessory.name) — \(excluded.reason)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Choose light changes to preview.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Preview")
        }
    }

    private var commitSection: some View {
        Section {
            Button("Commit selected lights") {
                Task {
                    if let record = await session.commit(in: library) { onReceipt(record) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isRunning || library.phase != .ready || session.proposal?.isEmpty != false)
            Button("Reset Demo") {
                Task {
                    if let record = await session.reset(in: library) { onReceipt(record) }
                }
            }
            .disabled(session.isRunning)
            if let message = session.message {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let report = session.report {
                Text(report.sceneSucceeded ? "Scene succeeded." : "Scene did not succeed.")
                    .font(.headline)
                ForEach(Array(report.outcomes.enumerated()), id: \.offset) { _, outcome in
                    Text(outcome.line)
                        .font(.callout)
                }
            }
            if let receipt = session.receipt {
                Text(receipt.receipt.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Receipt: \(receipt.receipt.summary)")
            }
        } header: {
            Text("Commit")
        } footer: {
            Text("A disconnected lamp fails its own outcome and keeps the whole scene from succeeding. The run is recorded through the operation service.")
        }
    }
}

/// The experiment on iPhone and iPad, pushed from its catalog page.
struct HomeSceneScreen: View {
    @State private var session = HomeSceneSession()

    var body: some View {
        HomeSceneForm(session: session)
    }
}

/// The catalog page's way in. Shown only on LAB-037.
struct HomeSceneLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == HomeSceneExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .homeSceneSandbox
            } label: {
                Label("Open \(HomeSceneExperiment.title)", systemImage: HomeSceneExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                HomeSceneScreen()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(HomeSceneExperiment.title)", systemImage: HomeSceneExperiment.symbol)
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
