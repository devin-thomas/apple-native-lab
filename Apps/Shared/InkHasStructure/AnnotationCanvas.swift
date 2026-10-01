import InkHasStructure
import SwiftUI

/// Pointer/touch drawing surface over the sample media. PencilKit's `PKCanvasView` is iOS-only; on
/// Mac this is the declared mouse path. Unsupported Pencil gestures are not offered here.
struct AnnotationCanvas: View {
    @Bindable var session: InkSession
    var showsPencilKit: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                mediaBackground
                strokes(in: geometry.size)
                notes(in: geometry.size)
                #if os(iOS)
                if showsPencilKit, session.capability.pencilKitCanvasAvailable {
                    PencilKitAnnotationCanvas(session: session, size: geometry.size)
                        .opacity(0.01) // receives input; strokes are mirrored into the domain layer above
                        .accessibilityLabel("PencilKit canvas, finger or Pencil")
                }
                #endif
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(in: geometry.size), including: showsPencilKit ? .subviews : .all)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Harbor chart annotation canvas")
            .accessibilityHint("Draw with the pointer or touch, or add a typed note below.")
        }
        .aspectRatio(CGSize(width: SampleMedia.harborChart.width, height: SampleMedia.harborChart.height), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
    }

    private var mediaBackground: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.35))
            VStack(spacing: 4) {
                Text(SampleMedia.harborChart.title)
                    .font(.headline)
                Text(SampleMedia.harborChart.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func strokes(in size: CGSize) -> some View {
        if let document = session.document {
            ForEach(document.layer.strokes) { stroke in
                Path { path in
                    let points = stroke.points.map { $0.point(in: document.size) }
                    guard let first = points.first else { return }
                    let sx = size.width / document.size.width
                    let sy = size.height / document.size.height
                    path.move(to: CGPoint(x: first.x * sx, y: first.y * sy))
                    for point in points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * sx, y: point.y * sy))
                    }
                }
                .stroke(strokeColor(stroke.tool), style: StrokeStyle(
                    lineWidth: max(2, stroke.width * min(size.width, size.height)),
                    lineCap: .round,
                    lineJoin: .round
                ))
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func notes(in size: CGSize) -> some View {
        if let document = session.document {
            ForEach(document.notes) { note in
                let point = note.anchor.point(in: document.size)
                let sx = size.width / document.size.width
                let sy = size.height / document.size.height
                Text(note.text)
                    .font(.caption.weight(.semibold))
                    .padding(4)
                    .background(.thinMaterial, in: .rect(cornerRadius: 4))
                    .position(x: point.x * sx, y: point.y * sy)
                    .allowsHitTesting(false)
            }
        }
    }

    private func drawGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.translation == .zero {
                    session.beginStroke(at: value.location, in: size)
                } else {
                    session.continueStroke(to: value.location)
                }
            }
            .onEnded { _ in
                Task { await session.endStroke(in: size) }
            }
    }

    private func strokeColor(_ tool: InkTool) -> Color {
        switch tool {
        case .pen: .primary
        case .marker: .orange.opacity(0.7)
        case .pencil: .secondary
        }
    }
}

#if os(iOS)
import PencilKit
import UIKit

/// PencilKit canvas with `drawingPolicy = .anyInput` so non-Pencil users can draw. Squeeze, hover
/// tools, and double-tap customization are not configured — they stay absent.
struct PencilKitAnnotationCanvas: UIViewRepresentable {
    @Bindable var session: InkSession
    let size: CGSize

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvas.delegate = context.coordinator
        // No PKToolPicker observer and no pencil interaction overrides: unsupported gestures absent.
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.session = session
        context.coordinator.viewSize = size
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session, viewSize: size) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var session: InkSession
        var viewSize: CGSize

        init(session: InkSession, viewSize: CGSize) {
            self.session = session
            self.viewSize = viewSize
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let document = session.document, viewSize.width > 0, viewSize.height > 0 else { return }
            var strokes: [InkStroke] = []
            for pkStroke in canvasView.drawing.strokes {
                var points: [AnnotationAnchor] = []
                let path = pkStroke.path
                guard path.count >= 2 else { continue }
                let step = max(1, path.count / 32)
                for index in stride(from: 0, to: path.count, by: step) {
                    let location = path[index].location
                    if let anchor = try? AnnotationAnchor(
                        x: min(1, max(0, location.x / viewSize.width)),
                        y: min(1, max(0, location.y / viewSize.height))
                    ) {
                        points.append(anchor)
                    }
                }
                if let last = path.last?.location,
                   let anchor = try? AnnotationAnchor(
                       x: min(1, max(0, last.x / viewSize.width)),
                       y: min(1, max(0, last.y / viewSize.height))
                   ), points.last != anchor {
                    points.append(anchor)
                }
                if let stroke = try? InkStroke(tool: .pen, width: 0.02, points: points) {
                    strokes.append(stroke)
                }
            }
            Task { @MainActor in
                await session.adoptPencilKitStrokes(strokes)
                _ = document
            }
        }
    }
}
#endif
