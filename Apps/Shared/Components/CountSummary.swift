import SwiftUI

/// A one-sentence reading of a set of counts, so a data display is never only a pattern of badges
/// or bars. For example "9 capabilities: 1 available, 2 need action, 6 unavailable."
///
/// Parts with a count of zero are left out; a total of zero says "No capabilities." Parts keep the
/// caller's order, which should be the display's own order.
struct CountSummary: Hashable, Sendable {
    struct Part: Hashable, Sendable {
        let count: Int
        let label: String
    }

    let total: Int
    let singular: String
    let plural: String
    let parts: [Part]

    var sentence: String {
        guard total > 0 else { return "No \(plural)." }
        let head = "\(total) \(total == 1 ? singular : plural)"
        let listed = parts.filter { $0.count > 0 }.map { "\($0.count) \($0.label)" }
        return listed.isEmpty ? "\(head)." : "\(head): \(listed.joined(separator: ", "))."
    }
}

/// A count summary shown as a line of text, so sighted readers get the same sentence.
struct CountSummaryText: View {
    let summary: CountSummary

    var body: some View {
        Text(summary.sentence)
            .font(.subheadline)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}
