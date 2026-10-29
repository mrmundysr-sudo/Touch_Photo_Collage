package com.mundymorning.touchphotocollage

import android.app.Application
import android.graphics.Bitmap
import android.graphics.RectF
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.mundymorning.collage.engine.export.ExportFormat
import com.mundymorning.collage.engine.export.ExportRequest
import com.mundymorning.collage.engine.export.Exporter
import com.mundymorning.collage.engine.face.FaceFinder
import com.mundymorning.collage.engine.face.MlKitFaceFinder
import com.mundymorning.collage.engine.io.FileBitmapProvider
import com.mundymorning.collage.engine.io.ImageImporter
import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutGenerator
import com.mundymorning.collage.engine.layout.LayoutTemplate
import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.project.*
import com.mundymorning.collage.engine.render.CollageRenderer
import com.mundymorning.collage.engine.transform.CropMath
import com.mundymorning.collage.engine.transform.Orientation
import com.mundymorning.touchphotocollage.ui.ThemeMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.ArrayDeque
import java.util.UUID

enum class Screen { HOME, EDITOR }

data class HomeData(val recents: List<ProjectSummary> = emptyList(), val templates: List<SavedTemplate> = emptyList())
data class Selection(val cell: Int? = null, val text: Int? = null)
data class BusyState(val message: String, val done: Int = 0, val total: Int = 0)
data class PreviewFrame(val bitmap: Bitmap, val textBounds: List<RectF>, val forProject: CollageProject)

sealed interface UiEvent {
    data class Message(val text: String) : UiEvent
    data class Saved(val uri: Uri, val where: String) : UiEvent
    data class Share(val uri: Uri, val mime: String) : UiEvent
}

class CollageViewModel(private val app: Application) : AndroidViewModel(app) {
    private val root = File(app.filesDir, "collage").apply { mkdirs() }
    private val store = ProjectStore(root)
    private val templateStore = TemplateStore(root)
    private val importer = ImageImporter(app, store.mediaDir)
    private val exporter = Exporter(app, store.mediaDir)
    private val faceFinder: FaceFinder = MlKitFaceFinder()
    private val provider = FileBitmapProvider(store.mediaDir, (Runtime.getRuntime().maxMemory() / 6L).toInt())
    private val renderer = CollageRenderer(provider)
    private val prefs = app.getSharedPreferences("prefs", 0)

    private val _screen = MutableStateFlow(Screen.HOME)
    val screen: StateFlow<Screen> = _screen.asStateFlow()
    private val _home = MutableStateFlow(HomeData())
    val home: StateFlow<HomeData> = _home.asStateFlow()
    private val _project = MutableStateFlow<CollageProject?>(null)
    val project: StateFlow<CollageProject?> = _project.asStateFlow()
    private val _selection = MutableStateFlow(Selection())
    val selection: StateFlow<Selection> = _selection.asStateFlow()
    private val _preview = MutableStateFlow<PreviewFrame?>(null)
    val preview: StateFlow<PreviewFrame?> = _preview.asStateFlow()
    private val _busy = MutableStateFlow<BusyState?>(null)
    val busy: StateFlow<BusyState?> = _busy.asStateFlow()
    private val _canUndo = MutableStateFlow(false)
    val canUndo: StateFlow<Boolean> = _canUndo.asStateFlow()
    private val _canRedo = MutableStateFlow(false)
    val canRedo: StateFlow<Boolean> = _canRedo.asStateFlow()
    private val _facesPending = MutableStateFlow(0)
    val facesPending: StateFlow<Int> = _facesPending.asStateFlow()
    private val _viewport = MutableStateFlow(0 to 0)
    private val _theme = MutableStateFlow(
        runCatching { ThemeMode.valueOf(prefs.getString("theme", "SYSTEM")!!) }.getOrDefault(ThemeMode.SYSTEM),
    )
    val theme: StateFlow<ThemeMode> = _theme.asStateFlow()
    private val _events = MutableSharedFlow<UiEvent>(extraBufferCapacity = 16)
    val events: SharedFlow<UiEvent> = _events.asSharedFlow()

    /** Pixel size of the canvas on screen, derived from the free area and the project's ratio. */
    val canvasPx: StateFlow<Pair<Int, Int>> get() = _canvasPx
    private val _canvasPx = MutableStateFlow(0 to 0)

    private val undo = ArrayDeque<CollageProject>()
    private val redo = ArrayDeque<CollageProject>()
    private var liveOpen = false
    private val facesCache = HashMap<String, List<FRect>>()
    private val faceJobs = HashSet<String>()
    private val faceMutex = Mutex()
    private var saveJob: Job? = null

