import AppIntents
import SwiftUI

/// The decision as a SwiftUI snippet: the same words as the in-app card.
///
/// `confirm` is the Shortcut button. The system's confirmation dialog omits it and uses its own
/// Set Aside and Cancel buttons, so the words are not doubled.
struct DecisionSnippetView: View {
    let card: DecisionCard
    var confirm: SetAsideSampleIntent?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.headline)
            if !card.note.isEmpty {
                Text(card.note)
            }
            Text(card.prompt)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.contextResolution)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let confirm {
                Button(card.acceptLabel, intent: confirm)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Associates the sample with this view and, when the host has an activity type, with an
/// `NSUserActivity` that carries the same entity identifier.
struct VisibleSampleAssociation: ViewModifier {
    let itemID: UUID
    let title: String
    let activityType: String?

    func body(content: Content) -> some View {
        if let activityType {
            content
                .appEntityIdentifier(VisibleSampleActivity.identifier(for: itemID))
                .userActivity(activityType) { activity in
                    VisibleSampleActivity.fill(activity, title: title, itemID: itemID)
                }
        } else {
            content.appEntityIdentifier(VisibleSampleActivity.identifier(for: itemID))
        }
    }
}

extension View {
    /// Marks this view as showing one lab sample. Replacing `itemID` associates the new sample.
    public func visibleSample(itemID: UUID, title: String, activityType: String?) -> some View {
        modifier(VisibleSampleAssociation(itemID: itemID, title: title, activityType: activityType))
    }
}
