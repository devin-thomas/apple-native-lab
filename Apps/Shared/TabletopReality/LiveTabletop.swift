#if os(iOS)
import ARKit
import LabDomain
import Observation
import RealityKit
import SwiftUI
import TabletopReality
import UIKit

/// The live AR adapter (iPhone and iPad): world tracking with plane detection and coaching, the
/// table's origin as the one lab-owned session anchor, occlusion where the device supports it,
/// relocalization with recovery, and the table map saved only with consent.
///
/// It changes the table only through `TabletopSession`, the same planner, gate, and operation
/// service as the virtual table. It never records video or stills: ARKit's frames are read for
/// tracking and mapping state and nothing else. It starts only from the Start AR Camera action,
/// after `PermissionStager` has allowed the camera, and only where the world-tracking probe
/// offered it. This path has not run on a physical device yet (LAB-023-B qualifies it).
@MainActor
@Observable
final class LiveTabletop: NSObject {
    /// Whether the table's origin has been placed in this session.
    private(set) var hasTable = false
    private(set) var mapping: WorldMappingReading = .notAvailable
    /// What occludes the virtual objects on this device.
    private(set) var occlusion = "None"
    private(set) var message: String?
    private(set) var hasSavedMap: Bool

    let session: TabletopSession
    let library: LabLibrary
    let controller = TabletopSceneController()
    @ObservationIgnored private weak var arView: ARView?
    @ObservationIgnored private var originEntity: AnchorEntity?
    private let vault = WorldMapVault()
    private let resumeFromMap: Bool

    init(session: TabletopSession, library: LabLibrary, resumeFromMap: Bool) {
        self.session = session
        self.library = library
        self.resumeFromMap = resumeFromMap
        hasSavedMap = vault.exists
    }

    var mappingDecision: MappingDecision {
        MappingPolicy.decision(isLive: true, tracking: session.tracking, mapping: mapping, hasTable: hasTable)
    }

    // MARK: Session

    func attach(_ view: ARView) {
        arView = view
        view.session.delegate = self
        if let kit = session.kit { controller.build(kit: kit, drawsTable: false) }
        run(fresh: !resumeFromMap)
    }

    /// Runs world tracking. A resumed run loads the saved map so ARKit can find the table again.
    private func run(fresh: Bool) {
        guard let arView else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        var occluders: [String] = []
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
            occluders.append("the room's surfaces (scene mesh)")
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
            occluders.append("people")
        }
        occlusion = occluders.isEmpty ? "None on this device: virtual objects draw over real ones." : occluders.joined(separator: " and ")
        if !fresh, let map = vault.load() {
            configuration.initialWorldMap = map
            message = "Look at the table from where you saved its map. Placing waits until it is found."
        } else if !fresh {
            message = "The saved map could not be read, so tracking starts fresh. Tap a surface to place the table."
        }
        arView.session.run(configuration, options: fresh ? [.resetTracking] : [])
        session.liveTrackingChanged(.notStarted)
    }

    func end() {
        arView?.session.pause()
        session.liveEnded()
    }

    // MARK: Taps

    func handleTap(at point: CGPoint) {
        guard let arView else { return }
        if let entity = arView.entity(at: point), let id = TabletopSceneController.anchorID(of: entity) {
            session.selectedAnchorID = session.selectedAnchorID == id ? nil : id
            return
        }
        guard let result = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
            message = "No surface there yet. Move the device slowly over the table."
            return
        }
        guard hasTable else {
            // The table's origin is the one anchor the lab adds to the session.
            guard session.tracking == .normal else {
                message = "\(session.tracking.title). Place the table once tracking is normal."
                return
            }
            arView.session.add(anchor: ARAnchor(name: LabAnchorNames.tableOrigin, transform: result.worldTransform))
            return
        }
        let world = SIMD3<Float>(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
        let point = controller.tablePoint(fromScene: world)
        Task {
            if session.tapMovesSelection, let id = session.selectedAnchorID {
                await session.move(id, toX: point.x, z: point.z, in: library)
            } else {
                await session.place(atX: point.x, z: point.z, in: library)
            }
        }
    }

    private func attachTable(to anchor: ARAnchor) {
        guard let arView, originEntity == nil else { return }
        let entity = AnchorEntity(anchor: anchor)
        entity.addChild(controller.root)
        arView.scene.addAnchor(entity)
        originEntity = entity
        hasTable = true
        message = "Table placed. Choose an object and tap the table to place it."
        syncObjects()
    }

    func syncObjects() {
        guard let kit = session.kit else { return }
        controller.sync(kit: kit, anchors: session.anchors, selection: session.selectedAnchorID)
    }

    // MARK: Recovery and reset

    /// Removes the lab's own session anchors, and only those: the detected planes stay, and the
    /// objects keep their places on the table in the store. Tap a surface to place the table again.
    func resetTablePosition() {
        guard let arView else { return }
        let records = (arView.session.currentFrame?.anchors ?? []).map { SessionAnchorRecord(identifier: $0.identifier, name: $0.name) }
        let removals = Set(LabAnchorNames.removals(from: records))
        for anchor in arView.session.currentFrame?.anchors ?? [] where removals.contains(anchor.identifier) {
            arView.session.remove(anchor: anchor)
        }
        detachTable()
        message = "Removed the table's position (\(removals.count) lab anchor\(removals.count == 1 ? "" : "s")). Detected surfaces were kept. Tap a surface to place the table again."
    }

    /// After a stalled relocalization: track again without the saved map, and place the table again.
    func startFresh() {
        resetTablePosition()
        run(fresh: true)
    }

    private func detachTable() {
        originEntity?.removeFromParent()
        controller.root.removeFromParent()
        originEntity = nil
        hasTable = false
    }

    // MARK: The table map

    /// Saves ARKit's world map for this table. Called only after the person confirmed the consent
    /// dialog, and only when the mapping policy allows it.
    func saveMap() {
        guard mappingDecision.canSave, let arView else { return }
        arView.session.getCurrentWorldMap { [weak self] map, error in
            let data = map.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            Task { @MainActor in
                guard let self else { return }
                guard let data, error == nil else {
                    self.message = "ARKit could not produce a map yet. Nothing was saved."
                    return
                }
                do {
                    try self.vault.save(data)
                    self.hasSavedMap = true
                    self.message = "Saved this table's map on this device only."
                } catch {
                    self.message = "The map could not be written. Nothing was saved."
                }
            }
        }
    }

    func forgetMap() {
        vault.forget()
        hasSavedMap = vault.exists
        message = hasSavedMap ? "The saved map could not be deleted." : "Deleted the saved table map."
    }
}

