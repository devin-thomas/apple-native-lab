import LabCatalog
import PointInspect
import SwiftUI
import UniformTypeIdentifiers

/// The inspection a person is editing. Nothing here is stored until they press Apply.
///
/// This is an `ObservableObject` because the domain type `Observation` hides the Observation
/// framework's registrar from `@Observable` in this file.
@MainActor
final class PointInspectSession: ObservableObject {
    @Published var title = ""
    @Published var body = ""
    @Published var status = "Choose an image, or type a title and apply it after you choose one. Nothing is saved until you apply it."
    @Published var badge: String?
    @Published var provenance = ""
    @Published var recognized = ""
    @Published var isBusy = false
    private var image: SelectedImage?
    private var record: Observation?
    private var flow: PointInspectFlow?

    func prepare(library: LabLibrary) {
        if flow == nil {
            flow = PointInspectFlow(backend: LibraryPointInspectBackend(library: library))
        }
    }

    /// Shows a system visual-search suggestion if one opened the app. Labels only.
    func takeVisualSearch() async {
        guard record == nil, let handed = await VisualSearchHandoff.shared.take() else { return }
        show(handed, status: "System visual search offered labels. They are a suggestion, not a command. Edit them, then apply.")
    }

    func open(fileAt url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            status = "The image could not be read."
            return
        }
        accept(data, origin: .userSelected, status: "Image chosen. It stays on this device. Read the text, describe it, or type the record.")
    }

    func replayFixture() {
        guard let url = Bundle.main.url(forResource: "swatch-card", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            status = "This build is missing the fixture image."
            return
        }
        accept(data, origin: .fixtureReplay, status: "Fixture replay. It is not a photograph and not a camera capture. Read the text or type the record.")
    }

    func readText() async {
        await inspect(route: .opticalRecognition, inspector: VisionImageAnalyzer())
    }

    func describe() async {
        await inspect(route: .onDeviceModel(OnDeviceImageInterpreter()), inspector: VisionImageAnalyzer())
    }

    func useFields() async {
        guard let image, let flow else {
            status = "Choose an image first. Then the fields become the record."
            return
        }
        await run {
            try await flow.inspect(
                image,
                route: .manual(title: title, body: body),
                inspector: UnavailableImageInspector(),
                consent: image.evidence.origin == .fixtureReplay ? .fixtureReplay : .chosenImage
            ).get()
        }
    }

    func apply() async {
        guard let flow else { return }
        if record == nil {
            await useFields()
        }
        guard var current = record else { return }
        current.suggestion = current.suggestion.edited(title: title, body: body)
        record = current
        isBusy = true
        defer { isBusy = false }
        switch await flow.commit(current) {
        case .success:
            record = nil
            status = "Saved in Inspections. The receipt is in this session. Reset Demo does not remove it."
        case .failure(let failure):
            status = failure.message
        }
    }

    private func accept(_ data: Data, origin: ImageOrigin, status: String) {
        do {
            image = try SelectedImage(data: data, origin: origin)
        } catch {
            self.status = error.message
            return
        }
        record = nil
        badge = nil
        recognized = ""
        provenance = image.map { "\($0.evidence.origin.label). \($0.evidence.byteCount) bytes. Stays on this device." } ?? ""
        self.status = status
    }

    private func inspect(route: PointInspectFlow.Route, inspector: any ImageInspecting) async {
        guard let image, let flow else {
            status = "Choose an image first."
            return
        }
        let consent: CaptureConsent = image.evidence.origin == .fixtureReplay ? .fixtureReplay : .chosenImage
        await run {
            try await flow.inspect(image, route: route, inspector: inspector, consent: consent).get()
        }
    }

    private func run(_ work: () async throws -> Observation) async {
        isBusy = true
        defer { isBusy = false }
        do {
            show(try await work(), status: nil)
        } catch let failure as InspectFailure {
            status = failure.message
        } catch {
            status = "The image could not be read. You can still type the record."
        }
    }

    private func show(_ observation: Observation, status: String?) {
        record = observation
        title = observation.suggestion.title
        body = observation.suggestion.body
        badge = observation.suggestion.source.badge
        provenance = "\(observation.evidence.origin.label). \(observation.consent.staysLocal ? "Stays on this device." : "") \(observation.evidence.digestPrefix)"
        let lines = observation.lines.map { line in
            line.isUncertain ? "\(line.text) (uncertain)" : line.text
        }
        let codes = observation.barcodes.map { "\($0.symbology): \($0.payload) (stored as text)" }
        recognized = (lines + codes).joined(separator: "\n")
        if let status {
            self.status = status
        } else if observation.suggestion.isUncertain {
            self.status = "Uncertain. Edit the title and note, then apply. Nothing is saved yet."
        } else {
            self.status = "Review the title and note, then apply. Nothing is saved yet."
        }
    }
}

