package com.mundymorning.touchphotocollage

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Looper
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.LocalContentColor
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import com.mundymorning.collage.engine.project.ProjectMode
import com.mundymorning.collage.engine.render.CollageRenderer
import com.mundymorning.touchgesture.TouchMode
import com.mundymorning.touchphotocollage.ui.AppTheme
import com.mundymorning.touchphotocollage.ui.EditorScreen
import com.mundymorning.touchphotocollage.ui.HomeScreen
import com.mundymorning.touchphotocollage.ui.ThemeMode
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** One-finger Touch Gesture Standard, exercised with real swipes and pinches on the real editor canvas. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h740dp-xxhdpi")
class GestureUiTest {
    @get:Rule val rule = createComposeRule()
    private lateinit var app: Application
    private lateinit var vm: CollageViewModel

    private fun photo(dir: File, name: String, w: Int, h: Int, color: Int): Uri {
        val f = File(dir, name)
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(b).apply { drawColor(color); drawCircle(w / 2f, h / 3f, minOf(w, h) / 6f, Paint().apply { this.color = Color.rgb(250, 220, 190) }) }
        f.outputStream().use { b.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return Uri.fromFile(f)
    }

    private fun waitFor(what: String, cond: () -> Boolean) {
        repeat(1200) { shadowOf(Looper.getMainLooper()).idle(); if (cond()) return; Thread.sleep(25) }
        throw AssertionError("timed out waiting for $what")
    }

    @Before fun setUp() {
        app = ApplicationProvider.getApplicationContext()
        app.getSharedPreferences("prefs", 0).edit().clear().commit()
        val dir = File(app.cacheDir, "gest").apply { mkdirs() }
        vm = CollageViewModel(app)
        vm.markIntroSeen()
        vm.startNew(ProjectMode.COLLAGE, listOf(photo(dir, "a.jpg", 800, 600, Color.rgb(200, 90, 60)), photo(dir, "b.jpg", 600, 800, Color.rgb(60, 120, 200))))
        waitFor("editor") { vm.screen.value == Screen.EDITOR }
        rule.setContent { AppTheme(ThemeMode.LIGHT) { EditorScreen(vm, onExport = {}) } }
        waitFor("canvas") { vm.canvasPx.value.first > 0 && vm.preview.value != null }
        sync()
    }

    private fun canvas() = rule.onNodeWithContentDescription("Collage preview", substring = true)
    private fun cell(i: Int) = vm.project.value!!.cells[i]

    private fun swipeInCell(i: Int, dx: Float, dy: Float) {
        val p = vm.project.value!!
        val (cw, ch) = vm.canvasPx.value
        val r = CollageRenderer.cellRects(p, cw, ch)[i]
        val c = Offset(r.cx, r.cy)
        step { canvas().performTouchInput { down(c) } }
        repeat(12) { step { canvas().performTouchInput { moveBy(Offset(dx / 12f, dy / 12f)) } } }
        step { canvas().performTouchInput { up() } }
    }

    /** Robolectric delivers injected events in one burst; idle the looper after each so the gesture coroutine sees every one, as on a device. */
    private fun step(block: () -> Unit) {
        rule.mainClock.autoAdvance = false // keep time under test control: no warping past the long-press timeout
        block(); rule.mainClock.advanceTimeBy(16); shadowOf(Looper.getMainLooper()).idle()
    }

    /** Apply pending state (mode, sensitivity, selection...) to the UI without letting time run away. */
    private fun sync() { rule.mainClock.autoAdvance = false; rule.mainClock.advanceTimeBy(32); shadowOf(Looper.getMainLooper()).idle() }

    /** Let animations, effects and the clock run normally again. */
    private fun settle() { rule.mainClock.autoAdvance = true; rule.waitForIdle(); shadowOf(Looper.getMainLooper()).idle() }

    // ---- smoothness: direct manipulation, no steps, no re-render, no jump --------------------------------------

    private fun centre(i: Int): Offset {
        val r = CollageRenderer.cellRects(vm.project.value!!, vm.canvasPx.value.first, vm.canvasPx.value.second)[i]
        return Offset(r.cx, r.cy)
    }

    /** Puts a finger down and moves it in the given increments, calling [each] after every single event. */
    private fun drag(i: Int, moves: List<Offset>, each: (Int) -> Unit = {}, lift: Boolean = true) {
        val c = centre(i)
        step { canvas().performTouchInput { down(c) } }
        moves.forEachIndexed { n, m -> step { canvas().performTouchInput { moveBy(m) } }; each(n) }
        if (lift) step { canvas().performTouchInput { up() } }
    }

    private val perDoubling get() = 160f * 3f / vm.zoomSensitivity.value // xxhdpi: 3 px per dp

    @Test fun zoomFollowsEveryFingerMovementWithoutStepsOrReRendering() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM); sync()
        val project0 = vm.project.value
        val frame0 = vm.preview.value
        val zooms = ArrayList<Float>()
        val z0 = cell(0).zoom
        drag(0, List(40) { Offset(0f, -4f) }, each = { zooms += vm.live.zoom }, lift = false)
        // while the finger is still down: project and rendered frame are untouched (nothing re-rendered / saved)
        assertTrue("project untouched during the gesture", vm.project.value === project0)
        assertTrue("no re-render during the gesture", vm.preview.value === frame0)
        assertTrue(vm.live.active)
        // every event moved the zoom, strictly, by a tiny amount: continuous, never quantised
        val moving = zooms.filter { it > z0 }
        assertTrue("zoom changed on (nearly) every event: ${moving.size}/${zooms.size}", moving.size >= zooms.size - 3)
        val ratios = zooms.zipWithNext { a, b -> b / a }.filter { it != 1f }
        assertTrue("strictly increasing", ratios.all { it > 1f })
        assertEquals("every intermediate value is distinct (no snapping)", zooms.size, zooms.distinct().size)
        val expectedStep = Math.pow(2.0, 4.0 / perDoubling).toFloat()
        // 4px per event: 1:1 once past the soft start, and at most twice that inside it
        assertTrue("per-event change bounded: max ${ratios.max()} vs ${expectedStep}", ratios.all { it in 1f..1f + (expectedStep - 1f) * 2.05f })
        assertTrue("steady 1:1 in the tail", ratios.takeLast(15).all { abs(it - expectedStep) < 1e-5f })
        // total equals the exponential of the finger travel (minus the soft start), in full float precision
        val total = vm.live.zoom / z0
        assertEquals(Math.pow(2.0, 160.0 / perDoubling).toFloat(), total, 0.03f)
        step { canvas().performTouchInput { up() } }
        // release commits exactly the live value: the final gesture position is preserved
        assertEquals("committed zoom == live zoom, bit for bit", vm.live.zoom, cell(0).zoom, 0f)
        assertTrue(cell(0).manual)
    }

    @Test fun panFollowsTheFingerOneToOneAndKeepsTheFinalPosition() {
        vm.selectCell(0); vm.stepCell(0, 0f, 0f, 3f); vm.setTouchMode(TouchMode.PAN); sync()
        val p = vm.project.value!!; val (cw, ch) = vm.canvasPx.value
        val r = CollageRenderer.cellRects(p, cw, ch)[0]; val c0 = cell(0)
        val ph = c0.photo!!
        val aspect = com.mundymorning.collage.engine.transform.Orientation.displaySize(ph.width, ph.height, ph.exif, c0.rotation).aspect
        val region = com.mundymorning.collage.engine.transform.CropMath.region(aspect, r.w / r.h, c0.zoom, c0.cx, c0.cy, c0.fit)
        val xs = ArrayList<Float>()
        drag(0, List(30) { Offset(-3f, 0f) }, each = { xs += vm.live.cx }, lift = false)
        val steps = xs.zipWithNext { a, b -> b - a }
        assertTrue("content moves every event", xs.zipWithNext().count { (a, b) -> b != a } >= xs.size - 3)
        assertTrue("all steps the same direction", steps.all { it >= 0f })
        // 90 px of finger travel moves the visible window by exactly 90/cellWidth of its width (1:1 with the finger)
        val expectedShift = 90f / r.w * region.visW
        assertEquals("1:1 with the finger", expectedShift, vm.live.cx - c0.cx, 1e-3f)
        val liveCx = vm.live.cx; val liveCy = vm.live.cy
        step { canvas().performTouchInput { up() } }
        assertEquals(liveCx, cell(0).cx, 0f); assertEquals(liveCy, cell(0).cy, 0f)
    }

    @Test fun crossingTheTouchSlopThresholdProducesNoJump() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM); sync()
        val zooms = ArrayList<Float>(); zooms += cell(0).zoom
        // 1 px events: slop is 8dp = 24px, soft start 4dp = 12px. Walk well past both.
        drag(0, List(60) { Offset(0f, -1f) }, each = { zooms += vm.live.zoom }, lift = false)
        val ratios = zooms.zipWithNext { a, b -> b / a }
        val oneStep = Math.pow(2.0, 1.0 / perDoubling).toFloat()
        // the largest single-event change anywhere (including at the slop and soft-start thresholds) is about one finger pixel (plus the soft-start ramp, at most 2x)
        assertTrue("no jump at thresholds: worst ${ratios.max()} vs 1px ${oneStep}", ratios.all { it <= 1f + (oneStep - 1f) * 2.05f })
        assertTrue("moves from the very first pixels (direct, not delayed by slop): ${zooms[12]}", zooms[12] > zooms[0])
        // once past the soft start, content moves exactly 1:1 again
        val tail = ratios.takeLast(20)
        assertTrue(tail.all { abs(it - oneStep) < 1e-5f })
        step { canvas().performTouchInput { up() } }
    }

    @Test fun tapsAndTinyTremorNeverChangeThePhoto() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.PAN); sync()
        val before = vm.project.value
        step { canvas().performTouchInput { down(centre(0)) } }
        step { canvas().performTouchInput { up() } }
        assertTrue("plain tap", vm.project.value === before)
        drag(0, listOf(Offset(2f, 1f), Offset(-3f, 2f), Offset(1f, -3f)))
        assertTrue("tremor within slop then lift == tap: project untouched", vm.project.value === before)
        assertFalse(vm.live.active)
        assertFalse(cell(0).manual)
    }

    @Test fun zoomHasNoSnappingAndStopsSmoothlyAtLimitsWithoutDeadTravel() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM); sync()
        drag(0, List(200) { Offset(0f, -30f) }, lift = false)           // far beyond the maximum
        assertEquals("clamped exactly at the maximum", 8f, vm.live.zoom, 0f)
        val atMax = vm.live.zoom
        step { canvas().performTouchInput { moveBy(Offset(0f, 6f)) } }  // reverse a little: responds immediately
        assertTrue("no dead travel when reversing from the limit", vm.live.zoom < atMax)
        step { canvas().performTouchInput { up() } }
        assertEquals(vm.live.zoom, cell(0).zoom, 0f)
        // and at the minimum
        drag(0, List(200) { Offset(0f, 30f) }, lift = false)
        assertEquals(1f, vm.live.zoom, 0f)
        step { canvas().performTouchInput { moveBy(Offset(0f, -6f)) } }
        assertTrue(vm.live.zoom > 1f)
        step { canvas().performTouchInput { up() } }
    }

    @Test fun zoomSensitivityChangesFingerTravelPerDoublingContinuously() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM)
        fun logZoomFor(sens: Float): Double {
            vm.setZoomSensitivity(sens); vm.resetCell(0); sync()
            drag(0, List(20) { Offset(0f, -5f) }, lift = false)
            val z = vm.live.zoom.toDouble()
            step { canvas().performTouchInput { up() } }
            return Math.log(z) / Math.log(2.0)
        }
        val normal = logZoomFor(1f)
        val fast = logZoomFor(2f)
        val fine = logZoomFor(0.4f)
        assertEquals("2x sensitivity = twice the zoom for the same movement", 2.0, fast / normal, 0.12)
        assertEquals("fine = 0.4x", 0.4, fine / normal, 0.08)
        assertTrue(fine < normal && normal < fast)
    }

    @Test fun finalCommitIsOneUndoStepAndResetStillRestoresAutomaticPlacement() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM); sync()
        val auto = cell(0)
        drag(0, List(25) { Offset(0f, -6f) })
        assertTrue(cell(0).zoom > auto.zoom)
        vm.undo()
        assertEquals("one drag = one undo step", auto.zoom, cell(0).zoom, 0f)
        vm.redo()
        rule.onNodeWithContentDescription("Reset the selected photo", substring = true).performClick(); sync()
        assertEquals(auto.zoom, cell(0).zoom, 1e-4f); assertEquals(auto.cx, cell(0).cx, 1e-4f); assertFalse(cell(0).manual)
    }

    @Test fun liveLayerIsRemovedOnceTheCommittedFrameIsShown() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM); sync()
        drag(0, List(20) { Offset(0f, -8f) })
        waitFor("committed frame rendered") { vm.preview.value?.forProject?.cells?.get(0)?.zoom == cell(0).zoom }
        // the live layer is dropped as soon as that frame is what is on screen (well before the 1.5 s safety timeout)
        repeat(10) { if (vm.live.active) { rule.mainClock.advanceTimeBy(16); shadowOf(Looper.getMainLooper()).idle() } }
        assertFalse("live layer removed once the committed frame is shown", vm.live.active)
    }

    @Test fun modeBarShowsActiveModeInWordsAndIsAccessible() {
        rule.onNodeWithText("Tap a photo to choose it").assertIsDisplayed()
        vm.selectCell(0); sync()
        rule.onNodeWithText("PAN: drag one finger to move the photo").assertIsDisplayed()
        rule.onNodeWithContentDescription("Zoom mode", substring = true).performClick()
        sync()
        rule.onNodeWithText("ZOOM: slide one finger up to zoom in, down to zoom out").assertIsDisplayed()
        rule.onNodeWithContentDescription("Reset the selected photo", substring = true).assertIsDisplayed()
        rule.onNode(hasContentDescription("Pan mode", substring = true)).assertIsDisplayed()
    }

    @Test fun oneFingerSlideUpZoomsInAndDownZoomsOutProportionally() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM); sync()
        val z0 = cell(0).zoom
        swipeInCell(0, 0f, -150f)
        val z1 = cell(0).zoom
        assertTrue("up zooms in: $z0 -> $z1", z1 > z0 * 1.2f)
        assertTrue(cell(0).manual)
        swipeInCell(0, 0f, 150f)
        val z2 = cell(0).zoom
        assertTrue("down zooms out: $z1 -> $z2", z2 < z1 * 0.9f)
        // a small movement makes a small change
        val before = cell(0).zoom
        swipeInCell(0, 0f, -70f)
        val small = cell(0).zoom / before
        assertTrue("small drag, small change ($small)", small > 1f && small < 1.2f)
        assertTrue(cell(0).zoom in 1f..8f)
    }

    @Test fun oneFingerDragPansInPanModeAndKeepsZoom() {
        vm.selectCell(0); vm.stepCell(0, 0f, 0f, 3f); sync()
        vm.setTouchMode(TouchMode.PAN); sync()
        val c0 = cell(0)
        swipeInCell(0, -40f, 30f)
        val c1 = cell(0)
        assertTrue("pans horizontally ${c0.cx} -> ${c1.cx}", c1.cx > c0.cx)
        assertTrue("pans vertically ${c0.cy} -> ${c1.cy}", c1.cy < c0.cy)
        assertEquals("panning never changes zoom", c0.zoom, c1.zoom, 1e-4f)
        assertTrue(c1.manual)
    }

    @Test fun zoomModeDoesNotPanAndPanModeDoesNotZoom() {
        vm.selectCell(0); vm.stepCell(0, 0f, 0f, 3f)
        vm.setTouchMode(TouchMode.ZOOM); sync()
        val a = cell(0)
        swipeInCell(0, 60f, -60f)
        assertEquals("zoom mode keeps the centre", a.cx, cell(0).cx, 1e-4f)
        assertTrue(cell(0).zoom > a.zoom)
        vm.setTouchMode(TouchMode.PAN); sync()
        val b = cell(0)
        swipeInCell(0, 0f, -80f)
        assertEquals(b.zoom, cell(0).zoom, 1e-4f)
    }

    @Test fun resetRestoresAutomaticPositionAndUndoWorks() {
        vm.selectCell(0); sync()
        val auto = cell(0)
        vm.setTouchMode(TouchMode.ZOOM); sync()
        swipeInCell(0, 0f, -200f)
        assertTrue(cell(0).zoom > auto.zoom)
        rule.onNodeWithContentDescription("Reset the selected photo", substring = true).performClick()
        sync()
        val r = cell(0)
        assertEquals(auto.zoom, r.zoom, 1e-4f); assertEquals(auto.cx, r.cx, 1e-4f); assertEquals(auto.cy, r.cy, 1e-4f)
        assertFalse(r.manual)
        vm.undo()
        assertTrue("reset is undoable", cell(0).zoom > auto.zoom)
    }

    @Test fun gesturesNeverDistortThePhoto() {
        vm.selectCell(1); vm.setTouchMode(TouchMode.ZOOM); sync()
        swipeInCell(1, 0f, -120f); vm.setTouchMode(TouchMode.PAN); swipeInCell(1, 50f, 50f)
        val p = vm.project.value!!
        val (cw, ch) = vm.canvasPx.value
        val r = CollageRenderer.cellRects(p, cw, ch)[1]
        val c = p.cells[1]; val ph = c.photo!!
        val disp = com.mundymorning.collage.engine.transform.Orientation.displaySize(ph.width, ph.height, ph.exif, c.rotation)
        val region = com.mundymorning.collage.engine.transform.CropMath.region(disp.aspect, r.w / r.h, c.zoom, c.cx, c.cy, c.fit)
        assertEquals("visible region keeps the cell's aspect", r.w / r.h, region.visW / region.visH * disp.aspect, 1e-3f)
    }

    @Test fun pinchStillWorksWhenEnabledAndIsIgnoredWhenDisabled() {
        vm.selectCell(0); sync()
        val p = vm.project.value!!; val (cw, ch) = vm.canvasPx.value
        val r = CollageRenderer.cellRects(p, cw, ch)[0]
        val c = Offset(r.cx, r.cy)
        fun pinchOut() {
            step { canvas().performTouchInput { down(0, Offset(c.x - 20, c.y)); down(1, Offset(c.x + 20, c.y)) } }
            for (i in 1..10) step { canvas().performTouchInput { moveTo(0, Offset(c.x - 20 - 7 * i, c.y)); moveTo(1, Offset(c.x + 20 + 7 * i, c.y)) } }
            step { canvas().performTouchInput { up(0); up(1) } }
        }
        val z0 = cell(0).zoom
        vm.setPinchEnabled(true); sync(); pinchOut()
        val z1 = cell(0).zoom
        assertTrue("pinch zooms when enabled ($z0 -> $z1)", z1 > z0 * 1.2f)
        vm.setPinchEnabled(false); sync(); pinchOut()
        assertEquals("pinch ignored when disabled", z1, cell(0).zoom, 1e-4f)
    }

    @Test fun modeAndPinchPreferencesSurviveANewSession() {
        vm.setTouchMode(TouchMode.ZOOM); vm.setPinchEnabled(false)
        val fresh = CollageViewModel(app)
        assertEquals(TouchMode.ZOOM, fresh.touchMode.value)
        assertFalse(fresh.pinchEnabled.value)
        assertTrue(fresh.introSeen.value)
    }

    @Test fun accessibilityActionsZoomAndMove() {
        vm.selectCell(0); sync()
        val z0 = cell(0).zoom
        vm.stepCell(0, 0f, 0f, 1.25f)
        assertTrue(cell(0).zoom > z0)
        val cx = cell(0).cx
        vm.stepCell(0, 0.1f, 0f, 1f)
        assertTrue(cell(0).cx < cx) // content moves right = window moves left
    }

    @Test fun controlTargetsAreAtLeast48dp() {
        vm.selectCell(0); sync()
        for (d in listOf("Pan mode", "Zoom mode", "Reset the selected photo")) {
            val b = rule.onNodeWithContentDescription(d, substring = true).fetchSemanticsNode().boundsInRoot
            assertTrue("$d height ${b.height}px", b.height >= 48 * 3f - 1f) // xxhdpi = 3px/dp
        }
    }
}

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h740dp-xxhdpi")
class FirstUseAndHomeTest {
    @get:Rule val rule = createComposeRule()

