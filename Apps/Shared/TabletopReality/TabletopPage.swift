import LabCatalog
import LabDomain
import LabSupport
import SwiftUI
import TabletopReality

/// Tabletop Reality on one page (iPhone and iPad): the virtual table, the tracking state, the
/// route and its Start AR Camera action where this device offers one, placing, the selected
/// object's controls, the object list, and the table's actions.
///
/// The Mac shows the same parts in its window columns (`Apps/Mac/Window/TabletopColumns.swift`).
struct TabletopPage: View {
    @Environment(LabLibrary.self) private var library
    @State private var session: TabletopSession
    @State private var isLive = false
    @State private var resumeFromMap = false
    @State private var liveRefusal: String?

    init(session: TabletopSession = TabletopSession()) {
        _session = State(initialValue: session)
    }

    var body: some View {
        List {
            Section {
                VirtualTabletopScene(session: session)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Drag to orbit and pinch to zoom. Tap the table to place the chosen object; tap an object to select it.")
            }
            Section("Tracking") {
                TrackingStatusSection(session: session)
            }
            Section("Route") {
                RouteSection(session: session, startLive: session.route?.offersLiveStart == true ? { startLive(resuming: false) } : nil)
                #if os(iOS)
                if session.route?.offersLiveStart == true, WorldMapVault().exists {
                    Button("Resume Saved Table", systemImage: "map") { startLive(resuming: true) }
                    Button("Forget Saved Map", systemImage: "trash", role: .destructive) { WorldMapVault().forget() }
                }
                #endif
                if let liveRefusal {
                    Text(liveRefusal).font(.callout).foregroundStyle(.orange)
                }
            }
            Section("Place") {
                PlacementControls(session: session)
            }
            Section("Selected object") {
                SelectionControls(session: session)
            }
            Section {
                ForEach(session.entries) { entry in
                    ObjectListRow(entry: entry, session: session)
                }
            } header: {
                Text("Objects on the table")
            } footer: {
                Text("Every object is listed here with its place and heading. VoiceOver actions on each row move, turn, and remove it.")
            }
            Section("Table") {
                TableActions(session: session)
            }
            if session.message != nil || session.lastRecord != nil || session.phase != .ready {
                Section("Result") {
                    TabletopResult(session: session)
                }
            }
        }
        .navigationTitle(TabletopExperiment.title)
        .task { await session.start(in: library) }
        // Reset Demo, an undo from the inspector, or another window can change the table.
        .onChange(of: library.latestReceipt?.id) { Task { await session.refresh(in: library) } }
        .onDisappear {
            session.stopReplay()
            session.cancelList()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isLive) {
            LiveTabletopScreen(session: session, library: library, resumeFromMap: resumeFromMap)
        }
        #endif
    }

    /// The explicit feature action: only here does the lab ask for the camera, and only after the
    /// world-tracking probe offered the live route.
    private func startLive(resuming: Bool) {
        Task {
            let outcome = await PermissionStager.live().request(for: TabletopRoute.startAction)
            switch outcome {
            case .granted, .notRequired, .systemAsksOnUse:
                liveRefusal = nil
                resumeFromMap = resuming
                isLive = true
            case .fallback(_, let reason):
                liveRefusal = Self.describe(reason)
            }
        }
    }

    static func describe(_ reason: FallbackReason) -> String {
        let why = switch reason {
        case .denied: "Camera access was declined. The lab does not ask again; you can allow it in Settings."
        case .restricted: "Camera access is restricted on this device."
        case .declinedNow: "Camera access was declined."
        case .missingPurposeString(let key): "This build does not declare \(key), so asking would end the app."
        case .missingEntitlement(let key): "This build lacks \(key)."
        case .unknownStatus: "The camera permission could not be read."
        }
        return "\(why) The virtual table stays available."
    }
}

/// An object-list row that selects its object when tapped, marks the selection, and carries the
/// object's VoiceOver actions.
struct ObjectListRow: View {
    let entry: SceneEntry
    let session: TabletopSession

    var body: some View {
        if case .anchor(let id) = entry.subject {
            Button {
                session.selectedAnchorID = session.selectedAnchorID == id ? nil : id
            } label: {
                HStack {
                    SceneEntryRow(entry: entry)
                    Spacer(minLength: 0)
                    if session.selectedAnchorID == id {
                        Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(session.selectedAnchorID == id ? .isSelected : [])
            .modifier(EntryActions(entry: entry, session: session))
        } else {
            SceneEntryRow(entry: entry)
                .accessibilityElement(children: .combine)
        }
    }
}

/// The experiment's entry on its catalog page: iPhone and iPad push the experiment, and the Mac
/// shows it in the frontmost window (also in the sidebar and with Command-9). Shown only on
/// LAB-023's page.
struct TabletopLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == TabletopExperiment.id {
            #if os(macOS)
            Button {
                window?.destination = .tabletopReality
            } label: {
                Label("Open \(TabletopExperiment.title)", systemImage: TabletopExperiment.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                TabletopPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(TabletopExperiment.title)", systemImage: TabletopExperiment.symbol)
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
