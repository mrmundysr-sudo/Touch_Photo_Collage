package com.mundymorning.collage.engine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.mundymorning.collage.engine.export.*
import com.mundymorning.collage.engine.io.FileBitmapProvider
import com.mundymorning.collage.engine.io.ImageImporter
import com.mundymorning.collage.engine.io.ImportException
import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutGenerator
import com.mundymorning.collage.engine.project.*
import com.mundymorning.collage.engine.render.CollageRenderer
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayOutputStream
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class RenderExportTest {
    private lateinit var ctx: Context
    private lateinit var root: File
    private lateinit var store: ProjectStore
    private lateinit var importer: ImageImporter

    @Before fun setUp() {
        ctx = ApplicationProvider.getApplicationContext()
        root = File(ctx.cacheDir, "render-${System.nanoTime()}").apply { mkdirs() }
        store = ProjectStore(root)
        importer = ImageImporter(ctx, store.mediaDir)
    }

    private fun source(name: String, w: Int = 40, h: Int = 20, exif: Int = 1): File =
        File(root, "src-$name.jpg").also { TestImages.redBlueJpeg(it, w, h, exif) }

    private fun flatProject(photo: PhotoRef, canvas: CanvasSpec = CanvasSpec.SQUARE, rot: Int = 0, mirror: Boolean = false): CollageProject {
        val layout = LayoutGenerator.candidates(1).single()
        return CollageProject(
            id = "t", layout = layout, canvas = canvas, style = CollageStyle(0f, 0f, 0f),
            cells = listOf(CellEdit(photo = photo, rotation = rot, mirror = mirror)),
        )
    }

    private fun render(p: CollageProject, w: Int, h: Int): Bitmap =
        CollageRenderer(FileBitmapProvider(store.mediaDir)).render(p, w, h)

    private fun isRed(px: Int) = Color.red(px) > 180 && Color.blue(px) < 90
    private fun isBlue(px: Int) = Color.blue(px) > 180 && Color.red(px) < 90

    @Test fun importCopiesWithoutTouchingTheOriginal() {
        val src = source("a", exif = 6)
        val before = TestImages.sha(src); val mtime = src.lastModified()
        val ref = importer.import(Uri.fromFile(src))
        assertEquals(40, ref.width); assertEquals(20, ref.height); assertEquals(6, ref.exif)
        assertEquals("original bytes unchanged", before, TestImages.sha(src))
        assertEquals(mtime, src.lastModified())
        assertEquals("private copy is byte-identical", before, TestImages.sha(File(store.mediaDir, ref.file)))
    }

    @Test fun importRejectsNonImagesAndLeavesNoDebris() {
        val bad = File(root, "notes.txt").apply { writeText("hello") }
        try { importer.import(Uri.fromFile(bad)); fail("should reject") } catch (e: ImportException) { /* expected */ }
        assertEquals(0, store.mediaDir.listFiles()!!.size)
        try { importer.import(Uri.fromFile(File(root, "missing.jpg"))); fail() } catch (e: ImportException) { }
    }

    @Test fun exifOrientationIsAppliedWhenRendering() {
        // raw: red left, blue right. EXIF 6 = rotate 90 CW => red on TOP, blue at the bottom.
        val ref = importer.import(Uri.fromFile(source("rot", exif = 6)))
        val bmp = render(flatProject(ref, CanvasSpec(1, 2)), 100, 200)
        assertTrue("top red", isRed(bmp.getPixel(50, 20)))
        assertTrue("bottom blue", isBlue(bmp.getPixel(50, 180)))
    }

    @Test fun exifOrientationOneKeepsLeftRightAndUserRotationMirrorWork() {
        val ref = importer.import(Uri.fromFile(source("plain")))
        var bmp = render(flatProject(ref, CanvasSpec(2, 1)), 200, 100)
        assertTrue(isRed(bmp.getPixel(20, 50))); assertTrue(isBlue(bmp.getPixel(180, 50)))
        bmp = render(flatProject(ref, CanvasSpec(2, 1), mirror = true), 200, 100)
        assertTrue("mirrored", isBlue(bmp.getPixel(20, 50))); assertTrue(isRed(bmp.getPixel(180, 50)))
        bmp = render(flatProject(ref, CanvasSpec(1, 2), rot = 1), 100, 200)
        assertTrue("rotated 90 CW: red on top", isRed(bmp.getPixel(50, 20))); assertTrue(isBlue(bmp.getPixel(50, 180)))
    }

    @Test fun fitModeKeepsWholePhotoUndistortedWithBars() {
        val ref = importer.import(Uri.fromFile(source("fit"))) // 2:1 landscape
        val p = flatProject(ref).let { it.copy(cells = listOf(it.cells[0].copy(fit = true)), background = Background(color1 = Color.WHITE)) }
        val bmp = render(p, 200, 200)
        assertEquals("letterbox bar", Color.WHITE, bmp.getPixel(100, 10))
        assertTrue(isRed(bmp.getPixel(20, 100))); assertTrue(isBlue(bmp.getPixel(180, 100)))
    }

    @Test fun exportedDimensionsMatchCanvasRatioAndQuality() {
        val ref = importer.import(Uri.fromFile(source("exp")))
        val exporter = Exporter(ctx, store.mediaDir)
        for ((canvas, ratio) in listOf(CanvasSpec.SQUARE to 1f, CanvasSpec.LANDSCAPE_4_3 to 4f / 3f, CanvasSpec.STORY_9_16 to 9f / 16f)) {
            for (q in ExportQuality.values()) for (f in ExportFormat.values()) {
                val out = ByteArrayOutputStream()
                val res = exporter.encode(flatProject(ref, canvas), ExportRequest(f, q), out)
                val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                val bytes = out.toByteArray()
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                assertEquals("width ${canvas.label} $q $f", res.width, opts.outWidth)
                assertEquals(res.height, opts.outHeight)
                assertEquals("longest side", maxOf(res.width, res.height), exporter.sizeFor(flatProject(ref, canvas), q).let { maxOf(it.first, it.second) })
                assertEquals(ratio, res.width.toFloat() / res.height, 0.01f)
                assertEquals(bytes.size.toLong(), res.bytes)
            }
        }
        val std = exporter.sizeFor(flatProject(ref), ExportQuality.STANDARD)
        val max = exporter.sizeFor(flatProject(ref), ExportQuality.MAXIMUM)
        assertTrue("maximum is larger than standard", max.first > std.first)
    }

    @Test fun exportToFileWritesDecodablePngWithTransparency() {
        val ref = importer.import(Uri.fromFile(source("png")))
        val p = flatProject(ref).copy(
            style = CollageStyle(0.1f, 0.1f, 0.2f), background = Background(type = BackgroundType.TRANSPARENT),
        )
        val file = File(root, "out.png")
        Exporter(ctx, store.mediaDir).exportToFile(p, ExportRequest(ExportFormat.PNG, ExportQuality.STANDARD, transparent = true), file)
        val bmp = BitmapFactory.decodeFile(file.path)
        assertTrue(bmp.hasAlpha())
        assertEquals("margin corner is transparent", 0, Color.alpha(bmp.getPixel(5, 5)))
        assertEquals("photo is opaque", 255, Color.alpha(bmp.getPixel(bmp.width / 2, bmp.height / 2)))
        // JPEG never keeps alpha: transparent background renders white
        val jpg = File(root, "out.jpg")
        Exporter(ctx, store.mediaDir).exportToFile(p, ExportRequest(ExportFormat.JPEG), jpg)
        val j = BitmapFactory.decodeFile(jpg.path)
        assertTrue(Color.red(j.getPixel(5, 5)) > 240 && Color.blue(j.getPixel(5, 5)) > 240)
    }

    @Test fun sourcePhotosAreUnchangedAfterEditingAndExporting() {
        val src = source("immut", exif = 3)
        val before = TestImages.sha(src)
        val ref = importer.import(Uri.fromFile(src))
        val p = flatProject(ref).let {
            it.copy(cells = listOf(it.cells[0].copy(
                adjustments = Adjustments(0.5f, 0.5f, 0.5f, 0.5f, 1f), filter = FilterType.VINTAGE, rotation = 1, zoom = 3f,
            )))
        }
        Exporter(ctx, store.mediaDir).exportToFile(p, ExportRequest(ExportFormat.JPEG, ExportQuality.MAXIMUM), File(root, "x.jpg"))
        assertEquals(before, TestImages.sha(src))
        assertEquals(before, TestImages.sha(File(store.mediaDir, ref.file)))
    }

    @Test fun multiPhotoCollageHasSpacingBackgroundAndRoundedCorners() {
        val a = importer.import(Uri.fromFile(source("m1")))
        val b = importer.import(Uri.fromFile(File(root, "solid.jpg").also { TestImages.solidJpeg(it, 30, 30, Color.GREEN) }))
        val p = ProjectOps.withLayout(ProjectOps.create(listOf(a, b), ProjectMode.COMPARE, now = 1L), LayoutGenerator.rows(2, 1)).copy(
            canvas = CanvasSpec.LANDSCAPE_3_2, style = CollageStyle(spacing = 0.05f, margin = 0f, cornerRadius = 0.1f),
            background = Background(color1 = Color.WHITE),
        )
        val bmp = render(p, 600, 400)
        assertEquals("divider is background", Color.WHITE, bmp.getPixel(300, 200))
        assertEquals("rounded outer corner shows background", Color.WHITE, bmp.getPixel(1, 1))
        assertTrue("left photo present", Color.red(bmp.getPixel(100, 200)) > 150 || Color.blue(bmp.getPixel(100, 200)) > 150)
        val g = bmp.getPixel(500, 200)
        assertTrue("right photo green", Color.green(g) > 150 && Color.red(g) < 100)
    }

    @Test fun textOverlayAndCaptionDrawPixels() {
        val ref = importer.import(Uri.fromFile(File(root, "dark.jpg").also { TestImages.solidJpeg(it, 50, 50, Color.BLACK) }))
        val base = flatProject(ref)
        val plain = render(base, 300, 300)
        val withText = render(base.copy(texts = listOf(TextOverlay("t", "HELLO", 0.5f, 0.5f, 0.2f, Color.WHITE, shadow = false))), 300, 300)
        var bright = 0
        for (y in 100 until 200) for (x in 50 until 250) if (Color.red(withText.getPixel(x, y)) > 128) bright++
        assertTrue("text rendered", bright > 100)
        assertTrue(Color.red(plain.getPixel(150, 150)) < 20)
        val cap = render(base.copy(cells = listOf(base.cells[0].copy(caption = CellCaption("Mum", "Mother", "34")))), 300, 300)
        var capBright = 0
        for (y in 230 until 300) for (x in 0 until 300) if (Color.red(cap.getPixel(x, y)) > 128) capBright++
        assertTrue("caption rendered", capBright > 20)
    }

    @Test fun sharpnessAndFiltersChangePixelsButNotSize() {
        val ref = importer.import(Uri.fromFile(source("filt")))
        val base = flatProject(ref, CanvasSpec(2, 1))
        val bw = render(base.copy(cells = listOf(base.cells[0].copy(filter = FilterType.BLACK_WHITE))), 200, 100)
        val px = bw.getPixel(20, 50)
        assertEquals(Color.red(px).toFloat(), Color.green(px).toFloat(), 3f)
        assertEquals(Color.green(px).toFloat(), Color.blue(px).toFloat(), 3f)
        val sharp = render(base.copy(cells = listOf(base.cells[0].copy(adjustments = Adjustments(sharpness = 1f)))), 200, 100)
        assertEquals(200, sharp.width)
    }

    @Test fun emptyCellsRenderWithoutCrashing() {
        val p = ProjectOps.create(listOf(importer.import(Uri.fromFile(source("e")))), ProjectMode.COLLAGE, 0L)
        val two = ProjectOps.withLayout(p, LayoutGenerator.rows(2, 1))
        render(two, 200, 200)
        assertNull(two.cells[1].photo)
    }

    @Test fun missingMediaFileRendersPlaceholderInsteadOfCrashing() {
        val ref = importer.import(Uri.fromFile(source("gone")))
        File(store.mediaDir, ref.file).delete()
        val bmp = render(flatProject(ref), 100, 100)
        assertEquals(100, bmp.width)
    }

    @Test fun exportSizingRespectsMemoryBudget() {
        val tiny = 20L * 1024 * 1024
        val (w, h) = ExportSizing.size(CanvasSpec.SQUARE, ExportQuality.MAXIMUM, tiny)
        assertTrue(w.toLong() * h * 4 <= tiny || maxOf(w, h) <= 1024)
        val big = ExportSizing.size(CanvasSpec.SQUARE, ExportQuality.MAXIMUM, 1L shl 30)
        assertEquals(4800, big.first)
        assertEquals(24L * 1024 * 1024, ExportSizing.budgetBytes(1))
    }
}
