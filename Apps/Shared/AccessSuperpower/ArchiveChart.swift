import AccessSuperpower
import LabDomain
import SwiftUI
#if canImport(Accessibility)
import Accessibility
#endif

/// Whether the archive chart carries its Audio Graph. It does wherever the Accessibility module
/// exists; the summary and the table never depend on it.
enum SonificationRoute: Hashable, Sendable {
    /// The chart has an `AXChartDescriptor`, so VoiceOver can describe it and play it.
    case audioGraph
    /// No chart descriptor. The summary and the list of archived samples carry the same numbers.
    case unavailable

    static var current: SonificationRoute {
        #if canImport(Accessibility)
        .audioGraph
        #else
        .unavailable
        #endif
    }

    var explanation: String {
        switch self {
        case .audioGraph:
            "This build attaches the chart's Audio Graph, so VoiceOver can describe the chart and play it as tones."
        case .unavailable:
            "The Audio Graph is unavailable here. The summary and the list of archived samples carry the same numbers."
        }
    }
}

extension EnvironmentValues {
    /// Tests set `.unavailable` to prove the fallback; the hosts leave the default.
    @Entry var accessSonification: SonificationRoute = .current
}

/// Archived samples per demo collection, as horizontal bars of one square per sample: filled for
/// archived, outlined for active. Counts are drawn as shapes and written as numbers, so the chart
/// reads without color.
///
/// For assistive technology it is a container named for the chart, with one element per bar that
/// reads the collection, then "3 of 4 samples archived, the most", and offers a Restore action for
/// each archived sample. The container carries the Audio Graph descriptor.
struct ArchiveChart: View {
    let tally: ArchiveTally
    /// Every Restore action on a bar calls this with the sample's ID.
    let restore: (ItemID) -> Void
    @Environment(\.accessSonification) private var route

    var body: some View {
        let semantics = ChartSemantics(tally: tally)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(tally.collections) { collection in
                ArchiveBar(collection: collection, tally: tally, restore: restore)
            }
            ChartKey()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(semantics.title)
        .modifier(AudioGraph(semantics: semantics, route: route))
    }
}

/// One collection's bar: its name, its count in words and digits, and its squares.
private struct ArchiveBar: View {
    let collection: CollectionTally
    let tally: ArchiveTally
    let restore: (ItemID) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var squareHeight: CGFloat = 16

    var body: some View {
        let isLeader = tally.isLeader(collection)
        VStack(alignment: .leading, spacing: 6) {
            // Side by side normally; stacked at accessibility sizes, so neither truncates.
            let heading = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            heading {
                Text(collection.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                // The count and "Most" stack too at accessibility sizes, so "Most" never breaks.
                let figures = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                figures {
                    Text("\(collection.archivedCount) of \(collection.total)")
                        .monospacedDigit()
                    if isLeader {
                        Label(tally.leaders.count > 1 ? "Tied for most" : "Most", systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.subheadline)
            }
            HStack(spacing: 4) {
                ForEach(0..<max(tally.largestCollection, 1), id: \.self) { index in
                    SampleSquare(mark: SampleSquare.Mark(index, of: collection))
                }
            }
            .frame(height: squareHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collection.title)
        .accessibilityValue(ChartSemantics.barValue(collection, in: tally))
        .accessibilityActions {
            ForEach(Self.actionOrder(collection.archived)) { sample in
                Button("Restore \(sample.title.value)") { restore(sample.id) }
            }
        }
    }

    /// The samples in the order their actions are declared, so the actions menu lists them by
    /// title. SwiftUI on macOS 27 lists custom actions in reverse declaration order;
    /// `AccessSuperpowerAccessibilityTests` fails if that changes.
    static func actionOrder(_ samples: [LabItem]) -> [LabItem] {
        #if os(macOS)
        samples.reversed()
        #else
        samples
        #endif
    }
}

/// One sample in a bar. An archived sample is filled and has a solid outline; an active one has
/// only a dashed outline. The outline tells them apart even where the fill's color cannot be
/// seen, and `AccessSuperpowerQualificationHostTests` checks that in grayscale.
struct SampleSquare: View {
    enum Mark: Hashable {
        case archived
        case active
        /// Past the end of a collection smaller than the largest one.
        case none

        init(_ index: Int, of collection: CollectionTally) {
            self = index < collection.archivedCount ? .archived : index < collection.total ? .active : .none
        }
    }

    let mark: Mark
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let increased = contrast == .increased
        switch mark {
        case .archived:
            shape.fill(.tint)
                .overlay(shape.strokeBorder(.primary.opacity(increased ? 1 : 0.35), lineWidth: increased ? 1.5 : 1))
        case .active:
            shape.strokeBorder(.secondary, style: StrokeStyle(lineWidth: increased ? 2 : 1, dash: [3, 2]))
        case .none:
            Color.clear
        }
    }
}

/// What the squares mean, for sighted readers. Hidden from assistive technology, which reads each
/// bar's count in words instead. It names the shapes, not a color, and uses primary text: it is
/// how a reader who cannot tell the fill's color apart decodes the chart.
private struct ChartKey: View {
    var body: some View {
        Text("Each square is one sample: filled with a solid edge when archived, a dashed outline when not.")
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

/// Attaches the Audio Graph descriptor when the route has one.
private struct AudioGraph: ViewModifier {
    let semantics: ChartSemantics
    let route: SonificationRoute

    func body(content: Content) -> some View {
        #if canImport(Accessibility)
        if route == .audioGraph {
            content.accessibilityChartDescriptor(ArchiveChartDescriptor(semantics: semantics))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if canImport(Accessibility)
/// The chart semantics as SwiftUI's chart descriptor source. SwiftUI keeps the first descriptor and
/// asks for updates, so an update rewrites every field.
struct ArchiveChartDescriptor: AXChartDescriptorRepresentable {
    let semantics: ChartSemantics

    func makeChartDescriptor() -> AXChartDescriptor {
        semantics.makeChartDescriptor()
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        semantics.update(descriptor)
    }
}
#endif
