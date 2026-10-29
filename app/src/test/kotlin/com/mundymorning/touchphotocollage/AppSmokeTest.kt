package com.mundymorning.touchphotocollage

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Looper
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.mundymorning.collage.engine.project.ProjectMode
import com.mundymorning.touchphotocollage.ui.AppTheme
import com.mundymorning.touchphotocollage.ui.EditorScreen
import com.mundymorning.touchphotocollage.ui.HomeScreen
import com.mundymorning.touchphotocollage.ui.ThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/** Drives the real Compose UI end to end (Robolectric): create from photos, edit in every tab, undo, close, reopen. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h740dp-xxhdpi")
class AppSmokeTest {
    @get:Rule val rule = createComposeRule()

    private fun photo(dir: File, name: String, w: Int, h: Int, color: Int): Uri {
        val f = File(dir, name)
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(b); c.drawColor(color)
        c.drawCircle(w / 2f, h / 3f, minOf(w, h) / 6f, Paint().apply { this.color = Color.rgb(250, 220, 190) })
        f.outputStream().use { b.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return Uri.fromFile(f)
    }

    private fun waitFor(what: String, cond: () -> Boolean) {
        repeat(400) {
            shadowOf(Looper.getMainLooper()).idle()
            if (cond()) return
            Thread.sleep(25)
        }
        throw AssertionError("timed out waiting for $what")
    }

    @Test fun appRequestsNoInternetPermissionSoItCannotUseTheNetwork() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        val info = app.packageManager.getPackageInfo(app.packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
        val perms = info.requestedPermissions?.toList() ?: emptyList()
        assertTrue("INTERNET must not be requested (merged manifest): $perms", "android.permission.INTERNET" !in perms)
    }

    @Test fun homeScreenShowsPrimaryActionsAndEmptyStates() {
        var created: ProjectMode? = null
        rule.setContent {
            AppTheme(ThemeMode.LIGHT) {
                HomeScreen(HomeData(), ThemeMode.LIGHT, {}, { created = it }, {}, {}, {}, {})
            }
        }
        rule.onNodeWithText("Create Collage").assertIsDisplayed()
        rule.onNodeWithText("Your collages will appear here").assertExists()
        rule.onNodeWithText("No templates yet").assertExists()
        rule.onNodeWithText("Create Collage").performClick()
        assertEquals(ProjectMode.COLLAGE, created)
    }

    @Test fun createEditExportFlowWorksThroughTheRealUi() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        val dir = File(app.cacheDir, "smoke").apply { mkdirs() }
        val uris = listOf(photo(dir, "a.jpg", 600, 800, Color.rgb(200, 90, 60)), photo(dir, "b.jpg", 800, 600, Color.rgb(60, 120, 200)), photo(dir, "c.jpg", 500, 500, Color.rgb(70, 160, 90)))
        val vm = CollageViewModel(app)
        vm.markIntroSeen()
        vm.startNew(ProjectMode.FAMILY, uris)
        waitFor("editor") { vm.screen.value == Screen.EDITOR && vm.project.value != null }
        assertEquals(3, vm.project.value!!.photoCount)

        rule.setContent { AppTheme(ThemeMode.DARK) { EditorScreen(vm, onExport = {}) } }
        waitFor("preview") { vm.preview.value != null }
        rule.onNodeWithText("Save").assertIsDisplayed()

        for (tab in listOf("Style", "Adjust", "Text", "Faces", "Layout")) {
            rule.onNodeWithContentDescription("$tab tab").performClick()
            rule.waitForIdle()
        }
        // exercise engine-backed edits and make sure undo/redo track them
        val before = vm.project.value!!
        vm.selectCell(0)
        vm.rotateCell(0)
        vm.mirrorCell(0)
        vm.addText("Hello")
        vm.setLayout(com.mundymorning.collage.engine.layout.LayoutGenerator.candidates(3).last())
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(vm.canUndo.value)
        repeat(5) { vm.undo() }
        assertEquals(before.layout, vm.project.value!!.layout)
        assertEquals(before.texts, vm.project.value!!.texts)
        assertTrue(vm.canRedo.value)

        rule.onNodeWithContentDescription("Style tab").performClick()
        rule.waitForIdle()
        waitFor("preview after edits") { vm.preview.value?.forProject == vm.project.value }
        assertNotNull(vm.preview.value)

        vm.closeEditor()
        waitFor("home") { vm.screen.value == Screen.HOME }
        waitFor("recents") { vm.home.value.recents.size == 1 }
        val id = vm.home.value.recents.single().id
        vm.openSaved(id)
        waitFor("reopened") { vm.screen.value == Screen.EDITOR && vm.project.value?.id == id }
        assertEquals(3, vm.project.value!!.photoCount)
    }
}
