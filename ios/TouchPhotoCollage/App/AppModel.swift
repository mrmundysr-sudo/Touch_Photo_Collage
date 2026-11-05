import Foundation
import UIKit
import SwiftUI
import Combine

enum AppScreen { case home, editor }
enum ThemeMode: String { case system = "SYSTEM", light = "LIGHT", dark = "DARK" }

struct HomeData { var recents: [ProjectSummary] = []; var templates: [SavedTemplate] = [] }
struct EditSelection: Equatable { var cell: Int? = nil; var text: Int? = nil }
struct BusyState: Equatable { var message: String; var done = 0; var total = 0 }
struct PreviewFrame { var image: CGImage; var textBounds: [CGRect]; var forProject: CollageProject }
struct ShareItem: Identifiable { let id = UUID(); let url: URL }

struct Toast: Identifiable, Equatable {
    enum Action: Equatable { case openPhotos }
    let id = UUID()
    var text: String
    var actionLabel: String? = nil
    var action: Action? = nil
}

/// Picked photos are first copied to a private temporary folder; once imported they are deleted again.
enum IncomingFiles {
    static let folderName = "tpc-incoming"

    static var directory: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func discard(_ url: URL) {
        if url.deletingLastPathComponent().lastPathComponent == folderName { try? FileManager.default.removeItem(at: url) }
    }
}

/// Command-line switches used by the automated UI tests (never set in normal use).
enum UITestSupport {
    static let args = ProcessInfo.processInfo.arguments
    static var seedPhotos: Bool { args.contains("-UITestSeed") }
    static var reset: Bool { args.contains("-UITestReset") }
    static var introSeen: Bool { args.contains("-UITestIntroSeen") }
    static let gestureKeys = ["touch_gesture_mode", "touch_gesture_pinch", "touch_gesture_zoom_sensitivity", "touch_gesture_frame_timing", "touch_gesture_intro_seen"]
    static var theme: ThemeMode? {
        guard let i = args.firstIndex(of: "-UITestTheme"), i + 1 < args.count else { return nil }
        return ThemeMode(rawValue: args[i + 1].uppercased())
    }
}

/// App state and every user action. Port of the Android `CollageViewModel`: same undo/redo, autosave, live-gesture
/// commit, face detection and export flow.
@MainActor
final class AppModel: ObservableObject {
    // storage
    let root: URL
    let store: ProjectStore
    private let templateStore: TemplateStore
    private let importer: ImageImporter
    private let exporter: Exporter
    private let faceFinder: FaceFinder
    private let provider: FileImageProvider
    let renderer: CollageRenderer
    private let gestureSettings: GestureSettings
    private let defaults = UserDefaults.standard

    // published state
    @Published private(set) var screen = AppScreen.home
    @Published private(set) var home = HomeData()
    @Published private(set) var project: CollageProject?
    @Published private(set) var selection = EditSelection()
    @Published private(set) var preview: PreviewFrame?
    @Published private(set) var busy: BusyState?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var facesPending = 0
    @Published private(set) var canvasSize = CGSize.zero
    @Published var theme: ThemeMode
    @Published private(set) var touchMode: TouchMode
    @Published private(set) var pinchEnabled: Bool
    @Published private(set) var introSeen: Bool
    @Published private(set) var zoomSensitivity: Double
    @Published private(set) var frameTiming: Bool
    @Published var toast: Toast?
    @Published var photosDenied = false
    @Published var shareItem: ShareItem?
    @Published var showExport = false
    private(set) var lastExportRequest = ExportRequest()

    /// Live (uncommitted) crop of the photo being dragged; see `LiveGesture`.
    let live = LiveGesture()

    private var undoStack: [CollageProject] = []
    private var redoStack: [CollageProject] = []
    private var liveOpen = false
    private var facesCache: [String: [FRect]] = [:]
    private var faceJobs = Set<String>()
    private let faceQueue = DispatchQueue(label: "faces", qos: .userInitiated)
    private var saveTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var viewport = CGSize.zero
    private var scale: CGFloat = 3
    private(set) var canvasPixels = (w: 0, h: 0)

    static let liveMaxSide = 2048