/// Choose an image, read it, edit the suggestion, and apply it.
struct PointInspectScreen: View {
    @Environment(LabLibrary.self) private var library
    @StateObject private var session = PointInspectSession()
    @State private var isChoosingImage = false

    var body: some View {
        Form {
            Section {
                Text("Choose an image. Read the text on this device, ask for an on-device description, or type the record. A barcode is stored as text. Nothing is saved until you apply it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Image") {
                Button("Choose Image…", systemImage: "photo") { isChoosingImage = true }
                    .disabled(session.isBusy || !library.canAct)
                Button("Replay Fixture", systemImage: "rectangle.split.2x1") { session.replayFixture() }
                    .disabled(session.isBusy)
                    .accessibilityHint("Loads the bundled swatch. It is a labeled replay, not a camera capture.")
                if !session.provenance.isEmpty {
                    Text(session.provenance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Read") {
                Button("Read Text", systemImage: "text.viewfinder") { Task { await session.readText() } }
                    .disabled(session.isBusy || !library.canAct)
                    .accessibilityHint("Recognizes text and barcodes on this device. A barcode is not run.")
                Button("Describe on this Device", systemImage: "sparkles") { Task { await session.describe() } }
                    .disabled(session.isBusy || !library.canAct)
                    .accessibilityHint("Asks the on-device model for a description. If it cannot, type the record.")
            }
            Section("Record") {
                TextField("Title", text: $session.title)
                TextField("Note", text: $session.body, axis: .vertical)
                    .lineLimit(3...8)
                if let badge = session.badge {
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !session.recognized.isEmpty {
                    Text(session.recognized)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                Button("Use These Fields", systemImage: "keyboard") { Task { await session.useFields() } }
                    .disabled(session.isBusy || !library.canAct)
                Button("Apply", systemImage: "checkmark.circle") { Task { await session.apply() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isBusy || !library.canAct || session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Saves this record in Inspections after you review it.")
            }
            if session.isBusy {
                ProgressView("Working")
            }
            Text(session.status)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .navigationTitle("Point, Inspect, Propose")
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.png, .jpeg, .gif]) { result in
            guard case .success(let url) = result else {
                session.status = "The image was not opened."
                return
            }
            session.open(fileAt: url)
        }
        .task {
            session.prepare(library: library)
            await session.takeVisualSearch()
        }
    }
}

/// The Mac sidebar's content column for this experiment. The work is in the detail column.
struct PointInspectListColumn: View {
    var body: some View {
        ContentUnavailableView {
            Label("Point, Inspect, Propose", systemImage: "viewfinder")
        } description: {
            Text("Choose an image in the detail, or type the record. Nothing is saved until you apply it.")
        }
    }
}

/// The entry on the experiment's catalog page.
struct PointInspectEntry: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == PointInspect.experimentID {
            VStack(alignment: .leading, spacing: 6) {
                #if os(iOS)
                NavigationLink {
                    PointInspectScreen()
                } label: {
                    Label("Open Point, Inspect, Propose", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                Button("Open Point, Inspect, Propose", systemImage: "viewfinder") {
                    window?.destination = .pointInspect
                }
                .controlSize(.large)
                .disabled(window == nil)
                #endif
                Text("Runs in this build: a chosen image, on-device text and barcodes, an on-device description where the system can attach an image, and fields you type. The image stays on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