    init {
        refreshHome()
        viewModelScope.launch {
            combine(_project, _viewport) { p, v -> p?.canvas?.aspect to v }.collectLatest { (aspect, v) ->
                if (aspect == null || v.first <= 0 || v.second <= 0) return@collectLatest
                _canvasPx.value = fitInside(v.first, v.second, aspect)
            }
        }
        viewModelScope.launch {
            combine(_project, _canvasPx) { p, c -> p to c }.collectLatest { (p, c) ->
                if (p == null || c.first <= 0) return@collectLatest
                val frame = withContext(Dispatchers.Default) {
                    try {
                        val bmp = renderer.render(p, c.first, c.second, CollageRenderer.Options(keepTransparent = true, showPlaceholders = true))
                        PreviewFrame(bmp, renderer.textBounds(p, c.first, c.second), p)
                    } catch (e: OutOfMemoryError) {
                        provider.clear(); null
                    }
                }
                if (frame != null) _preview.value = frame
            }
        }
    }

    // ---------------------------------------------------------------- home

    fun refreshHome() {
        viewModelScope.launch {
            val data = withContext(Dispatchers.IO) { HomeData(store.list(), templateStore.list()) }
            _home.value = data
        }
    }

    fun setTheme(mode: ThemeMode) {
        _theme.value = mode
        prefs.edit().putString("theme", mode.name).apply()
    }