    init(root: URL? = nil) {
        let base = root ?? AppModel.defaultRoot()
        if UITestSupport.reset { try? FileManager.default.removeItem(at: base) }
        let st = ProjectStore(root: base)
        if UITestSupport.reset { for k in UITestSupport.gestureKeys { UserDefaults.standard.removeObject(forKey: k) } }
        let gs = GestureSettings(defaults: .standard)
        if UITestSupport.introSeen { gs.introSeen = true }
        let cacheBytes = Int(min(ProcessInfo.processInfo.physicalMemory / 8, 512 * 1024 * 1024))
        let prov = FileImageProvider(mediaDir: st.mediaDir, cacheBytes: cacheBytes)
        self.root = base
        store = st
        templateStore = TemplateStore(root: base)
        importer = ImageImporter(mediaDir: st.mediaDir)
        exporter = Exporter(mediaDir: st.mediaDir)
        faceFinder = VisionFaceFinder()
        provider = prov
        renderer = CollageRenderer(provider: prov)
        gestureSettings = gs
        theme = UITestSupport.theme ?? ThemeMode(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system
        touchMode = gs.mode
        pinchEnabled = gs.pinchEnabled
        introSeen = gs.introSeen
        zoomSensitivity = gs.zoomSensitivity
        frameTiming = gs.showFrameTiming
        refreshHome()
    }

    static func defaultRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("collage", isDirectory: true)
    }

    // MARK: home

    func refreshHome() {
        let store = self.store, templates = self.templateStore
        Task {
            let data = await Task.detached(priority: .userInitiated) { HomeData(recents: store.list(), templates: templates.list()) }.value
            self.home = data
        }
    }

    func setTheme(_ m: ThemeMode) { theme = m; defaults.set(m.rawValue, forKey: "theme") }
    func setTouchMode(_ m: TouchMode) { touchMode = m; gestureSettings.mode = m }
    func setPinchEnabled(_ on: Bool) { pinchEnabled = on; gestureSettings.pinchEnabled = on }
    func setZoomSensitivity(_ v: Double) { let c = OneFingerMath.clampSensitivity(v); zoomSensitivity = c; gestureSettings.zoomSensitivity = c }
    func setFrameTiming(_ on: Bool) { frameTiming = on; gestureSettings.showFrameTiming = on }
    func markIntroSeen() { introSeen = true; gestureSettings.introSeen = true }

    func deleteProject(_ id: String) {
        let store = self.store
        Task {
            await Task.detached { store.delete(id) }.value
            refreshHome()
        }
    }

    func deleteTemplate(_ id: String) {
        let t = templateStore
        Task {
            await Task.detached { t.delete(id) }.value
            refreshHome()
        }
    }

    // MARK: toasts

