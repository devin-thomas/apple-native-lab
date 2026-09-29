import LabCatalog
import LabSupport
import SwiftUI

struct ExperimentDetailView: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Text(experiment.moment)
                    .font(.title3)
                statusNote
                DetailFact(title: "Runs on", value: experiment.hosts, symbol: "laptopcomputer.and.iphone")
                DetailFact(title: "Built with", value: experiment.primaryAPIs, symbol: "shippingbox")
                if !experiment.dependsOn.isEmpty {
                    DetailFact(
                        title: "Depends on",
                        value: experiment.dependsOn.joined(separator: ", "),
                        symbol: "arrow.triangle.branch"
                    )
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(experiment.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(experiment.id) · \(experiment.category) · \(experiment.milestone.rawValue) \(experiment.milestone.title)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            StateBadge(state: experiment.state)
        }
    }

    @ViewBuilder private var statusNote: some View {
        if !experiment.state.isLive {
            let build = experiment.tickets.first ?? "its build ticket"
            let qualify = experiment.tickets.last ?? "its qualification ticket"
            Label {
                Text("Not built yet. \(build) builds it and \(qualify) qualifies it on real devices. Until then this page describes the plan, not a working feature.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        }
    }
}

private struct DetailFact: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
