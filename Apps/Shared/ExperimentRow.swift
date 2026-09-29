import LabCatalog
import SwiftUI

struct ExperimentRow: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        // Keep the badge beside the title when it fits; otherwise stack it, so narrow
        // columns and large text never break the title mid-word.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleBlock
                Spacer(minLength: 8)
                StateBadge(state: experiment.state)
            }
            VStack(alignment: .leading, spacing: 6) {
                titleBlock
                StateBadge(state: experiment.state)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(experiment.title)
                .font(.headline)
            Text("\(experiment.id) · \(experiment.milestone.rawValue)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