    func showToast(_ text: String, actionLabel: String? = nil, action: Toast.Action? = nil) {
        let t = Toast(text: text, actionLabel: actionLabel, action: action)
        toast = t
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled, toast?.id == t.id { toast = nil }
        }
    }

    // MARK: creation

    private func importAll(_ urls: [URL], label: String) async -> [PhotoRef] {
        var failed = 0
        var out: [PhotoRef] = []
        busy = BusyState(message: label, done: 0, total: urls.count)
        let importer = self.importer
        for (i, u) in urls.enumerated() {
            let ref = await Task.detached(priority: .userInitiated) { try? importer.importFile(at: u) }.value
            if let ref = ref { out.append(ref) } else { failed += 1 }
            IncomingFiles.discard(u)
            busy = BusyState(message: label, done: i + 1, total: urls.count)
        }
        busy = nil
        if failed > 0 {
            showToast(failed == urls.count ? "Those photos couldn't be opened." : "\(failed) photo(s) couldn't be opened and were skipped.")
        }
        return out
    }

    func startNew(_ mode: ProjectMode, urls: [URL], gridColumns: Int = 3) {
        if urls.isEmpty { return }
        Task {
            let refs = await importAll(urls, label: "Importing photos")
            if refs.isEmpty { return }
            if (mode == .compare || mode == .family) && refs.count < 2 {
                let store = self.store
                await Task.detached { store.collectGarbage() }.value
                showToast(mode == .compare ? "Pick two photos to compare." : "Pick at least two photos for Family Resemblance.")
                return
            }
            let m: ProjectMode = (mode == .compare && refs.count != 2) ? .collage : mode
            open(ProjectOps.create(photos: refs.map(withCachedFaces), mode: m, now: nowMs(), gridColumns: gridColumns))
        }
    }

    func startFromTemplate(_ t: SavedTemplate, urls: [URL]) {
        if urls.isEmpty { return }
        Task {
            let refs = await importAll(Array(urls.prefix(t.layout.count)), label: "Importing photos")
            if refs.isEmpty { return }
            open(ProjectOps.fromTemplate(t, photos: refs, now: nowMs()))
        }
    }

    func openSaved(_ id: String) {
        let store = self.store
        Task {
            let p = await Task.detached { store.load(id) }.value
            if let p = p { open(p, save: false) } else { showToast("That project couldn't be opened.") }
        }
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func open(_ p: CollageProject, save: Bool = true) {
        undoStack.removeAll(); redoStack.removeAll(); liveOpen = false; updateUndoFlags()
        preview = nil
        selection = EditSelection()
        live.clear()
        for c in p.cells { if let ph = c.photo, let f = ph.faces { facesCache[ph.id] = f } }
        setProject(p)
        screen = .editor
        if save { scheduleSave(immediately: true) }
        ensureFaces()
    }

    /// Leave the editor: save the project and a thumbnail, return home.
    func closeEditor() {
        let p = project
        saveTask?.cancel()
        let store = self.store
        Task {
            if let p = p { await Task.detached { AppModel.persist(store, p, thumb: true) }.value }
            screen = .home
            project = nil
            preview = nil
            live.clear()
            showExport = false
            provider.clear()
            refreshHome()
        }
    }

    nonisolated static func persist(_ store: ProjectStore, _ p: CollageProject, thumb: Bool) {
        var stamped = p
        stamped.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try? store.save(stamped)
        if thumb {
            let (w, h) = LayoutEngine.sizeForLongSide(p.canvas, longSide: 480)
            let r = CollageRenderer(provider: FileImageProvider(mediaDir: store.mediaDir, cacheBytes: 0))
            if let img = r.render(p, width: w, height: h), let data = ImageIOUtil.encode(img, as: .jpeg, quality: 0.85) {
                store.saveThumb(p.id, jpeg: data)
            }
        }
    }

    private func scheduleSave(immediately: Bool = false) {
        saveTask?.cancel()
        let store = self.store
        saveTask = Task {
            if !immediately { try? await Task.sleep(nanoseconds: 700_000_000) }
            guard !Task.isCancelled, let p = project else { return }
            await Task.detached { AppModel.persist(store, p, thumb: immediately) }.value
        }
    }

    /// Called when the app leaves the foreground: write pending work right away, because iOS may end the process.
    func flushPendingSave() {
        guard let p = project, screen == .editor else { return }
        saveTask?.cancel()
        AppModel.persist(store, p, thumb: false)
    }

    // MARK: editing core

    func setViewport(_ size: CGSize, scale: CGFloat) {
        viewport = size; self.scale = max(1, scale)
        recomputeCanvas()
    }

    private func recomputeCanvas() {
        guard let p = project, viewport.width > 1, viewport.height > 1 else { return }
        let (pw, ph) = AppModel.fitInside(availW: Int(viewport.width * scale), availH: Int(viewport.height * scale), aspect: p.canvas.aspect)
        if pw != canvasPixels.w || ph != canvasPixels.h {
            canvasPixels = (pw, ph)
            canvasSize = CGSize(width: CGFloat(pw) / scale, height: CGFloat(ph) / scale)
        }
        scheduleRender()
    }

    static func fitInside(availW: Int, availH: Int, aspect: Double) -> (Int, Int) {
        var w = Double(availW)
        var h = w / aspect
        if h > Double(availH) { h = Double(availH); w = h * aspect }
        return (max(1, Int(w)), max(1, Int(h)))
    }

    private func setProject(_ p: CollageProject?) {
        let aspectChanged = project?.canvas != p?.canvas
        project = p
        if aspectChanged { recomputeCanvas() } else { scheduleRender() }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        guard let p = project, canvasPixels.w > 0 else { return }
        let (pw, ph) = (canvasPixels.w, canvasPixels.h)
        let pts = canvasSize
        let renderer = self.renderer
        renderTask = Task { [weak self] in
            // Coalesce bursts of edits (slider drags): only the newest request actually renders.
            try? await Task.sleep(nanoseconds: 10_000_000)
            if Task.isCancelled { return }
            let frame = await Task.detached(priority: .userInitiated) { () -> PreviewFrame? in
                if Task.isCancelled { return nil }
                guard let img = renderer.render(p, width: pw, height: ph, options: .init(keepTransparent: true, showPlaceholders: true)) else { return nil }
                return PreviewFrame(image: img, textBounds: renderer.textBounds(p, width: Double(pts.width), height: Double(pts.height)), forProject: p)
            }.value
            if Task.isCancelled { return }
            if let frame = frame { self?.preview = frame }
        }
    }

    private func updateUndoFlags() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }

    private func push(_ cur: CollageProject) {
        undoStack.append(cur)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
        updateUndoFlags()
    }

    /// Apply an edit. `live` edits (sliders, drags) record one undo step for the whole gesture; call `endLive` when the
    /// gesture finishes.
    func edit(live: Bool = false, _ f: (CollageProject) -> CollageProject) {
        guard let cur = project else { return }
        let next = f(cur)
        if next == cur { return }
        if live { if !liveOpen { push(cur); liveOpen = true } } else { push(cur); liveOpen = false }
        setProject(next)
        scheduleSave()
    }

    func endLive() { liveOpen = false }

    func undo() {
        guard let cur = project, let prev = undoStack.popLast() else { return }
        redoStack.append(cur)
        liveOpen = false
        setProject(mergeFaces(prev)); fixSelection(); updateUndoFlags(); scheduleSave()
    }

    func redo() {
        guard let cur = project, let next = redoStack.popLast() else { return }
        undoStack.append(cur)
        liveOpen = false
        setProject(mergeFaces(next)); fixSelection(); updateUndoFlags(); scheduleSave()
    }

    private func fixSelection() {
        guard let p = project else { return }
        selection = EditSelection(cell: selection.cell.flatMap { $0 < p.cells.count ? $0 : nil }, text: selection.text.flatMap { $0 < p.texts.count ? $0 : nil })
    }

    private func withCachedFaces(_ ref: PhotoRef) -> PhotoRef {
        if ref.faces == nil, let f = facesCache[ref.id] { var r = ref; r.faces = f; return r }
        return ref
    }

    private func mergeFaces(_ p: CollageProject) -> CollageProject {
        var q = p
        q.cells = p.cells.map { c in
            guard let ph = c.photo else { return c }
            var n = c; n.photo = withCachedFaces(ph); return n
        }
        return q
    }

    func selectCell(_ i: Int?) {
        let new = EditSelection(cell: i, text: nil)
        if new != selection { selection = new }
        if let i = i { prefetchLive(i) }
    }

    func selectText(_ i: Int?) {
        let new = EditSelection(cell: nil, text: i)
        if new != selection { selection = new }
    }

    /// Longest side (px) of the image used for live dragging: sharp enough to zoom, small enough to stay fast.
    private func liveSample(_ ref: PhotoRef) -> Int {
        var s = 1
        let long = max(ref.width, ref.height)
        while long / s > AppModel.liveMaxSide { s *= 2 }
        return s
    }

    /// Image for live dragging of cell `index`; cached, so after `prefetchLive` it costs nothing. Decoding here (cache
    /// miss) is the only blocking work a gesture can ever trigger, and only once per photo.
    func liveImage(_ index: Int) -> CGImage? {
        guard let p = project, p.cells.indices.contains(index), let ref = p.cells[index].photo else { return nil }
        return provider.image(for: ref, sample: liveSample(ref))
    }

    private func prefetchLive(_ index: Int) {
        guard let p = project, p.cells.indices.contains(index), let ref = p.cells[index].photo else { return }
        let provider = self.provider, s = liveSample(ref)
        Task.detached(priority: .userInitiated) { _ = provider.image(for: ref, sample: s) }
    }

    /// Commit the final crop of a drag/zoom as one undoable edit. Full float precision, no rounding.
    func commitCrop(_ index: Int, zoom: Double, cx: Double, cy: Double) {
        edit { p in
            var q = p
            guard q.cells.indices.contains(index) else { return p }
            q.cells[index].zoom = zoom; q.cells[index].cx = cx; q.cells[index].cy = cy; q.cells[index].manual = true
            return q
        }
    }

    // MARK: face detection

    private func ensureFaces() {
        guard let p = project else { return }
        let pending = p.cells.compactMap { $0.photo }.filter { $0.faces == nil && !faceJobs.contains($0.id) }
        for ref in pending {
            faceJobs.insert(ref.id)
            facesPending += 1
            let finder = faceFinder, dir = store.mediaDir
            faceQueue.async { [weak self] in
                let faces = finder.find(ref: ref, mediaDir: dir) ?? []
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.facesCache[ref.id] = faces
                    if let cur = self.project { self.setProject(ProjectOps.withFaces(cur, photoId: ref.id, faces: faces)) }
                    self.undoStack = self.undoStack.map { self.mergeFaces($0) }
                    self.faceJobs.remove(ref.id)
                    self.facesPending -= 1
                    self.scheduleSave()
                }
            }
        }
    }

    // MARK: cell gestures

    /// Pan/zoom one cell without a live layer (fallback when the image could not be decoded for live dragging).
    func transformCell(_ index: Int, panX: Double, panY: Double, zoomFactor: Double, fx: Double, fy: Double, cellW: Double, cellH: Double) {
        edit(live: true) { p in
            guard p.cells.indices.contains(index), let ph = p.cells[index].photo else { return p }
            let c = p.cells[index]
            let aspect = Orientation.displaySize(ph.width, ph.height, exif: ph.exif, quarterTurns: c.rotation).aspect
            var z = c.zoom, cx = c.cx, cy = c.cy
            if zoomFactor != 1 {
                (z, cx, cy) = CropMath.zoomAbout(imgAspect: aspect, cellAspect: cellW / cellH, zoom: z, cx: cx, cy: cy, fit: c.fit, newZoom: z * zoomFactor, fx: fx, fy: fy)
            }
            if panX != 0 || panY != 0 {
                (cx, cy) = CropMath.pan(imgAspect: aspect, cellW: cellW, cellH: cellH, zoom: z, cx: cx, cy: cy, fit: c.fit, dx: panX, dy: panY)
            }
            var q = p
            q.cells[index].zoom = z; q.cells[index].cx = cx; q.cells[index].cy = cy; q.cells[index].manual = true
            return q
        }
    }

    /// One discrete move/zoom step (VoiceOver actions, keyboards). Pan is a fraction of the cell size.
    func stepCell(_ index: Int, panFracX: Double, panFracY: Double, zoomFactor: Double) {
        guard let p = project, canvasSize.width > 0 else { return }
        let rects = CollageRenderer.cellRects(p, width: Double(canvasSize.width), height: Double(canvasSize.height))
        guard rects.indices.contains(index) else { return }
        let r = rects[index]
        transformCell(index, panX: panFracX * r.w, panY: panFracY * r.h, zoomFactor: zoomFactor, fx: 0.5, fy: 0.5, cellW: r.w, cellH: r.h)
        endLive()
    }

    func swapCells(_ a: Int, _ b: Int) {
        edit { ProjectOps.swapCells($0, a, b) }
        selection = EditSelection(cell: b, text: nil)
    }

    func moveCell(_ from: Int, delta: Int) {
        let to = from + delta
        edit { ProjectOps.moveCell($0, from: from, to: to) }
        if to >= 0 && to < (project?.cells.count ?? 0) { selection = EditSelection(cell: to, text: nil) }
    }

    func moveText(_ index: Int, nx: Double, ny: Double) {
        edit(live: true) { p in
            var q = p
            guard q.texts.indices.contains(index) else { return p }
            q.texts[index].x = min(max(nx, 0.02), 0.98)
            q.texts[index].y = min(max(ny, 0.02), 0.98)
            return q
        }
    }

    // MARK: layout & style

    func setLayout(_ l: LayoutTemplate) { edit { ProjectOps.withLayout($0, l) } }
    func setCanvas(_ c: CanvasSpec) { edit { ProjectOps.withLayout($0, $0.layout, canvas: c) } }

    func autoLayout() {
        edit { p in
            let photos = p.cells.compactMap { $0.photo }
            if photos.isEmpty { return p }
            var q = p
            q.cells = p.cells.map { var c = $0; c.manual = false; return c }
            return ProjectOps.withPhotos(q, photos)
        }
    }

    func shuffleArtistic() {
        edit { p in
            let n = p.layout.count
            if n < 2 { return p }
            let seed = Int.random(in: 0...0xFFFF)
            var l = LayoutGenerator.mosaic(n, seed: seed)
            l.name = "Artistic"
            return ProjectOps.withLayout(p, l)
        }
    }

    func setStyle(live: Bool = true, _ f: (inout CollageStyle) -> Void) {
        edit(live: live) { p in
            var q = p
            f(&q.style)
            return ProjectOps.autoCrop(q)
        }
    }

    func setBackground(_ bg: CanvasBackground) { edit { var q = $0; q.background = bg; return q } }
    func rename(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edit { var q = $0; q.name = t.isEmpty ? "Untitled collage" : t; return q }
    }

    func setFaceMode(_ mode: FaceMode) {
        edit { p in
            var q = p
            q.faceMode = mode
            q.cells = p.cells.map { var c = $0; c.manual = false; return c }
            return ProjectOps.autoCrop(q)
        }
    }

    func resetCrops() {
        edit { p in
            var q = p
            q.cells = p.cells.map { var c = $0; c.manual = false; return c }
            return ProjectOps.autoCrop(q)
        }
    }

    func setAvoidCropping(_ on: Bool) {
        edit { p in
            var q = p
            q.cells = p.cells.map { var c = $0; c.fit = on; c.manual = false; c.zoom = 1; c.cx = 0.5; c.cy = 0.5; return c }
            return ProjectOps.autoCrop(q)
        }
    }

    // MARK: per-cell edits

    func editCell(_ index: Int, live: Bool = false, _ f: (inout CellEdit) -> Void) {
        edit(live: live) { p in
            var q = p
            guard q.cells.indices.contains(index) else { return p }
            f(&q.cells[index])
            return q
        }
    }

    func editAllCells(live: Bool = false, _ f: (inout CellEdit) -> Void) {
        edit(live: live) { p in
            var q = p
            for i in q.cells.indices { f(&q.cells[i]) }
            return q
        }
    }

    private func editAuto(_ index: Int, _ f: (inout CellEdit) -> Void) {
        edit { p in
            var q = p
            guard q.cells.indices.contains(index) else { return p }
            f(&q.cells[index])
            return ProjectOps.autoCrop(q)
        }
    }

    func rotateCell(_ index: Int) {
        editAuto(index) { c in c.rotation = (c.rotation + 1) % 4; c.manual = false; c.zoom = 1; c.cx = 0.5; c.cy = 0.5 }
    }

    func mirrorCell(_ index: Int) { editAuto(index) { c in c.mirror.toggle(); c.cx = 1 - c.cx } }

    func toggleFit(_ index: Int) {
        editAuto(index) { c in c.fit.toggle(); c.zoom = 1; c.cx = 0.5; c.cy = 0.5; c.manual = false }
    }

    func resetCell(_ index: Int) {
        editAuto(index) { c in c.manual = false; c.zoom = 1; c.cx = 0.5; c.cy = 0.5 }
    }

    func removeCell(_ index: Int) {
        edit { ProjectOps.removeCell($0, index) }
        selection = EditSelection()
    }

    func replacePhoto(_ index: Int, url: URL) {
        Task {
            guard let ref = await importAll([url], label: "Importing photo").first else { return }
            edit { p in
                var q = p
                guard q.cells.indices.contains(index) else { return p }
                let old = q.cells[index]
                var c = CellEdit(photo: withCachedFaces(ref))
                c.caption = old.caption; c.adjustments = old.adjustments; c.filter = old.filter
                q.cells[index] = c
                return ProjectOps.autoCrop(q)
            }
            ensureFaces()
        }
    }

    func addPhotos(_ urls: [URL]) {
        if urls.isEmpty { return }
        Task {
            let refs = await importAll(urls, label: "Importing photos")
            if refs.isEmpty { return }
            edit { p in
                let existing = p.cells.compactMap { $0.photo }
                let hasEmpty = p.cells.contains { $0.photo == nil }
                if hasEmpty && existing.count + refs.count <= p.cells.count {
                    // fill empty template cells first
                    var k = 0
                    var q = p
                    q.cells = p.cells.map { c in
                        if c.photo == nil && k < refs.count { k += 1; return CellEdit(photo: refs[k - 1]) }
                        return c
                    }
                    return ProjectOps.autoCrop(q)
                }
                return ProjectOps.withPhotos(p, existing + refs)
            }
            ensureFaces()
        }
    }

    // MARK: text

    func addText(_ text: String, y: Double = 0.88) {
        let t = TextOverlay(id: UUID().uuidString.lowercased(), text: text, y: y)
        edit { var q = $0; q.texts.append(t); return q }
        selection = EditSelection(cell: nil, text: (project?.texts.count ?? 1) - 1)
    }

    func editText(_ index: Int, live: Bool = false, _ f: (inout TextOverlay) -> Void) {
        edit(live: live) { p in
            var q = p
            guard q.texts.indices.contains(index) else { return p }
            f(&q.texts[index])
            return q
        }
    }

    func deleteText(_ index: Int) {
        edit { p in
            var q = p
            if q.texts.indices.contains(index) { q.texts.remove(at: index) }
            return q
        }
        selection = EditSelection()
    }

    // MARK: templates

    func saveTemplate(_ name: String) {
        guard let p = project else { return }
        let t = ProjectOps.toTemplate(p, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My template" : name.trimmingCharacters(in: .whitespacesAndNewlines))
        let ts = templateStore
        Task {
            await Task.detached { ts.add(t) }.value
            refreshHome()
            showToast("Template saved. Find it on the home screen.")
        }
    }

    // MARK: export

    func sizeFor(_ quality: ExportQuality) -> (Int, Int) {
        project.map { exporter.sizeFor($0, quality) } ?? (0, 0)
    }

    /// Shows or hides the "loading photos" progress while the system picker hands files over (iCloud photos can take a while).
    func setLoadingPhotos(_ on: Bool) { busy = on ? BusyState(message: "Loading photos…") : nil }

    func reportPickFailures(_ failed: Int) {
        if failed > 0 { showToast("\(failed) photo(s) couldn't be loaded. If they are in iCloud, check your connection and try again.") }
    }

    /// Renders once at full quality, then either hands the file to the share sheet or saves it to Photos.
    func export(_ req: ExportRequest, share: Bool) {
        guard let p0 = project else { return }
        lastExportRequest = req
        var p = p0
        if req.transparent && req.format == .png { p.background.type = .transparent }
        busy = BusyState(message: share ? "Preparing your collage…" : "Saving full-quality image…")
        let exporter = self.exporter, store = self.store
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) { try exporter.prepareFile(p, req) }.value
                if share {
                    showExport = false
                    busy = nil
                    // let the export sheet finish dismissing before the share sheet is presented
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    shareItem = ShareItem(url: url)
                } else {
                    try await PhotoSaver.save(fileURL: url)
                    try? FileManager.default.removeItem(at: url)
                    showExport = false
                    showToast("Saved to Photos", actionLabel: "View", action: .openPhotos)
                }
                await Task.detached { AppModel.persist(store, p0, thumb: true) }.value
            } catch ExportError.photosDenied {
                // sheets hide alerts that belong to the view underneath, so close the export sheet first
                showExport = false
                busy = nil
                try? await Task.sleep(nanoseconds: 450_000_000)
                photosDenied = true
            } catch {
                provider.clear()
                showExport = false
                showToast("Couldn't export: \(error.localizedDescription)")
            }
            busy = nil
        }
    }
}
