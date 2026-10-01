import LabDomain
import SwiftUI
import TinyDoorway

/// Shared Tiny Doorway sections used by the iPhone page and the Mac columns.
struct DoorwayHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan a code or open a link and arrive at one tightly scoped visit on a demo sample — not a giant onboarding funnel.")
                .fixedSize(horizontal: false, vertical: true)
            Text(DoorwayFallback.caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DoorwayClipStatusRow: View {
    let status: DoorwayClipStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                status == .configured ? "App Clip configured" : "App Clip not configured",
                systemImage: status == .configured ? "appclip" : "app.dashed"
            )
            Text(status.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DoorwayLinkField: View {
    @Bindable var session: DoorwaySession
    let library: LabLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Doorway URL", text: $session.draftURL, prompt: Text("nativelab://doorway/…"))
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                #endif
            Toggle("Treat network as offline", isOn: Binding(
                get: { session.reachability == .offline },
                set: { session.reachability = $0 ? .offline : .online }
            ))
            .help("Offline https links show the explained fallback; deep links still validate.")
            Button("Validate Link") {
                session.open(session.draftURL, source: .pasted, in: library)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct DoorwayFixtureList: View {
    @Bindable var session: DoorwaySession
    let library: LabLibrary

    var body: some View {
        ForEach(DemoLinks.fixtures, id: \.url) { fixture in
            Button {
                session.openFixture(fixture.url, in: library)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fixture.name)
                    Text(fixture.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Validate this fixture without committing")
        }
    }
}

struct DoorwayProposalReview: View {
    @Bindable var session: DoorwaySession
    let library: LabLibrary
    var onConfirmed: ((ReceiptRecord) -> Void)?

    var body: some View {
        if case .proposal(let proposal) = session.validation {
            let title = library.item(id: proposal.itemID)?.title.value ?? DoorwayPolicy.sampleItemTitle
            VStack(alignment: .leading, spacing: 12) {
                Text(proposal.reviewSentence(itemTitle: title))
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Channel", value: proposal.channel == .deepLink ? "Full-app deep link" : "Universal-link shape")
                LabeledContent("Seal", value: String(proposal.seal.hex.prefix(12)) + "…")
                Text("Confirming appends the visit marker through the ordinary authorization and receipt path. The link itself is not a grant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Confirm Visit") {
                    Task {
                        if let record = await session.confirm(in: library) {
                            onConfirmed?(record)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canAct(in: library))
                .accessibilityHint("Commit the visit on \(title)")
            }
        }
    }
}

struct DoorwayInformationPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DoorwayFallback.informationTitle)
                .font(.headline)
            Text(DoorwayFallback.informationBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DoorwayResultSection: View {
    let outcome: DoorwaySession.Outcome?
    let message: String?

    var body: some View {
        if let outcome {
            Text("Visited “\(outcome.itemTitle)”. Handoff seal \(String(outcome.handoff.seal.hex.prefix(12)))…")
                .fixedSize(horizontal: false, vertical: true)
            ReceiptRow(record: outcome.record)
        }
        if let message, !message.isEmpty {
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DoorwayResetControls: View {
    @Bindable var session: DoorwaySession
    let library: LabLibrary

    var body: some View {
        HStack {
            Button("Reset Visits") { session.resetVisits(in: library) }
                .disabled(!session.canAct(in: library))
                .help("Remove only Tiny Doorway visit markers from demo samples")
            if session.isRunning {
                Button("Stop", role: .cancel) { session.cancelReset() }
            }
        }
    }
}