// ARKit calls these on the main queue: the session's delegate queue is left unset.
extension LiveTabletop: @preconcurrency ARSessionDelegate {
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        self.session.liveTrackingChanged(TrackingStatus(camera.trackingState))
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let reading = WorldMappingReading(frame.worldMappingStatus)
        if mapping != reading { mapping = reading }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        if let origin = anchors.first(where: { $0.name == LabAnchorNames.tableOrigin }) { attachTable(to: origin) }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        self.session.liveTrackingChanged(.interrupted)
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        self.session.liveTrackingChanged(.notAvailable)
        message = "The AR session stopped. Close the camera to return to the virtual table."
    }
}

extension TrackingStatus {
    init(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal: self = .normal
        case .notAvailable: self = .notAvailable
        case .limited(.initializing): self = .limited(.initializing)
        case .limited(.excessiveMotion): self = .limited(.excessiveMotion)
        case .limited(.insufficientFeatures): self = .limited(.insufficientFeatures)
        case .limited(.relocalizing): self = .limited(.relocalizing)
        case .limited: self = .limited(.initializing)
        }
    }
}

extension WorldMappingReading {
    init(_ status: ARFrame.WorldMappingStatus) {
        switch status {
        case .mapped: self = .mapped
        case .extending: self = .extending
        case .limited: self = .limited
        case .notAvailable: self = .notAvailable
        @unknown default: self = .notAvailable
        }
    }
}

/// The one file of mapping data the lab keeps: ARKit's world map for the table, in the app's
/// Application Support folder, protected until first unlock is not enough, so complete protection,
/// and excluded from backups. Nothing else reads it, and nothing exports it.
struct WorldMapVault {
    let url: URL = URL.applicationSupportDirectory.appending(path: "Tabletop", directoryHint: .isDirectory)
        .appending(path: "table.arworldmap")

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = url
        try marked.setResourceValues(values)
    }

    func load() -> ARWorldMap? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }

    func forget() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// The ARView, with ARKit's coaching overlay for finding a horizontal surface and relocalizing.
struct LiveTabletopView: UIViewRepresentable {
    let live: LiveTabletop

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        live.attach(view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        live.syncObjects()
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.live.end()
    }

    func makeCoordinator() -> Coordinator { Coordinator(live: live) }

    @MainActor
    final class Coordinator: NSObject {
        let live: LiveTabletop

        init(live: LiveTabletop) { self.live = live }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            live.handleTap(at: recognizer.location(in: view))
        }
    }
}

/// The camera screen: the AR view, the tracking state, and the table's controls. Done returns to
/// the virtual table; the objects stay where they are on the table.
struct LiveTabletopScreen: View {
    let session: TabletopSession
    @State private var live: LiveTabletop
    @State private var isConfirmingSave = false
    @Environment(\.dismiss) private var dismiss

    init(session: TabletopSession, library: LabLibrary, resumeFromMap: Bool) {
        self.session = session
        _live = State(initialValue: LiveTabletop(session: session, library: library, resumeFromMap: resumeFromMap))
    }

    var body: some View {
        // Read so the AR view updates when the table or selection changes.
        let _ = (session.anchors, session.selectedAnchorID)
        LiveTabletopView(live: live)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) { TrackingBadge(session: session) }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(live.message ?? (live.hasTable ? "Tap the table to place the chosen object." : "Tap a detected surface to place the table."))
                        .font(.callout)
                    Text("Occlusion: \(live.occlusion)").font(.footnote).foregroundStyle(.secondary)
                    if case .stalled = session.advice {
                        HStack {
                            Button("Keep Looking") { session.keepLooking() }
                            Button("Start Fresh") { live.startFresh() }
                        }
                    }
                    HStack {
                        Button("Save Map…") { isConfirmingSave = true }
                            .disabled(!live.mappingDecision.canSave)
                        Button("Reset Table Position") { live.resetTablePosition() }
                            .disabled(!live.hasTable)
                        Spacer()
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                    if let reason = live.mappingDecision.reason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
            .confirmationDialog(MappingPolicy.consentTitle, isPresented: $isConfirmingSave, titleVisibility: .visible) {
                Button("Save Map on This Device") { live.saveMap() }
            } message: {
                Text(MappingPolicy.consentMessage)
            }
    }
}
#endif
