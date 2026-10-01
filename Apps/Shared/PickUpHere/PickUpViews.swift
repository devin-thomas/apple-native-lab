import PickUpHere
import SwiftUI

/// The catalog page's way into Pick Up Here.
struct PickUpCatalogAction: View {
    var body: some View {
        #if os(iOS)
        NavigationLink {
            PickUpScreen()
        } label: {
            Label("Open Pick Up Here", systemImage: "arrow.left.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("Continue a draft at a section, or copy a link or the document.")
        #else
        PickUpMacCatalogButton()
        #endif
    }
}

#if os(macOS)
private struct PickUpMacCatalogButton: View {
    @Environment(MainWindowState.self) private var window

    var body: some View {
        Button {
            window.destination = .pickUpHere
        } label: {
            Label("Open Pick Up Here", systemImage: "arrow.left.arrow.right")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("Show Pick Up Here in this window (⌘9)")
        .accessibilityHint("Continue a draft at a section, or copy a link or the document.")
    }
}
#endif

extension View {
    /// Delivers a Handoff continuation into `session`. `open` shows Pick Up Here.
    func pickUpContinuation(session: PickUpSession, library: LabLibrary, open: @escaping () -> Void) -> some View {
        onContinueUserActivity(HandoffActivity.activityType) { activity in
            open()
            Task { await session.accept(activity, library: library) }
        }
    }
}

/// The iPhone screen. The Mac uses the window columns instead.
struct PickUpScreen: View {
    @Environment(LabLibrary.self) private var library
    @Environment(PickUpSession.self) private var session

    var body: some View {
        @Bindable var session = session
        List {
            Section {
                PickUpActions(session: session)
            }
            Section("Drafts") {
                if session.items.isEmpty {
                    Text("No drafts yet.")
                }
                ForEach(session.items) { item in
                    Button {
                        session.selectedItemID = item.id
                        session.selectedSection = 0
                    } label: {
                        Text(item.title.value)
                    }
                    .accessibilityAddTraits(session.selectedItemID == item.id ? .isSelected : [])
                }
            }
            Section("This draft") {
                PickUpEditor(session: session)
            }
            Section("Continue here") {
                PickUpIncoming(session: session)
            }
        }
        .navigationTitle("Pick Up Here")
        .task { await session.load(library) }
        .onChange(of: library.latestReceipt?.id) { Task { await session.load(library) } }
        .userActivity(HandoffActivity.activityType, isActive: session.isAdvertising) { activity in
            guard let offer = session.offer else { return }
            HandoffActivity.fill(activity, with: offer, handoffEligible: true)
        }
    }
}

struct PickUpActions: View {
    @Bindable var session: PickUpSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        Button("Add Sample Draft") { Task { await session.addSample(library) } }
            .disabled(session.isWorking || !library.canAct)
            .accessibilityHint("Adds an original three-section draft to one of your collections.")
        Button("Advertise") { Task { await session.advertise(library) } }
            .disabled(session.selectedItemID == nil || session.isWorking)
            .accessibilityHint("Tells Handoff the draft's identifier and section. The draft itself stays here.")
        Button("Copy Continuation Link") { Task { await session.copyLink(library) } }
            .disabled(session.selectedItemID == nil || session.isWorking)
            .accessibilityHint("Copies a link with the identifier and section, not the draft.")
        Button("Copy Document") { Task { await session.copyDocument(library) } }
            .disabled(session.selectedItemID == nil || session.isWorking)
            .accessibilityHint("Copies the draft so another device can import it. This is not Handoff.")
        Button("Revoke Access") { session.revokeSelected() }
            .disabled(session.selectedItemID == nil)
            .accessibilityHint("Hides this draft's contents until you allow access again.")
        Button("Allow Access") { session.allowSelected() }
            .disabled(session.selectedItemID == nil)
            .accessibilityHint("Allows a later continue to read this draft again. It does not show it yet.")
        Button("Clear Continuation") { session.clear() }
            .accessibilityHint("Drops the advertised activity and the text on screen. Drafts already in the lab stay.")
        if let message = session.message {
            Text(message)
        }
    }
}

struct PickUpEditor: View {
    @Bindable var session: PickUpSession

    var body: some View {
        if let item = session.item(session.selectedItemID) {
            let sections = session.sections(of: item)
            Picker("Section", selection: $session.selectedSection) {
                ForEach(sections.indices, id: \.self) { index in
                    Text("Section \(index + 1) of \(sections.count)").tag(index)
                }
            }
            .accessibilityHint("The section a continuation resumes at.")
            if case .accessRevoked(let locator) = session.decision, locator.documentID == item.id {
                Text("Access to this draft was revoked. Its contents are not shown.")
            } else if session.revoked.contains(item.id) {
                Text("Access to this draft was revoked. Its contents are not shown.")
            } else if sections.indices.contains(session.selectedSection) {
                Text(sections[session.selectedSection])
            }
        } else {
            Text("Choose a draft.")
        }
    }
}

struct PickUpIncoming: View {
    @Bindable var session: PickUpSession
    @Environment(LabLibrary.self) private var library

    var body: some View {
        TextField("Continuation link", text: $session.linkText)
            .accessibilityHint("Paste a continuation link. It does not contain the draft.")
        Button("Continue from Link") { Task { await session.resumeLink(library) } }
            .disabled(session.linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isWorking)
            .accessibilityHint("Looks the draft up in this lab. A missing draft asks you to import it.")
        TextField("Continuation document", text: $session.documentText, axis: .vertical)
            .lineLimit(3...8)
            .accessibilityHint("Paste a continuation document you copied. Importing it is a separate step.")
        Button("Import Document") { Task { await session.importPastedDocument(library) } }
            .disabled(session.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isWorking || !library.canAct)
            .accessibilityHint("Imports the pasted document through the lab's receipt path.")
        if let decision = session.decision {
            Text(decision.sentence)
            if let resumed = decision.resumed {
                Text(resumed.sectionText)
                    .font(.body)
            }
        }
    }
}
