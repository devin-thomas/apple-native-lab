import SwiftUI

/// The sizes the widget's content is drawn at.
public enum SessionWidgetLayout: String, CaseIterable, Sendable {
    case small
    case medium
    /// The Lock Screen's rectangular slot.
    case accessory
}

/// The widget's content, drawn from one `SurfacePresentation`.
///
/// The widget extension draws it inside WidgetKit with an interactive toggle; the app draws the
/// same view as a labeled preview with a toggle that only shows its state. It uses SwiftUI only,
/// so the CoreLocal app can draw it without linking WidgetKit.
public struct SessionWidgetView<Toggle: View>: View {
    let presentation: SurfacePresentation
    let layout: SessionWidgetLayout
    let toggle: Toggle

    public init(presentation: SurfacePresentation, layout: SessionWidgetLayout, @ViewBuilder toggle: () -> Toggle) {
        self.presentation = presentation
        self.layout = layout
        self.toggle = toggle()
    }

    public var body: some View {
        switch layout {
        case .small: small
        case .medium: medium
        case .accessory: accessory
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            stateLine
            status(showsRedaction: true)
            if presentation.state != nil {
                toggle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                stateLine
                // The right column says whether details are hidden, so this one does not repeat it.
                status(showsRedaction: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 8) {
                detail
                Spacer(minLength: 0)
                if presentation.state != nil {
                    toggle
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(SurfaceDeck.sessionName, systemImage: presentation.symbolName)
                .font(.headline)
            Text(presentation.stateTitle)
            if let detail = presentation.detailText {
                Text(detail)
                    .privacySensitive()
            } else {
                Text(presentation.statusText)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var header: some View {
        Label(SurfaceDeck.sessionName, systemImage: presentation.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var stateLine: some View {
        Text(presentation.stateTitle)
            .font(.title2.weight(.bold))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func status(showsRedaction: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch presentation.availability {
            case .stale:
                Label(presentation.statusText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .unavailable:
                Text(presentation.statusText)
                    .foregroundStyle(.secondary)
            case .current:
                if showsRedaction {
                    Text(presentation.statusText)
                        .foregroundStyle(.secondary)
                }
            }
            if let writtenAt = presentation.writtenAt {
                Text("As of \(writtenAt, format: .dateTime.hour().minute())")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }

    @ViewBuilder private var detail: some View {
        if let detail = presentation.detail {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.detailText ?? "")
                Text("at \(detail.changedAt, format: .dateTime.hour().minute())")
            }
            .font(.caption)
            .privacySensitive()
        } else if presentation.state != nil {
            Label("Details hidden", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// How a toggle looks when it only shows a state, for previews drawn in the app.
public struct SessionToggleLook: View {
    let isOn: Bool

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    /// Drawn like the widget's toggle: its label, filled with the tint when on.
    public var body: some View {
        Text("Running")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
            .accessibilityHidden(true)
    }
}

/// How the Control looks in Control Center, for the preview drawn in the app. The system draws the
/// real Control from `ControlWidgetToggle`; this is a picture of it, labeled as one.
public struct SessionControlPreview: View {
    let presentation: SurfacePresentation

    public init(presentation: SurfacePresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: presentation.symbolName)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(presentation.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .circle)
                .foregroundStyle(presentation.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            VStack(alignment: .leading, spacing: 2) {
                Text(SurfaceDeck.sessionName)
                    .font(.subheadline.weight(.semibold))
                Text(presentation.state == nil ? "Open Native Lab" : presentation.stateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
