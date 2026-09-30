import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A sentence spoken by assistive technology when a change lands somewhere other than where the
/// person is, such as a receipt arriving after a confirmation closes.
///
/// An announcement always repeats something visible (the receipt, the failure banner), so it is
/// never the only record of a change. A haptic or sound added later plays beside it, never instead:
/// every non-visual cue in the lab has these words as its text alternative.
struct LabAnnouncement: Hashable, Sendable {
    enum Priority: Hashable, Sendable {
        case normal
        /// Interrupts other speech: something did not happen as asked.
        case high
    }

    let text: String
    var priority: Priority = .normal

    /// What a committed or refused change did, and whether it can be undone.
    init(receipt: ReceiptPresentation) {
        if receipt.isCommitted {
            text = receipt.undo == nil ? receipt.summary : "\(receipt.summary) Undo is available."
            priority = .normal
        } else {
            // The summary of a refused change already starts "Not applied because …".
            text = receipt.summary
            priority = .high
        }
    }

    /// A change that failed before it produced a receipt. Library failures say what did not change.
    init(failure: String) {
        text = failure
        priority = .high
    }

    /// A sentence of the caller's own, such as the result of several changes that each left a
    /// receipt, or a receipt's sentence followed by what it meant for a task. The same words must
    /// be visible on screen.
    init(text: String, priority: Priority = .normal) {
        self.text = text
        self.priority = priority
    }

    /// The announcement for an action's result: its receipt, or the failure the library recorded.
    /// `nil` when there is neither, for example when the action was refused because another was
    /// still running.
    @MainActor
    static func outcome(of record: ReceiptRecord?, in library: LabLibrary) -> LabAnnouncement? {
        if let record { return LabAnnouncement(receipt: ReceiptPresentation(record)) }
        return library.failure.map(LabAnnouncement.init(failure:))
    }

    /// Speaks the text through the platform's announcement channel: a UIKit announcement on
    /// iPhone and iPad, and AppKit's `announcementRequested` notification on the Mac. The visible
    /// receipt stays the lasting record either way (docs/ACCESSIBILITY_REVIEW.md).
    @MainActor
    func post() {
        #if os(iOS)
        let attributed = NSAttributedString(string: text, attributes: [
            .accessibilitySpeechAnnouncementPriority: priority == .high ? UIAccessibilityPriority.high : .default,
        ])
        UIAccessibility.post(notification: .announcement, argument: attributed)
        #elseif os(macOS)
        let level: NSAccessibilityPriorityLevel = priority == .high ? .high : .medium
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: level.rawValue,
        ])
        #endif
    }
}
