import LabSupport
import SwiftUI

/// Implementation state with icon, text, and color, so meaning never depends on color alone.
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