    private fun waitFor(what: String, cond: () -> Boolean) {
        repeat(1200) { shadowOf(Looper.getMainLooper()).idle(); if (cond()) return; Thread.sleep(25) }
        throw AssertionError("timed out waiting for $what")
    }

    private fun solid(dir: File, n: String): Uri {
        val f = File(dir, n)
        val b = Bitmap.createBitmap(300, 400, Bitmap.Config.ARGB_8888); b.eraseColor(Color.rgb(90, 140, 200))
        f.outputStream().use { b.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return Uri.fromFile(f)
    }

    @Test fun firstUseExplanationShowsOnceAndIsRemembered() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        app.getSharedPreferences("prefs", 0).edit().clear().commit()
        val dir = File(app.cacheDir, "intro").apply { mkdirs() }
        val vm = CollageViewModel(app)
        vm.startNew(ProjectMode.COLLAGE, listOf(solid(dir, "1.jpg"), solid(dir, "2.jpg")))
        waitFor("editor") { vm.screen.value == Screen.EDITOR }
        rule.setContent { AppTheme(ThemeMode.DARK) { EditorScreen(vm, {}) } }
        rule.onNodeWithText("Move and zoom with one finger").assertIsDisplayed()
        rule.onNodeWithText("Got it").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Move and zoom with one finger").assertDoesNotExist()
        assertTrue(CollageViewModel(app).introSeen.value)
    }

    @Test fun recentProjectShowsRealPhotoCountAndDarkThemeUsesLightText() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        val dir = File(app.cacheDir, "home").apply { mkdirs() }
        val vm = CollageViewModel(app)
        vm.markIntroSeen()
        vm.startNew(ProjectMode.COLLAGE, listOf(solid(dir, "1.jpg"), solid(dir, "2.jpg"), solid(dir, "3.jpg")))
        waitFor("editor") { vm.screen.value == Screen.EDITOR }
        vm.closeEditor()
        waitFor("recents") { vm.home.value.recents.isNotEmpty() }
        var contentLum = -1f
        rule.setContent {
            AppTheme(ThemeMode.DARK) {
                contentLum = LocalContentColor.current.luminance()
                HomeScreen(vm.home.value, ThemeMode.DARK, {}, {}, {}, {}, {}, {})
            }
        }
        assertTrue("default text colour is light in dark theme ($contentLum)", contentLum > 0.6f)
        rule.onNodeWithText("3 photos").assertIsDisplayed()
        assertEquals(3, vm.home.value.recents.first().photoCount)
    }
}
