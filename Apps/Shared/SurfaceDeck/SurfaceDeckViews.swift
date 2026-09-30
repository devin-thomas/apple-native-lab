import LabCatalog
import LabDomain
import SurfaceDeck
import SwiftUI

/// The Surface Deck on one page (LAB-004): the demo session and its one reversible toggle, the
/// receipts, what the widget and the Control read, and previews of both drawn by the app.
///
/// iPhone and iPad push it from the experiment's catalog page, or show it when the launch action
/// runs. The Mac shows the same parts in its window columns (`Apps/Mac/Window/SurfaceDeckColumns.swift`).
struct SurfaceDeckPage: View {
    @State private var model = SurfaceDeckModel.shared

    var body: some View {
        List {
            Section {
                SessionStateCard(model: model)
                SessionToggleButton(model: model)
            } footer: {
                Text("Starting and pausing change only this demo state. Each change leaves a receipt with an undo, and Reset Demo pauses it.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            SessionReceiptsSection(model: model)
            SurfacesSection(model: model)
            Section {
                SurfacePreviewGallery(model: model)
            } header: {
                Text("Previews")
            } footer: {
                Text(SurfacePreviewGallery.caption(hasSurfaces: model.hasSurfaces))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle(SurfaceDeck.title)
        .task { await model.refresh() }
    }
}

/// The session's state, large, with its revision and the latest result.
struct SessionStateCard: View {
    let model: SurfaceDeckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(model.state.title)
                    .font(.largeTitle.weight(.bold))
            } icon: {
                Image(systemName: model.state.isRunning ? "play.circle.fill" : "pause.circle")
                    .foregroundStyle(model.state.isRunning ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(SurfaceDeck.sessionName), \(model.state.title)")
            Text(revisionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let message = model.lastMessage {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .unavailable(let reason) = model.phase {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var revisionText: String {
        guard let revision = model.state.revision else { return "\(SurfaceDeck.sessionName) · never started" }
        return "\(SurfaceDeck.sessionName) · revision \(revision)"
    }
}

/// The deck's toggle: one button that starts or pauses the session, pinned to the state shown.
struct SessionToggleButton: View {
    let model: SurfaceDeckModel

    var body: some View {
        Button {
            Task {
                let outcome = await model.setRunning(!model.state.isRunning)
                if let outcome { LabAnnouncement(text: outcome.message).post() }
            }
        } label: {
            Label(model.state.isRunning ? "Pause Session" : "Start Session",
                  systemImage: model.state.isRunning ? "pause.fill" : "play.fill")
                #if os(iOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(!model.canAct)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityHint("Changes the demo session. The receipt offers an undo.")
    }
}

/// This session's receipts for the demo session, newest first, each with its undo.
struct SessionReceiptsSection: View {
    let model: SurfaceDeckModel
    /// The Mac opens a receipt in the window's inspector; iPhone pushes it.
    var inspect: ((ReceiptRecord) -> Void)?
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Section {
            let receipts = model.receipts
            if receipts.isEmpty {
                Text("No changes yet in this session. Start or pause the session here, in its widget or Control, or with Shortcuts.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(receipts.prefix(5)) { record in
                if let inspect {
                    Button { inspect(record) } label: { ReceiptRow(record: record) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the receipt in the inspector.")
                } else {
                    NavigationLink {
                        ReceiptDetailView(record: record)
                            .navigationTitle("Receipt")
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                    } label: {
                        ReceiptRow(record: record)
                    }
                }
            }
            if let latest = receipts.first, latest.receipt.undo != nil, library.undone[latest.id] == nil {
                Button("Undo \(ReceiptPresentation(latest).operation)", systemImage: "arrow.uturn.backward") {
                    Task {
                        let result = await library.undo(latest)
                        LabAnnouncement.outcome(of: result, in: library)?.post()
                    }
                }
                .disabled(!library.canAct)
            }
        } header: {
            Text("Receipts")
        }
    }
}

/// What the widget and the Control read, and the one privacy choice for them.
struct SurfacesSection: View {
    @Bindable var model: SurfaceDeckModel

    var body: some View {
        Section {
            Label {
                Text(statusText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: model.hasSurfaces ? "square.stack.3d.up" : "square.stack.3d.up.slash")
            }
            Toggle("Show Details on Widgets", isOn: $model.showsDetailsOnSurfaces)
            #if os(macOS)
            SectionNote(Self.note)
            #endif
        } header: {
            Text("Widget and Control")
        } footer: {
            #if os(iOS)
            Text(Self.note)
            #endif
        }
    }

    static let note = "Off by default. When on, the widget also shows where and when the session last changed, and a locked device still hides that line. The widget and Control never read the lab's database."

    private var statusText: String {
        guard model.hasSurfaces else {
            return "This build has no widget or Control. The previews are drawn by Native Lab from the same snapshot a widget would read."
        }
        return switch model.publication {
        case .written(let date, _):
            "The widget and Control read a snapshot written at \(date.formatted(date: .omitted, time: .shortened)). It is rewritten only when the session or your choice below changes."
        case .failed:
            "The snapshot could not be written. The widget and Control keep showing the previous state."
        case .unchanged, .noSurfaces, nil:
            "The widget and Control read a snapshot this app writes after each change."
        }
    }
}

/// The widget in each size and the Control, drawn by the app from the snapshot the surfaces read.
/// Each is labeled as a preview: the system did not draw it.
struct SurfacePreviewGallery: View {
    let model: SurfaceDeckModel

    static func caption(hasSurfaces: Bool) -> String {
        hasSurfaces
            ? "Drawn by Native Lab from the snapshot the widget and Control read. Add the real ones from the Home Screen and Control Center."
            : "Drawn by Native Lab from the snapshot a widget and Control would read. This build has neither, so these previews are the fallback."
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let presentation = model.previewPresentation(at: context.date)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    PreviewFrame(title: "Small widget", width: 158, height: 158, presentation: presentation) {
                        SessionWidgetView(presentation: presentation, layout: .small) { SessionToggleLook(isOn: presentation.isOn) }
                    }
                    PreviewFrame(title: "Medium widget", width: 338, height: 158, presentation: presentation) {
                        SessionWidgetView(presentation: presentation, layout: .medium) { SessionToggleLook(isOn: presentation.isOn) }
                    }
                    PreviewFrame(title: "Lock Screen", width: 200, height: 84, padding: 10, presentation: presentation) {
                        SessionWidgetView(presentation: presentation, layout: .accessory) { EmptyView() }
                    }
                    PreviewFrame(title: "Lock Screen, locked", width: 200, height: 84, padding: 10, presentation: presentation) {
                        SessionWidgetView(presentation: presentation, layout: .accessory) { EmptyView() }
                            .redacted(reason: .privacy)
                    }
                    PreviewFrame(title: "Control", width: 200, height: 76, presentation: presentation, background: false) {
                        SessionControlPreview(presentation: presentation)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.visible)
        }
    }
}

/// One preview in a frame the size of the surface, captioned "Preview".
private struct PreviewFrame<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var padding: CGFloat = 14
    let presentation: SurfacePresentation
    var background = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
                .padding(background ? padding : 0)
                .frame(width: width, height: height, alignment: .topLeading)
                .background(background ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 22))
            Text("Preview · \(title)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(title.lowercased()), drawn by Native Lab")
        .accessibilityValue(presentation.accessibilityLabel)
    }
}

/// The experiment's entry on its catalog page: iPhone and iPad push the deck, and the Mac shows it
/// in the frontmost window (also in the sidebar and with Command-7). Shown only on LAB-004's page.
struct SurfaceDeckLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == SurfaceDeck.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .surfaceDeck
            } label: {
                Label("Open \(SurfaceDeck.title)", systemImage: SurfaceDeck.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘7)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                SurfaceDeckPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(SurfaceDeck.title)", systemImage: SurfaceDeck.symbol)
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

#if os(iOS)
/// Shows the deck when the launch action (the Open Surface Deck Control or Shortcuts action) runs.
struct SurfaceDeckPresenter: ViewModifier {
    @State private var model = SurfaceDeckModel.shared
    @Environment(LabLibrary.self) private var library

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.isDeckRequested) {
                NavigationStack {
                    SurfaceDeckPage()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { model.isDeckRequested = false }
                            }
                        }
                }
                // Observed in the iOS 27.0 simulator: a sheet raised while the launch action
                // brings the app forward did not inherit the library, so it is passed on here.
                .environment(library)
            }
    }
}

extension View {
    /// Presents the Surface Deck when its launch action runs (LAB-004).
    func surfaceDeckPresenter() -> some View {
        modifier(SurfaceDeckPresenter())
    }
}
#endif

/// Secondary text inside a section, for the Mac, whose list footers show one truncated line.
struct SectionNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
