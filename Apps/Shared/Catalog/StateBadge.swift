import LabCatalog
import LabSupport
import SwiftUI

/// Implementation state with icon, text, and color, so meaning never depends on color alone.
/// Each of the six states has its own symbol and its own word.
struct StateBadge: View {
    let state: ImplementationState

    var body: some View {
        Label(state.title, systemImage: state.symbolName)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(state.tint)
            .background(state.tint.opacity(0.14), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("State: \(state.title)")
    }
}

/// One lifecycle state with what it promises and how many experiments are in it.
struct StateLegendRow: View {
    let state: ImplementationState
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    StateBadge(state: state)
                    Spacer(minLength: 8)
                    countText
                }
                VStack(alignment: .leading, spacing: 4) {
                    StateBadge(state: state)
                    countText
                }
            }
            Text(state.meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.title): \(count == 1 ? "1 experiment" : "\(count) experiments")")
        .accessibilityHint(state.meaning)
    }

    private var countText: some View {
        Text(count == 1 ? "1 experiment" : "\(count) experiments")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

extension ImplementationState {
    var symbolName: String {
        switch self {
        case .specified: "doc.text"
        case .spiked: "flask"
        case .implemented: "hammer"
        case .deviceVerified: "checkmark.seal"
        case .releaseReady: "shippingbox"
        case .blocked: "exclamationmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .specified: .secondary
        case .spiked: .orange
        case .implemented: .blue
        case .deviceVerified, .releaseReady: .green
        case .blocked: .red
        }
    }
}
