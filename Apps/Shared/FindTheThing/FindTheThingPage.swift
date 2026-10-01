import FindTheThing
import LabCatalog
import SwiftUI

/// Search the shelf and read which records the answer used.
///
/// iPhone and iPad show the records and the answer on one page. The Mac shows the records in the
/// content column and this pane, with `showsRecords` off, in the detail column.
struct FindTheThingPage: View {
    @State private var session: FindTheThingSession
    var showsRecords: Bool

    init(session: FindTheThingSession, showsRecords: Bool = true) {
        _session = State(initialValue: session)
        self.showsRecords = showsRecords
    }

    var body: some View {
        @Bindable var session = session
        List {
            if showsRecords {
                Section("Shelf") {
                    ForEach(MessyCollection.corpus) { record in
                        FindTheThingRecordRow(record: record, indexed: session.indexedIDs.contains(record.id))
                            .tag(record.id)
                    }
                }
            }
            Section("Search") {
                TextField("Search records", text: $session.query)
                    .onSubmit { Task { await session.search() } }
                    .accessibilityLabel("Search records")
                Button {
                    Task { await session.search() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isWorking)
                .accessibilityHint("Searches opted-in records and cites the ones that matched.")
            }
            Section("Answer") {
                answer
            }
            Section("Index") {
                if let auditLine = session.auditLine {
                    Text(auditLine)
                }
                if let donationLine = session.donationLine {
                    Text(donationLine)
                }
                if let failure = session.failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
                Button("Delete Private Note", role: .destructive) {
                    Task { await session.deletePrivateNote() }
                }
                .disabled(session.isWorking || !session.indexedIDs.contains(MessyCollection.lockerNote.id))
                .accessibilityHint("Removes the private locker note from the app index.")
                Button("Reindex") { Task { await session.reindex() } }
                    .disabled(session.isWorking)
                    .accessibilityHint("Rebuilds the app index from the shelf. A deleted fixture stays out.")
                Button("Reset Fixtures") { Task { await session.resetFixtures() } }
                    .disabled(session.isWorking)
                    .accessibilityHint("Restores the shelf labels. Other lab records stay as they are.")
                Button("Donate Opted-in Records") { Task { await session.donate() } }
                    .disabled(session.isWorking)
                    .accessibilityHint("Updates this app's own index of opted-in records. It does not search other apps.")
            }
        }
        .navigationTitle(FindTheThing.title)
        .task { await session.prepare() }
    }

    @ViewBuilder private var answer: some View {
        if let outcome = session.outcome {
            switch outcome {
            case .unsupported(let refusal):
                Text(refusal.reason)
            case .answer(let answer):
                Text(answer.method == .lexical ? "Lexical search" : "Semantic retrieval")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(answer.prose)
                    .textSelection(.enabled)
                if answer.citations.isEmpty {
                    Text("No records cited.")
                        .foregroundStyle(.secondary)
                }
                ForEach(answer.citations) { citation in
                    Button {
                        session.selectedID = citation.recordID
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(citation.title)
                            Text(citation.recordID.rawValue.uuidString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(citation.deepLink.url.absoluteString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(citation.title), \(citation.recordID.rawValue.uuidString)")
                    .accessibilityHint("Shows this record. The answer cited it.")
                }
            }
        } else {
            Text("Search the shelf. The answer names the record identifiers it used.")
                .foregroundStyle(.secondary)
        }
    }
}

struct FindTheThingRecordRow: View {
    let record: SearchDocument
    let indexed: Bool

    private var indexStatus: String {
        if indexed { return "In the index" }
        if !record.optedIn { return "Not opted in" }
        return "Removed from the index"
    }

    private var indexStatusSpoken: String {
        if indexed { return "in the index" }
        if !record.optedIn { return "not opted in" }
        return "removed from the index"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.title)
            Text(indexStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if record.isPrivate {
                Text("Private")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.title), \(indexStatusSpoken)\(record.isPrivate ? ", private" : "")")
    }
}

/// The catalog page's way into Find the Thing.
struct FindTheThingLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == FindTheThing.id {
            #if os(macOS)
            Button {
                window?.destination = .findTheThing
            } label: {
                Label("Open \(FindTheThing.title)", systemImage: FindTheThing.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                FindTheThingPage(session: FindTheThingSession())
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(FindTheThing.title)", systemImage: FindTheThing.symbol)
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
