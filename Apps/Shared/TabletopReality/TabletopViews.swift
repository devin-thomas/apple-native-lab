import LabDomain
import RealityKit
import SwiftUI
import TabletopReality

/// The virtual table: an orbitable RealityKit scene with pointer and touch controls. It is the
/// declared fallback and the whole route on the Mac and in a simulator.
///
/// Drag orbits the camera and pinch or scroll zooms (`realityViewCameraControls(.orbit)`). A tap
/// or click on the table places the chosen object there, or moves the selected one, and a tap on
/// an object selects it. The view is one accessibility element that describes the scene; the
/// object list beside it names every object and carries every action.
struct VirtualTabletopScene: View {
    let session: TabletopSession
    @Environment(LabLibrary.self) private var library
    @State private var controller = TabletopSceneController()

    var body: some View {
        if let kit = session.kit {
            // Read here so the view updates when they change, then handed to the update closure.
            let anchors = session.anchors
            let selection = session.selectedAnchorID
            RealityView { content in
                controller.build(kit: kit, drawsTable: true)
                content.add(controller.root)
                content.cameraTarget = controller.root
            } update: { _ in
                controller.sync(kit: kit, anchors: anchors, selection: selection)
            }
            .realityViewCameraControls(.orbit)
            .gesture(tap)
            .overlay(alignment: .topLeading) { TrackingBadge(session: session) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("3D view of the \(kit.table.title.value.lowercased())")
            .accessibilityValue(sceneValue(anchors))
            .accessibilityHint("Drag to orbit. The object list names every object and has its actions.")
        }
    }

    private var tap: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if let id = TabletopSceneController.anchorID(of: value.entity) {
                    session.selectedAnchorID = session.selectedAnchorID == id ? nil : id
                    return
                }
                guard TabletopSceneController.isTable(value.entity),
                      let hit = value.hitTest(point: value.location, in: .local).first(where: { TabletopSceneController.isTable($0.entity) })
                else { return }
                let point = controller.tablePoint(fromScene: hit.position)
                Task {
                    if session.tapMovesSelection, let id = session.selectedAnchorID {
                        await session.move(id, toX: point.x, z: point.z, in: library)
                    } else {
                        await session.place(atX: point.x, z: point.z, in: library)
                    }
                }
            }
    }

    private func sceneValue(_ anchors: [LabAnchor]) -> String {
        let count = anchors.count == 1 ? "1 object" : "\(anchors.count) objects"
        let selected = session.selectedAnchor.map { ", \($0.title.value) selected" } ?? ""
        return "\(count)\(selected). \(session.tracking.title)."
    }
}

/// The tracking state over the scene, labeled as a replay while one plays.
struct TrackingBadge: View {
    let session: TabletopSession

