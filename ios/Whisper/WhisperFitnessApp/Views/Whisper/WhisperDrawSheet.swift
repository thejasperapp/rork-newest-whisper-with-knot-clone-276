import SwiftUI
import PencilKit

/// Full-screen drawing canvas for the DM composer's Draw action. Backed by
/// PencilKit so finger + Apple Pencil both work. On Send we rasterize the
/// canvas to a transparent PNG sized to the visible bounds and hand it back
/// to the thread to upload + send as an image message.
struct WhisperDrawSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onSend: (UIImage) -> Void

    @State private var canvas = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var canvasSize: CGSize = .zero
    @State private var hasStrokes: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                GeometryReader { geo in
                    DrawCanvas(canvas: $canvas, toolPicker: $toolPicker, hasStrokes: $hasStrokes)
                        .onAppear { canvasSize = geo.size }
                        .onChange(of: geo.size) { _, new in canvasSize = new }
                }
            }
            .navigationTitle("Draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            canvas.drawing = PKDrawing()
                            hasStrokes = false
                        } label: {
                            Image(systemName: "trash")
                                .font(.body.weight(.semibold))
                        }
                        .disabled(!hasStrokes)
                        // Send pinned top-right so the PencilKit tool palette
                        // at the bottom can't cover it.
                        Button {
                            Haptics.success()
                            let image = renderDrawing()
                            dismiss()
                            onSend(image)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                Text("Send")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(hasStrokes ? Color.black : Color.gray.opacity(0.4), in: Capsule())
                        }
                        .disabled(!hasStrokes)
                    }
                }
            }
        }
    }

    private func renderDrawing() -> UIImage {
        let bounds = canvas.drawing.bounds.isEmpty
            ? CGRect(origin: .zero, size: canvasSize == .zero ? CGSize(width: 1024, height: 1024) : canvasSize)
            : canvas.drawing.bounds.insetBy(dx: -24, dy: -24)
        return canvas.drawing.image(from: bounds, scale: UIScreen.main.scale)
    }
}

private struct DrawCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    @Binding var hasStrokes: Bool

    func makeCoordinator() -> Coordinator { Coordinator(hasStrokes: $hasStrokes) }

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        DispatchQueue.main.async {
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let hasStrokes: Binding<Bool>
        init(hasStrokes: Binding<Bool>) { self.hasStrokes = hasStrokes }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let any = !canvasView.drawing.strokes.isEmpty
            if hasStrokes.wrappedValue != any { hasStrokes.wrappedValue = any }
        }
    }
}
