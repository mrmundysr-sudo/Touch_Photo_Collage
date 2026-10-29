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
        repeat(400) { shadowOf(Looper.getMainLooper()).idle(); if (cond()) return; Thread.sleep(25) }
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
        rule.waitForIdle()
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
        rule.mainClock.autoAdvance = false
        block(); rule.mainClock.advanceTimeBy(16); shadowOf(Looper.getMainLooper()).idle()
        rule.mainClock.autoAdvance = true
    }

    @Test fun modeBarShowsActiveModeInWordsAndIsAccessible() {
        rule.onNodeWithText("Tap a photo to choose it").assertIsDisplayed()
        vm.selectCell(0); rule.waitForIdle()
        rule.onNodeWithText("PAN: drag one finger to move the photo").assertIsDisplayed()
        rule.onNodeWithContentDescription("Zoom mode", substring = true).performClick()
        rule.onNodeWithText("ZOOM: slide one finger up to zoom in, down to zoom out").assertIsDisplayed()
        rule.onNodeWithContentDescription("Reset the selected photo", substring = true).assertIsDisplayed()
        rule.onNode(hasContentDescription("Pan mode", substring = true)).assertIsDisplayed()
    }

    @Test fun oneFingerSlideUpZoomsInAndDownZoomsOutProportionally() {
        vm.selectCell(0); vm.setTouchMode(TouchMode.ZOOM); rule.waitForIdle()
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
        vm.selectCell(0); vm.stepCell(0, 0f, 0f, 3f); rule.waitForIdle()
        vm.setTouchMode(TouchMode.PAN); rule.waitForIdle()
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
        vm.setTouchMode(TouchMode.ZOOM); rule.waitForIdle()
        val a = cell(0)
        swipeInCell(0, 60f, -60f)
        assertEquals("zoom mode keeps the centre", a.cx, cell(0).cx, 1e-4f)
        assertTrue(cell(0).zoom > a.zoom)
        vm.setTouchMode(TouchMode.PAN); rule.waitForIdle()
        val b = cell(0)
        swipeInCell(0, 0f, -80f)
        assertEquals(b.zoom, cell(0).zoom, 1e-4f)
    }

    @Test fun resetRestoresAutomaticPositionAndUndoWorks() {
        vm.selectCell(0); rule.waitForIdle()
        val auto = cell(0)
        vm.setTouchMode(TouchMode.ZOOM); rule.waitForIdle()
        swipeInCell(0, 0f, -200f)
        assertTrue(cell(0).zoom > auto.zoom)
        rule.onNodeWithContentDescription("Reset the selected photo", substring = true).performClick()
        rule.waitForIdle()
        val r = cell(0)
        assertEquals(auto.zoom, r.zoom, 1e-4f); assertEquals(auto.cx, r.cx, 1e-4f); assertEquals(auto.cy, r.cy, 1e-4f)
        assertFalse(r.manual)
        vm.undo()
        assertTrue("reset is undoable", cell(0).zoom > auto.zoom)
    }

    @Test fun gesturesNeverDistortThePhoto() {
        vm.selectCell(1); vm.setTouchMode(TouchMode.ZOOM); rule.waitForIdle()
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
        vm.selectCell(0); rule.waitForIdle()
        val p = vm.project.value!!; val (cw, ch) = vm.canvasPx.value
        val r = CollageRenderer.cellRects(p, cw, ch)[0]
        val c = Offset(r.cx, r.cy)
        fun pinchOut() {
            step { canvas().performTouchInput { down(0, Offset(c.x - 20, c.y)); down(1, Offset(c.x + 20, c.y)) } }
            for (i in 1..10) step { canvas().performTouchInput { moveTo(0, Offset(c.x - 20 - 7 * i, c.y)); moveTo(1, Offset(c.x + 20 + 7 * i, c.y)) } }
            step { canvas().performTouchInput { up(0); up(1) } }
        }
        val z0 = cell(0).zoom
        vm.setPinchEnabled(true); rule.waitForIdle(); pinchOut()
        val z1 = cell(0).zoom
        assertTrue("pinch zooms when enabled ($z0 -> $z1)", z1 > z0 * 1.2f)
        vm.setPinchEnabled(false); rule.waitForIdle(); pinchOut()
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
        vm.selectCell(0); rule.waitForIdle()
        val z0 = cell(0).zoom
        vm.stepCell(0, 0f, 0f, 1.25f)
        assertTrue(cell(0).zoom > z0)
        val cx = cell(0).cx
        vm.stepCell(0, 0.1f, 0f, 1f)
        assertTrue(cell(0).cx < cx) // content moves right = window moves left
    }

    @Test fun controlTargetsAreAtLeast48dp() {
        vm.selectCell(0); rule.waitForIdle()
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
        repeat(400) { shadowOf(Looper.getMainLooper()).idle(); if (cond()) return; Thread.sleep(25) }
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
