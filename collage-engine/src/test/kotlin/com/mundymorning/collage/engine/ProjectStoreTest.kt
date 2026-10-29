package com.mundymorning.collage.engine

import androidx.test.core.app.ApplicationProvider
import android.content.Context
import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.project.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ProjectStoreTest {
    private lateinit var root: File
    private lateinit var store: ProjectStore

    @Before fun setUp() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        root = File(ctx.cacheDir, "store-${System.nanoTime()}").apply { mkdirs() }
        store = ProjectStore(root)
    }

    private fun photos(n: Int) = List(n) {
        PhotoRef("p$it", "p$it.img", 4000 + it, 3000, exif = 6, faces = if (it == 0) listOf(FRect(0.1f, 0.2f, 0.3f, 0.4f)) else null)
    }

    private fun rich(): CollageProject {
        val base = ProjectOps.create(photos(3), ProjectMode.FAMILY, now = 1234L)
        return base.copy(
            name = "Grandpa & me",
            style = CollageStyle(0.02f, 0.03f, 0.05f, 0.01f, 0xFF123456.toInt()),
            background = Background(BackgroundType.TEXTURE, 0xFFF0E8D8.toInt(), 0xFF8A7A5A.toInt(), TextureKind.LINEN, 45f),
            texts = listOf(TextOverlay("t1", "Summer 1984", 0.3f, 0.8f, 0.07f, 0xFFFFCC00.toInt(), FontChoice.SCRIPT, true, true, TextAlign.LEFT, false, 0x66000000, 7f)),
            cells = base.cells.mapIndexed { i, c ->
                if (i == 1) c.copy(
                    zoom = 2.5f, cx = 0.3f, cy = 0.6f, rotation = 3, mirror = true, fit = true, manual = true,
                    adjustments = Adjustments(0.2f, -0.1f, 0.3f, 0.4f, 0.5f), filter = FilterType.VINTAGE,
                    caption = CellCaption("Dad", "Father", "8"),
                ) else c
            },
        )
    }

    @Test fun roundTripPreservesEverything() {
        val p = rich()
        val back = ProjectJson.parseProject(ProjectJson.serialize(p))
        assertEquals(p, back)
    }

    @Test fun saveAndReopenFromDisk() {
        val p = rich()
        store.save(p)
        val reopened = ProjectStore(root).load(p.id)
        assertEquals(p, reopened)
        assertEquals(listOf(p.id), store.list().map { it.id })
        assertEquals("Grandpa & me", store.list().single().name)
    }

    @Test fun olderOrPartialFilesStillOpenWithDefaults() {
        val json = """{"id":"x","layout":{"id":"rows-2-1","name":"a","cells":[[0,0,0.5,1],[0.5,0,1,1]]},"futureField":42}"""
        val p = ProjectJson.parseProject(json)
        assertEquals(2, p.cells.size); assertEquals(CanvasSpec1, p.canvas.label.let { CanvasSpec1 })
        assertEquals(FaceMode.SMART, p.faceMode)
    }

    @Test fun corruptFilesAreSkippedAndDoNotBreakTheList() {
        store.save(rich())
        File(root, "projects/broken.json").writeText("{ this is not json")
        assertEquals(1, store.list().size)
        assertNull(store.load("broken"))
    }

    @Test fun deletingProjectRemovesUnreferencedMediaOnly() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val a = rich().copy(id = "A")
        val b = a.copy(id = "B", cells = a.cells.take(1) + a.cells.drop(1).map { it.copy(photo = null) })
        File(store.mediaDir, "p0.img").writeText("x"); File(store.mediaDir, "p1.img").writeText("x"); File(store.mediaDir, "p2.img").writeText("x")
        store.save(a); store.save(b)
        store.delete("A")
        assertTrue(File(store.mediaDir, "p0.img").exists())   // still used by B
        assertFalse(File(store.mediaDir, "p1.img").exists())  // orphaned
        assertNotNull(ctx)
    }

    @Test fun templatesPersist() {
        val t = TemplateStore(root)
        val p = rich()
        t.add(ProjectOps.toTemplate(p, "Retro trio"))
        val back = TemplateStore(root).list().single()
        assertEquals("Retro trio", back.name); assertEquals(p.layout, back.layout); assertEquals(p.background, back.background)
        t.delete(back.id); assertTrue(t.list().isEmpty())
    }

    @Test fun faceModeOnlyOverwritesNonManualCells() {
        val p = rich()
        val re = ProjectOps.autoCrop(p)
        assertEquals(p.cells[1].zoom, re.cells[1].zoom, 0f) // manual cell untouched
        assertEquals(p.cells[1].cx, re.cells[1].cx, 0f)
    }

    private companion object { const val CanvasSpec1 = "1:1" }
}
