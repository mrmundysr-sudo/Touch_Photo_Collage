package com.mundymorning.collage.engine.project

import com.mundymorning.collage.engine.face.FaceCrop
import com.mundymorning.collage.engine.face.FaceInput
import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutEngine
import com.mundymorning.collage.engine.layout.LayoutGenerator
import com.mundymorning.collage.engine.layout.LayoutTemplate
import com.mundymorning.collage.engine.transform.Orientation
import java.util.UUID

/** Pure project transformations (no Android): creation, relayout and automatic photo positioning. */
object ProjectOps {

    fun newId(): String = UUID.randomUUID().toString()

    fun defaultStyle(mode: ProjectMode): CollageStyle = when (mode) {
        ProjectMode.COMPARE -> CollageStyle(spacing = 0.008f, margin = 0f, cornerRadius = 0.03f)
        ProjectMode.GRID -> CollageStyle(spacing = 0.008f, margin = 0.008f, cornerRadius = 0f)
        ProjectMode.FAMILY -> CollageStyle(spacing = 0.012f, margin = 0.012f, cornerRadius = 0.035f)
        ProjectMode.COLLAGE -> CollageStyle()
    }

    fun defaultFaceMode(mode: ProjectMode): FaceMode = if (mode == ProjectMode.FAMILY) FaceMode.ALIGN else FaceMode.SMART

    fun defaultName(mode: ProjectMode): String = when (mode) {
        ProjectMode.COLLAGE -> "My collage"
        ProjectMode.COMPARE -> "Side by side"
        ProjectMode.FAMILY -> "Family resemblance"
        ProjectMode.GRID -> "Photo grid"
    }

    fun create(photos: List<PhotoRef>, mode: ProjectMode, now: Long, gridColumns: Int = 3, name: String = defaultName(mode)): CollageProject {
        require(photos.isNotEmpty()) { "no photos" }
        val aspects = photos.map { Orientation.displaySize(it.width, it.height, it.exif, 0).aspect }
        val n = photos.size
        val (layout, canvas) = when {
            mode == ProjectMode.COMPARE && n == 2 ->
                LayoutGenerator.auto(aspects, listOf(LayoutGenerator.rows(2, 1, "Side by side"), LayoutGenerator.rows(2, 2, "Stacked")))
            mode == ProjectMode.FAMILY && n >= 2 ->
                LayoutGenerator.auto(aspects, LayoutGenerator.candidates(n).filter { it.id.startsWith("rows-") || it.id.startsWith("cols-") })
            mode == ProjectMode.GRID -> {
                val g = LayoutGenerator.gridWithColumns(n, gridColumns)
                g to LayoutGenerator.auto(aspects, listOf(g)).second
            }
            else -> LayoutGenerator.auto(aspects)
        }
        val project = CollageProject(
            id = newId(), name = name, createdAt = now, updatedAt = now, mode = mode, canvas = canvas, layout = layout,
            style = defaultStyle(mode), background = Background(),
            cells = photos.map { CellEdit(photo = it) }, faceMode = defaultFaceMode(mode),
        )
        return autoCrop(project)
    }

    /** Change layout (and optionally canvas) keeping each photo's edits by cell index, then re-run auto positioning. */
    fun withLayout(p: CollageProject, layout: LayoutTemplate, canvas: CanvasSpec = p.canvas): CollageProject {
        val cells = List(layout.count) { p.cells.getOrNull(it) ?: CellEdit() }
        return autoCrop(p.copy(layout = layout, canvas = canvas, cells = cells))
    }

    /** Replace the photo set (e.g. after adding photos), choosing a fresh automatic layout. */
    fun withPhotos(p: CollageProject, photos: List<PhotoRef>): CollageProject {
        val keep = p.cells.mapNotNull { it.photo?.id }.toSet()
        val byId = p.cells.mapNotNull { c -> c.photo?.let { it.id to c } }.toMap()
        val cells = photos.map { ph -> if (ph.id in keep) byId.getValue(ph.id) else CellEdit(photo = ph) }
        val aspects = photos.map { Orientation.displaySize(it.width, it.height, it.exif, 0).aspect }
        val (layout, canvas) = LayoutGenerator.auto(aspects)
        return autoCrop(p.copy(layout = layout, canvas = canvas, cells = cells))
    }

