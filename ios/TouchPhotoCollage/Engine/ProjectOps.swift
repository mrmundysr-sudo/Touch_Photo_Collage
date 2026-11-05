import Foundation

/// Pure project transformations: creation, relayout and automatic photo positioning.
enum ProjectOps {
    static func newId() -> String { UUID().uuidString.lowercased() }

    static func defaultStyle(_ mode: ProjectMode) -> CollageStyle {
        switch mode {
        case .compare: return CollageStyle(spacing: 0.008, margin: 0, cornerRadius: 0.03)
        case .grid: return CollageStyle(spacing: 0.008, margin: 0.008, cornerRadius: 0)
        case .family: return CollageStyle(spacing: 0.012, margin: 0.012, cornerRadius: 0.035)
        case .collage: return CollageStyle()
        }
    }

    static func defaultFaceMode(_ mode: ProjectMode) -> FaceMode { mode == .family ? .align : .smart }

    static func defaultName(_ mode: ProjectMode) -> String {
        switch mode {
        case .collage: return "My collage"
        case .compare: return "Side by side"
        case .family: return "Family resemblance"
        case .grid: return "Photo grid"
        }
    }

    private static func aspects(_ photos: [PhotoRef]) -> [Double] {
        photos.map { Orientation.displaySize($0.width, $0.height, exif: $0.exif, quarterTurns: 0).aspect }
    }

    static func create(photos: [PhotoRef], mode: ProjectMode, now: Int64, gridColumns: Int = 3, name: String? = nil) -> CollageProject {
        precondition(!photos.isEmpty, "no photos")
        let asp = aspects(photos)
        let n = photos.count
        let pick: (LayoutTemplate, CanvasSpec)
        if mode == .compare && n == 2 {
            pick = LayoutGenerator.auto(photoAspects: asp, layouts: [LayoutGenerator.rows(2, 1, name: "Side by side"), LayoutGenerator.rows(2, 2, name: "Stacked")])
        } else if mode == .family && n >= 2 {
            pick = LayoutGenerator.auto(photoAspects: asp, layouts: LayoutGenerator.candidates(n).filter { $0.id.hasPrefix("rows-") || $0.id.hasPrefix("cols-") })
        } else if mode == .grid {
            let g = LayoutGenerator.gridWithColumns(n, gridColumns)
            pick = (g, LayoutGenerator.auto(photoAspects: asp, layouts: [g]).1)
        } else {
            pick = LayoutGenerator.auto(photoAspects: asp)
        }
        let (layout, canvas) = pick
        let project = CollageProject(
            id: newId(), name: name ?? defaultName(mode), createdAt: now, updatedAt: now, mode: mode, canvas: canvas, layout: layout,
            style: defaultStyle(mode), background: CanvasBackground(), cells: photos.map { CellEdit(photo: $0) }, faceMode: defaultFaceMode(mode)
        )
        return autoCrop(project)
    }

    /// Change layout (and optionally canvas) keeping each photo's edits by cell index, then re-run auto positioning.
    static func withLayout(_ p: CollageProject, _ layout: LayoutTemplate, canvas: CanvasSpec? = nil) -> CollageProject {
        var q = p
        q.cells = (0..<layout.count).map { $0 < p.cells.count ? p.cells[$0] : CellEdit() }
        q.layout = layout
        q.canvas = canvas ?? p.canvas
        return autoCrop(q)
    }

    /// Replace the photo set (e.g. after adding photos), choosing a fresh automatic layout.
    static func withPhotos(_ p: CollageProject, _ photos: [PhotoRef]) -> CollageProject {
        var byId: [String: CellEdit] = [:]
        for c in p.cells { if let ph = c.photo { byId[ph.id] = c } }
        let cells = photos.map { ph in byId[ph.id] ?? CellEdit(photo: ph) }
        let (layout, canvas) = LayoutGenerator.auto(photoAspects: aspects(photos))
        var q = p
        q.layout = layout; q.canvas = canvas; q.cells = cells
        return autoCrop(q)
    }

