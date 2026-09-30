import SwiftUI

/// A block of read-only text the remote can focus, so a long page scrolls with the remote alone.
///
/// On tvOS, text is not focusable, and focus is the only way to scroll. Each card takes focus as a
/// whole and is read by VoiceOver as one element; it has no action, so Select does nothing.
struct FocusCard<Content: View>: View {
    let identifier: String
    @ViewBuilder let content: Content
    @FocusState private var isFocused: Bool

    var body: some View {
        FocusCardSurface(content: content, isFocused: isFocused)
            .focusable()
            .focused($isFocused)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
    }
}

/// The card's surface: a quiet panel that brightens, outlines, and lifts while it has focus.
private struct FocusCardSurface<Content: View>: View {
    let content: Content
    let isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .background(isFocused ? AnyShapeStyle(.white.opacity(0.24)) : AnyShapeStyle(.white.opacity(0.07)),
                        in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(isFocused ? 0.7 : 0), lineWidth: 3)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.03 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 20, y: 12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFocused)
    }
}

/// A card's heading: a short label above its text, never the only carrier of meaning.
struct CardHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

/// A state as a word beside its symbol, with room between them at every text size.
struct SymbolLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}
