import SwiftUI

/// One status in words and a symbol, with color as a third cue only.
///
/// Every status the hosts show goes through this type, so none can depend on color: the word and
/// the symbol are required, and the tone only chooses a color. The spoken label names the kind of
/// status first, so "Blocked" is never heard without knowing what is blocked.
struct StatusDescriptor: Hashable, Sendable {
    /// The kind of status, spoken first: "State", "Readiness", "Status".
    let kind: String
    /// The word shown and spoken, such as "Specified" or "Committed".
    let title: String
    /// An SF Symbol, different for every status of the same kind.
    let symbol: String
    let tone: StatusTone

    /// What VoiceOver speaks and Voice Control shows, for example "State: Blocked".
    var spokenLabel: String { "\(kind): \(title)" }
}

/// The design language's semantic colors. A tone never carries meaning on its own.
enum StatusTone: Hashable, Sendable, CaseIterable {
    /// Not started, not measured, or not selected.
    case neutral
    /// Actionable, in progress, or waiting for a person's action.
    case active
    /// Completed or met.
    case success
    /// Needs attention: declined, restricted, or not applied.
    case attention
    /// Blocked or not met.
    case critical

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .active: .blue
        case .success: .green
        case .attention: .orange
        case .critical: .red
        }
    }
}

/// A status as a compact capsule: the tinted symbol and the word in the primary text color.
///
/// The word keeps full text contrast whatever the tone, because a tinted caption fails contrast in
/// light mode. With Increase Contrast the fill deepens and the outline becomes solid. The badge is
/// one accessibility element with the spoken label; it never shrinks its text to fit.
struct StatusBadge: View {
    let status: StatusDescriptor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increased = contrast == .increased
        Label {
            Text(status.title)
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tone.color)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.tone.color.opacity(increased ? 0.24 : 0.14), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(status.tone.color.opacity(increased ? 1 : 0.4), lineWidth: increased ? 1.5 : 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.spokenLabel)
    }
}

/// A status inline with text, without the capsule: the tinted symbol, then the word. Longer
/// status sentences wrap instead of truncating.
struct StatusLabel: View {
    let status: StatusDescriptor

    var body: some View {
        Label {
            Text(status.title)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tone.color)
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.spokenLabel)
    }
}