    var body: some View {
        Label {
            Text(session.trackingSource == .replay ? "Replay: \(session.tracking.title)" : session.tracking.title)
        } icon: {
            Image(systemName: session.tracking.allowsPrecision ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(session.tracking.allowsPrecision ? .green : .orange)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .padding(10)
        .accessibilityHidden(true)
    }
}

// MARK: - Status

/// Tracking now, what it allows, and, after a stalled relocalization, the two recoveries.
struct TrackingStatusSection: View {
    let session: TabletopSession
    var startFresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Tracking", value: session.trackingSource == .replay ? "Replay: \(session.tracking.title)" : session.tracking.title)
            Text(session.tracking.guidance)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if session.trackingSource == .replay {
                Text("A recorded tracking sequence, not a camera. It shows what the live adapter does when tracking is lost.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch session.advice {
            case .stalled:
                Text("The table has not been found again. Keep looking at it from where you were, or start fresh and place the table again; every object keeps its place on the table.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Keep Looking") { session.keepLooking() }
                    if let startFresh {
                        Button("Start Fresh", action: startFresh)
                    }
                }
            case .recovered:
                Text("Tracking recovered. Placing, moving, and turning are available again.")
                    .font(.callout)
            case .none, .searching:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Which route runs here and why, with the explicit Start AR Camera action where it is offered.
struct RouteSection: View {
    let session: TabletopSession
    var startLive: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let route = session.route {
                Text(route.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if route.offersLiveStart, let startLive {
                    Button("Start AR Camera", systemImage: "arkit", action: startLive)
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Asks for camera access if needed, then opens the camera to place the table on a real surface.")
                }
            } else {
                ProgressView("Checking AR support…")
            }
        }
    }
}

// MARK: - Placing

/// Choose an object, then place it by tapping the table or at the free spot nearest the center.
struct PlacementControls: View {
    @Bindable var session: TabletopSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        let place = session.availability(of: .place, in: library)
        if let kit = session.kit {
            Picker("Object", selection: $session.fixtureToPlace) {
                ForEach(kit.fixtures) { fixture in
                    Text(fixture.title.value).tag(Optional(fixture.key))
                }
            }
            Picker("A tap on the table", selection: $session.tapMovesSelection) {
                Text("Places the object").tag(false)
                Text("Moves the selection").tag(true)
            }
            Button("Place on Table", systemImage: "plus.circle") {
                Task { await session.placeAtFreeSpot(in: library) }
            }
            .disabled(!place.allowed)
            .keyboardShortcut("n", modifiers: [.command, .option])
            .accessibilityHint("Places the chosen object at the free spot nearest the center of the table.")
            Button("Set Out Starter Scene", systemImage: "square.grid.3x3.topleft.filled") {
                session.setOutStarter(in: library)
            }
            .disabled(!session.availability(of: .setOutStarter, in: library).allowed)
            .accessibilityHint("Places the kit's four starter objects wherever their spots are free, one receipt each.")
            if let reason = place.reason {
                Text(reason).font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - The selection

/// The selected object: where it is, and buttons to move, turn, and remove it. On the Mac each has
/// a keyboard shortcut: Option with an arrow moves, Option-[ and Option-] turn, Command-Delete
/// removes.
struct SelectionControls: View {
    @Bindable var session: TabletopSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        if let anchor = session.selectedAnchor, let entry = session.entry(for: anchor.id) {
            let move = session.availability(of: .move, in: library)
            let removable = session.availability(of: .remove, in: library).allowed
            LabeledContent("Object", value: entry.label)
            LabeledContent("Where", value: entry.value)
            Picker("Step", selection: $session.nudgeStep) {
                ForEach(NudgeStep.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    nudge(.awayFromYou, "arrow.up", .upArrow, enabled: move.allowed)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                GridRow {
                    nudge(.left, "arrow.left", .leftArrow, enabled: move.allowed)
                    nudge(.towardYou, "arrow.down", .downArrow, enabled: move.allowed)
                    nudge(.right, "arrow.right", .rightArrow, enabled: move.allowed)
                }
            }
            .buttonStyle(.bordered)
            HStack {
                Button("Turn Left", systemImage: "rotate.left") {
                    Task { await session.turn(clockwise: false, in: library) }
                }
                .keyboardShortcut("[", modifiers: .option)
                Button("Turn Right", systemImage: "rotate.right") {
                    Task { await session.turn(clockwise: true, in: library) }
                }
                .keyboardShortcut("]", modifiers: .option)
            }
            .disabled(!move.allowed)
            .accessibilityHint("Turns the object by \(TabletopPlanner.turnStep) degrees.")
            Button("Remove \(entry.label)", systemImage: "trash", role: .destructive) {
                Task { await session.remove(in: library) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!removable)
            .accessibilityHint("Removes the object from the table. Its receipt offers an undo.")
            if let reason = move.reason {
                Text(reason).font(.footnote).foregroundStyle(.orange)
            }
        } else {
            Text("Select an object in the list or tap it in the 3D view to move, turn, or remove it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nudge(_ direction: TableDirection, _ symbol: String, _ key: KeyEquivalent, enabled: Bool) -> some View {
        Button {
            Task { await session.nudge(direction, in: library) }
        } label: {
            Label("Move \(direction.title)", systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(minWidth: 28, minHeight: 28)
        }
        .keyboardShortcut(key, modifiers: .option)
        .disabled(!enabled)
        .help("Move \(direction.title.lowercased()) by \(session.nudgeStep.title) (⌥ arrow)")
    }
}

// MARK: - The object list

/// One row of the accessibility list: the object's name, where it is, and what it looks like. The
/// row that holds it adds `EntryActions`.
struct SceneEntryRow: View {
    let entry: SceneEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.label).font(.body.weight(.semibold))
            Text(entry.value).font(.callout)
            Text(entry.detail).font(.footnote).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An object row's VoiceOver actions: select, move, turn, and remove, so every change is reachable
/// without seeing or pointing at the 3D view. The table's row has none.
struct EntryActions: ViewModifier {
    let entry: SceneEntry
    let session: TabletopSession
    @Environment(LabLibrary.self) private var library

    func body(content: Content) -> some View {
        if case .anchor(let id) = entry.subject {
            content
                .accessibilityAction(named: "Select") { session.selectedAnchorID = id }
                .accessibilityAction(named: "Move Left") { run { await session.nudge(.left, id, in: library) } }
                .accessibilityAction(named: "Move Right") { run { await session.nudge(.right, id, in: library) } }
                .accessibilityAction(named: "Move Toward You") { run { await session.nudge(.towardYou, id, in: library) } }
                .accessibilityAction(named: "Move Away from You") { run { await session.nudge(.awayFromYou, id, in: library) } }
                .accessibilityAction(named: "Turn Left") { run { await session.turn(clockwise: false, id, in: library) } }
                .accessibilityAction(named: "Turn Right") { run { await session.turn(clockwise: true, id, in: library) } }
                .accessibilityAction(named: "Remove") { run { await session.remove(id, in: library) } }
        } else {
            content
        }
    }

    private func run(_ body: @escaping @MainActor () async -> ReceiptRecord?) {
        Task { _ = await body() }
    }
}

// MARK: - The table

/// Clear Table (with a confirmation) and the tracking replay.
struct TableActions: View {
    let session: TabletopSession
    @Environment(LabLibrary.self) private var library
    @State private var isConfirmingClear = false

    var body: some View {
        if session.isRunningList {
            HStack {
                ProgressView()
                Button("Stop", role: .cancel) { session.cancelList() }
            }
        }
        Button("Clear Table…", systemImage: "xmark.bin", role: .destructive) { isConfirmingClear = true }
            .disabled(session.anchors.isEmpty || !session.canAct(in: library))
            .confirmationDialog("Clear the table?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Remove \(session.anchors.count == 1 ? "1 Object" : "\(session.anchors.count) Objects")", role: .destructive) {
                    session.clearTable(in: library)
                }
            } message: {
                Text("Removes only the objects placed on this table, one receipt each; each receipt can undo its removal. Nothing in your collections changes.")
            }
        if session.trackingSource == .replay {
            Button("Stop Replay", systemImage: "stop.circle") { session.stopReplay() }
        } else {
            Button("Replay Tracking Loss", systemImage: "play.circle") { session.startReplay() }
                .disabled(session.trackingSource == .live)
                .accessibilityHint("Plays a recorded 15-second tracking sequence so you can see placing and moving pause and resume. It is not a camera.")
        }
    }
}

/// The last result, with its receipt.
struct TabletopResult: View {
    let session: TabletopSession
    var showReceipt: ((ReceiptRecord) -> Void)?

    var body: some View {
        if let message = session.message {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let record = session.lastRecord {
            if let showReceipt {
                Button { showReceipt(record) } label: { ReceiptRow(record: record) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the receipt in the inspector.")
            } else {
                NavigationLink {
                    ReceiptDetailView(record: record)
                        .navigationTitle("Receipt")
                } label: {
                    ReceiptRow(record: record)
                }
            }
        }
        if case .unavailable(let reason) = session.phase {
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
