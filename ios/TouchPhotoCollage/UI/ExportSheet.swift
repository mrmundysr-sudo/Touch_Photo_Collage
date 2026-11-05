import SwiftUI
import UIKit

struct ExportSheet: View {
    let project: CollageProject
    let sizeFor: (ExportQuality) -> (Int, Int)
    let onDismiss: () -> Void
    let onSave: (ExportRequest) -> Void
    let onShare: (ExportRequest) -> Void
    let busy: BusyState?

    @State private var format = ExportFormat.jpeg
    @State private var quality = ExportQuality.standard
    @State private var transparent: Bool

    init(project: CollageProject, sizeFor: @escaping (ExportQuality) -> (Int, Int), onDismiss: @escaping () -> Void, onSave: @escaping (ExportRequest) -> Void, onShare: @escaping (ExportRequest) -> Void, busy: BusyState?) {
        self.project = project; self.sizeFor = sizeFor; self.onDismiss = onDismiss; self.onSave = onSave; self.onShare = onShare; self.busy = busy
        _transparent = State(initialValue: project.background.type == .transparent)
    }

    var body: some View {
        let (w, h) = sizeFor(quality)
        let req = ExportRequest(format: format, quality: quality, transparent: transparent && format == .png)
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Format")
                    ChipRow {
                        SelectChip("JPEG · small file", format == .jpeg) { format = .jpeg }
                        SelectChip("PNG · lossless", format == .png) { format = .png }
                    }
                    SectionLabel("Quality")
                    ChipRow {
                        ForEach(ExportQuality.allCases, id: \.self) { q in
                            let (qw, qh) = sizeFor(q)
                            SelectChip("\(q.label) · \(qw) × \(qh)", quality == q) { quality = q }
                        }
                    }
                    Text("\(w) × \(h) pixels · \(format == .jpeg ? "JPEG \(quality.jpegQuality)%" : "PNG")")
                        .font(.bodyMedium).foregroundColor(Palette.onSurfaceVariant).accessibilityIdentifier("exportSummary")
                    if format == .png {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transparent background").font(.labelLarge)
                                TinyLabel("Gaps and margins become see-through")
                            }
                            Spacer()
                            Toggle("Transparent background", isOn: $transparent).labelsHidden().tint(Palette.primary)
                        }
                    }
                    Button("Save to Photos") { onSave(req) }.buttonStyle(FilledButton()).padding(.top, 4)
                        .accessibilityIdentifier("saveToPhotos")
                    Button("Share…") { onShare(req) }.buttonStyle(FilledButton(prominent: false))
                        .accessibilityIdentifier("shareCollage")
                    TinyLabel("Your collage is rendered once from your original photos at full resolution, then encoded a single time, so it is never recompressed.")
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            .background(Palette.background.ignoresSafeArea())
            .disabled(busy != nil)
            .overlay {
                if let b = busy {
                    VStack(spacing: 12) {
                        ProgressView().tint(Palette.primary)
                        Text(b.message).font(.titleMedium)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Palette.surfaceContainerHigh))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("exportBusy")
                }
            }
            .navigationTitle("Save or share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done", action: onDismiss).accessibilityIdentifier("exportDone") } }
        }
        .navigationViewStyle(.stack)
        .presentationDetents([.height(520), .large])
    }
}

/// The system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