    fun swapCells(p: CollageProject, a: Int, b: Int): CollageProject {
        if (a == b || a !in p.cells.indices || b !in p.cells.indices) return p
        val c = p.cells.toMutableList()
        val t = c[a]; c[a] = c[b]; c[b] = t
        return autoCrop(p.copy(cells = c))
    }

    fun moveCell(p: CollageProject, from: Int, to: Int): CollageProject {
        if (from == to || from !in p.cells.indices || to !in p.cells.indices) return p
        val c = p.cells.toMutableList()
        c.add(to, c.removeAt(from))
        return autoCrop(p.copy(cells = c))
    }

    fun removeCell(p: CollageProject, index: Int): CollageProject {
        val photos = p.cells.filterIndexed { i, c -> i != index && c.photo != null }.mapNotNull { it.photo }
        if (photos.isEmpty()) return p
        val byId = p.cells.mapNotNull { c -> c.photo?.let { it.id to c } }.toMap()
        val aspects = photos.map { Orientation.displaySize(it.width, it.height, it.exif, 0).aspect }
        val (layout, canvas) = LayoutGenerator.auto(aspects)
        return autoCrop(p.copy(layout = layout, canvas = canvas, cells = photos.map { byId.getValue(it.id) }))
    }

    /** Attach newly detected faces to every cell showing that photo. */
    fun withFaces(p: CollageProject, photoId: String, faces: List<com.mundymorning.collage.engine.model.FRect>): CollageProject =
        autoCrop(p.copy(cells = p.cells.map { c -> if (c.photo?.id == photoId) c.copy(photo = c.photo.copy(faces = faces)) else c }))

    /**
     * Automatic positioning for every cell the user has not positioned by hand. Faces missing or unreliable ->
     * centre crop. Never changes manual cells.
     */
    fun autoCrop(p: CollageProject, nominalWidth: Float = 1000f): CollageProject {
        val h = nominalWidth / p.canvas.aspect
        val unit = LayoutEngine.unit(nominalWidth, h)
        val rects = LayoutEngine.cellRects(p.layout, nominalWidth, h, p.style.margin * unit, p.style.spacing * unit)
        data class Item(val idx: Int, val input: FaceInput)
        val items = ArrayList<Item>()
        p.cells.forEachIndexed { i, c ->
            val ph = c.photo ?: return@forEachIndexed
            val r = rects.getOrNull(i) ?: return@forEachIndexed
            val disp = Orientation.displaySize(ph.width, ph.height, ph.exif, c.rotation)
            val faces = (ph.faces ?: emptyList()).map { Orientation.toDisplay(it, c.rotation, c.mirror) }
            items += Item(i, FaceInput(disp.aspect, faces, r.w / r.h, c.fit))
        }
        val states = when (p.faceMode) {
            FaceMode.OFF -> items.map { com.mundymorning.collage.engine.face.CropState(1f, 0.5f, 0.5f) }
            FaceMode.SMART -> items.map { FaceCrop.smart(it.input) }
            FaceMode.ALIGN -> FaceCrop.align(items.map { it.input })
        }
        val cells = p.cells.toMutableList()
        items.forEachIndexed { k, it ->
            val c = cells[it.idx]
            if (!c.manual) cells[it.idx] = c.copy(zoom = states[k].zoom, cx = states[k].cx, cy = states[k].cy)
        }
        return p.copy(cells = cells)
    }

    fun toTemplate(p: CollageProject, name: String): SavedTemplate =
        SavedTemplate(newId(), name, p.mode, p.canvas, p.layout, p.style, p.background)

    /** New project from a template, with as many photos as the template has cells (extra cells stay empty). */
    fun fromTemplate(t: SavedTemplate, photos: List<PhotoRef>, now: Long): CollageProject {
        val cells = List(t.layout.count) { CellEdit(photo = photos.getOrNull(it)) }
        return autoCrop(
            CollageProject(
                id = newId(), name = t.name, createdAt = now, updatedAt = now, mode = t.mode, canvas = t.canvas, layout = t.layout,
                style = t.style, background = t.background, cells = cells, faceMode = defaultFaceMode(t.mode),
            ),
        )
    }
}
