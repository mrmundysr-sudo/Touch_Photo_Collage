import SwiftUI
import UIKit

enum EditorTab: CaseIterable {
    case layout, style, adjust, text, faces

    var label: String {
        switch self {
        case .layout: return "Layout"
        case .style: return "Style"
        case .adjust: return "Adjust"
        case .text: return "Text"
        case .faces: return "Faces"
        }
    }

    var symbol: String {
        switch self {
        case .layout: return "square.grid.2x2"
        case .style: return "circle.lefthalf.filled"
        case .adjust: return "sun.max"
        case .text: return "textformat"
        case .faces: return "face.smiling"
        }
    }
}

struct EditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.verticalSizeClass) private var vSize

    @State private var tab: EditorTab
    @State private var panelOpen = true
    @State private var help = false
    @State private var renaming = false
    @State private var nameText = ""
    @State private var replacing = false
    @State private var adding = false

    init(model: AppModel) {
        self.model = model
        _tab = State(initialValue: model.project?.mode == .family ? .faces : .layout)
    }

    var body: some View {
        if let p = model.project {
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                Group {
                    if landscape {
                        HStack(spacing: 0) {
                            VStack(spacing: 0) { topBar(p); canvasArea(p) }
                            ScrollView { controls(p, panelHeight: nil) }.frame(width: min(380, geo.size.width * 0.46))
                                .background(Palette.surfaceContainer)
                        }
                    } else {
                        VStack(spacing: 0) {
                            topBar(p)
                            canvasArea(p)
                            controls(p, panelHeight: min(max(geo.size.height * 0.27, 150), 230))
                        }
                    }
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .background(
                // each sheet hangs on its own node: several .sheet modifiers on one view can cancel each other
                Color.clear.frame(width: 0, height: 0)
                    .sheet(isPresented: $model.showExport) {
                        ExportSheet(
                            project: p, sizeFor: { model.sizeFor($0) }, onDismiss: { model.showExport = false },
                            onSave: { model.export($0, share: false) }, onShare: { model.export($0, share: true) }, busy: model.busy
                        )
                    }
            )
            .background(
                Color.clear.frame(width: 0, height: 0)
                    .sheet(item: $model.shareItem) { item in ShareSheet(url: item.url).ignoresSafeArea() }
            )
            .sheet(isPresented: Binding(get: { !model.introSeen || help }, set: { if !$0 { model.markIntroSeen(); help = false } })) {
                GestureIntroSheet(
                    pinchEnabled: model.pinchEnabled, onPinchChange: model.setPinchEnabled,
                    sensitivity: model.zoomSensitivity, onSensitivityChange: model.setZoomSensitivity,
                    frameTiming: model.frameTiming, onFrameTimingChange: model.setFrameTiming,
                    onDismiss: { model.markIntroSeen(); help = false }
                )
            }
            .alert("Rename project", isPresented: $renaming) {
                TextField("Name", text: $nameText)
                Button("Rename") { model.rename(String(nameText.prefix(40))) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Photos access is off", isPresented: $model.photosDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Share instead") { model.export(model.lastExportRequest, share: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To save collages to your photo library, allow “Add Photos Only” for Touch Photo Collage in Settings. You can also choose Share and save to Files.")
            }
            .photoPicker(isPresented: $replacing, maxCount: 1, onLoading: model.setLoadingPhotos) { urls, failed in
                model.reportPickFailures(failed)
                if let u = urls.first, let i = model.selection.cell { model.replacePhoto(i, url: u) }
            }
            .photoPicker(isPresented: $adding, maxCount: 20, onLoading: model.setLoadingPhotos) { urls, failed in
                model.reportPickFailures(failed)
                model.addPhotos(urls)
            }
        }
    }

    // MARK: top bar

    private func topBar(_ p: CollageProject) -> some View {
        HStack(spacing: 0) {
            Button { model.closeEditor() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .accessibilityLabel("Back to home").accessibilityIdentifier("backButton")
            Button { nameText = p.name; renaming = true } label: {
                Text(p.name).font(.titleMedium).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Project name \(p.name). Tap to rename.").accessibilityIdentifier("projectName")
            glyphButton("arrow.uturn.backward", "Undo", model.canUndo, "undoButton") { model.undo() }
            glyphButton("arrow.uturn.forward", "Redo", model.canRedo, "redoButton") { model.redo() }
            Button { model.showExport = true } label: {
                Text("Save").font(.titleMedium).foregroundColor(Palette.onPrimary).padding(.horizontal, 18).frame(height: 40)
                    .background(Capsule().fill(Palette.primary))
            }
            .padding(.leading, 4).padding(.trailing, 12)
            .accessibilityIdentifier("saveButton").accessibilityLabel("Save or share")
        }
        .foregroundColor(Palette.onBackground)
        .padding(.leading, 4)
    }

    private func glyphButton(_ symbol: String, _ label: String, _ enabled: Bool, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 48).contentShape(Rectangle())
                .foregroundColor(enabled ? Palette.onBackground : Palette.outlineVariant)
        }
        .disabled(!enabled).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    // MARK: canvas

    private func canvasArea(_ p: CollageProject) -> some View {
        GeometryReader { geo in
            ZStack {
                if model.canvasSize.width > 0 {
                    CollageCanvasView(props: canvasProps(p))
                        .frame(width: model.canvasSize.width, height: model.canvasSize.height)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                let selCell = model.selection.cell.flatMap { p.cells.indices.contains($0) ? p.cells[$0] : nil }
                VStack {
                    HStack {
                        if let c = selCell, c.photo != nil, let i = model.selection.cell {
                            ModeBadge(live: model.live, mode: model.touchMode, cell: i, committedZoom: c.zoom)
                        }
                        Spacer()
                    }
                    Spacer()
                    if model.frameTiming { FrameTimingOverlay() }
                }
                .padding(2)
                if model.facesPending > 0 {
                    VStack {
                        Text("Finding faces…").font(.labelMedium).foregroundColor(Palette.onSecondaryContainer)
                            .padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(Palette.secondaryContainer))
                        Spacer()
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { model.setViewport(geo.size, scale: displayScale) }
            .onChange(of: geo.size) { model.setViewport($0, scale: displayScale) }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func canvasProps(_ p: CollageProject) -> CanvasProps {
        CanvasProps(
            project: p, frame: model.preview, selection: model.selection, mode: model.touchMode, pinchEnabled: model.pinchEnabled,
            sensitivity: model.zoomSensitivity, primary: Palette.uiPrimary, live: model.live, renderer: model.renderer,
            liveImage: { model.liveImage($0) },
            onSelectCell: { model.selectCell($0) }, onSelectText: { model.selectText($0) },
            onTransform: { i, dx, dy, z, fx, fy, w, h in model.transformCell(i, panX: dx, panY: dy, zoomFactor: z, fx: fx, fy: fy, cellW: w, cellH: h) },
            onMoveText: { i, x, y in model.moveText(i, nx: x, ny: y) },
            onSwap: { model.swapCells($0, $1) },
            onGestureEnd: { model.endLive() },
            onCommit: { i, z, cx, cy in model.commitCrop(i, zoom: z, cx: cx, cy: cy) },
            onZoomStep: { f in if let c = model.selection.cell { model.stepCell(c, panFracX: 0, panFracY: 0, zoomFactor: f) } },
            onPanStep: { dx, dy in if let c = model.selection.cell { model.stepCell(c, panFracX: dx, panFracY: dy, zoomFactor: 1) } },
            onReset: { if let c = model.selection.cell { model.resetCell(c) } }
        )
    }

    // MARK: controls

    private func controls(_ p: CollageProject, panelHeight: CGFloat?) -> some View {
        let selIndex = model.selection.cell
        let selected = selIndex.flatMap { p.cells.indices.contains($0) ? p.cells[$0] : nil }.flatMap { $0.photo != nil ? $0 : nil }
        return VStack(spacing: 4) {
            GestureModeBar(
                mode: model.touchMode, onModeChange: model.setTouchMode,
                onReset: { if let i = selIndex { model.resetCell(i) } },
                hasTarget: selected != nil, onHelp: { help = true },
                zoomLabel: selected.flatMap { c in selIndex.map { AnyView(ZoomReadout(live: model.live, cell: $0, committedZoom: c.zoom)) } }
            )
            if let i = selIndex, let cell = selected {
                ChipRow {
                    ToolChip(symbol: "rotate.right", label: "Rotate") { model.rotateCell(i) }
                    ToolChip(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Mirror") { model.mirrorCell(i) }
                    ToolChip(symbol: cell.fit ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", label: cell.fit ? "Fill" : "Fit whole") { model.toggleFit(i) }
                    ToolChip(symbol: "scope", label: "Reset crop") { model.resetCell(i) }
                    ToolChip(symbol: "photo", label: "Replace") { replacing = true }
                    if i > 0 { ToolChip(symbol: "chevron.left", label: "Move earlier") { model.moveCell(i, delta: -1) } }
                    if i < p.cells.count - 1 { ToolChip(symbol: "chevron.right", label: "Move later") { model.moveCell(i, delta: 1) } }
                    if p.photoCount > 1 { ToolChip(symbol: "xmark", label: "Remove") { model.removeCell(i) } }
                }
                .padding(.horizontal, 12)
            }
            tabsAndPanel(p, panelHeight: panelHeight)
        }
        .padding(.top, 4)
    }

    private func tabsAndPanel(_ p: CollageProject, panelHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(EditorTab.allCases, id: \.self) { t in
                    let sel = t == tab && panelOpen
                    Button {
                        if t == tab { panelOpen.toggle() } else { tab = t; panelOpen = true }
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: t.symbol).font(.system(size: 17))
                            Text(t.label).font(.labelSmall)
                        }
                        .foregroundColor(sel ? Palette.onPrimaryContainer : Palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(sel ? Palette.primaryContainer : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(t.label) tab").accessibilityIdentifier("tab-\(t.label)")
                    .accessibilityAddTraits(sel ? .isSelected : [])
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            if panelOpen {
                let content = ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case .layout:
                            LayoutPanel(model: model, p: p)
                            Button { adding = true } label: { Label("Add more photos", systemImage: "plus") }
                                .font(.labelLarge).foregroundColor(Palette.primary).frame(minHeight: 44).accessibilityIdentifier("addPhotos")
                        case .style: StylePanel(model: model, p: p)
                        case .adjust: AdjustPanel(model: model, p: p, selected: model.selection.cell)
                        case .text: TextPanel(model: model, p: p, selectedText: model.selection.text)
                        case .faces: FacesPanel(model: model, p: p, selected: model.selection.cell, facesPending: model.facesPending)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                if let h = panelHeight { content.frame(height: h) } else { content }
            }
        }
        .foregroundColor(Palette.onBackground)
        .background(
            UnevenRoundedRectangleShim(radius: 24).fill(Palette.surfaceContainer).ignoresSafeArea(edges: .bottom)
        )
    }
}

/// A rectangle with rounded top corners only (iOS 16 compatible).
struct UnevenRoundedRectangleShim: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
