import LabCatalog
import LabSupport
import SwiftUI

/// Implementation state as a shared status badge: each of the six states has its own symbol and
/// its own word, and is spoken as "State: <word>", so meaning never depends on color alone.
struct StateBadge: View {
    let state: ImplementationState

    var body: some View {
        StatusBadge(status: state.status)
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
    var status: StatusDescriptor {
        StatusDescriptor(kind: "State", title: title, symbol: symbolName, tone: tone)
    }

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

    var tone: StatusTone {
        switch self {
        case .specified: .neutral
        case .spiked: .attention
        case .implemented: .active
        case .deviceVerified, .releaseReady: .success
        case .blocked: .critical
        }
    }

    var tint: Color { tone.color }
}
