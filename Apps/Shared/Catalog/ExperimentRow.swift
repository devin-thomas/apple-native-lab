import LabCatalog
import SwiftUI

/// One experiment in a list. Every row has the same shape: title, then the state badge beside the
/// ID line. At accessibility text sizes the badge moves above the ID line in every row, so the
/// geometry depends on the text size, never on one title's length.
struct ExperimentRow: View {
    let experiment: RegisteredExperiment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(experiment.title)
                .font(.headline)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    StateBadge(state: experiment.state)
                    metadata
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StateBadge(state: experiment.state)
                    metadata
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        // Spoken in reading order with commas, not the visual middle dots.
        .accessibilityLabel("\(experiment.title), \(experiment.state.status.spokenLabel), \(experiment.id), \(experiment.milestone.rawValue), \(experiment.category)")
    }

    private var metadata: some View {
        Text("\(experiment.id) · \(experiment.milestone.rawValue) · \(experiment.category)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}
