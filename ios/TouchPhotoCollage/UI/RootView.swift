import SwiftUI
import UIKit

private struct GridPick: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var picking = false
    @State private var pendingMode = ProjectMode.collage
    @State private var pendingTemplate: SavedTemplate?
    @State private var grid: GridPick?

    private var pickLimit: Int {
        if pendingTemplate != nil { return 30 }
        switch pendingMode {
        case .compare: return 2
        case .family: return 8
        default: return 30
        }
    }

    var body: some View {
        ZStack {
            switch model.screen {
            case .home:
                HomeView(
                    data: model.home, theme: model.theme, onTheme: model.setTheme,
                    onCreate: { mode in
                        pendingMode = mode; pendingTemplate = nil
                        startPicking()
                    },
                    onOpen: model.openSaved, onDelete: model.deleteProject,
                    onTemplate: { t in
                        pendingTemplate = t; pendingMode = t.mode
                        startPicking()
                    },
                    onDeleteTemplate: model.deleteTemplate
                )
                .transition(.opacity)
            case .editor:
                EditorView(model: model).transition(.opacity)
            }

            if let b = model.busy { BusyOverlay(state: b) }
            VStack {
                Spacer()
                if let t = model.toast { ToastView(toast: t) { model.toast = nil } }
            }
            .padding(.bottom, 24).padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: model.toast)
        }
        .animation(.easeInOut(duration: 0.2), value: model.screen)
        .background(Palette.background.ignoresSafeArea())
        .photoPicker(isPresented: $picking, maxCount: pickLimit, onLoading: model.setLoadingPhotos) { urls, failed in
            model.reportPickFailures(failed)
            handle(urls)
        }
        .sheet(item: $grid, onDismiss: nil) { g in
            GridColumnsSheet(count: g.urls.count) { cols in
                grid = nil
                model.startNew(.grid, urls: g.urls, gridColumns: cols)
            } onCancel: {
                g.urls.forEach(IncomingFiles.discard)
                grid = nil
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.flushPendingSave() }
        }
    }

    private func startPicking() {
        if UITestSupport.seedPhotos {
            // Automated tests cannot drive the out-of-process photo picker; they get synthetic photos instead.
            let n = pendingTemplate?.layout.count ?? (pendingMode == .compare ? 2 : (pendingMode == .family ? 3 : 4))
            handle(TestPhotos.make(count: n))
        } else {
            picking = true
        }
    }

    private func handle(_ urls: [URL]) {
        let t = pendingTemplate
        pendingTemplate = nil
        if urls.isEmpty { return }
        if let t = t {
            model.startFromTemplate(t, urls: urls)
        } else if pendingMode == .grid {
            grid = GridPick(urls: urls)
        } else {
            model.startNew(pendingMode, urls: urls)
        }
    }
}

private struct GridColumnsSheet: View {
    let count: Int
    let onMake: (Int) -> Void
    let onCancel: () -> Void
    @State private var cols: Int

    init(count: Int, onMake: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.count = count; self.onMake = onMake; self.onCancel = onCancel
        _cols = State(initialValue: count <= 4 ? 2 : 3)
    }

    var body: some View {
        let rows = (count + cols - 1) / cols
        VStack(alignment: .leading, spacing: 12) {
            Text("How many columns?").font(.titleLarge)
            Text("\(count) photos in \(cols) columns makes \(rows) \(rows == 1 ? "row" : "rows").").font(.bodyMedium)
            ChipRow {
                ForEach(2...max(2, min(6, count)), id: \.self) { c in
                    SelectChip("\(c)", cols == c) { cols = c }.accessibilityIdentifier("cols-\(c)")
                }
            }
            HStack(spacing: 10) {
                Button("Cancel", action: onCancel).buttonStyle(FilledButton(prominent: false))
                Button("Make grid") { onMake(cols) }.buttonStyle(FilledButton()).accessibilityIdentifier("makeGrid")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .foregroundColor(Palette.onBackground)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.height(260)])
        .interactiveDismissDisabled()
    }
}

private struct BusyOverlay: View {
    let state: BusyState

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                if state.total > 0 {
                    ProgressView(value: Double(state.done), total: Double(state.total)).tint(Palette.primary).frame(width: 200)
                } else {
                    ProgressView().tint(Palette.primary)
                }
                Text(state.message).font(.titleMedium)
                if state.total > 0 {
                    Text("\(state.done) of \(state.total)").font(.bodyMedium).foregroundColor(Palette.onSurfaceVariant)
                }
            }
            .foregroundColor(Palette.onBackground)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 24).fill(Palette.surfaceContainer))
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("busyOverlay")
    }
}

private struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text).font(.bodyMedium).foregroundColor(Color(UIColor.systemBackground)).frame(maxWidth: .infinity, alignment: .leading)
            if let label = toast.actionLabel, let action = toast.action {
                Button(label) {
                    if action == .openPhotos, let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                    dismiss()
                }
                .font(.labelLarge).foregroundColor(Palette.sunny)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.label).opacity(0.92)))
        .onTapGesture(perform: dismiss)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toast")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