    fun deleteProject(id: String) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { store.delete(id) }
            refreshHome()
        }
    }

    fun deleteTemplate(id: String) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { templateStore.delete(id) }
            refreshHome()
        }
    }

    // ---------------------------------------------------------------- creation

    private suspend fun importAll(uris: List<Uri>, label: String): List<PhotoRef> {
        var failed = 0
        val out = ArrayList<PhotoRef>()
        _busy.value = BusyState(label, 0, uris.size)
        withContext(Dispatchers.IO) {
            uris.forEachIndexed { i, u ->
                try { out += importer.import(u) } catch (e: Exception) { failed++ }
                _busy.value = BusyState(label, i + 1, uris.size)
            }
        }
        _busy.value = null
        if (failed > 0) emit(UiEvent.Message(if (failed == uris.size) "Those photos couldn't be opened." else "$failed photo(s) couldn't be opened and were skipped."))
        return out
    }

    fun startNew(mode: ProjectMode, uris: List<Uri>, gridColumns: Int = 3) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            val refs = importAll(uris, "Importing photos")
            if (refs.isEmpty()) return@launch
            if ((mode == ProjectMode.COMPARE || mode == ProjectMode.FAMILY) && refs.size < 2) {
                withContext(Dispatchers.IO) { store.collectGarbage() }
                emit(UiEvent.Message(if (mode == ProjectMode.COMPARE) "Pick two photos to compare." else "Pick at least two photos for Family Resemblance."))
                return@launch
            }
            val m = if (mode == ProjectMode.COMPARE && refs.size != 2) ProjectMode.COLLAGE else mode
            open(ProjectOps.create(refs.map(::withCachedFaces), m, System.currentTimeMillis(), gridColumns))
        }
    }

    fun startFromTemplate(t: SavedTemplate, uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            val refs = importAll(uris.take(t.layout.count), "Importing photos")
            if (refs.isEmpty()) return@launch
            open(ProjectOps.fromTemplate(t, refs, System.currentTimeMillis()))
        }
    }

    fun openSaved(id: String) {
        viewModelScope.launch {
            val p = withContext(Dispatchers.IO) { store.load(id) }
            if (p == null) emit(UiEvent.Message("That project couldn't be opened.")) else open(p, save = false)
        }
    }

    private fun open(p: CollageProject, save: Boolean = true) {
        undo.clear(); redo.clear(); liveOpen = false; updateUndoFlags()
        _preview.value = null
        _selection.value = Selection()
        p.cells.forEach { c -> c.photo?.faces?.let { facesCache[c.photo!!.id] = it } }
        _project.value = p
        _screen.value = Screen.EDITOR
        if (save) scheduleSave(immediately = true)
        ensureFaces()
    }

    /** Leave the editor: save the project and a thumbnail, return home. */
    fun closeEditor() {
        val p = _project.value
        viewModelScope.launch {
            if (p != null) withContext(Dispatchers.IO) { persist(p, thumb = true) }
            _screen.value = Screen.HOME
            _project.value = null
            _preview.value = null
            provider.clear()
            refreshHome()
        }
    }

    private fun persist(p: CollageProject, thumb: Boolean) {
        val stamped = p.copy(updatedAt = System.currentTimeMillis())
        store.save(stamped)
        if (thumb) {
            try {
                val (w, h) = com.mundymorning.collage.engine.layout.LayoutEngine.sizeForLongSide(p.canvas, 480)
                val bmp = CollageRenderer(FileBitmapProvider(store.mediaDir, 0)).render(p, w, h)
                store.saveThumb(p.id, bmp); bmp.recycle()
            } catch (e: Throwable) { /* thumbnail is optional */ }
        }
    }

    private fun scheduleSave(immediately: Boolean = false) {
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            if (!immediately) delay(700)
            val p = _project.value ?: return@launch
            withContext(Dispatchers.IO) { persist(p, thumb = immediately) }
        }
    }

    // ---------------------------------------------------------------- editing core

    fun setViewport(w: Int, h: Int) { _viewport.value = w to h }

    private fun updateUndoFlags() { _canUndo.value = undo.isNotEmpty(); _canRedo.value = redo.isNotEmpty() }

    private fun push(cur: CollageProject) {
        undo.addLast(cur)
        while (undo.size > 60) undo.removeFirst()
        redo.clear()
        updateUndoFlags()
    }

    /**
     * Apply an edit. [live] edits (sliders, drags) record one undo step for the whole gesture; call [endLive]
     * when the gesture finishes.
     */
    fun edit(live: Boolean = false, f: (CollageProject) -> CollageProject) {
        val cur = _project.value ?: return
        val next = f(cur)
        if (next == cur) return
        if (live) { if (!liveOpen) { push(cur); liveOpen = true } } else { push(cur); liveOpen = false }
        _project.value = next
        scheduleSave()
    }

    fun endLive() { liveOpen = false }

    fun undo() {
        val cur = _project.value ?: return
        val prev = undo.pollLast() ?: return
        redo.addLast(cur)
        liveOpen = false
        _project.value = mergeFaces(prev); fixSelection(); updateUndoFlags(); scheduleSave()
    }

    fun redo() {
        val cur = _project.value ?: return
        val next = redo.pollLast() ?: return
        undo.addLast(cur)
        liveOpen = false
        _project.value = mergeFaces(next); fixSelection(); updateUndoFlags(); scheduleSave()
    }

    private fun fixSelection() {
        val p = _project.value ?: return
        _selection.update { s -> Selection(s.cell?.takeIf { it < p.cells.size }, s.text?.takeIf { it < p.texts.size }) }
    }

    private fun withCachedFaces(ref: PhotoRef): PhotoRef = if (ref.faces == null) facesCache[ref.id]?.let { ref.copy(faces = it) } ?: ref else ref

    private fun mergeFaces(p: CollageProject): CollageProject =
        p.copy(cells = p.cells.map { c -> c.photo?.let { c.copy(photo = withCachedFaces(it)) } ?: c })

    fun selectCell(i: Int?) { _selection.value = Selection(cell = i) }
    fun selectText(i: Int?) { _selection.value = Selection(text = i) }

    // ---------------------------------------------------------------- face detection

    private fun ensureFaces() {
        val p = _project.value ?: return
        p.cells.mapNotNull { it.photo }.filter { it.faces == null && faceJobs.add(it.id) }.forEach { ref ->
            _facesPending.update { it + 1 }
            viewModelScope.launch(Dispatchers.Default) {
                val faces = faceMutex.withLock { faceFinder.find(ref, store.mediaDir) } ?: emptyList()
                withContext(Dispatchers.Main) {
                    facesCache[ref.id] = faces
                    _project.update { cur -> cur?.let { ProjectOps.withFaces(it, ref.id, faces) } }
                    val merged = undo.map { snap -> mergeFaces(snap) }; undo.clear(); undo.addAll(merged)
                    faceJobs.remove(ref.id)
                    _facesPending.update { it - 1 }
                    scheduleSave()
                }
            }
        }
    }

    // ---------------------------------------------------------------- cell gestures

    /** Pan/zoom one cell. Pan is in screen pixels, [fx]/[fy] the pinch focus inside the cell (0..1). */
    fun transformCell(index: Int, panX: Float, panY: Float, zoomFactor: Float, fx: Float, fy: Float, cellW: Float, cellH: Float) {
        edit(live = true) { p ->
            val c = p.cells.getOrNull(index) ?: return@edit p
            val ph = c.photo ?: return@edit p
            val aspect = Orientation.displaySize(ph.width, ph.height, ph.exif, c.rotation).aspect
            var z = c.zoom; var cx = c.cx; var cy = c.cy
            if (zoomFactor != 1f) {
                val r = CropMath.zoomAbout(aspect, cellW / cellH, z, cx, cy, c.fit, z * zoomFactor, fx, fy)
                z = r.first; cx = r.second; cy = r.third
            }
            if (panX != 0f || panY != 0f) {
                val r = CropMath.pan(aspect, cellW, cellH, z, cx, cy, c.fit, panX, panY)
                cx = r.first; cy = r.second
            }
            p.copy(cells = p.cells.mapIndexed { i, cell -> if (i == index) cell.copy(zoom = z, cx = cx, cy = cy, manual = true) else cell })
        }
    }

    fun swapCells(a: Int, b: Int) {
        edit { ProjectOps.swapCells(it, a, b) }
        _selection.value = Selection(cell = b)
    }

    fun moveCell(from: Int, delta: Int) {
        val to = from + delta
        edit { ProjectOps.moveCell(it, from, to) }
        if (to in 0 until (_project.value?.cells?.size ?: 0)) _selection.value = Selection(cell = to)
    }

    fun moveText(index: Int, nx: Float, ny: Float) {
        edit(live = true) { p ->
            p.copy(texts = p.texts.mapIndexed { i, t -> if (i == index) t.copy(x = nx.coerceIn(0.02f, 0.98f), y = ny.coerceIn(0.02f, 0.98f)) else t })
        }
    }

    // ---------------------------------------------------------------- layout & style

    fun setLayout(l: LayoutTemplate) = edit { ProjectOps.withLayout(it, l) }
    fun setCanvas(c: CanvasSpec) = edit { ProjectOps.withLayout(it, it.layout, c) }

    fun autoLayout() = edit { p ->
        val photos = p.cells.mapNotNull { it.photo }
        if (photos.isEmpty()) p else ProjectOps.withPhotos(p.copy(cells = p.cells.map { it.copy(manual = false) }), photos)
    }

    fun shuffleArtistic() = edit { p ->
        val n = p.layout.count
        if (n < 2) p else {
            val seed = (UUID.randomUUID().hashCode() and 0xFFFF)
            ProjectOps.withLayout(p, LayoutGenerator.mosaic(n, seed).copy(name = "Artistic"))
        }
    }

    fun setStyle(live: Boolean = true, f: (CollageStyle) -> CollageStyle) = edit(live) { p ->
        ProjectOps.autoCrop(p.copy(style = f(p.style)))
    }

    fun setBackground(bg: Background) = edit { it.copy(background = bg) }

    fun rename(name: String) = edit { it.copy(name = name.trim().ifEmpty { "Untitled collage" }) }

    fun setFaceMode(mode: FaceMode) = edit { p ->
        ProjectOps.autoCrop(p.copy(faceMode = mode, cells = p.cells.map { it.copy(manual = false) }))
    }

    fun resetCrops() = edit { p ->
        ProjectOps.autoCrop(p.copy(cells = p.cells.map { it.copy(manual = false) }))
    }

    fun setAvoidCropping(on: Boolean) = edit { p ->
        ProjectOps.autoCrop(p.copy(cells = p.cells.map { it.copy(fit = on, manual = false, zoom = 1f, cx = 0.5f, cy = 0.5f) }))
    }

    // ---------------------------------------------------------------- per-cell edits

    fun editCell(index: Int, live: Boolean = false, f: (CellEdit) -> CellEdit) = edit(live) { p ->
        p.copy(cells = p.cells.mapIndexed { i, c -> if (i == index) f(c) else c })
    }

    fun editAllCells(live: Boolean = false, f: (CellEdit) -> CellEdit) = edit(live) { p -> p.copy(cells = p.cells.map(f)) }

    fun rotateCell(index: Int) = edit { p ->
        val c = p.cells.getOrNull(index) ?: return@edit p
        val r = c.copy(rotation = (c.rotation + 1) % 4, manual = false, zoom = 1f, cx = 0.5f, cy = 0.5f)
        ProjectOps.autoCrop(p.copy(cells = p.cells.mapIndexed { i, cell -> if (i == index) r else cell }))
    }

    fun mirrorCell(index: Int) = edit { p ->
        val c = p.cells.getOrNull(index) ?: return@edit p
        val r = c.copy(mirror = !c.mirror, cx = 1f - c.cx)
        ProjectOps.autoCrop(p.copy(cells = p.cells.mapIndexed { i, cell -> if (i == index) r else cell }))
    }

    fun toggleFit(index: Int) = edit { p ->
        val c = p.cells.getOrNull(index) ?: return@edit p
        val r = c.copy(fit = !c.fit, zoom = 1f, cx = 0.5f, cy = 0.5f, manual = false)
        ProjectOps.autoCrop(p.copy(cells = p.cells.mapIndexed { i, cell -> if (i == index) r else cell }))
    }

    fun resetCell(index: Int) = edit { p ->
        val c = p.cells.getOrNull(index) ?: return@edit p
        ProjectOps.autoCrop(p.copy(cells = p.cells.mapIndexed { i, cell -> if (i == index) c.copy(manual = false, zoom = 1f, cx = 0.5f, cy = 0.5f) else cell }))
    }

    fun removeCell(index: Int) = edit { ProjectOps.removeCell(it, index) }.also { _selection.value = Selection() }

    fun replacePhoto(index: Int, uri: Uri) {
        viewModelScope.launch {
            val ref = importAll(listOf(uri), "Importing photo").firstOrNull() ?: return@launch
            edit { p ->
                ProjectOps.autoCrop(
                    p.copy(cells = p.cells.mapIndexed { i, c ->
                        if (i == index) CellEdit(photo = withCachedFaces(ref), caption = c.caption, adjustments = c.adjustments, filter = c.filter) else c
                    }),
                )
            }
            ensureFaces()
        }
    }

    fun addPhotos(uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            val refs = importAll(uris, "Importing photos")
            if (refs.isEmpty()) return@launch
            edit { p ->
                val existing = p.cells.mapNotNull { it.photo }
                val empties = p.cells.indexOfFirst { it.photo == null }
                if (empties >= 0 && existing.size + refs.size <= p.cells.size) {
                    // fill empty template cells first
                    var k = 0
                    ProjectOps.autoCrop(p.copy(cells = p.cells.map { c -> if (c.photo == null && k < refs.size) CellEdit(photo = refs[k++]) else c }))
                } else ProjectOps.withPhotos(p, existing + refs)
            }
            ensureFaces()
        }
    }

    // ---------------------------------------------------------------- text

    fun addText(text: String, y: Float = 0.88f) {
        val t = TextOverlay(id = UUID.randomUUID().toString(), text = text, y = y)
        edit { it.copy(texts = it.texts + t) }
        _selection.value = Selection(text = (_project.value?.texts?.size ?: 1) - 1)
    }

    fun editText(index: Int, live: Boolean = false, f: (TextOverlay) -> TextOverlay) = edit(live) { p ->
        p.copy(texts = p.texts.mapIndexed { i, t -> if (i == index) f(t) else t })
    }

    fun deleteText(index: Int) {
        edit { p -> p.copy(texts = p.texts.filterIndexed { i, _ -> i != index }) }
        _selection.value = Selection()
    }

    // ---------------------------------------------------------------- templates

    fun saveTemplate(name: String) {
        val p = _project.value ?: return
        viewModelScope.launch {
            withContext(Dispatchers.IO) { templateStore.add(ProjectOps.toTemplate(p, name.trim().ifEmpty { "My template" })) }
            refreshHome()
            emit(UiEvent.Message("Template saved. Find it on the home screen."))
        }
    }

    // ---------------------------------------------------------------- export

    fun sizeFor(quality: com.mundymorning.collage.engine.export.ExportQuality): Pair<Int, Int> =
        _project.value?.let { exporter.sizeFor(it, quality) } ?: (0 to 0)

    fun export(req: ExportRequest, share: Boolean) {
        val p0 = _project.value ?: return
        val p = if (req.transparent && req.format == ExportFormat.PNG) p0.copy(background = p0.background.copy(type = BackgroundType.TRANSPARENT)) else p0
        viewModelScope.launch {
            _busy.value = BusyState(if (share) "Preparing your collage…" else "Saving full-quality image…")
            try {
                val uri = withContext(Dispatchers.IO) {
                    if (share) exporter.prepareShare(p, req, "${app.packageName}.fileprovider") else exporter.saveToGallery(p, req)
                }
                withContext(Dispatchers.IO) { persist(p0, thumb = true) }
                emit(if (share) UiEvent.Share(uri, req.format.mime) else UiEvent.Saved(uri, "Pictures/${Exporter.ALBUM}"))
            } catch (e: Throwable) {
                provider.clear()
                emit(UiEvent.Message(if (e is OutOfMemoryError) "Not enough memory for that size. Try Standard quality." else "Couldn't export: ${e.message ?: "unknown error"}"))
            } finally {
                _busy.value = null
            }
        }
    }

    private fun emit(e: UiEvent) { _events.tryEmit(e) }

    companion object {
        fun fitInside(availW: Int, availH: Int, aspect: Float): Pair<Int, Int> {
            var w = availW.toFloat()
            var h = w / aspect
            if (h > availH) { h = availH.toFloat(); w = h * aspect }
            return Math.max(1, w.toInt()) to Math.max(1, h.toInt())
        }
    }
}