    static func swapCells(_ p: CollageProject, _ a: Int, _ b: Int) -> CollageProject {
        guard a != b, p.cells.indices.contains(a), p.cells.indices.contains(b) else { return p }
        var q = p
        q.cells.swapAt(a, b)
        return autoCrop(q)
    }

    static func moveCell(_ p: CollageProject, from: Int, to: Int) -> CollageProject {
        guard from != to, p.cells.indices.contains(from), p.cells.indices.contains(to) else { return p }
        var q = p
        let c = q.cells.remove(at: from)
        q.cells.insert(c, at: to)
        return autoCrop(q)
    }

    static func removeCell(_ p: CollageProject, _ index: Int) -> CollageProject {
        let kept = p.cells.enumerated().filter { $0.offset != index && $0.element.photo != nil }.map { $0.element }
        if kept.isEmpty { return p }
        let photos = kept.map { $0.photo! }
        let (layout, canvas) = LayoutGenerator.auto(photoAspects: aspects(photos))
        var q = p
        q.layout = layout; q.canvas = canvas; q.cells = kept
        return autoCrop(q)
    }

    /// Attach newly detected faces to every cell showing that photo.
    static func withFaces(_ p: CollageProject, photoId: String, faces: [FRect]) -> CollageProject {
        var q = p
        q.cells = p.cells.map { c in
            guard var ph = c.photo, ph.id == photoId else { return c }
            ph.faces = faces
            var n = c; n.photo = ph
            return n
        }
        return autoCrop(q)
    }

    /// Automatic positioning for every cell the user has not positioned by hand. Faces missing or unreliable ->
    /// centre crop. Never changes manual cells.
    static func autoCrop(_ p: CollageProject, nominalWidth: Double = 1000) -> CollageProject {
        let h = nominalWidth / p.canvas.aspect
        let unit = LayoutEngine.unit(nominalWidth, h)
        let rects = LayoutEngine.cellRects(p.layout, canvasW: nominalWidth, canvasH: h, margin: p.style.margin * unit, spacing: p.style.spacing * unit)
        var items: [(idx: Int, input: FaceInput)] = []
        for (i, c) in p.cells.enumerated() {
            guard let ph = c.photo, i < rects.count else { continue }
            let r = rects[i]
            let disp = Orientation.displaySize(ph.width, ph.height, exif: ph.exif, quarterTurns: c.rotation)
            let faces = (ph.faces ?? []).map { Orientation.toDisplay($0, quarterTurns: c.rotation, mirror: c.mirror) }
            items.append((i, FaceInput(imgAspect: disp.aspect, faces: faces, cellAspect: r.w / r.h, fit: c.fit)))
        }
        let states: [CropState]
        switch p.faceMode {
        case .off: states = items.map { _ in CropState(zoom: 1, cx: 0.5, cy: 0.5) }
        case .smart: states = items.map { FaceCrop.smart($0.input) }
        case .align: states = FaceCrop.align(items.map { $0.input })
        }
        var q = p
        for (k, it) in items.enumerated() where !q.cells[it.idx].manual {
            q.cells[it.idx].zoom = states[k].zoom
            q.cells[it.idx].cx = states[k].cx
            q.cells[it.idx].cy = states[k].cy
        }
        return q
    }

    static func toTemplate(_ p: CollageProject, name: String) -> SavedTemplate {
        SavedTemplate(id: newId(), name: name, mode: p.mode, canvas: p.canvas, layout: p.layout, style: p.style, background: p.background)
    }

    /// New project from a template, with as many photos as the template has cells (extra cells stay empty).
    static func fromTemplate(_ t: SavedTemplate, photos: [PhotoRef], now: Int64) -> CollageProject {
        let cells = (0..<t.layout.count).map { CellEdit(photo: $0 < photos.count ? photos[$0] : nil) }
        return autoCrop(CollageProject(
            id: newId(), name: t.name, createdAt: now, updatedAt: now, mode: t.mode, canvas: t.canvas, layout: t.layout,
            style: t.style, background: t.background, cells: cells, faceMode: defaultFaceMode(t.mode)
        ))
    }
}
